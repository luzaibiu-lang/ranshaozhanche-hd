package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func streamFixture(t *testing.T) (*World, *Room, int64, int64, *httptest.Server, string) {
	t.Helper()
	w, r, host, guest := loadingRoom(t, false, false)
	raw := strings.Repeat("a", 64)
	w.sessions[raw] = Session{host, time.Now().Add(time.Hour)}
	srv := httptest.NewServer(newHandler(w, ""))
	t.Cleanup(srv.Close)
	return w, r, host, guest, srv, raw
}
func wsSend(t *testing.T, c *websocket.Conn, v any) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	raw, _ := json.Marshal(v)
	if err := c.Write(ctx, websocket.MessageText, raw); err != nil {
		t.Fatal(err)
	}
}
func wsRead(t *testing.T, c *websocket.Conn, id string) streamReply {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, raw, err := c.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var reply streamReply
		if err = json.Unmarshal(raw, &reply); err != nil {
			t.Fatal(err)
		}
		if reply.ID == id {
			return reply
		}
	}
}
func wsDial(t *testing.T, srv *httptest.Server, token string) *websocket.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"/api/stream", nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.CloseNow() })
	wsSend(t, c, streamRequest{ID: "auth", Type: "auth", Token: token})
	if reply := wsRead(t, c, "auth"); reply.Status != 200 {
		t.Fatalf("auth: %+v", reply)
	}
	return c
}
func TestStreamAuthenticationOriginAndExpiry(t *testing.T) {
	w, _, _, _, srv, token := streamFixture(t)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+"/api/stream", &websocket.DialOptions{HTTPHeader: http.Header{"Origin": []string{"https://evil.invalid"}}})
	if err == nil {
		c.CloseNow()
		t.Fatal("cross origin accepted")
	}
	c = wsDial(t, srv, token)
	wsSend(t, c, streamRequest{ID: "state", Path: "/api/state"})
	if reply := wsRead(t, c, "state"); reply.Status != 200 || reply.Data["profile"] == nil {
		t.Fatalf("missing state: %+v", reply)
	}
	w.mu.Lock()
	delete(w.sessions, token)
	w.store.revokeSession(token)
	w.mu.Unlock()
	wsSend(t, c, streamRequest{ID: "expired", Path: "/api/state"})
	reply := wsRead(t, c, "expired")
	if reply.Status != 401 {
		t.Fatalf("revoked stream authenticated: %+v", reply)
	}
}
func TestCommandReceiptsAcrossSocketReplacementAndREST(t *testing.T) {
	w, r, host, guest, srv, token := streamFixture(t)
	c := wsDial(t, srv, token)
	command := Command{Action: "pass", Generation: r.Battle.Generation, RequestID: "exactly-once-pass"}
	raw, _ := json.Marshal(command)
	wsSend(t, c, streamRequest{ID: "lost", Path: "/api/command", Payload: raw})
	// Wait for processing, discard the original acknowledgement as a broken
	// connection would. The next socket gets a current, successful receipt.
	first := wsRead(t, c, "lost")
	if first.Status != 200 {
		t.Fatal(first)
	}
	c.CloseNow()
	generation := r.Battle.Generation
	c = wsDial(t, srv, token)
	wsSend(t, c, streamRequest{ID: "retry", Path: "/api/command", Payload: raw})
	if reply := wsRead(t, c, "retry"); reply.Status != 200 {
		t.Fatal(reply)
	}
	if r.Battle.Generation != generation {
		t.Fatal("duplicate pass changed turn")
	}
	req := httptest.NewRequest(http.MethodPost, "/api/command", strings.NewReader(string(raw)))
	req.Header.Set("Authorization", "Bearer "+token)
	out := httptest.NewRecorder()
	newHandler(w, "").ServeHTTP(out, req)
	// The same api instance holds receipts. Test HTTP fallback on that instance.
	a := &api{world: w, receipts: map[string]commandReceipt{}}
	w.mu.Lock()
	r.Battle.Active = 0
	r.Battle.Generation = 100
	r.Battle.Deadline = nowSeconds() + 35
	status, _ := a.applyCommand(host, Command{Action: "pass", Generation: 100, RequestID: "rest-receipt"})
	after := r.Battle.Generation
	repeat, _ := a.applyCommand(host, Command{Action: "pass", Generation: 100, RequestID: "rest-receipt"})
	collision, _ := a.applyCommand(host, Command{Action: "fire", Generation: 100, RequestID: "rest-receipt"})
	cross, _ := a.applyCommand(guest, Command{Action: "pass", Generation: 100, RequestID: "rest-receipt"})
	w.mu.Unlock()
	if status != 200 || repeat != 200 || collision != 409 || cross == 200 || r.Battle.Generation != after {
		t.Fatalf("receipt status: %d %d %d %d", status, repeat, collision, cross)
	}
}
func TestStreamShotCacheAndFullReconnect(t *testing.T) {
	w, r, _, _, srv, token := streamFixture(t)
	w.mu.Lock()
	points := make([][2]float64, 1500)
	for i := range points {
		points[i] = [2]float64{float64(i), float64(i % 100)}
	}
	r.Battle.Shot = &Shot{ID: 9, Started: nowSeconds(), Duration: 5, Trails: []Trail{{Projectile: 1, Points: points, Duration: 5}}}
	battleID := r.Battle.ID
	w.mu.Unlock()
	c := wsDial(t, srv, token)
	get := func(id string) streamReply {
		wsSend(t, c, streamRequest{ID: id, Path: "/api/state"})
		return wsRead(t, c, id)
	}
	full := get("full")
	room := full.Data["room"].(map[string]any)
	battle := room["battle"].(map[string]any)
	if battle["shot"] == nil {
		t.Fatal("first state elided shot")
	}
	wsSend(t, c, streamRequest{Type: "cache", BattleID: battleID, ShotID: 9})
	small := get("cached")
	cached := small.Data["room"].(map[string]any)["battle"].(map[string]any)
	if cached["shot"] != nil || cached["shot_ref"] == nil {
		t.Fatal("cached state repeated immutable shot")
	}
	fullBytes, _ := json.Marshal(full)
	smallBytes, _ := json.Marshal(small)
	if len(smallBytes) > len(fullBytes)/3 {
		t.Fatalf("cache did not reduce payload: %d / %d", len(smallBytes), len(fullBytes))
	}
	c.CloseNow()
	c = wsDial(t, srv, token)
	fresh := get("fresh")
	if fresh.Data["room"].(map[string]any)["battle"].(map[string]any)["shot"] == nil {
		t.Fatal("reconnect omitted full shot")
	}
}

