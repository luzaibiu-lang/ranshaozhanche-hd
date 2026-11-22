package main

import "math"

// Original double at 00bd8488. Its truncated degree constant affects integer
// muzzle rounding (for example a left-facing Red Dragon at 150 degrees).
const nativeRadiansPerDegree = 0.017453288659453392

// HD item protocol IDs, separate from vehicle weapon IDs.
const itemHealProjectile = 105
const itemBlindProjectile = 106

// Original 00481050/00481780/00480130: 60 logic ticks, raw charge 0..300,
// charge/15 pixels per tick, gravity 0.18, wind/9.5 rounded to tenths and
// accumulated as displacement acceleration /100. Float state is native f32.
var nativeMountOffsets = [10][2]float64{{-1, -22}, {-2, -20}, {5, -18}, {4, -23}, {2, -23}, {-6, -19}, {0, -25}, {0, -20}, {16, -24}, {0, -20}}
var nativeBarrelLengths = [10]float64{18, 15, 6, 10, 10, 23, 5, 15, 15, 15}

func nativeMuzzle(actor *Unit, angle float64) (float64, float64) {
	family := (max(1, actor.Vehicle) - 1) % 10
	offset := nativeMountOffsets[family]
	mountAngle := math.Trunc(math.Atan2(-offset[1], offset[0]) * 180 / math.Pi)
	if actor.Face < 0 {
		mountAngle = 180 - mountAngle
	}
	mountAngle = (actor.Slope + mountAngle) * nativeRadiansPerDegree
	distance := math.Trunc(math.Hypot(offset[0], offset[1]))
	x := actor.X + math.Trunc(math.Cos(mountAngle)*distance+.5)
	y := actor.Y - math.Trunc(math.Sin(mountAngle)*distance+.5)
	radians := angle * nativeRadiansPerDegree
	return x + math.Trunc(math.Cos(radians)*nativeBarrelLengths[family]+.5), y - math.Trunc(math.Sin(radians)*nativeBarrelLengths[family]+.5)
}

func nativeBallisticProjectile(id int) bool {
	switch id {
	case 1, 2, 7, 8, 9, 11, 12, 13, 15, 16, 17, 19, 20, 21, 24, 26, 27, 28, 29, 47, 48, 49, 58, 59, 60, 78, 90, 92, 100, 103, 104, itemHealProjectile, itemBlindProjectile:
		return true
	}
	return false
}

func (t *Terrain) projectileContact(x, y float64, radius int) bool {
	ix, iy := int(x+.5), int(y+.5)
	for py := max(0, iy-radius); py <= min(t.H-1, iy+radius); py++ {
		for px := max(0, ix-radius); px <= min(t.W-1, ix+radius); px++ {
			if t.Solid[py*t.W+px] != 0 {
				return true
			}
		}
	}
	return false
}

func (b *Battle) nativeTrajectory(actor *Unit, angle, power float64, w Weapon) (Trail, Impact, bool) {
	x0, y0 := nativeMuzzle(actor, angle)
	x, y := float32(x0), float32(y0)
	radians := float64(int(angle+.5)%360) * nativeRadiansPerDegree
	rawCharge := math.Floor(power*300 + .5)
	speed := math.Floor((rawCharge/15+.0005)*1000) / 1000
	vx := float32(math.Floor((speed*math.Cos(radians)+.0005)*1000) / 1000)
	up := float32(math.Floor((speed*math.Sin(radians)+.0005)*1000) / 1000)
	wind := math.Floor((float64(b.Wind)/9.5+.05)*10) / 10
	acceleration := float32(math.Floor((wind/100+.0005)*1000)/1000) * float32(w.Wind)
	drift := float32(0)
	points := [][2]float64{{float64(x), float64(y)}}
	for tick := 0; tick < 1200; tick++ {
		drift += acceleration
		x += vx + drift
		y -= up
		up -= float32(.18)
		points = append(points, [2]float64{float64(x), float64(y)})
		duration := float64(tick+1) / 60
		trail := Trail{Points: points, Kind: w.Kind, Duration: duration, Projectile: w.Projectile}
		// User-requested boundary behavior: only the two sides and bottom
		// terminate a shot. A shot above the map keeps its physical trajectory.
		if x < 0 || x >= float32(b.Width) || y >= float32(b.Height) {
			return trail, Impact{}, false
		}
		hit := b.Terrain.projectileContact(float64(x), float64(y), 5)
		if !hit {
			for _, u := range b.Units {
				if u.HP > 0 && int(math.Hypot(float64(x)-u.X, float64(y)-u.Y)) < 15 {
					hit = true
					break
				}
			}
		}
		if hit {
			return trail, Impact{X: float64(int(x + .5)), Y: float64(int(y + .5)), Radius: w.Radius, Kind: w.Kind, At: duration}, true
		}
	}
	return Trail{Points: points, Kind: w.Kind, Duration: 20, Projectile: w.Projectile}, Impact{}, false
}
