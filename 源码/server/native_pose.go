package main

import (
	"errors"
	"math"
)

// The native barrel angle is relative to facing and terrain, not a world
// direction selected from 5..175 degrees (00533c60 / 00533ce0).
func (u *Unit) worldAngle(elevation float64) float64 {
	if u.Face < 0 {
		return math.Mod(u.Slope+180-elevation+720, 360)
	}
	return math.Mod(u.Slope+elevation+720, 360)
}

func (b *Battle) fireNative(elevation, power float64, weaponIndex int) error {
	u := b.active()
	if u == nil || u.HP <= 0 {
		return errors.New("没有可行动的战车")
	}
	v := vehicle(u.Vehicle)
	if math.IsNaN(elevation) || math.IsInf(elevation, 0) || elevation < v.AimMin || elevation > v.AimMax {
		return errors.New("超出当前战车的瞄准范围")
	}
	return b.fireWorld(u.worldAngle(elevation), power, weaponIndex, true)
}

// Original 004d9410 scans contact columns over an odd footprint. The two
// supporting ledges determine slope; neither the image bounds nor a cave
// ceiling may be used as the tank's floor.
func (t *Terrain) nativeSlope(u *Unit) float64 {
	width := 15
	if (u.Vehicle-1)%10 == 8 {
		width = 41 // Native width 40 is rounded up to odd.
	}
	left := int(u.X) - width/2
	bottom := int(u.Y) - 1
	heights := make([]int, width)
	for i := range heights {
		x := left + i
		heights[i] = t.H
		if x < 0 || x >= t.W {
			continue
		}
		for y := bottom - 1; y <= bottom+width-width/4; y++ {
			if t.solid(float64(x), float64(y)) {
				heights[i] = y
				break
			}
		}
		for y := bottom - 2; y >= 0 && t.solid(float64(x), float64(y)); y-- {
			heights[i] = y
		}
	}
	middle := width / 2
	li, ri := middle, middle
	for i := middle; i >= 0; i-- {
		if heights[i] <= heights[li] {
			li = i
		}
	}
	for i := middle; i < width; i++ {
		if heights[i] <= heights[ri] {
			ri = i
		}
	}
	if heights[li] >= t.H || heights[ri] >= t.H || li == ri {
		return u.Slope
	}
	return -math.Atan2(float64(heights[ri]-heights[li]), float64(ri-li)) * 180 / math.Pi
}

func (u *Unit) updateSlope(t *Terrain) {
	u.Slope = math.Trunc(t.nativeSlope(u))
	u.Aim = u.worldAngle(u.Elevation)
}
