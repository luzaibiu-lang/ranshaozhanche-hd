package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

func TestTerrainAfterShotMatchesOriginalCollisionBuffer(t *testing.T) {
	var f struct {
		Map, Weapon, Direction int
		Units                  []int
		Position               [2]float64 `json:"actor_position"`
		Initial                []struct {
			Vehicle  int
			Position [2]float64
			HP       int
		} `json:"initial_units"`
		Wind      int `json:"native_wind"`
		Slope     float64
		Charge    float64 `json:"raw_charge"`
		Elevation float64 `json:"relative_elevation"`
		Before    string  `json:"terrain_before"`
		After     string  `json:"terrain_after"`
	}
	data, e := os.ReadFile("testdata/native-crater-runtime.json")
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(data, &f); e != nil {
		t.Fatal(e)
	}
	terrain, e := loadTerrain("../client/assets", f.Map)
	if e != nil {
		t.Fatal(e)
	}
	digest := func() string { h := sha256.Sum256(terrain.Solid); return hex.EncodeToString(h[:]) }
	if digest() != f.Before {
		t.Fatal("source map differs from original runtime collision buffer")
	}
	if f.Before == f.After {
		t.Fatal("fixture did not change original terrain")
	}
	units := []*Unit{}
	for i, v := range f.Initial {
		units = append(units, &Unit{Seat: i * 4, Vehicle: v.Vehicle, X: v.Position[0], Y: v.Position[1], HP: v.HP, Face: 1})
	}
	actor := units[0]
	actor.Slope = f.Slope
	if f.Direction == 1 {
		actor.Face = -1
	}
	b := &Battle{Width: terrain.W, Height: terrain.H, Terrain: terrain, Units: units, Wind: f.Wind, NativeAim: true}
	b.nativeVolley(actor, actor.worldAngle(f.Elevation), f.Charge/300, vehicle(actor.Vehicle).Weapons[f.Weapon], 0, &Shot{})
	if digest() != f.After {
		t.Fatalf("terrain after original shot differs: got %s want %s", digest(), f.After)
	}
}
