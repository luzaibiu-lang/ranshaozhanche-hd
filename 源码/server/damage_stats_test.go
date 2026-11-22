package main

import "testing"

func TestScoreCountsAppliedDamageAndSurvivesSnapshotCopy(t *testing.T) {
	b := flatBattle()
	actor := b.active()
	target := b.Units[1]
	target.HP = 9
	impact := Impact{X: target.X, Y: target.Y - 15, Radius: 55, Kind: "normal"}
	shot := &Shot{}
	b.impact(actor, Weapon{Damage: 100, Radius: 55}, impact, shot)
	if target.HP != 0 || actor.Damage != 9 {
		t.Fatalf("score should count actual HP removed: hp=%d damage=%d", target.HP, actor.Damage)
	}
	if b.copy().active().Damage != 9 {
		t.Fatal("score disappeared when battle was copied for the next shot")
	}
}
