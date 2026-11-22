package main

import "math"

type nativeSupport struct {
	x, y, slope float64
	valid, off  bool
}

// 004d9410: sample an odd footprint around the current bottom edge,
// rather than dropping a ray from the top of the map onto a cave ceiling.
func (t *Terrain) nativeSupport(u *Unit) nativeSupport {
	width := 15
	if (u.Vehicle-1)%10 == 8 {
		width = 41
	}
	left, bottom := int(u.X)-width/2, int(u.Y)-1
	h := make([]int, width)
	contact := false
	for i := range h {
		x := left + i
		h[i] = t.H
		if x < 0 || x >= t.W {
			continue
		}
		contact = contact || t.solid(float64(x), u.Y)
		for y := bottom - 1; y <= bottom+width-width/4; y++ {
			if t.solid(float64(x), float64(y)) {
				h[i] = y
				break
			}
		}
		for y := bottom - 2; y >= 0 && t.solid(float64(x), float64(y)); y-- {
			h[i] = y
		}
	}
	s := nativeSupport{x: u.X, y: u.Y, off: true}
	if !contact {
		return s
	}
	mid := width / 2
	li, ri, nearL, nearR := mid, mid, mid, mid
	best, bestNear := t.H, t.H
	for i := mid; i >= 0; i-- {
		if h[i] < bestNear && h[i]-int(u.Y) < width/3+1 {
			nearL = i
			bestNear = h[i]
		}
		if h[i] <= best {
			li = i
			best = h[i]
		}
	}
	best, bestNear = t.H, t.H
	for i := mid; i < width; i++ {
		if h[i] < bestNear && h[i]-int(u.Y) < width/3+1 {
			nearR = i
			bestNear = h[i]
		}
		if h[i] <= best {
			ri = i
			best = h[i]
		}
	}
	start, end := li, ri
	if h[li] < t.H && h[ri] < t.H {
		s.valid = true
		s.y = float64(max(h[li], h[ri]))
		s.off = false
	} else if h[li] < t.H && mid-nearL <= width/4+1 && h[nearL] < t.H {
		end = nearL
		s.valid = true
		s.off = false
		s.y = float64((h[li] + h[nearL]) / 2)
	} else if h[ri] < t.H && nearR-mid <= width/4+1 && h[nearR] < t.H {
		start = nearR
		s.valid = true
		s.off = false
		s.y = float64((h[ri] + h[nearR]) / 2)
	}
	if s.valid {
		s.slope = math.Mod(-math.Atan2(float64(h[end]-h[start]), float64(end-start))*180/math.Pi+360, 360)
		if u.Y < s.y {
			s.valid = false
			s.off = true
		}
	}
	return s
}

func (b *Battle) nativeFallStep(u *Unit) bool {
	if u.Carried {
		u.Falling = true
		u.FallTicks = 0
		return false
	}
	if u.HP <= 0 {
		u.Falling = false
		u.FallTicks = 0
		return false
	}
	beforeX, beforeY, beforeSlope, beforeFalling := u.X, u.Y, u.Slope, u.Falling
	check := func() (nativeSupport, int) {
		s := b.Terrain.nativeSupport(u)
		slide := 0
		if s.valid && s.slope > 65 && s.slope < 90 {
			slide = -1
		}
		if s.valid && s.slope > 270 && s.slope < 295 {
			slide = 1
		}
		return s, slide
	}
	s, slide := check()
	if s.valid && slide == 0 {
		u.X, u.Y, u.Slope = s.x, s.y, math.Trunc(s.slope)
		u.Falling = false
		u.FallTicks = 0
	} else {
		u.Falling = true
		u.FallTicks++
		distance := min(5, u.FallTicks/12)
		if distance == 0 && u.FallTicks%2 == 1 {
			distance = 1
		}
		for i := 0; i < distance; i++ {
			s, slide = check()
			if !s.valid || slide != 0 {
				u.Y++
				u.X += float64(slide)
			}
			s, slide = check()
			if s.valid && slide == 0 {
				u.X, u.Y, u.Slope = s.x, s.y, math.Trunc(s.slope)
				u.Falling = false
				u.FallTicks = 0
				break
			}
			if s.valid && slide != 0 {
				u.Slope = math.Trunc(s.slope)
			} else {
				u.Slope = 0
			}
		}
	}
	if u.Y > float64(b.Height+100) || u.X < 0 || u.X >= float64(b.Width) {
		u.HP = 0
		u.Shield = 0
		u.Stealth = 0
		u.Falling = false
		u.FallTicks = 0
		u.Y = min(u.Y, float64(b.Height+100))
	}
	u.Aim = u.worldAngle(u.Elevation)
	return beforeX != u.X || beforeY != u.Y || beforeSlope != u.Slope || beforeFalling != u.Falling
}

func (b *Battle) nativeFalls() (changed, falling bool) {
	for _, u := range b.Units {
		changed = b.nativeFallStep(u) || changed
		falling = falling || u.Falling
	}
	return
}
