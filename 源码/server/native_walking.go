package main

import "math"

// 00530210 checks the next bottom-edge footprint, rather than lifting the
// tank onto a center-column surface up to 22 pixels above its current feet.
// 00533f70 limits uphill inclination to 65 degrees; 00530210 additionally
// rejects a 40-degree uphill change and a rise of five or more pixels.
func (t *Terrain) nativeWalkPose(u *Unit, direction int) (nativeSupport, bool) {
	width := 15
	if (u.Vehicle-1)%10 == 8 {
		width = 41
	}
	current := t.nativeFootprint(u, width, true)
	next := *u
	next.X += float64(direction)
	pose := t.nativeFootprint(&next, width, true)
	if direction == 0 || u.Falling {
		return pose, false
	}
	if direction < 0 && int(next.X) <= width/2 || direction > 0 && int(next.X)+width/2 >= t.W {
		return pose, false
	}
	signed := func(angle float64) float64 { return math.Mod(angle+540, 360) - 180 }
	uphill := signed(pose.slope) * float64(direction)
	if uphill > 65 {
		return pose, false
	}
	previous := current.slope
	if signed(previous)*float64(direction) < 0 {
		previous = 0
	}
	difference := signed(pose.slope - previous)
	if difference*float64(direction) >= 40 || current.y-pose.y >= 5 {
		return pose, false
	}
	return pose, true
}
