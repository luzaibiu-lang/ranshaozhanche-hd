package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestWalkingAcknowledgementIsIdempotentAndTurnBound(t *testing.T) {
	s, e := openStore(filepath.Join(t.TempDir(), "qa.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer s.db.Close()
	p, e := s.register("walk_ack", "test-password-895432")
	if e != nil {
		t.Fatal(e)
	}
	w, e := newWorld(s, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	b := flatBattle()
	b.Units[0].Player = p.ID
	r := &Room{ID: 1, Owner: p.ID, Battle: b, Members: []*Member{{ID: p.ID, Seat: 0}}}
	w.rooms[1] = r
	c := Command{Action: "move", Distance: 12, MoveSequence: 1, Generation: b.Generation}
	if e = w.command(p.ID, c); e != nil {
		t.Fatal(e)
	}
	if b.Units[0].X != 312 || b.Units[0].MoveSequence != 1 {
		t.Fatal("walk not acknowledged")
	}
	sp, spent := b.Units[0].SP, b.Units[0].MoveSpent
	if e = w.command(p.ID, c); e != nil {
		t.Fatal(e)
	}
	if b.Units[0].X != 312 || b.Units[0].SP != sp || b.Units[0].MoveSpent != spent {
		t.Fatal("duplicate move charged or moved twice")
	}
	c.MoveSequence = 2
	c.Distance = -5
	if e = w.command(p.ID, c); e != nil {
		t.Fatal(e)
	}
	if b.Units[0].X != 307 || b.Units[0].Face != -1 {
		t.Fatal("direction change lost")
	}
	b.Generation++
	c.MoveSequence = 3
	if w.command(p.ID, c) == nil || b.Units[0].X != 307 {
		t.Fatal("old-turn move was applied")
	}
	b.Deadline = nowSeconds() - .01
	for _, action := range []string{"move", "fire", "pass", "item"} {
		c.Action, c.Generation = action, b.Generation
		if w.command(p.ID, c) == nil {
			t.Fatalf("expired turn accepted %s before next ticker", action)
		}
	}
}

func TestFallOutCueUsesNativeDeathTimeOnce(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	b.Units[0].Y = 950
	b.Units[0].X = 300
	clear(b.Terrain.Solid)
	initial := b.copy()
	shot := &Shot{Trails: []Trail{}, Impacts: []Impact{}}
	b.recordShotState(shot, 0)
	for tick := 1; tick <= 240 && b.Units[0].HP > 0; tick++ {
		if changed, _ := b.nativeFalls(); changed {
			b.recordShotState(shot, float64(tick)/60)
		}
	}
	b.prepareShotVisuals(shot, 0)
	cues := 0
	for _, v := range shot.Visuals {
		for _, f := range v.Falls {
			if f.Seat == 0 {
				cues++
				if f.Vehicle != 1 || v.At <= 0 {
					t.Fatal("fall cue identity/time lost")
				}
			}
		}
	}
	if cues != 1 {
		t.Fatalf("fall cue count=%d", cues)
	}
	if path := os.Getenv("BCHD_FALL_FIXTURE"); path != "" {
		shot.ID = 1
		shot.Started = 100
		shot.Duration = shot.Motion[len(shot.Motion)-1].At
		initial.Map = 9
		initial.Shot = shot
		initial.Deadline = 0
		data, e := json.Marshal(initial)
		if e != nil {
			t.Fatal(e)
		}
		if e = os.WriteFile(path, data, 0600); e != nil {
			t.Fatal(e)
		}
	}
}
