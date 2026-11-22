package main

import "math"

// 00570fa0/0047fc40: Warp sweeps an eight-pixel forward semicircle
// against terrain. Tanks do not prematurely stop the teleporter in midair.
func (b *Battle) nativeWarpHit(p *nativeFlying, oldX, oldY float32) bool {
	ox, oy := int(oldX), int(oldY)
	ex, ey := int(p.x+.5), int(p.y+.5)
	steps := int(math.Hypot(float64(ex-ox), float64(ey-oy)))
	r := nativeRound3(p.angle) * nativeRadiansPerDegree
	for step := 0; step <= steps+1; step++ {
		x := int(float32(ox) + float32(nativeRound3(math.Cos(r)*float64(step))))
		y := int(float32(oy) - float32(nativeRound3(math.Sin(r)*float64(step))))
		if step == steps+1 {
			x, y = ex, ey
		}
		if _, hit := b.Terrain.nativeContactNormal(x, y, int(p.angle), 8); hit {
			p.x, p.y = float32(x), float32(y)
			return true
		}
	}
	return false
}
