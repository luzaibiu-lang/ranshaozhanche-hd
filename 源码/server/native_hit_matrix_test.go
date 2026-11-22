package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func impactMatrixBattle(id int, targetX float64, hp int) *Battle {
	terrain := &Terrain{W: 1800, H: 1600, Solid: make([]byte, 1800*1600)}
	for y := 800; y < terrain.H; y++ {
		for x := 0; x < terrain.W; x++ {
			terrain.Solid[y*terrain.W+x] = 1
		}
	}
	actor := &Unit{Seat: 0, Player: 1, Name: "射击测试", Vehicle: id, X: 250, Y: 800, HP: 1000000, MaxHP: 1000000, SP: 200, Move: 100, Face: 1, Aim: 35, Elevation: 35}
	b := &Battle{ID: fmt.Sprintf("hit-matrix-%02d", id), Map: 9, Width: terrain.W, Height: terrain.H, Terrain: terrain, NativeAim: true, Units: []*Unit{actor}, Holes: []Hole{}, Round: 1, Active: 0, Generation: 1}
	if targetX > 0 {
		b.Units = append(b.Units, &Unit{Seat: 4, Player: 2, Name: "命中目标", Team: 1, Vehicle: 1, X: targetX, Y: 800, HP: hp, MaxHP: hp, SP: 150, Move: 100, Face: -1, Aim: 145, Elevation: 35})
	}
	return b
}

func TestAllNinetyNativeWeaponsDamageAndPublishImpacts(t *testing.T) {
	type evidenceRow struct {
		Vehicle, Slot, Logical, Projectile int
		Power, TargetX, Duration           float64
		Damage, Impacts, Holes, FallFrames int
		Battle                             *Battle `json:"battle,omitempty"`
	}
	rows := []evidenceRow{}
	for id := 1; id <= 30; id++ {
		for slot, w := range vehicle(id).Weapons {
			t.Run(fmt.Sprintf("vehicle%02d/slot%d", id, slot), func(t *testing.T) {
				var landed *Battle
				var shot *Shot
				power, targetX := 0.0, 0.0
				for _, charge := range []float64{.35, .5, .25, .65} {
					probe := impactMatrixBattle(id, 0, 0)
					probeShot := &Shot{}
					probe.nativeVolley(probe.Units[0], 35, charge, w, 0, probeShot)
					for _, impact := range probeShot.Impacts {
						if impact.X < 330 || impact.X > 1500 || impact.Kind == "heal" {
							continue
						}
						candidate := impactMatrixBattle(id, impact.X, 1000000)
						attempt := &Shot{ID: 1, Started: 100, Actor: 0, Trails: []Trail{}, Impacts: []Impact{}}
						candidate.recordShotState(attempt, 0)
						candidate.nativeVolley(candidate.Units[0], 35, charge, w, 0, attempt)
						if candidate.Units[1].HP < 1000000 {
							landed, shot, power, targetX = candidate, attempt, charge, impact.X
							break
						}
					}
					if landed != nil {
						break
					}
				}
				if landed == nil {
					t.Fatalf("logical %d projectile %d never damaged a supported live target", w.NativeID, w.Projectile)
				}
				landed.prepareShotVisuals(shot, 0)
				maximum := w.Count
				switch w.Projectile {
				case 3, 43:
					maximum = 6
				case 42:
					maximum = 4
				case 72:
					maximum = 2
					if w.NativeID == 72 {
						maximum = 7
					}
				case 5:
					maximum = 7
				case 10:
					maximum = 9
				case 25:
					maximum = 5
				case 58:
					maximum = 2 // carrier impact plus a distinct healing drop
				}
				if len(shot.Impacts) > maximum {
					t.Fatalf("logical %d repeated damage beyond native object/wave count: impacts=%d native maximum=%d", w.NativeID, len(shot.Impacts), maximum)
				}
				// Native logical10's small ground flames deliberately leave
				// terrain intact; its logical11 stronger flame does carve.
				wantCrater := w.NativeID != 10
				if len(shot.Impacts) == 0 || (len(landed.Holes) > 0) != wantCrater {
					t.Fatalf("logical %d has damage but lacks explosion/crater: impacts=%d holes=%d", w.NativeID, len(shot.Impacts), len(landed.Holes))
				}
				numbers, delta, previousHole := 0, 0, 0
				for _, frame := range shot.Visuals {
					if frame.Holes < previousHole {
						t.Fatal("visible crater count moved backwards")
					}
					previousHole = frame.Holes
					for _, number := range frame.Numbers {
						if number.Seat == 4 {
							numbers++
							delta += number.Delta
						}
					}
				}
				if numbers == 0 || delta != landed.Units[1].HP-1000000 {
					t.Fatalf("damage timeline/number mismatch: numbers=%d delta=%d actual=%d", numbers, delta, landed.Units[1].HP-1000000)
				}
				falls := 0
				for _, frame := range shot.Motion {
					for _, pose := range frame.Poses {
						if int(pose[0]) == 4 && pose[4] != 0 {
							falls++
						}
					}
				}
				initial := impactMatrixBattle(id, targetX, 1000000)
				initial.Shot = shot
				initial.Terrain = nil
				rows = append(rows, evidenceRow{id, slot, w.NativeID, w.Projectile, power, targetX, shot.Duration, 1000000 - landed.Units[1].HP, len(shot.Impacts), len(landed.Holes), falls, initial})
			})
		}
	}
	if folder := os.Getenv("HD_HIT_EVIDENCE"); folder != "" {
		if err := os.MkdirAll(folder, 0755); err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(rows)
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(folder, "native-hit-matrix.json"), data, 0644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestNativeSweepCatchesSkippedThinTerrainAndVehicle(t *testing.T) {
	for _, kind := range []string{"thin wall", "live tank", "dead tank"} {
		t.Run(kind, func(t *testing.T) {
			b := &Battle{Width: 300, Height: 200, Terrain: &Terrain{W: 300, H: 200, Solid: make([]byte, 300*200)}}
			if kind == "thin wall" {
				b.Terrain.Solid[100*300+150] = 1
			} else {
				hp := 300
				if kind == "dead tank" {
					hp = 0
				}
				b.Units = []*Unit{{X: 150, Y: 100, HP: hp}}
			}
			p := &nativeFlying{w: Weapon{Projectile: 101}, x: 190, y: 100}
			if b.nativeHit(p) {
				t.Fatal("fixture must reproduce a missed endpoint")
			}
			x, y, hit := b.nativeHitAlong(p, 110, 100)
			if hit != (kind != "dead tank") {
				t.Fatalf("swept contact=%v at %.2f,%.2f", hit, x, y)
			}
			if hit && (x >= 150 || math.Abs(y-100) > .01) {
				t.Fatalf("missed entry side: %.3f,%.3f", x, y)
			}
		})
	}
	// Source endpoint impacts retain their original tick and coordinate.
	b := &Battle{Width: 300, Height: 200, Terrain: &Terrain{W: 300, H: 200, Solid: make([]byte, 300*200)}, Units: []*Unit{{X: 190, Y: 100, HP: 300}}}
	p := &nativeFlying{x: 190, y: 100}
	if x, y, hit := b.nativeHitAlong(p, 110, 100); !hit || x != 190 || y != 100 {
		t.Fatal("existing native endpoint impact was changed")
	}
}
