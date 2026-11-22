package main

import (
	"path/filepath"
	"testing"
	"time"
)

func TestLobbyPresenceTracksPollingAndExpiresWithoutSessions(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "presence.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	p, e := s.register("presence_test", "qa-only-895432")
	if e != nil {
		t.Fatal(e)
	}
	w := &World{store: s, rooms: map[int]*Room{}, sessions: map[string]Session{}, version: 1}
	w.touchPresence(p.ID)
	version := w.version
	w.touchPresence(p.ID)
	if w.version != version || len(w.presence) != 1 {
		t.Fatal("polling duplicated presence or invalidated every ETag")
	}
	state, e := w.snapshot(p.ID)
	if e != nil || len(state.Players) != 1 || state.Players[0].Name != p.Name {
		t.Fatal("lobby omitted online player", e)
	}
	w.presence[p.ID].Seen = time.Now().Add(-76 * time.Second)
	w.tick()
	if len(w.presence) != 0 || w.version <= version {
		t.Fatal("offline player remained in list")
	}
}
