package main

import (
	"math"
	"testing"
)

func TestNativeWeaponIdentityAndStreams(t *testing.T) {
	// Compare concrete samples against the original weapon factory and CTank
	// stream loop: the first vehicle has 1 / 3 / 5 projectiles, not generic
	// 1 / 3 / 3 shells with invented 72 / 88 / 175 damage values.
	v := vehicle(1)
	if v.HP != 300 || math.Abs(v.Armor-1.1) > .0001 {
		t.Fatal("native vehicle durability changed")
	}
	for i, w := range v.Weapons {
		counts := []int{1, 3, 5}
		damage := []int{62, 28, 26}
		if w.Count != counts[i] || w.Damage != damage[i] {
			t.Fatalf("native weapon %d drifted: %+v", i, w)
		}
	}
	if vehicle(30).Weapons[0].Count != 20 || vehicle(26).Weapons[1].Count != 4 || vehicle(26).Weapons[2].Count != 6 {
		t.Fatal("native repeated streams or beam arrays lost")
	}
	b := flatBattle()
	b.active().Vehicle = 30
	b.active().SP = 200
	if e := b.fire(55, .7, 0); e != nil {
		t.Fatal(e)
	}
	if len(b.Shot.Trails) != 20 || b.Shot.Trails[0].Start != 0 || b.Shot.Trails[19].Start <= 1 {
		t.Fatal("stream was flattened or clipped")
	}
}

func TestDoubleFiresASecondVolleyAndMovementUsesNativeFuel(t *testing.T) {
	b := flatBattle()
	b.active().Double = true
	if e := b.fire(65, .65, 0); e != nil {
		t.Fatal(e)
	}
	if len(b.Shot.Trails) != 2 || b.Shot.Trails[1].Start < b.Shot.Trails[0].Duration {
		t.Fatal("double item became simultaneous spread")
	}
	normal := flatBattle()
	efficient := flatBattle()
	normal.active().SP = 100
	efficient.active().SP = 100
	efficient.useItem(15)
	if e := normal.move(40); e != nil {
		t.Fatal(e)
	}
	if e := efficient.move(40); e != nil {
		t.Fatal(e)
	}
	if normal.active().SP != 95 || efficient.active().SP != 98 {
		t.Fatalf("native movement fuel and 50%% economy wrong: %d %d", normal.active().SP, efficient.active().SP)
	}
}
