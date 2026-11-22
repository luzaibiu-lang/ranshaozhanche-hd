package main

import "testing"

func TestNativeDeathVisualClockAndReplay(t *testing.T) {
	for _, mode := range []string{"fatal", "fall", "departed"} {
		t.Run(mode, func(t *testing.T) {
			alive := &Unit{Seat: 4, Vehicle: 7, HP: 300, X: 50, Y: 50}
			dead := *alive
			dead.HP = 0
			if mode == "fall" {
				dead.Y = 101
			}
			if mode == "departed" {
				dead.Departed = true
			}
			b := &Battle{Width: 100, Height: 100}
			s := &Shot{Duration: 1, Cues: []ShotCue{{Kind: "lock", At: .1}}, States: []ShotState{
				{At: 0, Units: []*Unit{alive}}, {At: .5, Units: []*Unit{&dead}},
			}}
			b.prepareShotVisuals(s, 0)
			b.prepareShotVisuals(s, 0)
			count := 0
			for _, cue := range s.Cues {
				if cue.Kind == "death" {
					count++
					if cue.At != .5 || cue.Seat != 4 || cue.X != 50 || cue.Y != 50 {
						t.Fatalf("wrong fatal cue: %+v", cue)
					}
				}
			}
			want := 0
			if mode == "fatal" {
				want = 1
				if s.Duration < 4.5 {
					t.Fatal("turn/results would cut off the native destruction sequence")
				}
			}
			if count != want {
				t.Fatalf("destruction count %d, want %d", count, want)
			}
			if s.Cues[0].Kind != "lock" {
				t.Fatal("death preparation lost homing cues")
			}
		})
	}
}
