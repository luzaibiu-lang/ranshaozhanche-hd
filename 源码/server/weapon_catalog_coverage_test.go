package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"testing"
)

// This is a coverage/safety check. Runtime fixtures in the other native tests
// remain the authority for behavioral equivalence; completing a volley alone
// does not establish that every original weapon has been fully restored.
func TestAllNativeWeaponCatalogBindings(t *testing.T) {
	var evidence struct {
		Logical []struct {
			Weapon      int   `json:"weapon"`
			Projectiles []int `json:"projectiles"`
		} `json:"logical_weapons"`
	}
	raw, err := os.ReadFile("../docs/original-shots.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &evidence); err != nil {
		t.Fatal(err)
	}
	bindings := map[int][]int{}
	for _, row := range evidence.Logical {
		bindings[row.Weapon] = row.Projectiles
	}
	for id := 1; id <= 30; id++ {
		v := vehicle(id)
		for slot, w := range v.Weapons {
			if w.NativeID != originalWeaponIDs[id-1][slot] {
				t.Errorf("vehicle=%d slot=%d logical=%d want=%d", id, slot, w.NativeID, originalWeaponIDs[id-1][slot])
			}
			found := false
			for _, projectile := range bindings[w.NativeID] {
				found = found || projectile == w.Projectile
			}
			if !found {
				t.Errorf("vehicle=%d slot=%d logical=%d projectile=%d absent in original factory %v", id, slot, w.NativeID, w.Projectile, bindings[w.NativeID])
			}
			if !nativeSimulatedWeapon(w) {
				t.Errorf("vehicle=%d slot=%d falls back to the legacy guessed trajectory", id, slot)
			}
			wantCost := originalWeaponCosts[id-1][slot]
			if slot == 0 {
				wantCost = 0 // Explicit user preference, retained from old edition.
			}
			if w.Cost != wantCost {
				t.Errorf("vehicle=%d slot=%d cost=%d want=%d", id, slot, w.Cost, wantCost)
			}
		}
	}
}

func TestAllNinetyNativeWeaponsProduceFiniteVolleys(t *testing.T) {
	for id := 1; id <= 30; id++ {
		for slot, w := range vehicle(id).Weapons {
			for _, face := range []int{1, -1} {
				for _, setting := range []struct{ elevation, power float64 }{{35, .65}, {80, 1}, {-10, .08}} {
					name := fmt.Sprintf("vehicle%02d/slot%d/face%d/angle%.0f", id, slot, face, setting.elevation)
					t.Run(name, func(t *testing.T) {
						b := flatBattle()
						b.NativeAim = true
						actor := b.Units[0]
						actor.Vehicle, actor.Face = id, face
						if face < 0 {
							actor.X, b.Units[1].X = 1600, 1000
						}
						shot := &Shot{}
						b.nativeVolley(actor, actor.worldAngle(setting.elevation), setting.power, w, 0, shot)
						if len(shot.Trails) == 0 {
							t.Fatal("weapon did not create a projectile")
						}
						if math.IsNaN(shot.Duration) || math.IsInf(shot.Duration, 0) || shot.Duration <= 0 || shot.Duration > 40 {
							t.Fatalf("invalid or unbounded shot duration %f", shot.Duration)
						}
						for i, trail := range shot.Trails {
							if len(trail.Points) == 0 || len(trail.Points) > 1801 || math.IsNaN(trail.Duration) || math.IsInf(trail.Duration, 0) {
								t.Fatalf("invalid trail %d: points=%d duration=%f", i, len(trail.Points), trail.Duration)
							}
							for _, point := range trail.Points {
								if math.IsNaN(point[0]) || math.IsNaN(point[1]) || math.IsInf(point[0], 0) || math.IsInf(point[1], 0) {
									t.Fatalf("nonfinite projectile point %v", point)
								}
							}
						}
						for _, impact := range shot.Impacts {
							if math.IsNaN(impact.X) || math.IsNaN(impact.Y) || math.IsNaN(impact.At) || impact.At > shot.Duration+.0001 {
								t.Fatalf("invalid impact %+v", impact)
							}
						}
					})
				}
			}
		}
	}
}

func TestKnightPrimaryPreservesNative47IdentityAndCrater(t *testing.T) {
	w := vehicle(15).Weapons[0]
	if w.NativeID != 47 || w.Projectile != 47 || w.Damage != 62 || w.Radius != 55 {
		t.Fatalf("knight primary lost its original variant: %+v", w)
	}
	if nativeCraterIDs[47] != nativeCraterIDs[1] || nativeCraterIDs[47] != 9 {
		t.Fatal("native 00541e50 crater mask differs for shared CWeapon01 update")
	}
	var visuals struct {
		Projectiles map[string]struct {
			Sprite, Source string
			Layers         []struct {
				First, Count int
				Blend        string
			}
		}
	}
	data, err := os.ReadFile("../client/assets/projectiles/native-visuals.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &visuals); err != nil {
		t.Fatal(err)
	}
	variant := visuals.Projectiles["47"]
	if variant.Sprite != "44" || variant.Source != "New/Weapon44.spr" || len(variant.Layers) != 2 {
		t.Fatalf("wrong native47 sprite binding: %+v", variant)
	}
	for i, layer := range variant.Layers {
		if layer.First != 1 || layer.Count != 1 || layer.Blend != []string{"add", "mix"}[i] {
			t.Fatalf("00541b20 native47 layer %d drifted: %+v", i, layer)
		}
	}
	var audio struct {
		Projectiles map[string]struct{ Fire, Impact, Routine string }
	}
	data, err = os.ReadFile("../client/assets/audio/native-audio.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &audio); err != nil {
		t.Fatal(err)
	}
	if audio.Projectiles["47"] != audio.Projectiles["1"] || audio.Projectiles["47"].Routine != "00541e50" {
		t.Fatal("native47 must retain the native01 shot and impact sound identity")
	}
	b := flatBattle()
	b.NativeAim = true
	b.Units[0].Vehicle = 15
	shot := &Shot{}
	b.nativeVolley(b.Units[0], 35, .65, w, 0, shot)
	if len(shot.Trails) != 1 || shot.Trails[0].Projectile != 47 || len(shot.Impacts) != 1 || shot.Impacts[0].Projectile != 47 || len(b.Holes) != 1 || b.Holes[0].Mask != 10 {
		t.Fatalf("native47 must reach the client and use the original crater: trails=%+v impacts=%+v holes=%+v", shot.Trails, shot.Impacts, b.Holes)
	}
}
