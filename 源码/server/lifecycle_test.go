package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRememberedSessionSurvivesRestartAndLogoutRevokes(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "session.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	p, e := s.register("remember_test", "test-password-895432")
	if e != nil {
		t.Fatal(e)
	}
	raw := token()
	if e = s.createSession(raw, p.ID, time.Now().Add(time.Hour)); e != nil {
		t.Fatal(e)
	}
	var stored string
	s.db.QueryRow("SELECT hash FROM sessions").Scan(&stored)
	if stored == raw || len(stored) != 64 {
		t.Fatal("session bearer stored without hashing")
	}
	w, e := newWorld(s, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	h := newHandler(w, "")
	request := func(path, body string) int {
		r := httptest.NewRequest(http.MethodGet, path, nil)
		if body != "" {
			r = httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
		}
		r.Header.Set("Authorization", "Bearer "+raw)
		out := httptest.NewRecorder()
		h.ServeHTTP(out, r)
		return out.Code
	}
	if request("/api/state", "") != 200 {
		t.Fatal("remembered session lost after restart")
	}
	if request("/api/logout", "{}") != 200 || request("/api/state", "") != 401 {
		t.Fatal("logout did not revoke session")
	}
	if _, ok := s.session(raw); ok {
		t.Fatal("revoked credential survived in database")
	}
}

func TestRoomMatchSettlementReturnAndSecondMatch(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "match.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	w, e := newWorld(s, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	a, _ := s.register("match_owner", "test-password-895432")
	b, _ := s.register("match_friend", "test-password-895432")
	command := func(id int64, c Command) {
		t.Helper()
		if e := w.command(id, c); e != nil {
			t.Fatalf("%s: %v", c.Action, e)
		}
	}
	command(a.ID, Command{Action: "create", Map: 4, Capacity: 8})
	r, _ := w.roomFor(a.ID)
	command(b.ID, Command{Action: "join", Room: r.ID})
	command(a.ID, Command{Action: "settings", Map: 9})
	snapshot, _ := w.snapshot(b.ID)
	if snapshot.Room.Map != 9 {
		t.Fatal("owner map not synchronized")
	}
	bots := make([]BotChoice, 16)
	for i := range bots {
		bots[i].Seat = i
	}
	bots[8] = BotChoice{8, 3, 30}
	bots[12] = BotChoice{12, 1, 0}
	command(a.ID, Command{Action: "bots", Bots: bots})
	for match := 0; match < 2; match++ {
		command(a.ID, Command{Action: "vehicle", Vehicle: 30 - match})
		command(a.ID, Command{Action: "start"})
		battle := r.Battle
		if battle.Map != 9 || len(battle.Units) != 4 {
			t.Fatal("bad match state")
		}
		for _, u := range battle.Units {
			if u.SP != 150 {
				t.Fatal("starting SP changed")
			}
		}
		// A spectator's death must not stop AI-vs-AI turns. Human is retained in
		// the room while the authoritative match keeps progressing.
		battle.Units[0].HP = 0
		battle.Units[1].HP = 0
		battle.Active = 8
		turns := 0
		for battle.Result == nil && turns < 250 {
			battle.aiAt = time.Now().Add(-time.Second)
			w.tick()
			finishAIWalkForTest(t, w, battle)
			if battle.pending != nil {
				battle.busyUntil = time.Now().Add(-time.Second)
				w.tick()
			}
			if battle.Result == nil && battle.Active < 8 {
				t.Fatal("dead human stalled AI match")
			}
			turns++
		}
		if battle.Result == nil {
			t.Fatal("AI match never finished")
		}
		data, _ := json.Marshal(battle)
		if len(data) > 4*1024*1024 {
			t.Fatal("unbounded snapshot")
		}
		before, _ := s.profile(a.ID)
		w.finish(r, -1, "duplicate")
		after, _ := s.profile(a.ID)
		if before.Gold != after.Gold || before.Games != match+1 {
			t.Fatal("settlement duplicated")
		}
		command(a.ID, Command{Action: "return"})
		snapshot, _ = w.snapshot(a.ID)
		if snapshot.Room.Battle != nil {
			t.Fatal("returned player remained trapped in result")
		}
		if e := w.command(a.ID, Command{Action: "start"}); e == nil {
			t.Fatal("started before friend returned")
		}
		command(b.ID, Command{Action: "return"})
		if r.Battle != nil {
			t.Fatal("match state leaked into room")
		}
	}
}
