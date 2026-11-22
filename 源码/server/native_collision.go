package main

import "math"

// Native ordinary shells test a small terrain box and the sum of collision
// radii at their external integer position (0047fb20 / 00481d40). Keep an
// already-detected endpoint impact unchanged; additionally check the skipped
// interval when an accelerating missile has crossed a thin obstacle in one
// tick. Special reflection, warp and terrain-ignoring shells keep their own
// native collision handlers in nativeVolley.
func (b *Battle) nativeHitAlong(p *nativeFlying, fromX, fromY float64) (float64, float64, bool) {
	x, y := p.point()
	if b.nativeHit(p) {
		return x, y, true
	}
	dx, dy := x-fromX, y-fromY
	steps := int(math.Ceil(max(math.Abs(dx), math.Abs(dy))))
	if steps <= 1 {
		return x, y, false
	}
	// Skip the launch point: the muzzle may touch the firing tank without
	// the original first advancing tick being an impact.
	for step := 1; step < steps; step++ {
		fraction := float64(step) / float64(steps)
		px, py := fromX+dx*fraction, fromY+dy*fraction
		if px < 0 || px >= float64(b.Width) || py >= float64(b.Height) {
			continue
		}
		if !b.nativeHitAt(px, py) {
			continue
		}
		return px, py, true
	}
	return x, y, false
}

func (b *Battle) nativeHitAt(x, y float64) bool {
	if b.Terrain.projectileContact(x, y, 5) {
		return true
	}
	for _, u := range b.Units {
		if u.HP > 0 && int(math.Hypot(x-u.X, y-u.Y)) < 15 {
			return true
		}
	}
	return false
}
