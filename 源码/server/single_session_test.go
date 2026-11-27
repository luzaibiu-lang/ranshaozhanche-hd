package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestExclusiveSessionMigrationRestartAndRollback(t *testing.T) {
	path := filepath.Join(t.TempDir(), "legacy.sqlite3")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec("CREATE TABLE sessions(hash TEXT PRIMARY KEY,player INTEGER NOT NULL,expires INTEGER NOT NULL)")
	if err != nil {
		t.Fatal(err)
	}
	older, newer, other := token(), token(), token()
	expires := time.Now().Add(time.Hour)
	for _, row := range []struct {
		raw    string
		player int64
	}{{older, 1}, {newer, 1}, {other, 2}} {
		if _, err = db.Exec("INSERT INTO sessions(hash,player,expires) VALUES(?,?,?)", sessionHash(row.raw), row.player, expires.Unix()); err != nil {
			t.Fatal(err)
		}
	}
	db.Close()
	store, err := openStore(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := store.session(older); ok || !store.sessionReplaced(older) {
		t.Fatal("legacy older session was not replaced")
	}
	if _, ok := store.session(newer); !ok {
		t.Fatal("latest legacy session lost")
	}
	if _, ok := store.session(other); !ok {
		t.Fatal("other player was evicted")
	}
	// A failed insert must roll back revocation of the previous active session.
	if err = store.createSession(newer, 2, expires); err == nil {
		t.Fatal("duplicate credential unexpectedly inserted")
	}
	if _, ok := store.session(other); !ok {
		t.Fatal("failed login revoked prior session")
	}
	replacement := token()
	if err = store.createSession(replacement, 1, expires); err != nil {
		t.Fatal(err)
	}
	store.db.Close()
	store, err = openStore(path)
	if err != nil {
		t.Fatal(err)
	}
	defer store.db.Close()
	if _, ok := store.session(newer); ok || !store.sessionReplaced(newer) {
		t.Fatal("replaced session returned after restart")
	}
	if _, ok := store.session(replacement); !ok {
		t.Fatal("new session did not survive restart")
	}
	var count int
	store.db.QueryRow("SELECT count(*) FROM sessions WHERE player=1 AND revoked=0").Scan(&count)
	if count != 1 {
		t.Fatalf("active sessions=%d", count)
	}
}

type sessionTestClient struct{ handler http.Handler }

func (c sessionTestClient) request(path, credential, body string) (int, map[string]any) {
	method := http.MethodGet
	if body != "" {
		method = http.MethodPost
	}
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.RemoteAddr = "127.0.0.1:45001"
	if credential != "" {
		req.Header.Set("Authorization", "Bearer "+credential)
	}
	out := httptest.NewRecorder()
	c.handler.ServeHTTP(out, req)
	data := map[string]any{}
	json.Unmarshal(out.Body.Bytes(), &data)
	return out.Code, data
}
func (c sessionTestClient) login(t *testing.T, name string) string {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"name": name, "password": "single-session-fixture"})
	status, data := c.request("/api/login", "", string(body))
	if status != 200 {
		t.Fatalf("login=%d %v", status, data)
	}
	return data["token"].(string)
}
func sessionWorld(t *testing.T) (*World, sessionTestClient) {
	t.Helper()
	s, err := openStore(filepath.Join(t.TempDir(), "login.sqlite3"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.db.Close() })
	for _, name := range []string{"single_owner", "single_friend"} {
		if _, err = s.register(name, "single-session-fixture"); err != nil {
			t.Fatal(err)
		}
	}
	w, err := newWorld(s, "../client/assets")
	if err != nil {
		t.Fatal(err)
	}
	return w, sessionTestClient{newHandler(w, "")}
}
func TestNewLoginReplacesOldWithoutLeavingRoom(t *testing.T) {
	w, c := sessionWorld(t)
	old := c.login(t, "single_owner")
	friend := c.login(t, "single_friend")
	status, data := c.request("/api/command", old, `{"action":"create","name":"single-room","map":4}`)
	if status != 200 {
		t.Fatal(data)
	}
	roomID := int(data["room"].(map[string]any)["id"].(float64))
	wrong, _ := c.request("/api/login", "", `{"name":"single_owner","password":"wrong-password"}`)
	if wrong != 400 {
		t.Fatal("wrong password unexpectedly accepted")
	}
	if status, _ = c.request("/api/state", old, ""); status != 200 {
		t.Fatal("wrong password evicted valid session")
	}
	current := c.login(t, "single_owner")
	for _, action := range []string{"state", "leave", "chat", "move"} {
		path, body := "/api/command", fmt.Sprintf(`{"action":%q}`, action)
		if action == "state" {
			path, body = "/api/state", ""
		}
		status, data = c.request(path, old, body)
		if status != 401 || data["code"] != "session_replaced" {
			t.Fatalf("old %s=%d %v", action, status, data)
		}
	}
	if status, _ = c.request("/api/logout", old, "{}"); status != 200 {
		t.Fatal("old logout failed")
	}
	status, data = c.request("/api/state", current, "")
	if status != 200 || int(data["room"].(map[string]any)["id"].(float64)) != roomID {
		t.Fatal("old logout removed the new login's room")
	}
	if len(w.rooms) != 1 {
		t.Fatal("login duplicated or destroyed room")
	}
	if status, _ = c.request("/api/state", friend, ""); status != 200 {
		t.Fatal("unrelated account was evicted")
	}
}
func TestConcurrentLoginsKeepExactlyOneCredential(t *testing.T) {
	w, c := sessionWorld(t)
	tokens := make(chan string, 6)
	failures := make(chan int, 6)
	var jobs sync.WaitGroup
	for i := 0; i < 6; i++ {
		jobs.Add(1)
		go func() {
			defer jobs.Done()
			status, data := c.request("/api/login", "", `{"name":"single_owner","password":"single-session-fixture"}`)
			if status != 200 {
				failures <- status
				return
			}
			tokens <- data["token"].(string)
		}()
	}
	jobs.Wait()
	close(tokens)
	close(failures)
	for status := range failures {
		t.Fatalf("concurrent login=%d", status)
	}
	valid := 0
	for raw := range tokens {
		status, _ := c.request("/api/state", raw, "")
		if status == 200 {
			valid++
		}
	}
	if valid != 1 {
		t.Fatalf("valid credentials after concurrent logins=%d", valid)
	}
	w.mu.Lock()
	cached := 0
	for _, s := range w.sessions {
		if s.Player == 1 {
			cached++
		}
	}
	w.mu.Unlock()
	var stored int
	w.store.db.QueryRow("SELECT count(*) FROM sessions WHERE player=1 AND revoked=0").Scan(&stored)
	if cached != 1 || stored != 1 {
		t.Fatalf("cache=%d store=%d", cached, stored)
	}
}
func TestLiveStreamReceivesReplacementAndNewSessionKeepsRoom(t *testing.T) {
	_, c := sessionWorld(t)
	old := c.login(t, "single_owner")
	_, data := c.request("/api/command", old, `{"action":"create","name":"socket-room","map":4}`)
	roomID := data["room"].(map[string]any)["id"]
	srv := httptest.NewServer(c.handler)
	defer srv.Close()
	socket := wsDial(t, srv, old)
	current := c.login(t, "single_owner")
	reply := wsRead(t, socket, "")
	for reply.Status != 401 {
		reply = wsRead(t, socket, "")
	}
	if reply.Data["code"] != "session_replaced" {
		t.Fatalf("replacement=%v", reply)
	}
	if status, _ := c.request("/api/logout", old, "{}"); status != 200 {
		t.Fatal("revoked logout rejected")
	}
	status, state := c.request("/api/state", current, "")
	if status != 200 || state["room"].(map[string]any)["id"] != roomID {
		t.Fatal("new session lost room after old socket closed")
	}
}
