package main

import (
	"math"
	"math/rand/v2"
)

// Native 60 Hz projectile updates, resolved together in time order. A later
// projectile sees the ground and surviving tanks after earlier impacts.
// Ordinary motion: 00481050/00480130. Cluster: 005437b0/00544530/00544cc0.
type nativeFlying struct {
	w                                                         Weapon
	x, y, vx, up, initialUp, drift, acceleration              float32
	speedCounter, launchSpeed                                 float32
	angle                                                     float64
	age, startTick, splitTick, children                       int
	targetX, targetY                                          float64
	targetSeat                                                int
	guided                                                    bool
	guideLocked                                               bool
	guideAngle, guideSpeed                                    float64
	trail                                                     int
	dead                                                      bool
	variant                                                   int
	initialAngle                                              float64
	rayX, rayY, rayOriginX, rayOriginY, rayAngle, rayDistance float64
	rayTicks                                                  int
	peer                                                      *nativeFlying
	landed, linked                                            bool
	peerX                                                     float64
	bounced, frozen                                           bool
	carried                                                   []int
	lastBounceX, lastBounceY                                  int
	bounceCount                                               int
	absorption                                                *nativeAbsorption
}

func nativeSimulatedWeapon(w Weapon) bool {
	return nativeBallisticProjectile(w.Projectile) || nativeCluster(w.Projectile) || w.Projectile == 5 || w.Projectile == 10 || w.Projectile == 25 || w.Projectile == 91 || w.Projectile == 18 || w.Projectile == 101 || w.Projectile == 102 || w.Projectile == 14 || w.Projectile == 6 || w.Projectile == 81 || w.Projectile == 79
}

func nativeCluster(id int) bool { return id == 3 || id == 42 || id == 43 || id == 72 }

func newNativeFlying(actor *Unit, angle, power float64, w Weapon, wind int) *nativeFlying {
	x, y := nativeMuzzle(actor, angle)
	radians := float64(int(angle+.5)%360) * nativeRadiansPerDegree
	raw := power * 300
	speed := math.Floor((raw/15+.0005)*1000) / 1000
	p := &nativeFlying{w: w, x: float32(x), y: float32(y), angle: angle, initialAngle: float64(int(angle+.5) % 360), splitTick: -1}
	p.rayX, p.rayY = x, y
	p.vx = float32(math.Floor((speed*math.Cos(radians)+.0005)*1000) / 1000)
	p.up = float32(math.Floor((speed*math.Sin(radians)+.0005)*1000) / 1000)
	p.initialUp = p.up
	p.speedCounter, p.launchSpeed = float32(speed), float32(speed)
	force := math.Floor((float64(wind)/9.5+.05)*10) / 10
	p.acceleration = float32(math.Floor((force/100+.0005)*1000)/1000) * float32(w.Wind)
	return p
}

