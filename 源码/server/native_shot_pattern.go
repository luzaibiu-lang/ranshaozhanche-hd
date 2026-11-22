package main

import "math/rand/v2"

// Concrete CTank::fire branches from 005387d0, with continued stream shots
// from 005359b0. These are angular/power offsets, not equal-speed fan shots.
func nativeShotParameters(id, index int, angle, power float64) (float64, float64, bool) {
	sign := 1.0
	if angle > 90 && angle < 270 {
		sign = -1
	}
	switch id {
	case 8:
		return angle + sign*[]float64{2.5, 0, -2.5}[index%3], power * []float64{1.1, 1, .9}[index%3], true
	case 13:
		return angle + sign*[]float64{2, 0, -2}[index%3], power * []float64{1.12, 1, .88}[index%3], true
	case 21:
		return angle + sign*[]float64{1, 1, 0, -1, -1}[index%5], power * []float64{1.12, 1.06, 1, .94, .88}[index%5], true
	case 60:
		return angle + sign*[]float64{1, 0, -1}[index%3], power * []float64{1.02, 1, .98}[index%3], true
	case 1, 14:
		if index == 0 || index == 3 {
			return angle, power, true
		}
		return angle + float64(rand.IntN(8)-4), power + float64(rand.IntN(16)-8)/300, true
	case 27:
		if index == 0 {
			return angle, power, true
		}
		return angle + float64(rand.IntN(8)-4), power + float64(rand.IntN(16)-8)/300, true
	case 15, 16, 19, 20, 48, 49, 81, 82:
		return angle, power, true
	}
	return angle, power, false
}
