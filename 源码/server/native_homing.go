package main

import "math"

// Native CWeapon18::findTarget (00551b40) and CHMissile::findTarget
// (0056f650) run automatically after the launch-speed counter reaches zero.
// They select a fixed point within a forward cone; there is no manual click
// target and no guarantee that steering can overcome terrain or a bad shot.
func (b *Battle) acquireNativeHoming(p *nativeFlying) bool {
	if p.guided || p.speedCounter > 0 || (p.w.Projectile != 18 && p.w.Projectile != 101) {
		return false
	}
	cone, maximum, divisor := float32(30), float32(500), float32(50)
	if p.w.Projectile == 101 {
		// Constants 00be61dc=40, 00be6abc=600, 00bdbd54=30.
		cone, maximum, divisor = 40, 600, 30
	}
	speed := float32(math.Abs(float64(p.vx)) + math.Abs(float64(p.up)))
	rangeLimit := int(speed/divisor*600) + 100
	// Target selection uses the external integer pose written by 00480940,
	// rather than the higher precision internal integration coordinates.
	px, py := float32(int(p.x+.5)), float32(int(p.y+.5))
	heading := float64(int(p.angle + .5))
	best := float32(360)
	var selected *Unit
	for _, candidate := range b.Units {
		// +0x258/+0x25c are present/alive. Native targeting does not
		// inspect the separate stealth counter at +0x2c8 or team.
		if candidate.HP <= 0 {
			continue
		}
		tx, ty := float32(int(candidate.X)), float32(int(candidate.Y))
		target := nativeDirection(px, py, tx, ty)
		difference := float32(math.Abs(math.Mod(target-heading+540, 360) - 180))
		distance := float32(nativeRound3(math.Hypot(float64(tx-px), float64(ty-py))))
		score := distance/maximum*100 + difference
		if difference <= cone && distance <= float32(rangeLimit) && distance <= maximum && score < best {
			best, selected = score, candidate
		}
	}
	if selected == nil {
		return false
	}
	p.targetX, p.targetY = float64(int(selected.X)), float64(int(selected.Y))
	p.targetSeat = selected.Seat
	p.guideAngle, p.guideSpeed = heading, float64(speed)
	p.x, p.y = px, py
	p.guided = true
	return true
}
