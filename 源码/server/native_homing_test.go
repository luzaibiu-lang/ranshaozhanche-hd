package main

import (
	"encoding/json"
	"math"
	"os"
	"strconv"
	"testing"
)

func TestNativeHomingAutomaticallyAcquiresOriginalCone(t *testing.T) {
	// Original item 101 sees a target 35 degrees off-axis: its cone is 40,
	// while the five-shell CWeapon18 cone is only 30 (0056f650/00551b40).
	target := &Unit{Seat: 4, HP: 300, X: 664, Y: 385}
	b := &Battle{Units: []*Unit{target}}
	for _, id := range []int{18, 101} {
		p := &nativeFlying{w: Weapon{Projectile: id}, x: 500, y: 500, vx: 6, speedCounter: -.1, angle: 0}
		got := b.acquireNativeHoming(p)
		if got != (id == 101) {
			t.Fatalf("native projectile %d cone: acquired=%v", id, got)
		}
		if got && (!p.guided || p.targetX != target.X || p.targetY != target.Y) {
			t.Fatal("automatic lock did not retain the selected native target point")
		}
	}
}

func TestNativeHomingAcquisitionEligibilityAndLimits(t *testing.T) {
	for _, test := range []struct {
		name    string
		hp      int
		stealth int
		x, y    float64
		counter float32
		want    bool
	}{
		{"launch counter still positive", 300, 0, 600, 500, .1, false},
		{"alive target at zero counter", 300, 0, 600, 500, 0, true},
		{"dead target", 0, 0, 600, 500, 0, false},
		{"native lock includes invisible target", 300, 4, 600, 500, 0, true},
		{"behind projectile", 300, 0, 400, 500, 0, false},
		{"outside forward cone", 300, 0, 500, 400, 0, false},
		{"outside speed-dependent range", 300, 0, 950, 500, 0, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			// Same team deliberately remains eligible, as the original finder
			// checks existence/alive flags without a team or stealth branch.
			b := &Battle{Units: []*Unit{{Seat: 0, Team: 0, HP: test.hp, Stealth: test.stealth, X: test.x, Y: test.y}}}
			p := &nativeFlying{w: Weapon{Projectile: 101}, x: 500, y: 500, vx: 6, speedCounter: test.counter, angle: 0}
			if got := b.acquireNativeHoming(p); got != test.want {
				t.Fatalf("acquired=%v want %v", got, test.want)
			}
		})
	}
}

func TestNativeHomingDoesNotOrbitAfterPassingAimPoint(t *testing.T) {
	p := &nativeFlying{w: Weapon{Projectile: 101}, guided: true, x: 500, y: 500, guideAngle: 0, guideSpeed: 6, targetX: 520, targetY: 500}
	for tick := 0; tick < 20; tick++ {
		p.step()
		if !p.guideLocked || p.guideAngle != 0 || p.y != 500 {
			t.Fatalf("tick %d: aligned native missile steered back: angle=%v position=%v,%v locked=%v", tick, p.guideAngle, p.x, p.y, p.guideLocked)
		}
	}
	if p.x <= 520 {
		t.Fatal("fixture must actually pass the aim point")
	}
}

func TestNativeVolleyAcquiresTargetWithoutClickSelection(t *testing.T) {
	for _, id := range []int{18, 101} {
		t.Run(strconv.Itoa(id), func(t *testing.T) {
			terrain := &Terrain{W: 1536, H: 1024, Solid: make([]byte, 1536*1024)}
			for y := 550; y < terrain.H; y++ {
				for x := 0; x < terrain.W; x++ {
					terrain.Solid[y*terrain.W+x] = 1
				}
			}
			actor := &Unit{Seat: 0, Vehicle: 1, X: 500, Y: 550, Face: 1, HP: 300, MaxHP: 300}
			enemy := &Unit{Seat: 4, Vehicle: 1, X: 850, Y: 550, Face: -1, HP: 300, MaxHP: 300}
			b := &Battle{Width: terrain.W, Height: terrain.H, Terrain: terrain, Units: []*Unit{actor, enemy}, NativeAim: true}
			shot := &Shot{}
			w := Weapon{Projectile: id, Kind: "homing", Count: 1, Damage: 26, Radius: 55, Wind: 1}
			b.nativeVolley(actor, 35, .3, w, 0, shot)
			found := false
			for _, impact := range shot.Impacts {
				if math.Abs(impact.X-850) < 30 {
					found = true
				}
			}
			if !found || enemy.HP >= 300 {
				t.Fatalf("native %d did not automatically steer into eligible target: hp=%d impacts=%v", id, enemy.HP, shot.Impacts)
			}
		})
	}
}

func TestNativeGuidanceMatchesOriginalMode5Samples(t *testing.T) {
	for _, id := range []int{18, 101} {
		t.Run(strconv.Itoa(id), func(t *testing.T) {
			var fixture struct {
				Objects []struct {
					Samples []struct {
						Tick     int
						Position [2]float64
						Target   [2]float64
						Heading  float64
						Speed    float64
						Locked   bool
					}
				}
			}
			name := "testdata/native-homing-guided-" + strconv.Itoa(id) + ".json"
			data, err := os.ReadFile(name)
			if err != nil {
				t.Fatal(err)
			}
			if err = json.Unmarshal(data, &fixture); err != nil {
				t.Fatal(err)
			}
			checked, lockChecks := 0, 0
			maxPositionError, maxHeadingError := 0.0, 0.0
			for _, object := range fixture.Objects {
				if len(object.Samples) < 2 {
					continue
				}
				first := object.Samples[0]
				p := &nativeFlying{w: Weapon{Projectile: id}, guided: true, guideLocked: first.Locked, x: float32(first.Position[0]), y: float32(first.Position[1]), guideAngle: first.Heading, guideSpeed: first.Speed, targetX: first.Target[0], targetY: first.Target[1]}
				tick := first.Tick
				previous := first.Position
				for _, sample := range object.Samples[1:] {
					if math.Abs(sample.Position[0]-previous[0]) > 768 {
						break // The user explicitly removed native side wrapping.
					}
					previous = sample.Position
					for tick < sample.Tick {
						p.step()
						tick++
					}
					maxPositionError = max(maxPositionError, math.Hypot(float64(p.x)-sample.Position[0], float64(p.y)-sample.Position[1]))
					maxHeadingError = max(maxHeadingError, math.Abs(p.guideAngle-sample.Heading))
					if math.Abs(float64(p.x)-sample.Position[0]) > .025 || math.Abs(float64(p.y)-sample.Position[1]) > .025 || math.Abs(p.guideAngle-sample.Heading) > .002 {
						t.Fatalf("native %d tick %d: got position=(%.6f,%.6f) heading=%.6f lock=%v; want %v heading=%.6f lock=%v", id, tick, p.x, p.y, p.guideAngle, p.guideLocked, sample.Position, sample.Heading, sample.Locked)
					}
					if p.guideLocked != sample.Locked {
						t.Fatalf("native %d tick %d: alignment latch differs", id, tick)
					}
					if sample.Locked {
						lockChecks++
					}
					checked++
				}
			}
			if checked < 5 || lockChecks < 2 {
				t.Fatalf("insufficient true mode5/latch coverage: samples=%d locked=%d", checked, lockChecks)
			}
			t.Logf("original mode5 samples=%d locked=%d max_position_error=%.6f max_heading_error=%.6f", checked, lockChecks, maxPositionError, maxHeadingError)
		})
	}
}
