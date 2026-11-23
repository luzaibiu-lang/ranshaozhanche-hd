package main

import (
	"encoding/json"
	"testing"
)

func TestOriginalMapIdentityAndWeaponCosts(t *testing.T) {
	// Names/IDs come from the native switch table, not an invented catalogue.
	for id, expected := range map[int]string{1: "废弃都市", 2: "大雪山", 6: "神秘岩洞", 9: "干枯大地", 14: "天空之城", 19: "双龙柱"} {
		if mapNames[id-1] != expected {
			t.Fatalf("map %d identity changed", id)
		}
	}
	for _, sample := range []struct{ id, second, ultimate int }{{1, 12, 125}, {3, 13, 110}, {15, 13, 130}, {23, 12, 120}, {29, 14, 125}} {
		v := vehicle(sample.id)
		if v.Weapons[0].Cost != 0 || v.Weapons[1].Cost != sample.second || v.Weapons[2].Cost != sample.ultimate {
			t.Fatalf("native weapon costs changed for %d", sample.id)
		}
	}
}

func TestSuppliesMatchOriginalItemDescriptions(t *testing.T) {
	b := flatBattle()
	u := b.active()
	u.HP = 50
	if b.useItem(5) || u.HP != 100 {
		t.Fatal("small supply must heal 50 without ending the turn")
	}
	if !b.useItem(6) || u.HP != 200 {
		t.Fatal("large supply must heal 100 and end the turn")
	}
	ally := &Unit{Seat: 1, Player: 2, Team: 0, HP: 100, MaxHP: 300, SP: 50}
	b.Units = append(b.Units, ally)
	if !b.useItem(7) || ally.HP != 140 || u.HP != 240 {
		t.Fatal("team supply must heal each living ally 40")
	}
	u.SP = 40
	if b.useItem(8) || u.SP != 80 {
		t.Fatal("fuel must recover 40 SP")
	}
	if !b.useItem(11) || u.SP != 100 || ally.SP != 70 {
		t.Fatal("team fuel must recover 20 for each ally")
	}
	if b.useItem(12) || u.Stealth != 3 {
		t.Fatal("stealth must last three rounds")
	}
}

func TestSupplyFeedbackTracksNominalAmountAndEligibleUnits(t *testing.T) {
	b := flatBattle()
	u := b.active()
	u.HP = u.MaxHP - 5
	ally := &Unit{Seat: 1, Team: u.Team, HP: 40, MaxHP: 300}
	dead := &Unit{Seat: 2, Team: u.Team, MaxHP: 300}
	b.Units = append(b.Units, ally, dead)

	if !b.useItem(7) || u.HP != u.MaxHP || ally.HP != 80 || dead.HP != 0 {
		t.Fatal("team supply did not cap health or excluded the wrong units")
	}
	if len(b.Supplies) != 2 || b.Supplies[0].Seat != u.Seat || b.Supplies[1].Seat != ally.Seat {
		t.Fatalf("unexpected team supply recipients: %+v", b.Supplies)
	}
	for i, cue := range b.Supplies {
		if cue.Amount != 40 || cue.Fuel || cue.ID != uint64(i+1) || cue.At <= 0 {
			t.Fatalf("invalid health feedback: %+v", cue)
		}
		if cue.ItemEffect != (cue.Seat == u.Seat) {
			t.Fatalf("team recovery must place one native item burst on its user: %+v", cue)
		}
	}
	b.useItem(5)
	if u.HP != u.MaxHP || b.Supplies[2].Amount != 50 || !b.Supplies[2].ItemEffect {
		t.Fatal("full health must stay capped while retaining the original +50 feedback")
	}
	u.SP = 140
	b.useItem(15)
	b.useItem(8)
	if u.SP != 180 || u.Move != float64(180)/(vehicle(u.Vehicle).MoveCost*.5) || !b.Supplies[3].Fuel || b.Supplies[3].Amount != 40 {
		t.Fatal("fuel feedback must preserve the engine's discounted movement cost")
	}
	b.useItem(11)
	b.useItem(6)
	snapshot, err := json.Marshal(b)
	if err != nil {
		t.Fatal(err)
	}
	var wire struct {
		Supplies []struct {
			ItemEffect *bool `json:"item_effect"`
		} `json:"supplies"`
	}
	if err := json.Unmarshal(snapshot, &wire); err != nil {
		t.Fatal(err)
	}
	// An omitted flag plays the legacy recovery effect in the client.
	wantEffects := []bool{true, false, true, false, false, false, true}
	if len(wire.Supplies) != len(wantEffects) {
		t.Fatalf("got %d supply cues, want %d", len(wire.Supplies), len(wantEffects))
	}
	for i, want := range wantEffects {
		if got := wire.Supplies[i].ItemEffect; got == nil || *got != want {
			t.Errorf("supply cue %d must encode item_effect:%t", i+1, want)
		}
	}
	b.Wind = 0
	b.useItem(13)
	if b.Wind != 0 {
		t.Fatal("reversing calm wind must keep wind strength zero")
	}
	b.Wind = 18
	b.useItem(13)
	if b.Wind != -18 {
		t.Fatal("wind change must preserve strength")
	}
}

func TestOriginalShieldBlocksOneHitAndShockRevealsStealth(t *testing.T) {
	b := flatBattle()
	u := b.active()
	b.useItem(10)
	hp := u.HP
	shot := &Shot{}
	b.impact(b.Units[1], Weapon{Damage: 100}, Impact{X: u.X, Y: u.Y - 15, Radius: 30, Kind: "normal"}, shot)
	if u.HP != hp || u.Shield != 0 {
		t.Fatal("shield did not absorb one attack")
	}
	u.Stealth = 3
	b.impact(b.Units[1], Weapon{Damage: 10}, Impact{X: u.X, Y: u.Y - 15, Radius: 30, Kind: "stun"}, shot)
	if u.Stun != 3 || u.Stealth != 0 {
		t.Fatal("electric shock must prevent movement for three turns and reveal stealth")
	}
}

func TestFuelItemsDoNotBypassFinalShockTurn(t *testing.T) {
	b := flatBattle()
	u := b.active()
	u.Stun = 1
	b.advance()
	b.advance()
	if b.active() != u || u.Stun != 0 || u.Move != 0 {
		t.Fatal("fixture needs the final movement-restricted turn")
	}
	b.useItem(8)
	b.useItem(15)
	if u.Move != 0 || b.move(5) == nil {
		t.Fatal("restoring fuel or halving movement cost must not remove shock")
	}
	b.advance()
	b.advance()
	if b.active() != u || u.Move <= 0 || b.move(5) != nil {
		t.Fatal("movement did not recover after the final restricted turn")
	}
}
