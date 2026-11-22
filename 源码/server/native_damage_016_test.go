package main

import (
	"math"
	"testing"
)

func TestNativeShieldBlocksWholeShotAndDoubleVolley(t *testing.T) {
	b := impactMatrixBattle(8, 600, 300)
	actor, target := b.Units[0], b.Units[1]
	target.Shield = 1
	actor.Double = true
	shot := &Shot{}
	for pellet := 0; pellet < 12; pellet++ {
		b.impact(actor, Weapon{Damage: 95, Radius: 55, Projectile: 1}, Impact{X: target.X, Y: target.Y, Radius: 55, Kind: "normal", At: float64(pellet) / 60}, shot)
		if target.HP != 300 || target.Shield != 1 || actor.Damage != 0 {
			t.Fatalf("pellet %d bypassed an active native shield: hp=%d shield=%d damage=%d", pellet, target.HP, target.Shield, actor.Damage)
		}
	}
	if !shot.shielded[target.Seat] {
		t.Fatal("shield usage was not marked for action-sync consumption")
	}
	// Exercise the actual fireWorld completion, including all native children
	// and the second double volley, rather than just calling impact in a loop.
	probe := impactMatrixBattle(8, 0, 0)
	probeShot := &Shot{}
	probe.nativeVolley(probe.Units[0], 35, .35, vehicle(8).Weapons[1], 0, probeShot)
	// The first stream shell has no random spread. Place the shield on that
	// real endpoint instead of depending on one of the random shells hitting x=500.
	points := probeShot.Trails[0].Points
	b = impactMatrixBattle(8, points[len(points)-1][0], 300)
	b.Units[0].Double = true
	b.Units[1].Shield = 1
	if err := b.fireNative(35, .35, 1); err != nil {
		t.Fatal(err)
	}
	if len(b.Shot.Trails) != 12 || !b.Shot.shielded[4] {
		t.Fatal("fixture did not exercise a real twelve-shell double volley hitting the shield")
	}
	if b.pending.Units[1].HP != 300 || b.pending.Units[1].Shield != 0 || b.Units[1].Shield != 1 {
		t.Fatalf("shield lifecycle: live hp=%d shield=%d, resolved hp=%d shield=%d", b.Units[1].HP, b.Units[1].Shield, b.pending.Units[1].HP, b.pending.Units[1].Shield)
	}
}

func TestNativeUnusedShieldSurvivesShot(t *testing.T) {
	b := impactMatrixBattle(1, 1700, 300)
	b.Units[1].Shield = 1
	if err := b.fireNative(35, .15, 0); err != nil {
		t.Fatal(err)
	}
	if b.pending.Units[1].Shield != 1 {
		t.Fatal("untriggered native shield was consumed")
	}
}

func TestNativePowerBoostPrecedesArmorAndFalloff(t *testing.T) {
	for id := 1; id <= 30; id++ {
		for _, raw := range []int{10, 16, 41, 62, 95, 250} {
			b := impactMatrixBattle(1, 600, 10000)
			b.Units[0].Power = true
			b.Units[1].Vehicle = id
			const radius, distance = 65, 5
			base := int(float64(raw+raw/2)*vehicle(id).Armor + .5)
			want := max(1, base*(radius-distance)/radius)
			b.impact(b.Units[0], Weapon{Damage: raw, Radius: radius, Projectile: 1}, Impact{X: 595, Y: 800, Radius: radius, Kind: "normal"}, &Shot{})
			if got := 10000 - b.Units[1].HP; got != want {
				t.Fatalf("vehicle%d raw%d power damage=%d want native %d", id, raw, got, want)
			}
		}
	}
}

func TestNativeGroundWaveHasSevenOriginalBursts(t *testing.T) {
	b := impactMatrixBattle(7, 0, 0)
	shot := &Shot{}
	w := vehicle(7).Weapons[2]
	b.nativeVolley(b.Units[0], 35, .35, w, 0, shot)
	if w.Projectile != 5 || len(shot.Impacts) != 7 {
		t.Fatalf("00545960 requires burst counter 0,18,...,108: got %d", len(shot.Impacts))
	}
	for i := 1; i < 7; i++ {
		if math.Abs(shot.Impacts[i].At-shot.Impacts[i-1].At-.3) > .000001 {
			t.Fatal("native wave burst interval changed")
		}
	}
}
