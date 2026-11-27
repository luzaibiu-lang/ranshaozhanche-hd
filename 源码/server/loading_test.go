package main

import (
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func loadingRoom(t *testing.T, hostSupports, guestSupports bool) (*World, *Room, int64, int64) {
	t.Helper()
	store, err := openStore(filepath.Join(t.TempDir(), "loading.sqlite3"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.db.Close() })
	w, err := newWorld(store, "../client/assets")
	if err != nil {
		t.Fatal(err)
	}
	a, err := store.register("loading_host", "test-only-password")
	if err != nil {
		t.Fatal(err)
	}
	b, err := store.register("loading_guest", "test-only-password")
	if err != nil {
		t.Fatal(err)
	}
	if err = w.command(a.ID, Command{Action: "create", Capacity: 8, LoadingBarrier: hostSupports}); err != nil {
		t.Fatal(err)
	}
	room, _ := w.roomFor(a.ID)
	if err = w.command(b.ID, Command{Action: "join", Room: room.ID, LoadingBarrier: guestSupports}); err != nil {
		t.Fatal(err)
	}
	if err = w.command(a.ID, Command{Action: "start"}); err != nil {
		t.Fatal(err)
	}
	return w, room, a.ID, b.ID
}

func TestBattleWaitsForEachLoadingPlayer(t *testing.T) {
	w, r, host, guest := loadingRoom(t, true, true)
	b := r.Battle
	if b.Map < 1 || b.Map > 19 || r.Map != 0 || !b.Loading || b.Deadline != 0 || !b.aiAt.IsZero() ||
		!slices.Equal(b.LoadingSeats, []int{0, 4}) {
		t.Fatalf("unexpected starting state: map=%d loading=%v deadline=%v seats=%v", b.Map, b.Loading, b.Deadline, b.LoadingSeats)
	}
	for _, action := range []string{"move", "fire", "pass", "item"} {
		if err := w.command(host, Command{Action: action, Generation: b.Generation}); err == nil {
			t.Fatalf("%s accepted before loading", action)
		}
	}
	if err := w.command(guest, Command{Action: "battle_loaded", BattleID: "old-battle"}); err == nil {
		t.Fatal("stale battle confirmation accepted")
	}
	ack := Command{Action: "battle_loaded", BattleID: b.ID}
	for range 2 {
		if err := w.command(host, ack); err != nil {
			t.Fatal(err)
		}
	}
	// Even a past action deadline and a due AI cannot advance a loading battle.
	b.Deadline = nowSeconds() - 5
	b.Units[0].AI = 1
	b.aiAt = time.Now().Add(-time.Second)
	w.tick()
	if !b.Loading || b.Generation != 1 || b.Active != 0 || b.Shot != nil || b.aiAction != nil ||
		!slices.Equal(b.LoadingSeats, []int{4}) {
		t.Fatal("battle changed before the guest confirmed")
	}
	b.Units[0].AI = 0
	before := nowSeconds()
	if err := w.command(guest, ack); err != nil {
		t.Fatal(err)
	}
	if b.Loading || b.LoadingDeadline != 0 || len(b.LoadingSeats) != 0 ||
		b.Deadline < before+35 || b.Deadline > nowSeconds()+35 || !b.aiAt.After(time.Now()) {
		t.Fatalf("first turn did not start with a fresh timer: deadline=%v", b.Deadline)
	}
	deadline := b.Deadline
	if err := w.command(guest, ack); err != nil || b.Deadline != deadline {
		t.Fatalf("retry changed first-turn timer: %v", err)
	}
	if err := w.command(host, Command{Action: "pass", Generation: b.Generation}); err != nil {
		t.Fatal(err)
	}
	if b.Active != 4 || b.Round != 1 || b.Generation != 2 {
		t.Fatal("normal first-round rotation did not resume")
	}
}

func TestLoadingBarrierAllowsLegacyClients(t *testing.T) {
	w, r, _, guest := loadingRoom(t, false, true)
	b := r.Battle
	if !slices.Equal(b.LoadingSeats, []int{4}) {
		t.Fatalf("legacy host was asked to confirm loading: %v", b.LoadingSeats)
	}
	if err := w.command(guest, Command{Action: "battle_loaded", BattleID: b.ID}); err != nil {
		t.Fatal(err)
	}
	if b.Loading || b.Deadline <= nowSeconds() {
		t.Fatal("legacy host prevented game start")
	}
	_, r, _, _ = loadingRoom(t, false, false)
	if r.Battle.Loading || r.Battle.Deadline <= nowSeconds() {
		t.Fatal("legacy-only room did not start immediately")
	}
}

func TestBattleLoadingTimeoutAndLeaveReturnToRoom(t *testing.T) {
	w, r, host, guest := loadingRoom(t, true, true)
	expired := r.Battle.ID
	r.Battle.LoadingDeadline = nowSeconds() - 1
	w.tick()
	if r.Battle != nil || len(r.Chat) != 1 {
		t.Fatal("loading timeout did not return to the room with a message")
	}
	if err := w.command(host, Command{Action: "start"}); err != nil {
		t.Fatalf("could not start again after loading timeout: %v", err)
	}
	if err := w.command(guest, Command{Action: "battle_loaded", BattleID: expired}); err == nil {
		t.Fatal("previous match confirmation accepted after retry")
	}
	if err := w.command(guest, Command{Action: "leave"}); err != nil {
		t.Fatal(err)
	}
	if r.Battle != nil || len(r.Members) != 1 || len(r.Chat) != 2 {
		t.Fatal("departure did not cancel loading")
	}
	p, err := w.store.profile(host)
	if err != nil || p.Games != 0 {
		t.Fatalf("cancelled match changed player records: %+v, %v", p, err)
	}
}
