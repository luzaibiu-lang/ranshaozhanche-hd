package main

import (
	"encoding/json"
	"math"
	"os"
	"strconv"
	"testing"
)

func TestNativeHomingMapNineVolley(t *testing.T) {
	terrain, err := loadTerrain("../client/assets", 9)
	if err != nil {
		t.Fatal(err)
	}
	actor := &Unit{Seat: 0, Face: 1, Vehicle: 1, HP: 300, MaxHP: 300, SP: 500, X: 548}
	target := &Unit{Seat: 4, Team: 1, Face: -1, Vehicle: 1, HP: 300, MaxHP: 300, X: 897}
	b := &Battle{NativeAim: true, Units: []*Unit{actor, target}, Map: 9, Width: terrain.W, Height: terrain.H, Terrain: terrain, Wind: 26}
	for _, u := range b.Units {
		u.Y = terrain.ground(u.X, 735)
		b.nativeFallStep(u)
	}
	blocked := b.copy()
	if err := b.fireNative(42, 120.0/300, 2); err != nil {
		t.Fatal(err)
	}
	t.Logf("shooter=(%.0f,%.0f) inclination=%.0f target=(%.0f,%.0f) hp=%d, cues=%v impacts=%v", actor.X, actor.Y, actor.Slope, target.X, target.Y, b.pending.Units[1].HP, b.Shot.Cues, b.Shot.Impacts)
	if len(b.Shot.Trails) != 5 || len(b.Shot.Impacts) != 5 || len(b.Shot.Cues) != 1 || b.pending.Units[1].HP >= target.HP {
		t.Fatal("expected all five F3 projectiles, one airborne lock and damage to the target")
	}
	cue := b.Shot.Cues[0]
	if cue.Kind != "lock" || cue.Seat != target.Seat || cue.At != 41.0/60 {
		t.Fatalf("unexpected lock: %+v", cue)
	}
	index := -1
	for i, trail := range b.Shot.Trails {
		if trail.LockAt == 0 {
			continue
		}
		if index >= 0 || trail.LockAt != cue.At || trail.LockAt >= trail.Start+trail.Duration {
			t.Fatalf("incorrect per-shell lock timestamp: shell=%d at=%v", i, trail.LockAt)
		}
		index = i
	}
	if index < 0 {
		t.Fatal("lock sound has no corresponding guided projectile")
	}
	trail := b.Shot.Trails[index]
	point := trail.Points[int(math.Round((cue.At-trail.Start)*60))]
	// Touch the leading edge of the missile's 5px collision box exactly
	// on the acquisition tick. Other missiles may still fly independently.
	x, y := int(point[0]+.5)+5, int(point[1]+.5)
	blocked.Terrain.Solid[y*blocked.Width+x] = 1
	if err := blocked.fireNative(42, 120.0/300, 2); err != nil {
		t.Fatal(err)
	}
	stopped := blocked.Shot.Trails[index]
	if stopped.Start+stopped.Duration != cue.At || stopped.LockAt != 0 {
		t.Fatalf("shell terminated at %.3f (wanted %.3f) but reported lock at %.3f", stopped.Start+stopped.Duration, cue.At, stopped.LockAt)
	}
	for _, sound := range blocked.Shot.Cues {
		if sound.Kind == "lock" && sound.At == cue.At {
			t.Fatal("terrain impact triggered the lock sound")
		}
	}
}

