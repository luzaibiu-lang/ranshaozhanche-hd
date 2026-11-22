package main

import (
	"strconv"
	"testing"
)

func TestNativeHomingPublishesTimedTargetCue(t *testing.T) {
	for _, id := range []int{18, 101} {
		t.Run(strconv.Itoa(id), func(t *testing.T) {
			terrain := &Terrain{W: 1536, H: 1024, Solid: make([]byte, 1536*1024)}
			for y := 550; y < terrain.H; y++ {
				for x := 0; x < terrain.W; x++ {
					terrain.Solid[y*terrain.W+x] = 1
				}
			}
			actor := &Unit{Seat: 0, Vehicle: 1, X: 500, Y: 550, Face: 1, HP: 300, MaxHP: 300}
			target := &Unit{Seat: 4, Vehicle: 1, X: 850, Y: 550, Face: -1, HP: 300, MaxHP: 300}
			b := &Battle{Width: terrain.W, Height: terrain.H, Terrain: terrain, Units: []*Unit{actor, target}, NativeAim: true}
			shot := &Shot{}
			b.nativeVolley(actor, 35, .3, Weapon{Projectile: id, Kind: "homing", Count: 1, Damage: 26, Radius: 55, Wind: 1}, 0, shot)
			if len(shot.Cues) != 1 {
				t.Fatalf("one missile must produce one lock event, got %v", shot.Cues)
			}
			cue := shot.Cues[0]
			if cue.Kind != "lock" || cue.Seat != 4 || cue.X != 850 || cue.Y != 550 || cue.At <= 0 || cue.At >= shot.Duration {
				t.Fatalf("invalid native target event: %+v, duration=%v", cue, shot.Duration)
			}
			if len(shot.Impacts) == 0 || cue.At >= shot.Impacts[0].At {
				t.Fatal("the target marker/sound must precede impact")
			}
		})
	}
}
