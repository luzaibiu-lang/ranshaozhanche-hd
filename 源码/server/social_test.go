package main

import (
	"path/filepath"
	"testing"
)

func TestOriginalPrivacyControlsPersistAndWhispersStayPrivate(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "social.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	w, e := newWorld(s, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	ids := []int64{}
	for _, name := range []string{"social_owner", "social_guest", "social_other"} {
		p, e := s.register(name, "qa-only-895432")
		if e != nil {
			t.Fatal(e)
		}
		ids = append(ids, p.ID)
		w.touchPresence(p.ID)
	}
	owner, guest, other := ids[0], ids[1], ids[2]
	if e = w.command(owner, Command{Action: "chat", Text: "/w social_guest hello"}); e != nil {
		t.Fatal(e)
	}
	for _, id := range []int64{owner, guest} {
		state, e := w.snapshot(id)
		if e != nil || len(state.Whispers) != 1 || len(state.Chat) != 0 {
			t.Fatal("private message failed recipient routing", e)
		}
	}
	state, _ := w.snapshot(other)
	if len(state.Whispers) != 0 || len(state.Chat) != 0 {
		t.Fatal("private message leaked to an unrelated player")
	}
	if e = w.command(guest, Command{Action: "preferences", RejectPrivate: true, RejectInvites: true}); e != nil {
		t.Fatal(e)
	}
	p, e := s.profile(guest)
	if e != nil || !p.RejectPrivate || !p.RejectInvites {
		t.Fatal("privacy settings were not persisted", e)
	}
	if e = w.command(owner, Command{Action: "chat", Text: "/w social_guest rejected"}); e == nil {
		t.Fatal("refused private message delivered")
	}
	if len(w.whispers[guest]) != 1 {
		t.Fatal("rejected whisper changed recipient inbox")
	}
	if e = w.command(owner, Command{Action: "create", Name: "social room", Capacity: 8, Map: 4}); e != nil {
		t.Fatal(e)
	}
	if e = w.command(owner, Command{Action: "invite", Player: guest}); e == nil {
		t.Fatal("refused room invitation delivered")
	}
	if e = w.command(guest, Command{Action: "preferences"}); e != nil {
		t.Fatal(e)
	}
	if e = w.command(owner, Command{Action: "invite", Player: guest}); e != nil {
		t.Fatal("re-enabled invitation did not work", e)
	}
	if e = w.command(guest, Command{Action: "preferences", RejectInvites: true}); e != nil {
		t.Fatal(e)
	}
	state, _ = w.snapshot(guest)
	if state.Invitation != nil {
		t.Fatal("new refusal did not clear a pending invitation")
	}
}