func TestNativeHomingFromMuzzleThroughAcquisition(t *testing.T) {
	for _, id := range []int{18, 101} {
		t.Run(strconv.Itoa(id), func(t *testing.T) {
			var ref struct {
				Wind              int
				Charge, Elevation float64
				InitialTarget     [2]float64 `json:"initial_target"`
				PlacedAfter       int        `json:"target_placed_after_tick"`
				Trails            []struct {
					Speed          float64
					Muzzle, Target [2]float64
					EntryTick      int        `json:"entry_tick"`
					EntryPosition  [2]float64 `json:"entry_position"`
					EntryHeading   float64    `json:"entry_heading"`
					Samples        []struct {
						Tick, Mode int
						Position   [2]float64
					}
				}
			}
			data, err := os.ReadFile("testdata/native-homing-launch-" + strconv.Itoa(id) + ".json")
			if err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(data, &ref); err != nil {
				t.Fatal(err)
			}
			expected := 1
			if id == 18 {
				expected = 5
			}
			if len(ref.Trails) != expected {
				t.Fatalf("expected %d trails", expected)
			}
			// Vehicle 1's right-facing 35-degree muzzle is 15 px ahead
			// and 32 px above the foot point. Recover the falling shooter's
			// missing foot pose using that fixed offset, independent of nativeMuzzle.
			muzzle := ref.Trails[0].Muzzle
			actor := &Unit{Vehicle: 1, Face: 1, HP: 300, X: muzzle[0] - 15, Y: muzzle[1] + 32}
			nativeID := 101
			if id == 18 {
				nativeID = 21
			}
			w := Weapon{NativeID: nativeID, Projectile: id, Count: expected, Wind: 1, Kind: "homing"}
			terrain := &Terrain{W: 1536, H: 1024, Solid: make([]byte, 1536*1024)}
			empty := &Battle{Terrain: terrain, Width: terrain.W, Height: terrain.H, Wind: ref.Wind}
			var shot Shot
			empty.nativeVolley(actor, ref.Elevation, ref.Charge/300, w, 0, &shot)
			if len(shot.Trails) != expected {
				t.Fatalf("volley emitted %d trails", len(shot.Trails))
			}
			var maxError float64
			total := 0
			for i, trail := range ref.Trails {
				points := shot.Trails[i].Points
				if len(points) <= ref.PlacedAfter || points[0] != trail.Muzzle {
					t.Fatalf("shell %d wrong launch from network trail: %v, expected %v", i, points, trail.Muzzle)
				}
				for _, s := range trail.Samples {
					if s.Tick > ref.PlacedAfter {
						break
					}
					pos := points[s.Tick]
					if math.Hypot(pos[0]-s.Position[0], pos[1]-s.Position[1]) > .03 {
						t.Fatalf("shell %d published tick %d: %v, expected %v", i, s.Tick, pos, s.Position)
					}
				}
				angle, power := ref.Elevation, ref.Charge/300
				if id == 18 {
					angle, power, _ = nativeShotParameters(21, i, angle, power)
				}
				p := newNativeFlying(actor, angle, power, w, ref.Wind)
				p.x, p.y = float32(points[0][0]), float32(points[0][1])
				if math.Abs(float64(p.launchSpeed)-trail.Speed) > .0001 {
					t.Fatalf("shell %d launch speed %.4f want %.4f", i, p.launchSpeed, trail.Speed)
				}
				target := &Unit{Seat: 4, HP: 300, X: ref.InitialTarget[0], Y: ref.InitialTarget[1]}
				b := &Battle{Units: []*Unit{target}}
				lockedAt, next := 0, 0
				if len(trail.Samples) < 2 || trail.Samples[0].Mode != 1 || trail.Samples[len(trail.Samples)-1].Mode != 5 {
					t.Fatalf("shell %d has incomplete capture", i)
				}
				for tick := 1; tick <= trail.Samples[len(trail.Samples)-1].Tick; tick++ {
					p.step()
					preX, preY := p.x, p.y
					if tick > ref.PlacedAfter {
						// Ground was cleared in the five-shell capture. The target's Y
						// at each individual acquisition is recorded by the native missile.
						target.X, target.Y = trail.Target[0], trail.Target[1]
					}
					if b.acquireNativeHoming(p) {
						lockedAt = tick
						if tick != trail.EntryTick || float64(p.x) != trail.EntryPosition[0] || float64(p.y) != trail.EntryPosition[1] || p.guideAngle != trail.EntryHeading {
							t.Fatalf("shell %d lock tick %d at (%.2f, %.2f), heading %.2f; native tick %d at %v heading %.2f", i, tick, p.x, p.y, p.guideAngle, trail.EntryTick, trail.EntryPosition, trail.EntryHeading)
						}
					}
					for next < len(trail.Samples) && trail.Samples[next].Tick == tick {
						s := trail.Samples[next]
						x, y := p.x, p.y
						if s.Mode == 1 && lockedAt == tick {
							x, y = preX, preY
						}
						if (s.Mode == 5 && !p.guided) || (s.Mode == 1 && lockedAt > 0 && lockedAt < tick) {
							t.Fatalf("shell %d tick %d native mode %d guided=%v", i, tick, s.Mode, p.guided)
						}
						d := math.Hypot(float64(x)-s.Position[0], float64(y)-s.Position[1])
						maxError = max(maxError, d)
						if d > .03 {
							t.Fatalf("shell %d tick %d position (%.4f, %.4f), native %v error %.4f", i, tick, x, y, s.Position, d)
						}
						next++
						total++
					}
				}
				if lockedAt == 0 || next != len(trail.Samples) {
					t.Fatalf("shell %d did not complete capture", i)
				}
			}
			t.Logf("native launch-to-guidance shells=%d samples=%d max_position_error=%.6f px", len(ref.Trails), total, maxError)
		})
	}
}
