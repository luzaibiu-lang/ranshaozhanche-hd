package main

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestBallisticsMatchOriginalRuntimeSamples(t *testing.T) {
	files, e := filepath.Glob("testdata/native-ballistic-*.json")
	if e != nil || len(files) == 0 {
		t.Fatal("original runtime fixtures missing")
	}
	for _, name := range files {
		var fixture struct {
			Vehicle   int        `json:"vehicle"`
			Position  [2]float64 `json:"actor_position"`
			Slope     float64    `json:"slope"`
			Direction int        `json:"native_direction"`
			Charge    float64    `json:"raw_charge"`
			Elevation float64    `json:"elevation"`
			Wind      int        `json:"wind"`
			Samples   []struct {
				Tick     int        `json:"tick"`
				Position [2]float64 `json:"position"`
				Spawn    [2]float64 `json:"spawn"`
			} `json:"samples"`
		}
		data, e := os.ReadFile(name)
		if e != nil {
			t.Fatal(e)
		}
		if e = json.Unmarshal(data, &fixture); e != nil {
			t.Fatal(e)
		}
		actor := &Unit{Seat: 0, Vehicle: fixture.Vehicle, X: fixture.Position[0], Y: fixture.Position[1], Slope: fixture.Slope, Face: 1, HP: 300, Elevation: fixture.Elevation}
		if fixture.Direction != 0 {
			actor.Face = -1
		}
		battle := &Battle{Width: 4000, Height: 4000, Wind: fixture.Wind, Units: []*Unit{actor}, Terrain: &Terrain{4000, 4000, make([]byte, 4000*4000)}, NativeAim: true}
		angle := actor.worldAngle(fixture.Elevation)
		x, y := nativeMuzzle(actor, angle)
		if x != fixture.Samples[0].Spawn[0] || y != fixture.Samples[0].Spawn[1] {
			t.Fatalf("%s muzzle drift: got %.3f,%.3f expected %v", name, x, y, fixture.Samples[0].Spawn)
		}
		trail, _, _ := battle.nativeTrajectory(actor, angle, fixture.Charge/300, vehicle(fixture.Vehicle).Weapons[0])
		shot := &Shot{}
		battle.nativeVolley(actor, angle, fixture.Charge/300, vehicle(fixture.Vehicle).Weapons[0], 0, shot)
		for _, sample := range fixture.Samples {
			// The user explicitly disabled native horizontal wrapping. Compare
			// flight only until the reference leaves the left edge.
			if sample.Position[0] < 0 {
				break
			}
			if sample.Tick >= len(trail.Points) {
				t.Fatalf("%s prematurely terminated shot", name)
			}
			point := trail.Points[sample.Tick]
			if math.Abs(point[0]-sample.Position[0]) > .0002 || math.Abs(point[1]-sample.Position[1]) > .0002 {
				t.Fatalf("%s tick %d differs from original runtime: got %v expected %v", name, sample.Tick, point, sample.Position)
			}
			if len(shot.Trails) == 0 || sample.Tick >= len(shot.Trails[0].Points) || math.Abs(shot.Trails[0].Points[sample.Tick][0]-sample.Position[0]) > .0002 || math.Abs(shot.Trails[0].Points[sample.Tick][1]-sample.Position[1]) > .0002 {
				t.Fatalf("%s concurrent simulator differs at native tick %d", name, sample.Tick)
			}
		}
	}
}

func TestNativeShotAboveMapReturnsAndSideShotTerminates(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	u := b.active()
	u.Y = 120
	trail, _, _ := b.nativeTrajectory(u, 85, .6, vehicle(1).Weapons[0])
	above, returned := false, false
	for _, point := range trail.Points {
		if point[1] < 0 {
			above = true
		}
		if above && point[1] > 0 {
			returned = true
		}
	}
	if !above || !returned {
		t.Fatal("shot was discarded at top of map")
	}
	u.X = 1
	u.Face = -1
	trail, _, hit := b.nativeTrajectory(u, 170, 1, vehicle(1).Weapons[0])
	if hit || len(trail.Points) > 3 {
		t.Fatal("side exit wrapped or continued inside the map")
	}
}
