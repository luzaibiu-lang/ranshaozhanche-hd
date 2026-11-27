package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"time"

	"github.com/coder/websocket"
)

// Receipts are session-scoped and survive socket replacement. Replaying a
// receipt returns the CURRENT snapshot, never an old battle or inventory.
type commandReceipt struct {
	at          time.Time
	fingerprint [32]byte
	status      int
	message     string
}

func (a *api) applyCommand(player int64, c Command) (int, string) {
	if c.RequestID == "" || c.Action == "move" {
		if err := a.world.command(player, c); err != nil {
			return 400, err.Error()
		}
		return 200, ""
	}
	if len(c.RequestID) > 96 {
		return 400, "操作编号无效"
	}
	key := fmt.Sprintf("%d:%s", player, c.RequestID)
	copy := c
	copy.RequestID = ""
	body, _ := json.Marshal(copy)
	fingerprint := sha256.Sum256(body)
	if a.receipts == nil {
		a.receipts = map[string]commandReceipt{}
	}
	now := time.Now()
	if old, ok := a.receipts[key]; ok && now.Sub(old.at) < 10*time.Minute {
		if old.fingerprint != fingerprint {
			return 409, "操作编号已用于其他操作"
		}
		return old.status, old.message
	}
	// Bound memory even if a client keeps issuing fresh IDs. Entries older than
	// the retry lifetime can go; live receipts are never silently evicted.
	if len(a.receipts) >= 8192 {
		for k, v := range a.receipts {
			if now.Sub(v.at) >= 10*time.Minute {
				delete(a.receipts, k)
			}
		}
		if len(a.receipts) >= 8192 {
			return 429, "操作确认暂时繁忙，请稍后重试"
		}
	}
	status, message := 200, ""
	if err := a.world.command(player, c); err != nil {
		status, message = 400, err.Error()
	}
	a.receipts[key] = commandReceipt{now, fingerprint, status, message}
	return status, message
}

type streamRequest struct {
	ID          string          `json:"id"`
	Type        string          `json:"type"`
	Token       string          `json:"token,omitempty"`
	Path        string          `json:"path"`
	Payload     json.RawMessage `json:"payload"`
	Conditional bool            `json:"conditional"`
	ETag        string          `json:"etag"`
	BattleID    string          `json:"battle_id"`
	ShotID      int             `json:"shot_id"`
}
type streamReply struct {
	ID     string         `json:"id"`
	Type   string         `json:"type,omitempty"`
	Status int            `json:"status"`
	Data   map[string]any `json:"data"`
	ETag   string         `json:"etag,omitempty"`
}