func (p *nativeFlying) step() {
	if p.frozen {
		p.age++
		return
	}
	oldX, oldY := p.x, p.y
	if p.guided {
		// 004809f0 switches the child from its 30-tick opening arc into
		// mode 5: 3 degrees/tick steering and +0.15 speed/tick.
		target := nativeDirection(p.x, p.y, float32(p.targetX), float32(p.targetY))
		delta := math.Mod(target-p.guideAngle+540, 360) - 180
		turn := 3.0
		acceleration := float32(.15)
		if p.w.Projectile == 18 || p.w.Projectile == 101 {
			turn = float64(float32(1.9))
			if p.w.Projectile == 101 {
				turn = 2.5
			}
			acceleration = .2
		}
		// 00480130 mode 5 permanently releases steering after exact
		// alignment. A missile that passes its fixed aim point keeps flying;
		// it must not turn back and orbit that point indefinitely.
		if p.guideAngle == target {
			p.guideLocked = true
		} else if !p.guideLocked {
			p.guideAngle = float64(float32(p.guideAngle + max(-turn, min(turn, delta))))
		}
		p.guideSpeed = float64(float32(p.guideSpeed) + acceleration)
		r := p.guideAngle * nativeRadiansPerDegree
		p.x += float32(math.Floor((math.Cos(r)*p.guideSpeed+.0005)*1000) / 1000)
		p.y -= float32(math.Floor((math.Sin(r)*p.guideSpeed+.0005)*1000) / 1000)
	} else if p.w.Projectile == 4 || p.w.Projectile == 71 {
		// 00480e70 mode 3: sine-eased radial opening, 3 degrees/tick,
		// 40/80/40 pixel distance for the three successive pairs.
		phase := min(90, float64(p.age+1)*3)
		distance := math.Sin(phase*nativeRadiansPerDegree) * p.guideSpeed
		r := p.angle * nativeRadiansPerDegree
		p.x = float32(p.targetX + float64(int(math.Cos(r)*distance+.5)))
		p.y = float32(p.targetY - float64(int(math.Sin(r)*distance+.5)))
		if phase >= 90 {
			p.guided = true
			p.guideAngle = p.angle
			p.guideSpeed = 0
			p.targetX, p.targetY = float64(p.vx), float64(p.up)
		}
	} else {
		p.drift += p.acceleration
		p.x += p.vx + p.drift
		p.y -= p.up
		p.up -= float32(.18)
		p.speedCounter -= float32(.18)
	}
	if p.w.Projectile != 4 && p.w.Projectile != 71 {
		p.angle = nativeDirection(oldX, oldY, p.x, p.y)
	}
	p.age++
	if p.w.Projectile == 81 {
		p.updateRay()
	}
}

// CWeapon81 (00566720) retargets four/six CBeamWeapon81 objects every
// eight ticks. Each child follows a sine-eased 11.25-degree radial segment.
func (p *nativeFlying) updateRay() {
	if (p.age-1)%8 == 0 {
		radius := math.Mod(float64(p.age)*5.625, 180)
		if radius > 90 {
			radius = 180 - radius
		}
		count := 4
		if p.w.NativeID == 82 {
			count = 6
		}
		heading := float64(int(p.angle + .5))
		phase := float64(int(heading+(float64(p.variant)+.5)*360/float64(count))%360) * nativeRadiansPerDegree
		x := float64(int(p.x+.5)) + nativeRound3(math.Cos(phase)*radius)
		y := float64(int(p.y+.5)) - nativeRound3(math.Sin(phase)*radius)
		r := heading * nativeRadiansPerDegree
		x += nativeRound3(math.Cos(r) * radius / 2)
		y -= nativeRound3(math.Sin(r) * radius / 2)
		tx, ty := float64(int(x)), float64(int(y))
		p.rayOriginX, p.rayOriginY = p.rayX, p.rayY
		p.rayAngle = math.Trunc(nativeDirection(float32(p.rayX), float32(p.rayY), float32(tx), float32(ty)))
		p.rayDistance = float64(float32(math.Hypot(tx-p.rayX, ty-p.rayY)))
		p.rayTicks = 0
	}
	p.rayTicks++
	distance := float64(float32(math.Sin(min(90, float64(p.rayTicks)*11.25)*nativeRadiansPerDegree))) * p.rayDistance
	if p.rayTicks >= 8 {
		distance = p.rayDistance
	}
	r := p.rayAngle * nativeRadiansPerDegree
	p.rayX = p.rayOriginX + float64(int(math.Cos(r)*distance+.5))
	p.rayY = p.rayOriginY - float64(int(math.Sin(r)*distance+.5))
}

