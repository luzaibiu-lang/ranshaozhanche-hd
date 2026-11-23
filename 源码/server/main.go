package main

import (
	"context"
	"crypto/hmac"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const version = "0.1.16"

//go:embed gm.html
var gmHTML string

func main() {
	listen := flag.String("listen", "127.0.0.1:18180", "Independent HD HTTP listen address")
	data := flag.String("data", "data", "HD-only writable data directory")
	assets := flag.String("assets", "../client/assets", "Extracted HD assets")
	cert := flag.String("cert", "", "Optional TLS certificate")
	key := flag.String("key", "", "Optional TLS private key")
	adminFile := flag.String("admin-password-file", "", "Read an independent GM password from this file")
	updates := flag.String("updates", "", "Independent HD client publication directory")
	flag.Parse()
	store, e := openStore(filepath.Join(*data, "hd.sqlite3"))
	if e != nil {
		log.Fatal(e)
	}
	defer store.db.Close()
	world, e := newWorld(store, *assets)
	if e != nil {
		log.Fatal(e)
	}
	admin := ""
	if *adminFile != "" {
		b, e := os.ReadFile(*adminFile)
		if e != nil {
			log.Fatal(e)
		}
		admin = strings.TrimSpace(string(b))
		if len(admin) < 8 {
			log.Fatal("GM password must contain at least 8 bytes")
		}
	}
	handler := newPublicationHandler(world, admin, *updates)
	srv := &http.Server{Addr: *listen, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 65 * time.Second, MaxHeaderBytes: 16 * 1024}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		ticker := time.NewTicker(150 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				world.tick()
			}
		}
	}()
	go func() {
		<-stop
		c, done := context.WithTimeout(context.Background(), 5*time.Second)
		defer done()
		srv.Shutdown(c)
		cancel()
	}()
	log.Printf("Burning Chariot HD %s listening on %s; independent data: %s", version, *listen, *data)
	if *cert != "" && *key != "" {
		e = srv.ListenAndServeTLS(*cert, *key)
	} else {
		e = srv.ListenAndServe()
	}
	if e != nil && !errors.Is(e, http.ErrServerClosed) {
		log.Fatal(e)
	}
}

type api struct {
	world         *World
	admin         string
	rates         map[string][]time.Time
	adminSessions map[string]time.Time
}

