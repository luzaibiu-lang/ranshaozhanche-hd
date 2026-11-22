package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func TestReflectionMatchesOriginalRuntime(t *testing.T) {
	var fixture struct {
		Vehicle   int        `json:"vehicle"`
		Position  [2]float64 `json:"actor_position"`
		Wind      int        `json:"native_wind"`
		Slope     float64    `json:"slope"`
		Direction int        `json:"direction"`
		Elevation float64    `json:"relative_elevation"`
		Charge    float64    `json:"raw_charge"`
		Map       int        `json:"map"`
		Objects   []struct {
			Samples []struct {
				Tick     int        `json:"tick"`
				Position [2]float64 `json:"position"`
			} `json:"samples"`
		} `json:"objects"`
	}
	data, e := os.ReadFile("testdata/native-reflection-runtime.json")
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(data, &fixture); e != nil {
		t.Fatal(e)
	}
	terrain, e := loadTerrain("../client/assets", fixture.Map)
	if e != nil {
		t.Fatal(e)
	}
	face := 1
	if fixture.Direction == 1 {
		face = -1
	}
	actor := &Unit{Seat: 0, Vehicle: fixture.Vehicle, X: fixture.Position[0], Y: fixture.Position[1], Slope: fixture.Slope, Face: face, HP: 300}
	b := &Battle{Width: terrain.W, Height: terrain.H, Wind: fixture.Wind, Units: []*Unit{actor}, Terrain: terrain, NativeAim: true}
	shot := &Shot{}
	b.nativeVolley(actor, actor.worldAngle(fixture.Elevation), fixture.Charge/300, vehicle(fixture.Vehicle).Weapons[2], 0, shot)
	if len(shot.Trails) != 1 {
		t.Fatal("expected single native reflection shell")
	}
	for _, s := range fixture.Objects[0].Samples {
		if s.Tick >= len(shot.Trails[0].Points) {
			t.Fatalf("terminated before native tick %d", s.Tick)
		}
		got := shot.Trails[0].Points[s.Tick]
		if math.Abs(got[0]-s.Position[0]) > .02 || math.Abs(got[1]-s.Position[1]) > .02 {
			t.Fatalf("tick %d: got %v want %v", s.Tick, got, s.Position)
		}
	}
}

func TestFallingMatchesOriginalRuntime(t *testing.T) {
	var f struct {
		Map, Vehicle int
		Position     [2]float64 `json:"initial_position"`
		Samples      []struct {
			Tick     int
			Position [2]float64
			HP       int
		}
	}
	data, e := os.ReadFile("testdata/native-fall-runtime.json")
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
	u := &Unit{Vehicle: f.Vehicle, X: f.Position[0], Y: f.Position[1], HP: 300, Face: 1}
	b := &Battle{Width: terrain.W, Height: terrain.H, Terrain: terrain, Units: []*Unit{u}, NativeAim: true}
	tick := 0
	for i, s := range f.Samples {
		if i == 0 {
			continue
		}
		if s.Tick == 0 {
			for count := 0; count < 300; count++ {
				b.nativeFallStep(u)
				if !u.Falling {
					break
				}
			}
		} else {
			for tick < s.Tick {
				b.nativeFallStep(u)
				tick++
			}
		}
		if u.X != s.Position[0] || u.Y != s.Position[1] || u.HP != s.HP {
			t.Fatalf("native falling tick %d: got %.0f,%.0f hp=%d; want %v hp=%d", s.Tick, u.X, u.Y, u.HP, s.Position, s.HP)
		}
	}
}