func nativeDirection(x0, y0, x1, y1 float32) float64 {
	dx, dy := float64(x1-x0), float64(y0-y1)
	if dx == 0 && dy == 0 {
		return 0
	}
	if dx == 0 {
		if dy > 0 {
			return 90
		}
		return 270
	}
	// 004fd860 rounds the absolute ratio before atan, then the angle.
	ratio := float64(float32(math.Floor((math.Abs(dy)/math.Abs(dx)+.0005)*1000) / 1000))
	angle := float64(float32(math.Floor((math.Atan(ratio)/nativeRadiansPerDegree+.0005)*1000) / 1000))
	if dx < 0 {
		if dy < 0 {
			angle += 180
		} else {
			angle = 180 - angle
		}
	} else if dy < 0 {
		angle = 360 - angle
	}
	return float64(float32(angle))
}

func (b *Battle) nativeHit(p *nativeFlying) bool {
	x, y := p.point()
	return b.nativeHitAt(x, y)
}

func nativeRound3(value float64) float64 {
	return float64(float32(math.Floor((value+.0005)*1000) / 1000))
}

func (p *nativeFlying) point() (float64, float64) {
	if p.w.Projectile == 81 {
		return p.rayX, p.rayY
	}
	if p.w.Projectile == 14 {
		// 0054e780: the native controller carries two/four separately
		// colliding beams around one ballistic center, eight degrees/tick.
		sign := -1.0
		if p.initialAngle > 90 && p.initialAngle < 270 {
			sign = 1
		}
		phase := float64(p.age)*8*sign + []float64{0, 180, -90, 90}[p.variant%4]
		radius := min(10, float64(p.age)*.5)
		if p.w.NativeID == 20 {
			radius = min(23, float64(p.age)*.5)
		}
		r := phase * nativeRadiansPerDegree
		return float64(int(float64(int(p.x+.5)) + nativeRound3(math.Cos(r)*radius))), float64(int(float64(int(p.y+.5)) - nativeRound3(math.Sin(r)*radius)))
	}
	if p.w.Projectile == 6 && p.w.NativeID == 19 {
		// 00546930 variants 1/2/3: center wave and opposite sine waves.
		phase := float64(max(0, p.age-1)) * 8 * nativeRadiansPerDegree
		offset := math.Sin(phase) * 30
		if p.variant == 0 {
			offset = math.Cos(phase) * 15 * min(1, float64(max(0, p.age-1))/10)
		}
		if p.variant == 2 {
			offset = -offset
		}
		r := (p.angle + 90) * nativeRadiansPerDegree
		return float64(int(float32(float64(p.x) + nativeRound3(math.Cos(r)*offset)))), float64(int(float32(float64(p.y) - nativeRound3(math.Sin(r)*offset))))
	}
	return float64(p.x), float64(p.y)
}

func (b *Battle) recordShotState(shot *Shot, at float64) {
	units := make([]*Unit, len(b.Units))
	for i, u := range b.Units {
		c := *u
		units[i] = &c
	}
	state := ShotState{At: at, Units: units, Holes: len(b.Holes)}
	frame := MotionFrame{At: at, Poses: make([][5]float64, 0, len(b.Units))}
	for _, u := range b.Units {
		falling := 0.0
		if u.Falling {
			falling = 1
		}
		frame.Poses = append(frame.Poses, [5]float64{float64(u.Seat), u.X, u.Y, u.Slope, falling})
	}
	if n := len(shot.Motion); n > 0 && math.Abs(shot.Motion[n-1].At-at) < .00001 {
		shot.Motion[n-1] = frame
	} else {
		shot.Motion = append(shot.Motion, frame)
	}
	if n := len(shot.States); n > 0 && math.Abs(shot.States[n-1].At-at) < .00001 {
		shot.States[n-1] = state
	} else {
		shot.States = append(shot.States, state)
	}
}

