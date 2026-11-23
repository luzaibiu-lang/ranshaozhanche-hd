package main

import (
	"path/filepath"
	"testing"
)

func TestReturnedMembersCanConfigureBeforeEveryoneReturns(t *testing.T) {
	s, err := openStore(filepath.Join(t.TempDir(), "rooms.sqlite3"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.db.Close() })
	w, err := newWorld(s, "../client/assets")
	if err != nil {
		t.Fatal(err)
	}
	player := func(name string) int64 {
		t.Helper()
		p, err := s.register(name, "test-password-895432")
		if err != nil {
			t.Fatal(err)
		}
		return p.ID
	}
	owner, friend, last := player("return_owner"), player("return_friend"), player("return_last")
	cmd := func(id int64, c Command) {
		t.Helper()
		if err := w.command(id, c); err != nil {
			t.Fatalf("player %d %s: %v", id, c.Action, err)
		}
	}
	reject := func(id int64, c Command) {
		t.Helper()
		if err := w.command(id, c); err == nil {
			t.Fatalf("player %d unexpectedly allowed %s", id, c.Action)
		}
	}
	view := func(id int64, phase string, waiting int) *Room {
		t.Helper()
		state, err := w.snapshot(id)
		if err != nil {
			t.Fatal(err)
		}
		if len(state.Rooms) != 1 || state.Rooms[0]["phase"] != phase || state.Rooms[0]["waiting_returns"] != waiting || state.Rooms[0]["started"] != (phase != "waiting") {
			t.Fatalf("unexpected list state: %+v", state.Rooms)
		}
		return state.Room
	}
	cmd(owner, Command{Action: "create", Map: 1})
	r, _ := w.roomFor(owner)
	for _, id := range []int64{friend, last} {
		cmd(id, Command{Action: "join", Room: r.ID})
	}
	_, m := w.roomFor(friend)
	cmd(last, Command{Action: "seat", Seat: 12})
	cmd(last, Command{Action: "ready", Ready: true})
	cmd(owner, Command{Action: "start"})
	battle := r.Battle
	buy := Command{Action: "buy", Item: 1, Slot: 0}
	reject(friend, buy)
	cmd(friend, Command{Action: "chat", Text: "battle chat"})
	if got := view(owner, "battle", 0).Chat; len(got) != 1 || got[0].Text != "battle chat" {
		t.Fatalf("battle chat missing: %+v", got)
	}
	w.finish(r, 0, "test")
	reject(friend, buy)
	reject(friend, Command{Action: "ready", Ready: false})
	cmd(friend, Command{Action: "return"})
	if view(friend, "settlement", 2).Battle != nil || view(last, "settlement", 2).Battle != battle || !m.Ready {
		t.Fatal("settlement must remain visible only to unreturned players")
	}
	cmd(friend, Command{Action: "ready", Ready: false})
	cmd(friend, Command{Action: "return"})
	if m.Ready {
		t.Fatal("repeated return overwrote player's choice")
	}
	for _, change := range []Command{buy, {Action: "sell", Slot: 0}, {Action: "outfit", Outfit: 0}, {Action: "vehicle", Vehicle: 2}, {Action: "seat", Seat: 8}} {
		cmd(friend, Command{Action: "ready", Ready: true})
		cmd(friend, change)
		if m.Ready {
			t.Fatalf("%s failed to clear ready", change.Action)
		}
	}
	cmd(friend, Command{Action: "ready", Ready: true})
	reject(friend, Command{Action: "sell", Slot: 0})
	if !m.Ready {
		t.Fatal("failed purchase/sale cleared ready")
	}
	cmd(friend, Command{Action: "ready", Ready: false})
	cmd(owner, Command{Action: "return"})
	bots := make([]BotChoice, 16)
	for i := range bots {
		bots[i].Seat = i
	}
	bots[4] = BotChoice{Seat: 4, Level: 2, Vehicle: 1}
	cmd(owner, Command{Action: "settings", Map: 2})
	cmd(owner, Command{Action: "bots", Bots: bots})
	reject(owner, Command{Action: "start"})
	ownerHP := battle.Units[0].HP
	cmd(owner, Command{Action: "leave"})
	if r.Owner != friend || view(last, "settlement", 1).Battle != battle || battle.Units[0].Departed || battle.Units[0].HP != ownerHP {
		t.Fatal("owner departure corrupted settlement or ownership transfer")
	}
	reject(friend, Command{Action: "start"})
	cmd(last, Command{Action: "return"})
	if view(last, "waiting", 0).Battle != nil || m.Returned || m.Ready {
		t.Fatal("final return overwrote another player's choice or left battle behind")
	}
	cmd(last, Command{Action: "ready", Ready: false})
	reject(friend, Command{Action: "start"})
	cmd(last, Command{Action: "ready", Ready: true})
	cmd(friend, Command{Action: "start"})
	if r.Battle == battle || r.Battle.Map != 2 || len(r.Battle.Units) != 3 {
		t.Fatal("second battle did not use the new room configuration")
	}
	w.finish(r, 0, "test")
	cmd(friend, Command{Action: "return"})
	cmd(last, Command{Action: "leave"})
	if view(friend, "waiting", 0).Battle != nil {
		t.Fatal("last unreturned player leaving did not clear settlement")
	}
}