func (a *api) stream(w http.ResponseWriter, r *http.Request) {
	// Origin checking remains enabled. Native clients have no Origin; browsers
	// must be same-origin with the game page. Tokens never enter URLs or logs.
	if r.URL.RawQuery != "" {
		writeError(w, 400, "长连接地址不接受查询参数")
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(64 * 1024)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	authCtx, done := context.WithTimeout(ctx, 8*time.Second)
	_, raw, err := conn.Read(authCtx)
	done()
	var auth streamRequest
	if err != nil || json.Unmarshal(raw, &auth) != nil || auth.Type != "auth" || len(auth.Token) != 64 {
		return
	}
	token := auth.Token
	authenticated := func() bool {
		req := httptest.NewRequest(http.MethodGet, "/api/state", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		a.world.mu.Lock()
		_, ok := a.identify(req)
		a.world.mu.Unlock()
		return ok
	}
	sessionError := func() map[string]any {
		req := httptest.NewRequest(http.MethodGet, "/api/state", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		a.world.mu.Lock()
		defer a.world.mu.Unlock()
		return a.sessionError(req)
	}
	send := func(reply streamReply) bool {
		data, err := json.Marshal(reply)
		if err != nil {
			return false
		}
		c, d := context.WithTimeout(ctx, 5*time.Second)
		defer d()
		return conn.Write(c, websocket.MessageText, data) == nil
	}
	if !authenticated() {
		send(streamReply{ID: auth.ID, Status: 401, Data: sessionError()})
		return
	}
	if !send(streamReply{ID: auth.ID, Type: "hello", Status: 200, Data: map[string]any{"ok": true, "protocol": 1, "receipts": true, "shot_cache": true}}) {
		return
	}
	inbox := make(chan streamRequest, 8)
	go func() {
		defer cancel()
		for {
			_, data, e := conn.Read(ctx)
			if e != nil {
				return
			}
			var in streamRequest
			if json.Unmarshal(data, &in) != nil {
				return
			}
			select {
			case inbox <- in:
			case <-ctx.Done():
				return
			}
		}
	}()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	lastClient, lastSend := time.Now(), time.Now()
	cachedBattle, cachedShot := "", -1
	lastDigest := [32]byte{}
	lastVersion := uint64(0)
	lastCheck := time.Time{}
	execute := func(in streamRequest) streamReply {
		reply := streamReply{ID: in.ID, Status: 400, Data: map[string]any{"error": "长连接操作无效"}}
		if in.Path != "/api/state" && in.Path != "/api/command" {
			return reply
		}
		method := http.MethodGet
		var body string
		if in.Path == "/api/command" {
			method = http.MethodPost
			body = string(in.Payload)
		}
		req := httptest.NewRequest(method, in.Path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		if in.Conditional && in.ETag != "" {
			req.Header.Set("If-None-Match", in.ETag)
		}
		capture := httptest.NewRecorder()
		if in.Path == "/api/state" {
			a.state(capture, req)
		} else {
			a.command(capture, req)
		}
		reply.Status = capture.Code
		reply.ETag = capture.Header().Get("ETag")
		if reply.Status == 304 {
			reply.Data = map[string]any{"unchanged": true}
		} else if func() error { reply.Data = nil; return json.Unmarshal(capture.Body.Bytes(), &reply.Data) }() != nil {
			reply.Status = 500
			reply.Data = map[string]any{"error": "状态读取失败"}
		}
		return reply
	}
	compact := func(reply *streamReply) {
		room, ok := reply.Data["room"].(map[string]any)
		if !ok {
			return
		}
		battle, ok := room["battle"].(map[string]any)
		if !ok {
			return
		}
		shot, ok := battle["shot"].(map[string]any)
		if !ok {
			return
		}
		if battle["id"] == cachedBattle && int(shot["id"].(float64)) == cachedShot {
			battle["shot"] = nil
			battle["shot_ref"] = map[string]any{"battle_id": cachedBattle, "shot_id": cachedShot}
		}
	}
	for {
		select {
		case <-ctx.Done():
			return
		case in := <-inbox:
			lastClient = time.Now()
			if in.Type == "cache" {
				cachedBattle, cachedShot = in.BattleID, in.ShotID
				continue
			}
			if in.Type == "ping" {
				if !authenticated() {
					send(streamReply{Status: 401, Data: sessionError()})
					return
				}
				if !send(streamReply{ID: in.ID, Type: "pong", Status: 200, Data: map[string]any{"server_time": nowSeconds()}}) {
					return
				}
			} else {
				reply := execute(in)
				compact(&reply)
				if !send(reply) {
					return
				}
				if reply.Status == 401 {
					return
				}
			}
			lastSend = time.Now()
		case <-ticker.C:
			if time.Since(lastClient) > 40*time.Second {
				return
			}
			a.world.mu.Lock()
			currentVersion := a.world.version
			a.world.mu.Unlock()
			if currentVersion == lastVersion && time.Since(lastCheck) < 5*time.Second {
				continue
			}
			lastCheck = time.Now()
			reply := execute(streamRequest{Path: "/api/state"})
			if value, ok := reply.Data["version"].(float64); ok {
				lastVersion = uint64(value)
			}
			if reply.Status == 401 {
				send(reply)
				return
			}
			// Global room changes should not repeatedly transmit an unrelated battle.
			scope := map[string]any{}
			for k, v := range reply.Data {
				if k != "server_time" && k != "version" {
					scope[k] = v
				}
			}
			if scope["room"] != nil {
				delete(scope, "rooms")
				delete(scope, "players")
			}
			data, _ := json.Marshal(scope)
			digest := sha256.Sum256(data)
			if digest != lastDigest {
				lastDigest = digest
				reply.Type = "state"
				compact(&reply)
				if !send(reply) {
					return
				}
				lastSend = time.Now()
			} else if time.Since(lastSend) >= 5*time.Second {
				if !send(streamReply{Type: "heartbeat", Status: 200, Data: map[string]any{"server_time": nowSeconds()}}) {
					return
				}
				lastSend = time.Now()
			}
		}
	}
}
