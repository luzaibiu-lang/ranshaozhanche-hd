package main

import "math"

// 004d9cc0 obtains the mid-angle of occupied pixels inside a forward
// semicircle. It is not a height-map slope: crater walls and overhangs count.
func (t *Terrain) nativeContactNormal(x, y, heading, radius int) (int, bool) {
	low, high, count := 360, 0, 0
	for py := max(0, y-radius); py <= min(t.H-1, y+radius); py++ {
		for px := max(0, x-radius); px <= min(t.W-1, x+radius); px++ {
			if !t.solid(float64(px), float64(py)) || int(math.Hypot(float64(px-x), float64(py-y))) > radius {
				continue
			}
			angle := int(nativeDirection(float32(x), float32(y), float32(px), float32(py)))
			if absNativeAngle(heading, angle) < 90 {
				low, high = min(low, angle), max(high, angle)
				count++
			}
		}
	}
	return (low + high) / 2, count > 0
}

func signedNativeAngle(from, to int) int {
	return (to-from+540)%360 - 180
}

func absNativeAngle(from, to int) int {
	return int(math.Abs(float64(signedNativeAngle(from, to))))
}

// 00564910: this shell bounces once, picks up nearby tanks, and detonates
// when the reflected upward motion finishes. The initial terrain contact is
// not an explosion. Sides terminate; the top remains open by user request.
func (b *Battle) nativeReflect(p *nativeFlying, oldX, oldY float32) bool {
	grenade := p.w.Projectile == 100
	ricochet := p.w.Projectile == 78
	if grenade && p.age >= 210 {
		return true
	}
	if p.frozen {
		return !grenade
	}
	if p.bounced && !grenade && !ricochet {
		return p.up < 0 || p.frozen
	}
	steps := int(math.Hypot(float64(p.x-oldX), float64(p.y-oldY)))
	for i := 0; i <= steps+1; i++ {
		x := int(float64(oldX) + float64(p.x-oldX)*float64(i)/float64(max(1, steps)))
		y := int(float64(oldY) + float64(p.y-oldY)*float64(i)/float64(max(1, steps)))
		if i == steps+1 {
			x, y = int(p.x+.5), int(p.y+.5)
		}
		heading := int(p.angle)
		if (grenade || ricochet) && x == p.lastBounceX && y == p.lastBounceY {
			continue
		}
		normal, hit := b.Terrain.nativeContactNormal(x, y, heading, 8)
		if !hit {
			continue
		}
		normal = (normal + 180) % 360
		reflected := normal - signedNativeAngle(normal, (heading+180)%360)
		p.bounced = true
		p.bounceCount++
		if !grenade && !ricochet && reflected >= 181 && reflected <= 360 {
			return true
		}
		speed := nativeRound3((math.Abs(float64(p.vx)) + math.Abs(float64(p.up))) * .5)
		if grenade || ricochet {
			speed = nativeRound3((math.Abs(float64(p.vx)) + math.Abs(float64(p.up))) * float64(float32(.35)))
		}
		angle := float64(int(float64(reflected)+.5)%360) * nativeRadiansPerDegree
		p.x, p.y = float32(x), float32(y)
		p.vx, p.up = float32(nativeRound3(speed*math.Cos(angle))), float32(nativeRound3(speed*math.Sin(angle)))
		p.drift, p.acceleration = 0, 0
		p.speedCounter, p.launchSpeed = float32(speed), float32(speed)
		p.angle = float64(reflected)
		p.frozen = speed <= float64(float32(.2))
		p.lastBounceX, p.lastBounceY = x, y
		for _, u := range b.Units {
			if grenade || ricochet {
				break
			}
			if u.HP > 0 && int(math.Hypot(u.X-float64(x), u.Y-float64(y))) < 15 {
				p.carried = append(p.carried, u.Seat)
			}
		}
		return ricochet && p.bounceCount >= 2
	}
	return false
}
