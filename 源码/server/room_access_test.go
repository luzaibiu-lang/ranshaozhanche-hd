package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPrivateRoomAndRecipientBoundInvitation(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "room.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	w, e := newWorld(s, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	players := []int64{}
	for _, name := range []string{"room_owner", "room_guest", "room_other"} {
		p, e := s.register(name, "qa-only-895432")
		if e != nil {
			t.Fatal(e)
		}
		players = append(players, p.ID)
		w.touchPresence(p.ID)
	}
	owner, guest, other := players[0], players[1], players[2]
	if e = w.command(owner, Command{Action: "create", Name: "私人房间", Capacity: 8, Map: 4, Private: true, Password: "qa-room-123"}); e != nil {
		t.Fatal(e)
	}
	r, _ := w.roomFor(owner)
	state, e := w.snapshot(guest)
	if e != nil {
		t.Fatal(e)
	}
	encoded, _ := json.Marshal(state)
	if !r.Locked || strings.Contains(string(encoded), "qa-room-123") || strings.Contains(string(encoded), "PasswordHash") {
		t.Fatal("room lock or public snapshot exposed password")
	}
	if e = w.command(guest, Command{Action: "join", Room: r.ID, Password: "wrong"}); e == nil {
		t.Fatal("private room accepted wrong password")
	}
	if current, _ := w.roomFor(guest); current != nil || len(r.Members) != 1 {
		t.Fatal("rejected join mutated membership")
	}
	if e = w.command(owner, Command{Action: "invite", Player: guest}); e != nil {
		t.Fatal(e)
	}
	state, e = w.snapshot(guest)
	if e != nil || state.Invitation == nil || state.Invitation.Room != r.ID {
		t.Fatal("recipient did not receive invitation", e)
	}
	state, e = w.snapshot(other)
	if e != nil || state.Invitation != nil {
		t.Fatal("invitation leaked to another player", e)
	}
	if e = w.command(other, Command{Action: "accept_invite", Room: r.ID}); e == nil {
		t.Fatal("uninvited player bypassed room password")
	}
	if e = w.command(guest, Command{Action: "accept_invite", Room: r.ID}); e != nil {
		t.Fatal(e)
	}
	if current, _ := w.roomFor(guest); current != r {
		t.Fatal("accepted invitation did not join actual room")
	}
	if _, ok := w.invites[guest]; ok {
		t.Fatal("accepted invite can be reused")
	}
	if e = w.command(owner, Command{Action: "invite", Player: guest}); e == nil {
		t.Fatal("invited a player who is already in a room")
	}
	if e = w.command(owner, Command{Action: "invite", Player: other}); e != nil {
		t.Fatal(e)
	}
	v := w.invites[other]
	v.Expires = nowSeconds() - 1
	w.invites[other] = v
	if e = w.command(other, Command{Action: "accept_invite", Room: r.ID}); e == nil {
		t.Fatal("expired invitation bypassed password")
	}
	w.tick()
	if _, ok := w.invites[other]; ok {
		t.Fatal("expired invitation not removed")
	}
	if e = w.command(other, Command{Action: "join", Room: r.ID, Password: "qa-room-123"}); e != nil {
		t.Fatal("correct private password rejected", e)
	}
	w.presence[other].Seen = time.Now().Add(-76 * time.Second)
}
