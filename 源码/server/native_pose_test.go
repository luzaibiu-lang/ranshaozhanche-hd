package main

import (
	"math"
	"testing"
)

func TestNativeAimTurnsWithVehicleAndPreservesElevation(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	u := b.active()
	u.Elevation = 30
	if e := b.move(-10); e != nil {
		t.Fatal(e)
	}
	if u.Face != -1 || u.Elevation != 30 {
		t.Fatal("moving left lost facing/elevation")
	}
	if e := b.fireNative(30, .65, 0); e != nil {
		t.Fatal(e)
	}
	points := b.Shot.Trails[0].Points
	if len(points) < 2 || points[1][0] >= points[0][0] || u.Face != -1 {
		t.Fatal("left-facing tank fired to the right")
	}
}

func TestNativeAimLimitsAndDownwardShot(t *testing.T) {
	for id := 1; id <= 30; id++ {
		b := flatBattle()
		b.active().Vehicle = id
		v := vehicle(id)
		for _, invalid := range []float64{v.AimMin - .1, v.AimMax + .1, math.NaN(), math.Inf(1)} {
			if b.fireNative(invalid, .65, 0) == nil || b.Shot != nil || b.pending != nil {
				t.Fatalf("vehicle %d accepted invalid native elevation", id)
			}
		}
	}
	b := flatBattle()
	if e := b.fireNative(-10, .5, 0); e != nil {
		t.Fatal(e)
	}
	points := b.Shot.Trails[0].Points
	if len(points) < 2 || points[1][1] <= points[0][1] {
		t.Fatal("native negative elevation did not shoot downward")
	}
}

func TestBlockedMovementStillTurnsVehicle(t *testing.T) {
	b := flatBattle()
	u := b.active()
	u.Move, u.SP = 0, 0
	if e := b.move(-10); e != nil {
		t.Fatal(e)
	}
	if u.Face != -1 || u.X != 300 {
		t.Fatal("blocked movement must turn without consuming movement")
	}
}

func TestNativeFootprintSlopeIgnoresDistantCaveRoof(t *testing.T) {
	b := flatBattle()
	u := b.active()
	for x := 0; x < b.Terrain.W; x++ {
		b.Terrain.Solid[30*b.Terrain.W+x] = 1
	}
	u.updateSlope(b.Terrain)
	if math.Abs(u.Slope) > .001 {
		t.Fatalf("cave ceiling changed floor slope: %f", u.Slope)
	}
	for x := 280; x < 320; x++ {
		for y := 580; y < 620; y++ {
			b.Terrain.Solid[y*b.Terrain.W+x] = 0
			if y >= 600-(x-300)/2 {
				b.Terrain.Solid[y*b.Terrain.W+x] = 1
			}
		}
	}
	u.updateSlope(b.Terrain)
	if u.Slope < 10 || u.Slope > 40 {
		t.Fatalf("supported incline not reflected in vehicle slope: %f", u.Slope)
	}
}
