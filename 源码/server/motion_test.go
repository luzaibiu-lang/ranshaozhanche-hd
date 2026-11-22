package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestRenderedMotionKeepsAuthoritativeFallFramesAndNoFutureStats(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	u := b.active()
	u.Y = 400
	shot := &Shot{}
	b.recordShotState(shot, 0)
	for tick := 1; tick <= 120; tick++ {
		changed, falling := b.nativeFalls()
		if changed {
			b.recordShotState(shot, float64(tick)/60)
		}
		if !falling {
			break
		}
	}
	if len(shot.Motion) < 30 {
		t.Fatal("fall animation lost its original per-tick positions")
	}
	for i, frame := range shot.Motion {
		if i > 0 && frame.At <= shot.Motion[i-1].At {
			t.Fatal("motion times are not strictly increasing")
		}
		if len(frame.Poses) != len(b.Units) {
			t.Fatal("motion missed a participant")
		}
		if frame.Poses[0][0] != float64(u.Seat) {
			t.Fatal("motion lost seat identity")
		}
	}
	if shot.Motion[len(shot.Motion)-1].Poses[0][2] != u.Y {
		t.Fatal("rendered landing differs from authoritative landing")
	}
	// Continuous poses never carry commandable stats. Sparse presentation
	// checkpoints now accompany real shots so their impacts remain in sync.
	wire, e := json.Marshal(shot.Motion)
	if e != nil {
		t.Fatal(e)
	}
	for _, key := range []string{`"states"`, `"hp"`, `"sp"`, `"inventory"`, `"holes"`} {
		if strings.Contains(string(wire), key) {
			t.Fatal("motion revealed future game state", key)
		}
	}
	if !strings.Contains(string(wire), `"poses"`) {
		t.Fatal("continuous motion not sent to renderer")
	}
}