func (b *Battle) nativeVolley(actor *Unit, angle, power float64, w Weapon, start float64, shot *Shot) {
	power = math.Floor(power*300+.5) / 300
	count := min(20, max(1, w.Count))
	flying := []*nativeFlying{}
	type groundBlast struct {
		tick    int
		x, y    float64
		w       Weapon
		surface bool
	}
	blasts := []groundBlast{}
	refundIndex := len(shot.refunds)
	launch := func(p *nativeFlying, tick int) {
		p.startTick = tick
		p.trail = len(shot.Trails)
		shot.Trails = append(shot.Trails, Trail{Points: [][2]float64{{float64(p.x), float64(p.y)}}, Kind: p.w.Kind, Projectile: p.w.Projectile, Start: start + float64(tick)/60})
		flying = append(flying, p)
	}
	for tick := 0; tick < 1800; tick++ {
		for i := 0; i < count; i++ {
			if tick != int(math.Round(float64(i)*w.Delay*60)) {
				continue
			}
			a, p := angle, power
			if count > 1 && w.Delay == 0 {
				a += (float64(i) - float64(count-1)/2) * 1.5
			}
			if na, np, ok := nativeShotParameters(w.NativeID, i, angle, power); ok {
				a, p = na, np
			}
			f := newNativeFlying(actor, a, p, w, b.Wind)
			// CTank computes the muzzle before applying per-shell angle
			// offsets; a fan shares one barrel endpoint (005387d0).
			muzzleX, muzzleY := nativeMuzzle(actor, angle)
			f.x, f.y = float32(muzzleX), float32(muzzleY)
			f.rayX, f.rayY = muzzleX, muzzleY
			f.variant = i
			launch(f, tick)
		}
		alive := false
		for _, p := range append([]*nativeFlying{}, flying...) {
			if p.dead {
				continue
			}
			alive = true
			oldX, oldY := p.x, p.y
			oldPointX, oldPointY := p.point()
			refunded := false
			if p.absorption != nil {
				refunded = p.stepAbsorption(actor)
			} else {
				p.step()
			}
			warpHit := false
			if p.w.Projectile == 102 {
				warpHit = b.nativeWarpHit(p, oldX, oldY)
			}
			reflectExplode := false
			if p.w.Projectile == 79 || p.w.Projectile == 100 || p.w.Projectile == 78 {
				reflectExplode = b.nativeReflect(p, oldX, oldY)
				for _, seat := range p.carried {
					for _, u := range b.Units {
						if u.Seat == seat && u.HP > 0 {
							u.X, u.Y = float64(p.x), float64(p.y)
						}
					}
				}
				if len(p.carried) > 0 {
					b.recordShotState(shot, start+float64(tick+1)/60)
				}
			}
			ordinaryHit := false
			contactX, contactY := 0.0, 0.0
			if p.absorption == nil && p.w.Projectile != 71 && p.w.Projectile != 79 && p.w.Projectile != 100 && p.w.Projectile != 78 && p.w.Projectile != 102 {
				contactX, contactY, ordinaryHit = b.nativeHitAlong(p, oldPointX, oldPointY)
			}
			x, y := p.point()
			if ordinaryHit {
				x, y = contactX, contactY
			}
			trail := &shot.Trails[p.trail]
			trail.Points = append(trail.Points, [2]float64{x, y})
			trail.Duration = float64(p.age) / 60
			shot.Duration = max(shot.Duration, trail.Start+trail.Duration)
			if p.absorption != nil {
				if refunded {
					b.recordShotState(shot, start+float64(tick+1)/60)
				}
				continue
			}
			if x < 0 || x >= float64(b.Width) {
				p.dead = true
				continue
			}
			if p.w.Projectile == 71 {
				// 00560d80 deliberately ignores terrain. The paired shells
				// trigger at the map bottom, then pulse on the current surface.
				if y > float64(b.Height) {
					p.dead, p.landed = true, true
					if p.peer != nil && !p.peer.landed && !p.peer.dead {
						p.peer.peerX = float64(int(x + .5))
						p.linked = true
					}
					pulses := 1
					if p.w.NativeID == 72 && !p.linked {
						pulses = 6
					}
					ownX := float64(int(x + .5))
					targetX := p.peerX
					if targetX == 0 {
						targetX = ownX
					}
					for i := 0; i < pulses; i++ {
						gx := ownX + float64(int((targetX-ownX)/6))*float64(i)
						blasts = append(blasts, groundBlast{tick + i*18, gx, 0, p.w, true})
					}
				}
				continue
			}
			if y >= float64(b.Height) {
				p.dead = true
				continue
			}
			if ordinaryHit || reflectExplode || warpHit {
				p.dead = true
				if p.w.Projectile == 102 {
					blasts = append(blasts, groundBlast{tick + 26, x, y, p.w, false})
					at := start + float64(tick+1)/60
					shot.Trails = append(shot.Trails, Trail{Points: [][2]float64{{x, y}, {x, y}}, Kind: "warp_portal", Projectile: 102, Start: at, Duration: 146.0 / 60})
					shot.Duration = max(shot.Duration, at+146.0/60)
					continue
				}
				if p.w.Projectile == 5 {
					// 00545960 bursts at 0..108 inclusive, then terminates:
					// seven ground bursts, 18 native ticks apart.
					// This is not a shell bouncing twice from the same crater.
					for i := 0; i < 7; i++ {
						x := float64(int(x + .5))
						if i > 0 {
							x += float64(rand.IntN(150) - 75)
						}
						if x >= 0 && x < float64(b.Width) {
							blasts = append(blasts, groundBlast{tick + i*18, x, 0, p.w, true})
						}
					}
					continue
				}
				if p.w.Projectile == 25 || p.w.Projectile == 91 {
					blasts = append(blasts, groundBlast{tick, x, y, p.w, false})
					for i := 0; i < 4 && p.w.Projectile != 91; i++ {
						offset := float64(-20 + i*10)
						blasts = append(blasts, groundBlast{tick + (i+1)*18, x + offset, y + offset, p.w, false})
					}
					continue
				}
				if p.w.Projectile == 10 {
					spacing, interval := 15, 10
					if p.w.NativeID == 11 {
						spacing, interval = 25, 18
					}
					blasts = append(blasts, groundBlast{tick, x, y, p.w, false})
					for _, direction := range []int{-1, 1} {
						gx, gy := x, y
						for wave := 1; wave <= 4; wave++ {
							ok := true
							for step := 0; step < spacing; step++ {
								nx := gx + float64(direction)
								ny := b.Terrain.ground(nx, int(gy)-25)
								if math.Abs(ny-gy) > 25 || ny >= float64(b.Height) {
									ok = false
									break
								}
								gx, gy = nx, ny
							}
							if !ok {
								break
							}
							blasts = append(blasts, groundBlast{tick + wave*interval, gx, gy, p.w, false})
						}
					}
					continue
				}
				at := start + float64(tick+1)/60
				b.impact(actor, p.w, Impact{X: float64(int(x + .5)), Y: float64(int(y + .5)), Radius: p.w.Radius, Kind: p.w.Kind, At: at, heading: p.angle}, shot)
				b.recordShotState(shot, at)
				continue
			}
			// 00551eb0/0056f9a0 only search for targets after the missile
			// survives the current tick's terrain and tank collision checks.
			if b.acquireNativeHoming(p) {
				at := start + float64(tick+1)/60
				trail.LockAt = at
				shot.Cues = append(shot.Cues, ShotCue{At: at, Kind: "lock", Seat: p.targetSeat, X: p.targetX, Y: p.targetY})
			}
			if p.w.Projectile == 58 && p.age == 110 {
				child := &nativeFlying{w: Weapon{Kind: "heal", Damage: 75, Radius: 50, Wind: 1, Projectile: 60}, x: float32(int(p.x + .5)), y: float32(int(p.y + .5)), drift: p.drift, splitTick: -1}
				launch(child, tick+1)
			}
			if nativeCluster(p.w.Projectile) && p.speedCounter <= 0 {
				if p.splitTick < 0 {
					p.splitTick = tick
					projection := *p
					for i := 0; i < 1200; i++ {
						projection.step()
						if projection.speedCounter <= -p.launchSpeed && (p.w.Projectile != 72 || i >= 61) {
							break
						}
					}
					p.targetX, p.targetY = float64(int(projection.x)), float64(int(projection.y))
				}
				limit, damage := 6, 41
				if p.w.Projectile == 42 {
					limit, damage = 4, 31
				}
				if p.w.Projectile == 72 {
					limit, damage = 2, 50
				}
				if p.children < limit && (tick-p.splitTick)%5 == 0 {
					pair := p.children / 2
					spread := []float64{130, 90, 50}[pair]
					if p.w.Projectile == 42 {
						spread = []float64{90, 50}[pair]
					}
					distance := []float64{40, 80, 40}[pair]
					childID, radius := 4, 60.0
					if p.w.Projectile == 72 {
						spread, distance, childID, radius = 60, 100, 71, 50
					}
					var sibling *nativeFlying
					for _, sign := range []float64{1, -1} {
						child := &nativeFlying{w: Weapon{Kind: "normal", Damage: damage, Radius: radius, Wind: 1, Projectile: childID, NativeID: p.w.NativeID}, x: float32(int(p.x + .5)), y: float32(int(p.y + .5)), angle: float64((int(p.angle+sign*spread+.5)%360 + 360) % 360), targetX: float64(int(p.x + .5)), targetY: float64(int(p.y + .5)), guideSpeed: distance, vx: float32(p.targetX), up: float32(p.targetY), splitTick: -1}
						if sibling != nil {
							child.peer, sibling.peer = sibling, child
						}
						sibling = child
						launch(child, tick+1)
					}
					p.children += 2
					if p.children >= limit {
						p.dead = true
					}
				}
			}
		}
		for i := 0; i < len(blasts); {
			e := blasts[i]
			if e.tick > tick {
				i++
				continue
			}
			at := start + float64(tick+1)/60
			if e.surface {
				e.y = b.Terrain.nativeGround(e.x, 20)
			}
			b.impact(actor, e.w, Impact{X: e.x, Y: e.y, Radius: e.w.Radius, Kind: e.w.Kind, At: at}, shot)
			b.recordShotState(shot, at)
			shot.Duration = max(shot.Duration, at)
			blasts = append(blasts[:i], blasts[i+1:]...)
		}
		for refundIndex < len(shot.refunds) {
			p := newNativeAbsorption(shot.refunds[refundIndex])
			if p.absorption.sp {
				p.w.Kind = "sp_return"
			}
			launch(p, tick+1)
			refundIndex++
		}
		lastLaunch := int(math.Round(float64(count-1) * w.Delay * 60))
		for _, u := range b.Units {
			u.Carried = false
			for _, p := range flying {
				if p.dead {
					continue
				}
				for _, seat := range p.carried {
					if seat == u.Seat {
						u.Carried = true
					}
				}
			}
		}
		changed, falling := b.nativeFalls()
		if changed {
			at := start + float64(tick+1)/60
			b.recordShotState(shot, at)
			shot.Duration = max(shot.Duration, at)
		}
		if !alive && !falling && tick > lastLaunch && len(blasts) == 0 {
			break
		}
	}
}

func (b *Battle) advanceShot(now float64) bool {
	if b.pending == nil || b.Shot == nil {
		return false
	}
	changed := false
	for b.shotState < len(b.Shot.States) && b.Shot.States[b.shotState].At <= now-b.Shot.Started {
		state := b.Shot.States[b.shotState]
		b.Units = make([]*Unit, len(state.Units))
		for i, u := range state.Units {
			c := *u
			b.Units[i] = &c
		}
		b.Holes = append([]Hole{}, b.pending.Holes[:min(state.Holes, len(b.pending.Holes))]...)
		b.shotState++
		changed = true
	}
	return changed
}