func TestSpecialWeaponsMatchOriginalRuntime(t *testing.T) {
	for _, family := range []string{"wave", "homing", "grenade", "ricochet", "supply"} {
		t.Run(family, func(t *testing.T) {
			var f struct {
				Map, Vehicle, Weapon int
				Position             [2]float64 `json:"actor_position"`
				Wind                 int        `json:"native_wind"`
				Slope                float64
				Direction            int
				Elevation            float64 `json:"relative_elevation"`
				Charge               float64 `json:"raw_charge"`
				Initial              []struct {
					Vehicle  int
					Position [2]float64
					HP       int
				} `json:"initial_units"`
				Objects []struct {
					Samples []struct {
						Tick     int
						Position [2]float64
						Visual   struct {
							Variant int
							Derived [2]float64
						}
					}
				} `json:"objects"`
			}
			data, e := os.ReadFile("testdata/native-" + family + "-runtime.json")
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
			units := []*Unit{}
			for i, v := range f.Initial {
				units = append(units, &Unit{Seat: i * 4, Vehicle: v.Vehicle, X: v.Position[0], Y: v.Position[1], HP: v.HP, Face: 1})
			}
			actor := units[0]
			actor.Slope = f.Slope
			if f.Direction == 1 {
				actor.Face = -1
			}
			b := &Battle{Width: terrain.W, Height: terrain.H, Wind: f.Wind, Units: units, Terrain: terrain, NativeAim: true}
			shot := &Shot{}
			weapon := vehicle(f.Vehicle).Weapons[f.Weapon]
			if family == "grenade" {
				weapon = Weapon{Kind: "normal", Damage: 105, Radius: 55, Count: 1, Wind: 1, Projectile: 100}
			}
			if family == "ricochet" {
				weapon = Weapon{Kind: "normal", Damage: 105, Radius: 55, Count: 1, Wind: 1, Projectile: 78}
			}
			if family == "supply" {
				weapon = Weapon{Kind: "normal", Damage: 41, Radius: 60, Count: 1, Wind: 1, Projectile: 58}
			}
			b.nativeVolley(actor, actor.worldAngle(f.Elevation), f.Charge/300, weapon, 0, shot)
			if len(shot.Trails) != len(f.Objects) {
				t.Fatalf("got %d native objects want %d", len(shot.Trails), len(f.Objects))
			}
			for i, g := range f.Objects {
				checks := 0
				previous := shot.Trails[i].Points[0]
				for _, s := range g.Samples {
					want := s.Position
					if math.Abs(want[0]-previous[0]) > float64(terrain.W)/2 {
						break
					} // user explicitly removed native side wrap
					previous = want
					if family == "wave" {
						want = [2]float64{float64(int(s.Visual.Derived[0])), float64(int(s.Visual.Derived[1]))}
					}
					if want[0] < 0 || want[0] >= float64(terrain.W) {
						break
					}
					if s.Tick >= len(shot.Trails[i].Points) {
						t.Fatalf("object %d terminated before native tick %d", i, s.Tick)
					}
					got := shot.Trails[i].Points[s.Tick]
					if math.Abs(got[0]-want[0]) > .02 || math.Abs(got[1]-want[1]) > .02 {
						t.Fatalf("object %d tick %d got %v want %v", i, s.Tick, got, want)
					}
					checks++
				}
				if checks < 5 {
					t.Fatal("insufficient native trajectory samples")
				}
			}
		})
	}
}

func TestBeamsMatchOriginalRuntime(t *testing.T) {
	for _, name := range []string{"native-orbital-beams.json", "native-ray-beams.json"} {
		t.Run(name, func(t *testing.T) {
			var fixture struct {
				Vehicle   int        `json:"vehicle"`
				Position  [2]float64 `json:"actor_position"`
				Wind      int        `json:"native_wind"`
				Slope     float64    `json:"slope"`
				Elevation float64    `json:"relative_elevation"`
				Charge    float64    `json:"raw_charge"`
				Weapon    int        `json:"weapon"`
				Samples   []struct {
					Tick   int          `json:"tick"`
					Beams  [][2]float64 `json:"beams"`
					Active []int        `json:"active"`
				} `json:"samples"`
			}
			data, e := os.ReadFile("testdata/" + name)
			if e != nil {
				t.Fatal(e)
			}
			if e = json.Unmarshal(data, &fixture); e != nil {
				t.Fatal(e)
			}
			actor := &Unit{Seat: 0, Vehicle: fixture.Vehicle, X: fixture.Position[0], Y: fixture.Position[1], Slope: fixture.Slope, Face: 1, HP: 300}
			b := &Battle{Width: 4000, Height: 4000, Wind: fixture.Wind, Units: []*Unit{actor}, Terrain: &Terrain{4000, 4000, make([]byte, 4000*4000)}, NativeAim: true}
			shot := &Shot{}
			b.nativeVolley(actor, actor.worldAngle(fixture.Elevation), fixture.Charge/300, vehicle(fixture.Vehicle).Weapons[fixture.Weapon], 0, shot)
			count := len(fixture.Samples[0].Active)
			if name == "native-orbital-beams.json" {
				count = 2
			}
			if len(shot.Trails) != count {
				t.Fatalf("native weapon must have %d beams", count)
			}
			for _, s := range fixture.Samples {
				for beam := 0; beam < count; beam++ {
					if s.Active[beam] == 0 {
						continue
					}
					if s.Tick >= len(shot.Trails[beam].Points) {
						t.Fatal("beam ended before native sample")
					}
					if got := shot.Trails[beam].Points[s.Tick]; got != s.Beams[beam] {
						t.Fatalf("beam %d tick %d got %v want %v", beam, s.Tick, got, s.Beams[beam])
					}
				}
			}
		})
	}
}

