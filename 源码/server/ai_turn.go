package main

import (
	"math"
	"time"
)

// A plan is valid for one live turn. Walking is observable through normal
// position snapshots before the final aim and projectile are published.
type aiTurnAction struct {
	generation uint64
	remaining  int
	face       int
	angle      float64
	power      float64
	weapon     int
	pass       bool
}

func (b *Battle) stepAIAction(now time.Time) {
	plan := b.aiAction
	bot := b.active()
	if plan == nil || plan.generation != b.Generation || bot == nil || bot.HP <= 0 || bot.AI == 0 {
		b.aiAction = nil
		return
	}
	if plan.remaining != 0 {
		direction := 1
		if plan.remaining < 0 {
			direction = -1
		}
		// Use the native one-pixel tick and the player's uphill slowdown.
		for steps := 0; steps < 12 && !b.aiAt.After(now) && plan.remaining != 0; steps++ {
			slope := math.Mod(bot.Slope+540, 360) - 180
			stepTime := (1 + max(0, slope*float64(direction))/65*2.5) / 60
			before := bot.X
			if err := b.move(float64(direction)); err != nil || before == bot.X {
				plan.remaining = 0
				break
			}
			plan.remaining -= direction
			b.aiAt = b.aiAt.Add(time.Duration(stepTime * float64(time.Second)))
		}
		if plan.remaining == 0 {
			// Let both clients receive the standing pose before the shot.
			b.aiAt = now.Add(400 * time.Millisecond)
		}
		return
	}
	b.aiAction = nil
	bot.Face = plan.face
	bot.Aim = bot.worldAngle(bot.Elevation)
	if plan.pass {
		b.advance()
		return
	}
	var err error
	if b.NativeAim {
		err = b.fireNative(plan.angle, plan.power, plan.weapon)
	} else {
		err = b.fire(plan.angle, plan.power, plan.weapon)
	}
	if err != nil {
		b.advance()
	}
}