func newHandler(w *World, admin string) http.Handler {
	return newPublicationHandler(w, admin, "")
}
func newPublicationHandler(w *World, admin, updates string) http.Handler {
	a := &api{world: w, admin: admin, rates: map[string][]time.Time{}, adminSessions: map[string]time.Time{}}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.health)
	mux.HandleFunc("/api/register", a.auth)
	mux.HandleFunc("/api/login", a.auth)
	mux.HandleFunc("/api/logout", a.logout)
	mux.HandleFunc("/api/state", a.state)
	mux.HandleFunc("/api/command", a.command)
	mux.HandleFunc("/api/catalog", a.catalog)
	mux.HandleFunc("/gm/api/state", a.gm)
	mux.HandleFunc("/gm/api/login", a.gmLogin)
	mux.HandleFunc("/gm/api/action", a.gm)
	mux.HandleFunc("/gm", a.gmPage)
	if updates != "" {
		mux.Handle("/updates/", http.StripPrefix("/updates/", http.FileServer(http.Dir(updates))))
	}
	return compressGameJSON(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		rw.Header().Set("Cache-Control", "no-store")
		rw.Header().Set("X-Content-Type-Options", "nosniff")
		rw.Header().Set("Referrer-Policy", "no-referrer")
		if r.Method == "OPTIONS" {
			rw.WriteHeader(204)
			return
		}
		defer func() {
			if p := recover(); p != nil {
				log.Printf("request failed: %T", p)
				writeError(rw, 500, "服务器暂时繁忙")
			}
		}()
		mux.ServeHTTP(rw, r)
	}))
}
func jsonOut(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
func writeError(w http.ResponseWriter, status int, text string) {
	jsonOut(w, status, map[string]any{"ok": false, "error": text})
}
func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if r.Method != "POST" {
		writeError(w, 405, "请使用 POST")
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, 64*1024)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		writeError(w, 400, "请求格式无效")
		return false
	}
	return true
}
func (a *api) health(w http.ResponseWriter, r *http.Request) {
	jsonOut(w, 200, map[string]any{"ok": true, "runtime": "go", "version": version, "edition": "hd"})
}
func (a *api) catalog(w http.ResponseWriter, r *http.Request) {
	maps := []MapInfo{}
	for i := 1; i <= 19; i++ {
		t := a.world.terrain[i]
		maps = append(maps, MapInfo{i, mapNames[i-1], t.W, t.H})
	}
	jsonOut(w, 200, map[string]any{"vehicles": vehicles, "maps": maps, "items": items, "version": version})
}
func (a *api) auth(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name     string `json:"name"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	a.world.mu.Lock()
	recent := []time.Time{}
	for _, t := range a.rates[host] {
		if time.Since(t) < time.Minute {
			recent = append(recent, t)
		}
	}
	if len(recent) >= 20 {
		a.world.mu.Unlock()
		writeError(w, 429, "操作频繁，请稍后再试")
		return
	}
	a.rates[host] = append(recent, time.Now())
	a.world.mu.Unlock()
	var p *Profile
	var e error
	if strings.HasSuffix(r.URL.Path, "register") {
		p, e = a.world.store.register(in.Name, in.Password)
	} else {
		p, e = a.world.store.login(in.Name, in.Password)
	}
	if e != nil {
		writeError(w, 400, e.Error())
		return
	}
	t := token()
	expires := time.Now().Add(30 * 24 * time.Hour)
	if e := a.world.store.createSession(t, p.ID, expires); e != nil {
		writeError(w, 500, "无法保存登录，请重试")
		return
	}
	a.world.mu.Lock()
	a.world.sessions[t] = Session{p.ID, expires}
	a.world.mu.Unlock()
	jsonOut(w, 200, map[string]any{"ok": true, "token": t, "profile": p})
}
func (a *api) identify(r *http.Request) (int64, bool) {
	t := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	s, ok := a.world.sessions[t]
	if !ok && len(t) == 64 {
		s, ok = a.world.store.session(t)
		if ok {
			a.world.sessions[t] = s
		}
	}
	return s.Player, ok && time.Now().Before(s.Expires)
}
func (a *api) logout(w http.ResponseWriter, r *http.Request) {
	var in struct{}
	if !readJSON(w, r, &in) {
		return
	}
	a.world.mu.Lock()
	defer a.world.mu.Unlock()
	id, ok := a.identify(r)
	if ok {
		a.world.leave(id)
		delete(a.world.presence, id)
		a.world.version++
	}
	t := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if e := a.world.store.revokeSession(t); e != nil {
		writeError(w, 500, "退出失败，请重试")
		return
	}
	delete(a.world.sessions, t)
	jsonOut(w, 200, map[string]any{"ok": true})
}
func (a *api) state(w http.ResponseWriter, r *http.Request) {
	a.world.mu.Lock()
	defer a.world.mu.Unlock()
	id, ok := a.identify(r)
	if !ok {
		writeError(w, 401, "登录已过期，请重新登录")
		return
	}
	if room, m := a.world.roomFor(id); room != nil && m != nil {
		m.Seen = time.Now()
	}
	a.world.touchPresence(id)
	etag := fmt.Sprintf("\"hd-%s-%d\"", a.world.epoch, a.world.version)
	w.Header().Set("ETag", etag)
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(304)
		return
	}
	state, e := a.world.snapshot(id)
	if e != nil {
		writeError(w, 500, "读取玩家资料失败")
		return
	}
	jsonOut(w, 200, state)
}
func (a *api) command(w http.ResponseWriter, r *http.Request) {
	var c Command
	if !readJSON(w, r, &c) {
		return
	}
	a.world.mu.Lock()
	defer a.world.mu.Unlock()
	id, ok := a.identify(r)
	if !ok {
		writeError(w, 401, "登录已过期，请重新登录")
		return
	}
	if e := a.world.command(id, c); e != nil {
		writeError(w, 400, e.Error())
		return
	}
	state, e := a.world.snapshot(id)
	if e != nil {
		writeError(w, 500, "读取状态失败")
		return
	}
	jsonOut(w, 200, state)
}
func (a *api) gm(w http.ResponseWriter, r *http.Request) {
	supplied := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	a.world.mu.Lock()
	defer a.world.mu.Unlock()
	expires, sessionOK := a.adminSessions[sessionHash(supplied)]
	if a.admin == "" || (!hmac.Equal([]byte(supplied), []byte(a.admin)) && !(sessionOK && time.Now().Before(expires))) {
		writeError(w, 401, "管理员凭据无效")
		return
	}
	if r.URL.Path == "/gm/api/action" {
		var in struct {
			Action string `json:"action"`
			Player int64  `json:"player"`
			Amount int    `json:"amount"`
			Room   int    `json:"room"`
		}
		if !readJSON(w, r, &in) {
			return
		}
		switch in.Action {
		case "add_gold":
			if e := a.world.store.addGold(in.Player, in.Amount); e != nil {
				writeError(w, 400, e.Error())
				return
			}
		case "end_match":
			room := a.world.rooms[in.Room]
			if room == nil || room.Battle == nil {
				writeError(w, 400, "对局不存在")
				return
			}
			a.world.finish(room, -1, "管理员结束了本局对战")
		case "close_room":
			room := a.world.rooms[in.Room]
			if room != nil {
				delete(a.world.rooms, room.ID)
			}
		default:
			writeError(w, 400, "未知管理操作")
			return
		}
		a.world.version++
	}
	rooms := []*Room{}
	for _, room := range a.world.rooms {
		rooms = append(rooms, room)
	}
	rows, e := a.world.store.db.Query("SELECT id,name,gold,wins,games FROM players ORDER BY id DESC LIMIT 300")
	if e != nil {
		writeError(w, 500, "无法读取数据")
		return
	}
	players := []map[string]any{}
	for rows.Next() {
		var id int64
		var name string
		var gold, wins, games int
		rows.Scan(&id, &name, &gold, &wins, &games)
		players = append(players, map[string]any{"id": id, "name": name, "gold": gold, "wins": wins, "games": games})
	}
	rows.Close()
	jsonOut(w, 200, map[string]any{"ok": true, "players": players, "rooms": rooms})
}
func (a *api) gmLogin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name     string `json:"name"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	a.world.mu.Lock()
	defer a.world.mu.Unlock()
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	key := "gm:" + host
	recent := []time.Time{}
	for _, t := range a.rates[key] {
		if time.Since(t) < time.Minute {
			recent = append(recent, t)
		}
	}
	if len(recent) >= 10 {
		writeError(w, 429, "操作频繁，请稍后再试")
		return
	}
	a.rates[key] = append(recent, time.Now())
	if in.Name != "admin" || a.admin == "" || !hmac.Equal([]byte(in.Password), []byte(a.admin)) {
		writeError(w, 401, "管理员账号或密码错误")
		return
	}
	credential := token()
	for hash, expires := range a.adminSessions {
		if time.Now().After(expires) {
			delete(a.adminSessions, hash)
		}
	}
	a.adminSessions[sessionHash(credential)] = time.Now().Add(8 * time.Hour)
	jsonOut(w, 200, map[string]any{"ok": true, "token": credential})
}
func (a *api) gmPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(gmHTML))
}
