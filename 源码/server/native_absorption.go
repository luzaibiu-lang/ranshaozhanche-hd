package main

import "math"

// CWeapon22: 00555680/00555770. HP/SP is delivered by the returning
// object, not by the initial explosion. It ignores terrain on its way home.
type nativeRefund struct {
	x, y, angle float64
	amount      int
	sp          bool
}

type nativeAbsorption struct {
	nativeRefund
	mode  int
	limit float32
}

func newNativeAbsorption(refund nativeRefund) *nativeFlying {
	a := float64((int(refund.angle+.5)%360 + 360) % 360)
	return &nativeFlying{w: Weapon{Projectile: 22, Kind: "hp_return"},
		x: float32(refund.x), y: float32(refund.y), angle: a, initialAngle: a,
		targetX: refund.x, targetY: refund.y,
		absorption: &nativeAbsorption{nativeRefund: refund, limit: 10}}
}

func (p *nativeFlying) stepAbsorption(actor *Unit) bool {
	a := p.absorption
	if actor.HP <= 0 {
		p.dead = true
		return false
	}
	if a.mode == 3 {
		if a.sp {
			actor.SP = min(200, actor.SP+a.amount)
		} else {
			actor.HP = min(actor.MaxHP, actor.HP+a.amount)
		}
		p.dead = true
		return true
	}
	oldX, oldY := p.x, p.y
	p.age++
	if a.mode == 0 {
		phase := min(90, float64(p.age)*1.5)
		distance := float32(math.Sin(phase*nativeRadiansPerDegree)) * 70
		r := p.initialAngle * nativeRadiansPerDegree
		p.x = float32(a.x + float64(int(math.Cos(r)*float64(distance)+.5)))
		p.y = float32(a.y - float64(int(math.Sin(r)*float64(distance)+.5)))
		if phase >= 90 {
			a.mode = 1
			p.targetX, p.targetY = actor.X, actor.Y+40
			p.guideAngle = p.initialAngle
			p.guideSpeed = 0
		}
	} else {
		target := nativeDirection(p.x, p.y, float32(p.targetX), float32(p.targetY))
		delta := math.Mod(target-p.guideAngle+540, 360) - 180
		turn := .5
		if a.mode == 1 {
			turn = min(5, .6+float64(max(0, p.age-61))*.1)
		} else {
			turn = 3.5 + float64(max(0, p.rayTicks))*.1
		}
		p.guideAngle = float64(float32(p.guideAngle) + float32(max(-turn, min(turn, delta))))
		p.guideSpeed = float64(float32(p.guideSpeed) + float32(.15))
		r := nativeRound3(p.guideAngle) * nativeRadiansPerDegree
		p.x += float32(nativeRound3(math.Cos(r) * p.guideSpeed))
		p.y -= float32(nativeRound3(math.Sin(r) * p.guideSpeed))
		// Native collision and target checks use the rounded object position.
		x, y := float64(int(p.x+.5)), float64(int(p.y+.5))
		distance := float32(math.Hypot(x-actor.X, y-actor.Y))
		limit := max(float32(.2), min(float32(20), distance/250*20))
		if a.mode == 2 {
			a.limit = min(max(1, a.limit-float32(.01)), limit)
			limit = min(limit, a.limit)
		}
		p.guideSpeed = min(p.guideSpeed, float64(limit))
		if a.mode == 1 && math.Hypot(x-p.targetX, y-p.targetY) <= 60 {
			a.mode = 2
			p.rayTicks = 0
		}
		if a.mode == 2 {
			p.targetX, p.targetY = actor.X, actor.Y
			p.rayTicks++
			if distance <= 5 {
				a.mode = 3
			}
		}
	}
	if p.x != oldX || p.y != oldY {
		p.angle = nativeDirection(oldX, oldY, p.x, p.y)
	}
	return false
}