func TestReceiptsDoNotRepeatFireOrConsumeTwice(t *testing.T) {
	for _, action := range []string{"fire", "item"} {
		t.Run(action, func(t *testing.T) {
			w, r, host, _ := loadingRoom(t, false, false)
			a := &api{world: w, receipts: map[string]commandReceipt{}}
			if action == "item" {
				if _, err := w.store.buy(host, 2, 0, false); err != nil {
					t.Fatal(err)
				}
				r.Battle.Units[0].HP = 100
			}
			c := Command{Action: action, Generation: r.Battle.Generation, RequestID: "lost-reply", Angle: 45, Power: .6, Weapon: 1, Slot: 0, AimMode: "native", AimFace: 1}
			w.mu.Lock()
			status, message := a.applyCommand(host, c)
			generation := r.Battle.Generation
			shot := r.Battle.Shot
			sp := r.Battle.Units[0].SP
			hp := r.Battle.Units[0].HP
			again, err := a.applyCommand(host, c)
			w.mu.Unlock()
			if status != 200 || again != 200 || err != "" {
				t.Fatalf("first=%d %s retry=%d %s", status, message, again, err)
			}
			if r.Battle.Generation != generation || r.Battle.Shot != shot || r.Battle.Units[0].SP != sp || r.Battle.Units[0].HP != hp {
				t.Fatal("receipt replay repeated the action")
			}
			if action == "item" {
				profile, _ := w.store.profile(host)
				if profile.Inventory[0] != 0 {
					t.Fatal("item not consumed")
				}
			}
		})
	}
}
