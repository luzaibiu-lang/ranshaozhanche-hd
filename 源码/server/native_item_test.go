package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestStatusItemOverridesEveryVehicleWeapon(t *testing.T) {
	base := flatBattle()
	base.NativeAim = true
	for v := 1; v <= 30; v++ {
		for slot := 0; slot < 3; slot++ {
			for _, tc := range []struct {
				id, projectile int
				kind           string
			}{{16, itemHealProjectile, "heal"}, {17, itemBlindProjectile, "blind"}} {
				t.Run(fmt.Sprintf("vehicle%d-slot%d-item%d", v, slot, tc.id), func(t *testing.T) {
					// fireNative clones the terrain before simulation; the flat input is read-only.
					b := *base
					actor, target := *base.Units[0], *base.Units[1]
					actor.Vehicle, actor.SP, actor.ShotMode = v, 0, tc.id
					actor.HP = actor.MaxHP - 80
					b.Units = []*Unit{&actor, &target}
					if err := b.fireNative(vehicle(v).AimMin, 0, slot); err != nil {
						t.Fatal(err)
					}
					if len(b.Shot.Trails) != 1 || b.Shot.Trails[0].Projectile != tc.projectile ||
						len(b.Shot.Impacts) != 1 || b.Shot.Impacts[0].Kind != tc.kind || len(b.pending.Holes) != 0 {
						t.Fatalf("wrong status projectile, impacts or terrain for %s", tc.kind)
					}
					hit := b.pending.Units[0]
					if tc.id == 16 && hit.HP != actor.HP+70 || tc.id == 17 && (hit.HP != actor.HP || hit.Blind != 3) {
						t.Fatalf("status hit HP %d, blind %d (started at %d)", hit.HP, hit.Blind, actor.HP)
					}
				})
			}
		}
	}
}

func TestNativeItemProjectilesAndNonDestructiveStatusEffects(t *testing.T) {
	for _, tc := range []struct{ item, projectile int }{{2, 100}, {3, 101}, {4, 102}, {9, 104}} {
		b := flatBattle()
		b.NativeAim = true
		b.active().ShotMode = tc.item
		if e := b.fireNative(45, .4, 0); e != nil {
			t.Fatal(e)
		}
		if b.Shot.Trails[0].Projectile != tc.projectile {
			t.Fatalf("item %d emitted wrong native projectile", tc.item)
		}
		if tc.item == 2 && b.Shot.Trails[0].Duration != 3.5 {
			t.Fatalf("native grenade must retain its 210 tick fuse, got %.3f", b.Shot.Trails[0].Duration)
		}
		if tc.item == 9 || tc.item == 4 {
			if len(b.pending.Holes) != 0 {
				t.Fatal("status item destroyed terrain")
			}
		}
	}
	b := flatBattle()
	b.NativeAim = true
	target := b.Units[1]
	target.Stealth = 3
	hp := target.HP
	b.impact(b.active(), Weapon{Kind: "stun", Damage: 58, Radius: 90, Projectile: 104}, Impact{X: target.X, Y: target.Y, Radius: 90, Kind: "stun"}, &Shot{})
	if target.HP != hp || target.Stun != 3 || target.Stealth != 0 || len(b.Holes) > 0 {
		t.Fatal("electric shock must disable movement and stealth without direct damage or crater")
	}
}

func TestNativeSlopeWrapKeepsRelativeElevationAfterFiring(t *testing.T) {
	for _, face := range []int{-1, 1} {
		b := flatBattle()
		b.NativeAim = true
		b.active().Face = face
		b.active().Slope = 355
		if e := b.fireNative(35, .4, 0); e != nil {
			t.Fatal(e)
		}
		if b.active().Elevation != 35 {
			t.Fatalf("relative elevation corrupted after wrapping slope: %v", b.active().Elevation)
		}
	}
}

func TestFutureShotCheckpointsAreNotSentToClients(t *testing.T) {
	b := flatBattle()
	b.NativeAim = true
	if e := b.fireNative(35, .4, 1); e != nil {
		t.Fatal(e)
	}
	if len(b.Shot.States) < 2 {
		t.Fatal("fixture needs native impact timeline")
	}
	raw, e := json.Marshal(b.Shot)
	if e != nil {
		t.Fatal(e)
	}
	var wire map[string]any
	if e = json.Unmarshal(raw, &wire); e != nil {
		t.Fatal(e)
	}
	if _, exists := wire["states"]; exists {
		t.Fatal("private future simulation copied into every network snapshot")
	}
}
