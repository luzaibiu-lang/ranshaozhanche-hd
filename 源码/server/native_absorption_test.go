package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func TestNativeAbsorptionMatchesOriginalRuntime(t *testing.T) {
	var f struct {
		Origin  [2]float64
		Angle   float64
		Amount  int
		Samples []struct {
			Tick            int
			Position, Owner [2]float64
			Mode, HP        int
		}
	}
	raw, e := os.ReadFile("testdata/native-absorption-runtime.json")
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(raw, &f); e != nil {
		t.Fatal(e)
	}
	p := newNativeAbsorption(nativeRefund{f.Origin[0], f.Origin[1], f.Angle, f.Amount, false})
	actor := &Unit{HP: 267, MaxHP: 300}
	tick := 0
	for _, s := range f.Samples {
		actor.X, actor.Y = s.Owner[0], s.Owner[1]
		for tick < s.Tick {
			p.stepAbsorption(actor)
			tick++
		}
		if math.Abs(float64(p.x)-s.Position[0]) > .02 || math.Abs(float64(p.y)-s.Position[1]) > .02 {
			t.Fatalf("native return tick %d: got %v,%v want %v (mode %d/%d)", tick, p.x, p.y, s.Position, p.absorption.mode, s.Mode)
		}
	}
}

func TestNativeAbsorptionArrivesBeforeCreditingHPOrSP(t *testing.T) {
	for _, sp := range []bool{false, true} {
		b := flatBattle()
		b.NativeAim = true
		actor, target := b.Units[0], b.Units[1]
		actor.HP, actor.SP = 150, 100
		shot := &Shot{}
		w := Weapon{Projectile: 20, Damage: 41, Radius: 50, Kind: "normal"}
		if sp {
			w.Projectile, w.Kind = 21, "drain"
		}
		b.impact(actor, w, Impact{X: target.X, Y: target.Y, Radius: 50, Kind: w.Kind}, shot)
		if actor.HP != 150 || actor.SP != 100 || len(shot.refunds) != 1 {
			t.Fatal("absorption credited before the native return object arrived")
		}
		if sp && target.SP >= 150 {
			t.Fatal("SP must leave the target at impact")
		}
		p := newNativeAbsorption(shot.refunds[0])
		for tick := 0; tick < 1200 && !p.dead; tick++ {
			p.stepAbsorption(actor)
			if tick < 59 && (actor.HP != 150 || actor.SP != 100) {
				t.Fatal("refund skipped its opening arc")
			}
		}
		if !p.dead || (sp && actor.SP <= 100) || (!sp && actor.HP <= 150) {
			t.Fatalf("return object failed to credit its live owner: %+v", actor)
		}
		deadOwner := *actor
		deadOwner.HP = 0
		p = newNativeAbsorption(shot.refunds[0])
		p.stepAbsorption(&deadOwner)
		if deadOwner.HP != 0 || !p.dead {
			t.Fatal("absorption revived a dead tank")
		}
	}
}

func TestNativeWarpPreservesPortalBeforeAndAfterTeleport(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	b.active().ShotMode = 4
	if e := b.fireNative(35, .4, 0); e != nil {
		t.Fatal(e)
	}
	var portal *Trail
	for i := range b.Shot.Trails {
		if b.Shot.Trails[i].Kind == "warp_portal" {
			portal = &b.Shot.Trails[i]
		}
	}
	if portal == nil || portal.Duration < 2 || len(b.Shot.Impacts) != 1 {
		t.Fatal("warp lost the original landing animation")
	}
	impact := b.Shot.Impacts[0]
	if d := impact.At - portal.Start; d < 25.9/60 || d > 26.1/60 {
		t.Fatalf("warp teleported outside native opening time: %v", d)
	}
	if b.Shot.Duration < portal.Start+portal.Duration {
		t.Fatal("turn ended before the original portal faded")
	}
}

func TestNativeWarpMatchesOriginalLanding(t *testing.T) {
	var f struct {
		Map, Direction int
		Position       [2]float64 `json:"actor_position"`
		Wind           int        `json:"native_wind"`
		Slope          float64
		Charge         float64 `json:"raw_charge"`
		Elevation      float64 `json:"relative_elevation"`
		Samples        []struct {
			Tick, Mode int
			Position   [2]float64
		}
	}
	raw, e := os.ReadFile("testdata/native-warp-runtime.json")
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(raw, &f); e != nil {
		t.Fatal(e)
	}
	terrain, e := loadTerrain("../client/assets", f.Map)
	if e != nil {
		t.Fatal(e)
	}
	actor := &Unit{Seat: 0, Vehicle: 1, X: f.Position[0], Y: f.Position[1], Slope: f.Slope, Face: 1, HP: 300, MaxHP: 300}
	if f.Direction == 1 {
		actor.Face = -1
	}
	b := &Battle{Terrain: terrain, Width: terrain.W, Height: terrain.H, Wind: f.Wind, NativeAim: true, Units: []*Unit{actor}}
	shot := &Shot{}
	b.nativeVolley(actor, actor.worldAngle(f.Elevation), f.Charge/300, Weapon{Projectile: 102, Kind: "teleport", Wind: 1}, 0, shot)
	if len(shot.Trails) != 2 {
		t.Fatal("Warp fixture did not produce flight and portal")
	}
	flight, portal := shot.Trails[0], shot.Trails[1]
	for _, s := range f.Samples {
		if s.Mode == 0 && s.Tick < len(flight.Points) {
			p := flight.Points[s.Tick]
			if int(p[0]+.5) != int(s.Position[0]) || int(p[1]+.5) != int(s.Position[1]) {
				t.Fatalf("Warp flight tick %d: %v vs %v", s.Tick, p, s.Position)
			}
		}
		if s.Mode == 1 {
			if portal.Points[0] != s.Position {
				t.Fatalf("Warp landing: %v vs %v", portal.Points[0], s.Position)
			}
			break
		}
	}
}
