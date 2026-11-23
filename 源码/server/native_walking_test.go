package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func TestNativeWalkingMatchesOriginalMachineCode(t *testing.T) {
	var fixture struct {
		Width, Height int
		Profiles      map[string][]int
		Cases         []struct {
			Profile                    string
			Footprint, X, Y, Direction int
			Expected                   struct {
				Allowed, Valid, Off, Unsupported bool
				X, Y                             int
				Slope                            float64
			}
		}
	}
	raw, err := os.ReadFile("testdata/native-walking-oracle.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	terrains := map[string]*Terrain{}
	for name, heights := range fixture.Profiles {
		terrain := &Terrain{W: fixture.Width, H: fixture.Height, Solid: make([]byte, fixture.Width*fixture.Height)}
		for x, height := range heights {
			for y := height; y < terrain.H; y++ {
				terrain.Solid[y*terrain.W+x] = 1
			}
		}
		terrains[name] = terrain
	}
	failed := 0
	for i, sample := range fixture.Cases {
		vehicle := 1
		if sample.Footprint == 41 {
			vehicle = 9
		}
		unit := &Unit{Vehicle: vehicle, X: float64(sample.X), Y: float64(sample.Y)}
		pose, allowed := terrains[sample.Profile].nativeWalkPose(unit, sample.Direction)
		if allowed != sample.Expected.Allowed || pose.valid != sample.Expected.Valid || int(pose.x) != sample.Expected.X || int(pose.y) != sample.Expected.Y || math.Abs(pose.slope-sample.Expected.Slope) > .002 {
			if failed < 15 {
				t.Errorf("case %d %s width%d (%d,%d) dir%d: got allowed=%v pose=%+v; original=%+v", i, sample.Profile, sample.Footprint, sample.X, sample.Y, sample.Direction, allowed, pose, sample.Expected)
			}
			failed++
		}
	}
	if failed > 0 {
		t.Fatalf("%d of %d original machine-code samples differ", failed, len(fixture.Cases))
	}
}
