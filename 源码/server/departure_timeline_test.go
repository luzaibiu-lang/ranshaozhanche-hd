package main

import (
	"encoding/json"
	"testing"
)

func TestDepartureDuringShotCannotResurrectThroughCheckpoint(t *testing.T) {
	for _, leaving := range []int64{1, 2} {
		t.Run(map[int64]string{1: "actor_and_owner", 2: "other_human"}[leaving], func(t *testing.T) {
			b := flatBattle()
			b.NativeAim = true
			b.Units[1].Player, b.Units[1].AI = 2, 0
			if e := b.fireNative(35, .4, 1); e != nil {
				t.Fatal(e)
			}
			if b.pending == nil || len(b.Shot.States) < 2 || len(b.Shot.Visuals) < 2 {
				t.Fatal("fixture requires an in-flight shot with future checkpoints")
			}
			r := &Room{ID: 1, Owner: 1, Battle: b, Members: []*Member{{ID: 1, Seat: 0}, {ID: 2, Seat: 4}}}
			w := &World{rooms: map[int]*Room{r.ID: r}, version: 1}
			w.leave(leaving)
			if len(r.Members) != 1 || r.Members[0].ID == leaving || r.Owner != r.Members[0].ID || w.rooms[r.ID] != r {
				t.Fatal("departure did not preserve the remaining human's room and ownership")
			}
			check := func(units []*Unit) {
				t.Helper()
				found := false
				for _, u := range units {
					if u.Player == leaving {
						found = true
						if !u.Departed || u.HP != 0 {
							t.Fatalf("departed player resurrected: player=%d hp=%d departed=%v", leaving, u.HP, u.Departed)
						}
					} else if u.Departed {
						t.Fatal("departure also marked the remaining participant")
					}
				}
				if !found {
					t.Fatal("departure removed unit identity from the battle")
				}
			}
			check(b.Units)
			check(b.pending.Units)
			check(b.copy().Units)
			for _, checkpoint := range b.Shot.States {
				check(checkpoint.Units)
				b.advanceShot(b.Shot.Started + checkpoint.At + .000001)
				check(b.Units)
			}
			wire, e := json.Marshal(b.Units)
			if e != nil {
				t.Fatal(e)
			}
			var published []*Unit
			if e = json.Unmarshal(wire, &published); e != nil {
				t.Fatal(e)
			}
			check(published)
		})
	}
}
