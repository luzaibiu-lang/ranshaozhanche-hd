package main

import (
	"math"
	"testing"
)

func TestNativeShotPreparationAndMuzzleShareOneTimeline(t *testing.T) {
	for _, tc := range []struct {
		name              string
		slot, item, ticks int
	}{
		{"cannon", 0, 0, 30},
		{"special", 2, 0, 190},
		{"item from special tab", 2, 3, 30},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b := flatBattle()
			b.NativeAim = true
			b.active().ShotMode = tc.item
			b.active().SP = 200
			before := nowSeconds()
			if err := b.fireNative(45, .6, tc.slot); err != nil {
				t.Fatal(err)
			}
			s := b.Shot
			if s.Prepared < before+.399 || math.Abs((s.Started-s.Prepared)*60-float64(tc.ticks)) > .001 {
				t.Fatalf("wrong prepare/launch times: %f %f", s.Prepared, s.Started)
			}
			if s.Overdrive != (tc.ticks == 190) || b.advanceShot(s.Started-.001) {
				t.Fatal("wrong special cue or authoritative state advanced before muzzle")
			}
			if diff := float64(b.busyUntil.UnixMicro())/1e6 - (s.Started + s.Duration + .65); math.Abs(diff) > .00001 {
				t.Fatalf("turn completion uses a different clock: %f", diff)
			}
		})
	}
}