func TestClusterMatchesOriginalRuntimeObjects(t *testing.T) {
	for _, name := range []string{"native-cluster-runtime.json", "native-chain-runtime.json"} {
		t.Run(name, func(t *testing.T) { testClusterFixture(t, name) })
	}
}

func testClusterFixture(t *testing.T, name string) {
	var fixture struct {
		Vehicle   int        `json:"vehicle"`
		Position  [2]float64 `json:"actor_position"`
		Wind      int        `json:"native_wind"`
		Slope     float64    `json:"slope"`
		Elevation float64    `json:"relative_elevation"`
		Charge    float64    `json:"raw_charge"`
		Objects   []struct {
			Projectile int `json:"projectile"`
			Samples    []struct {
				Tick     int        `json:"tick"`
				Position [2]float64 `json:"position"`
			} `json:"samples"`
		} `json:"objects"`
	}
	data, e := os.ReadFile("testdata/" + name)
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(data, &fixture); e != nil {
		t.Fatal(e)
	}
	actor := &Unit{Seat: 0, Vehicle: fixture.Vehicle, X: fixture.Position[0], Y: fixture.Position[1], Slope: fixture.Slope, Face: 1, HP: 300}
	b := &Battle{Width: 4000, Height: 4000, Wind: fixture.Wind, Units: []*Unit{actor}, Terrain: &Terrain{4000, 4000, make([]byte, 4000*4000)}, NativeAim: true}
	shot := &Shot{}
	b.nativeVolley(actor, actor.worldAngle(fixture.Elevation), fixture.Charge/300, vehicle(fixture.Vehicle).Weapons[2], 0, shot)
	if len(shot.Trails) != len(fixture.Objects) {
		t.Fatalf("native object count %d, want %d", len(shot.Trails), len(fixture.Objects))
	}
	for i, object := range fixture.Objects {
		trail := shot.Trails[i]
		for _, s := range object.Samples {
			if s.Tick >= len(trail.Points) {
				t.Fatalf("object %d terminated before recorded native tick %d", i, s.Tick)
			}
			got := trail.Points[s.Tick]
			// Native x87 trig and Go libm can round adjacent thousandths at a
			// guided heading. Bound accumulated error to 1/50 of a source pixel.
			if math.Abs(got[0]-s.Position[0]) > .02 || math.Abs(got[1]-s.Position[1]) > .02 {
				t.Fatalf("object %d projectile %d tick %d: got %v want %v", i, object.Projectile, s.Tick, got, s.Position)
			}
		}
	}
}

func TestImpactCheckpointsStayPrivateUntilTheirTime(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	if e := b.fireWorld(35, .4, 1, true); e != nil {
		t.Fatal(e)
	}
	if len(b.Shot.States) < 2 {
		t.Fatal("multi-shot fixture needs separate impact times")
	}
	initialHoles := len(b.Holes)
	initialSP := b.active().SP
	first := b.Shot.States[0]
	if b.advanceShot(b.Shot.Started+first.At-.0001) || len(b.Holes) != initialHoles {
		t.Fatal("future terrain leaked before first impact")
	}
	if !b.advanceShot(b.Shot.Started+first.At+.0001) || len(b.Holes) != first.Holes {
		t.Fatal("first impact did not update terrain on time")
	}
	if b.active().SP != initialSP {
		t.Fatal("the impact checkpoint charged SP a second time")
	}
	copyHP := first.Units[0].HP
	b.Units[0].HP = 1
	if first.Units[0].HP != copyHP {
		t.Fatal("live units mutated immutable shot state")
	}
	if len(b.Holes) >= len(b.pending.Holes) {
		t.Fatal("all later impacts were revealed at the first hit")
	}
}

func TestClusterSplitsBeforeGroundContact(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	u := b.active()
	u.Vehicle = 3
	u.SP = 200
	if e := b.fireWorld(85, .6, 2, true); e != nil {
		t.Fatal(e)
	}
	if len(b.Shot.Trails) != 7 {
		t.Fatalf("expected carrier and six children, got %d", len(b.Shot.Trails))
	}
	firstChild := b.Shot.Trails[1]
	if firstChild.Start <= 0 || firstChild.Start >= b.Shot.Trails[0].Duration {
		t.Fatal("children spawned after the carrier impact")
	}
	if firstChild.Points[0][1] >= 500 {
		t.Fatal("cluster did not split near the apex")
	}
	for i := 1; i < 7; i++ {
		if b.Shot.Trails[i].Projectile != 4 {
			t.Fatal("child lost its native projectile identity")
		}
	}
}
