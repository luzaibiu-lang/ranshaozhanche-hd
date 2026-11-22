package main

import (
	"testing"
	"time"
)

func finishAIWalkForTest(t *testing.T, w *World, b *Battle) {
	t.Helper()
	for n := 0; b.aiAction != nil; n++ {
		if n > 45 {
			t.Fatal("AI walk never finished")
		}
		b.aiAt = time.Now().Add(-150 * time.Millisecond)
		w.tick()
	}
}

func TestAIWalkPublishesPositionsBeforeFiring(t *testing.T) {
	b := flatBattle()
	b.Active = 4
	w := &World{rooms: map[int]*Room{1: {ID: 1, Battle: b}}}
	start := b.active().X
	w.tick()
	dist := start - b.active().X
	if b.aiAction == nil || b.pending != nil || dist <= 0 || dist >= 34 {
		t.Fatalf("expected intermediate walking state, moved %v", dist)
	}
	for b.aiAction.remaining != 0 {
		b.aiAt = time.Now().Add(-time.Millisecond * 150)
		w.tick()
	}
	if start-b.active().X != 34 || b.pending != nil || time.Until(b.aiAt) <= 300*time.Millisecond {
		t.Fatal("the final walking position must be visible before firing")
	}
	b.aiAt = time.Now().Add(-time.Millisecond)
	w.tick()
	if b.pending == nil || b.Shot == nil || b.aiAction != nil {
		t.Fatal("AI didn't fire after completing its walk")
	}
}

func TestAIWalkExpiresWithItsTurn(t *testing.T) {
	b := flatBattle()
	b.Active = 4
	w := &World{rooms: map[int]*Room{1: {ID: 1, Battle: b}}}
	w.tick()
	if b.aiAction == nil {
		t.Fatal("expected AI to be walking")
	}
	b.Deadline = nowSeconds() - 1
	w.tick()
	if b.aiAction != nil || b.Active != 0 || b.Shot != nil {
		t.Fatal("expired AI move or shot escaped its turn")
	}
}
