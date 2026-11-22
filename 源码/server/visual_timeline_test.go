package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func TestVisualTimelineMatchesNativeImpactsAndLandings(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	terrain, e := loadTerrain("../client/assets", 9)
	if e != nil {
		t.Fatal(e)
	}
	b.ID, b.Map, b.Width, b.Height, b.Terrain = "native-impact-visual-fixture", 9, terrain.W, terrain.H, terrain
	b.Units[0].X = 700
	b.Units[0].Y = terrain.ground(700, 100)
	b.Units[0].updateSlope(terrain)
	// Put the second tank at the first native shell's actual ground contact.
	_, impact, ok := b.trajectory(b.Units[0], 35, .35, vehicle(1).Weapons[0])
	if !ok {
		t.Fatal("fixture did not contact original terrain")
	}
	b.Units[1].X = impact.X
	b.Units[1].Y = terrain.ground(impact.X, int(impact.Y)-20)
	b.Units[1].updateSlope(terrain)
	if e := b.fireWorld(35, .35, 0, true); e != nil {
		t.Fatal(e)
	}
	shot := b.Shot
	if len(shot.Visuals) < 2 || len(shot.Cuts) == 0 {
		t.Fatal("missing impact visual checkpoints")
	}
	if shot.Visuals[0].At != 0 || shot.Visuals[0].Holes != 0 {
		t.Fatal("initial visual state already destroyed terrain")
	}
	damaged, fell := false, false
	for i, frame := range shot.Visuals {
		if i > 0 && frame.At <= shot.Visuals[i-1].At {
			t.Fatal("visual timestamps are not increasing")
		}
		var actual *ShotState
		for j := range shot.States {
			if math.Abs(shot.States[j].At-frame.At) < .00001 {
				actual = &shot.States[j]
				break
			}
		}
		if actual == nil || frame.Holes != actual.Holes-shot.HoleBase {
			t.Fatal("crater and simulation checkpoint differ")
		}
		for j, u := range frame.Units {
			if u != visualUnit(actual.Units[j]) {
				t.Fatal("visual health/status differs from authority")
			}
		}
		for _, number := range frame.Numbers {
			if number.Delta < 0 {
				damaged = true
			}
			previous := shot.Visuals[i-1]
			for j, u := range frame.Units {
				if u.Seat == number.Seat && u.HP-previous.Units[j].HP != number.Delta {
					t.Fatal("floating damage is not actual HP delta")
				}
			}
		}
	}
	for _, frame := range shot.Motion {
		for _, pose := range frame.Poses {
			if pose[4] == 1 {
				fell = true
			}
		}
	}
	if !damaged || !fell {
		t.Fatalf("fixture must cover damage and falling: damage=%v fall=%v", damaged, fell)
	}
	// Visual publication must not advance the commandable battle ahead of time.
	if len(b.Holes) != 0 || b.Units[1].HP != 370 {
		t.Fatal("visual preparation changed live authority")
	}
	wire, e := json.Marshal(shot)
	if e != nil {
		t.Fatal(e)
	}
	var public map[string]any
	if e = json.Unmarshal(wire, &public); e != nil {
		t.Fatal(e)
	}
	if _, ok := public["states"]; ok {
		t.Fatal("private simulation checkpoints published")
	}
	if path := os.Getenv("BCHD_VISUAL_FIXTURE"); path != "" {
		shot.Started = 100.0
		data, e := json.MarshalIndent(b, "", "  ")
		if e != nil {
			t.Fatal(e)
		}
		if e = os.WriteFile(path, data, 0600); e != nil {
			t.Fatal(e)
		}
	}
}

func TestDepartureDuringShotSurvivesPresentationAndCheckpointAdvance(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	if e := b.fireWorld(35, .35, 0, true); e != nil {
		t.Fatal(e)
	}
	r := &Room{ID: 1, Owner: 1, Battle: b, Members: []*Member{{ID: 1, Seat: 0}, {ID: 2, Seat: 4}}}
	w := &World{rooms: map[int]*Room{1: r}}
	w.leave(1)
	if !b.Units[0].Departed || b.Units[0].HP != 0 || !b.pending.Units[0].Departed {
		t.Fatal("departure not represented in live and pending units")
	}
	b.advanceShot(b.Shot.Started + b.Shot.Duration + .1)
	if !b.Units[0].Departed || b.Units[0].HP != 0 {
		t.Fatal("shot checkpoint resurrected a departed participant")
	}
	if r.Owner != 2 || len(r.Members) != 1 {
		t.Fatal("remaining participant lost room ownership")
	}
}
