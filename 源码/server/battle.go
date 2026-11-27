package main

import (
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"sort"
	"time"
)

type Unit struct {
	Seat         int     `json:"seat"`
	Player       int64   `json:"player"`
	Name         string  `json:"name"`
	Team         int     `json:"team"`
	Vehicle      int     `json:"vehicle"`
	AI           int     `json:"ai"`
	X            float64 `json:"x"`
	Y            float64 `json:"y"`
	HP           int     `json:"hp"`
	MaxHP        int     `json:"max_hp"`
	SP           int     `json:"sp"`
	Move         float64 `json:"move"`
	Face         int     `json:"face"`
	Aim          float64 `json:"aim"`
	Elevation    float64 `json:"elevation"`
	Slope        float64 `json:"slope"`
	Shield       int     `json:"shield"`
	Poison       int     `json:"poison"`
	Burn         int     `json:"burn"`
	Stun         int     `json:"stun"`
	Blind        int     `json:"blind"`
	Stealth      int     `json:"stealth"`
	Power        bool    `json:"power"`
	Double       bool    `json:"double"`
	ShotMode     int     `json:"shot_mode"`
	Economy      bool    `json:"economy"`
	Damage       int     `json:"damage"`
	MoveSpent    float64 `json:"move_spent"`
	MoveSequence uint64  `json:"move_sequence,omitempty"`
	Falling      bool    `json:"falling"`
	FallTicks    int     `json:"-"`
	Carried      bool    `json:"carried"`
	Departed     bool    `json:"departed,omitempty"`
}
type Trail struct {
	LockAt     float64      `json:"lock_at,omitempty"`
	Points     [][2]float64 `json:"points"`
	Kind       string       `json:"kind"`
	Duration   float64      `json:"duration"`
	Start      float64      `json:"start"`
	Projectile int          `json:"projectile"`
}
type Impact struct {
	Projectile int     `json:"projectile"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	Radius     float64 `json:"radius"`
	Kind       string  `json:"kind"`
	At         float64 `json:"at"`
	heading    float64
}
type ShotCue struct {
	At   float64 `json:"at"`
	Kind string  `json:"kind"`
	Seat int     `json:"seat"`
	X    float64 `json:"x"`
	Y    float64 `json:"y"`
}
type Shot struct {
	ID        int         `json:"id"`
	Prepared  float64     `json:"prepared"`
	Overdrive bool        `json:"overdrive,omitempty"`
	Started   float64     `json:"started"`
	Duration  float64     `json:"duration"`
	Trails    []Trail     `json:"trails"`
	Impacts   []Impact    `json:"impacts"`
	Actor     int         `json:"actor"`
	Cues      []ShotCue   `json:"cues,omitempty"`
	States    []ShotState `json:"-"`
	refunds   []nativeRefund
	shielded  map[int]bool
	Motion    []MotionFrame `json:"motion,omitempty"`
	Visuals   []VisualFrame `json:"visuals,omitempty"`
	HoleBase  int           `json:"hole_base"`
	Cuts      []Hole        `json:"cuts,omitempty"`
}

// Rendering-only trajectory. The accompanying sparse visual checkpoints use
// the same shot clock; game commands still use the private authoritative state.
type MotionFrame struct {
	At    float64      `json:"at"`
	Poses [][5]float64 `json:"poses"` // seat, x, y, slope, falling
}

// States are immutable checkpoints at impact times. Live room snapshots advance
// through them while the shot is playing, instead of revealing all destruction
// and health changes together at the end of a volley.
type ShotState struct {
	At    float64 `json:"at"`
	Units []*Unit `json:"units"`
	Holes int     `json:"holes"`
}
type Result struct {
	Team    int            `json:"team"`
	Reason  string         `json:"reason"`
	Rewards map[string]int `json:"rewards"`
}
type Battle struct {
	ID              string      `json:"id"`
	Map             int         `json:"map"`
	Width           int         `json:"width"`
	Height          int         `json:"height"`
	Units           []*Unit     `json:"units"`
	Holes           []Hole      `json:"holes"`
	Round           int         `json:"round"`
	Active          int         `json:"active"`
	Wind            int         `json:"wind"`
	Deadline        float64     `json:"deadline"`
	Loading         bool        `json:"loading,omitempty"`
	LoadingSeats    []int       `json:"loading_seats,omitempty"`
	LoadingDeadline float64     `json:"loading_deadline,omitempty"`
	Shot            *Shot       `json:"shot"`
	Result          *Result     `json:"result"`
	Generation      uint64      `json:"generation"`
	NativeAim       bool        `json:"native_aim"`
	Supplies        []SupplyCue `json:"supplies,omitempty"`
	Terrain         *Terrain    `json:"-"`
	acted           map[int]bool
	pending         *Battle
	busyUntil       time.Time
	aiAt            time.Time
	aiAction        *aiTurnAction
	shotID          int
	planning        bool
	planScore       float64
	shotState       int
	supplyID        uint64
	moveBlocked     bool
}

func nowSeconds() float64 { return float64(time.Now().UnixMilli()) / 1000 }

func (b *Battle) startFirstTurn(now time.Time) {
	b.Loading = false
	b.LoadingSeats = nil
	b.LoadingDeadline = 0
	b.Deadline = float64(now.UnixMilli())/1000 + 35
	b.aiAt = now.Add(time.Second)
}

func (b *Battle) active() *Unit {
	for _, u := range b.Units {
		if u.Seat == b.Active {
			return u
		}
	}
	return nil
}
func (b *Battle) copy() *Battle {
	v := *b
	v.Units = make([]*Unit, len(b.Units))
	for i, u := range b.Units {
		c := *u
		v.Units[i] = &c
	}
	v.Holes = append([]Hole{}, b.Holes...)
	v.Terrain = b.Terrain.clone()
	v.acted = make(map[int]bool, len(b.acted))
	for seat, done := range b.acted {
		v.acted[seat] = done
	}
	v.pending = nil
	return &v
}
func (b *Battle) aliveTeams() map[int]bool {
	teams := map[int]bool{}
	for _, u := range b.Units {
		if u.HP > 0 {
			teams[u.Team] = true
		}
	}
	return teams
}
func (b *Battle) settleFalls() {
	for _, u := range b.Units {
		if u.HP <= 0 {
			continue
		}
		ground := b.Terrain.ground(u.X, int(u.Y)-15)
		drop := ground - u.Y
		if ground > float64(b.Height) {
			u.HP = 0
			u.Y = float64(b.Height + 80)
		} else {
			u.Y = ground
			u.updateSlope(b.Terrain)
			if drop > 130 {
				u.HP = max(0, u.HP-int((drop-130)*.3))
			}
		}
		if u.HP == 0 {
			u.Shield = 0
			u.Stealth = 0
		}
	}
}
func (b *Battle) move(distance float64) error {
	u := b.active()
	if u == nil || u.HP <= 0 || u.Stun > 0 || b.moveBlocked {
		return errors.New("当前无法移动")
	}
	distance = max(-45, min(45, distance))
	direction := 1.0
	if distance < 0 {
		direction = -1
	}
	if distance != 0 {
		u.Face = int(direction)
		u.Aim = u.worldAngle(u.Elevation)
	}
	cost := vehicle(u.Vehicle).MoveCost
	if u.Economy {
		cost *= .5
	}
	steps := min(int(math.Abs(distance)), int(u.Move), int(float64(u.SP)/cost))
	moved := 0
	for i := 0; i < steps; i++ {
		x := u.X + direction
		y := b.Terrain.ground(x, int(u.Y)-22)
		if math.Abs(y-u.Y) > 24 || y > float64(b.Height-20) {
			break
		}
		if b.NativeAim {
			pose, allowed := b.Terrain.nativeWalkPose(u, int(direction))
			if !allowed || !pose.valid && pose.y <= u.Y {
				break
			}
			y = pose.y
			u.Slope = math.Trunc(pose.slope)
		}
		u.X, u.Y = x, y
		u.Face = int(direction)
		moved++
	}
	u.Move -= float64(moved)
	u.MoveSpent += float64(moved) * cost
	spent := int(u.MoveSpent)
	u.SP = max(0, u.SP-spent)
	u.MoveSpent -= float64(spent)
	if b.NativeAim {
		u.Aim = u.worldAngle(u.Elevation)
	} else {
		u.updateSlope(b.Terrain)
	}
	return nil
}
func (b *Battle) trajectory(actor *Unit, angle, power float64, w Weapon) (Trail, Impact, bool) {
	if b.NativeAim && nativeSimulatedWeapon(w) {
		return b.nativeTrajectory(actor, angle, power, w)
	}
	radians := angle * math.Pi / 180
	speed := 620 * power
	vx, vy := math.Cos(radians)*speed, -math.Sin(radians)*speed
	x, y := actor.X+math.Cos(radians)*22, actor.Y-22-math.Sin(radians)*16
	points := [][2]float64{{x, y}}
	gravity := 180.0
	if w.Projectile == 81 {
		gravity = 0
		vx *= 1.35
		vy *= 1.35
	}
	bounces := 0
	pierced := 0
	const dt = 1.0 / 90
	for tick := 0; tick < 1800; tick++ {
		oldX, oldY := x, y
		vx += float64(b.Wind) * 1.25 * w.Wind * dt
		vy += gravity * dt
		x += vx * dt
		y += vy * dt
		if w.Kind == "homing" && tick > 45 {
			var target *Unit
			best := math.MaxFloat64
			for _, e := range b.Units {
				if e.Team != actor.Team && e.HP > 0 && e.Stealth == 0 {
					d := math.Hypot(e.X-x, e.Y-20-y)
					if d < best {
						best = d
						target = e
					}
				}
			}
			if target != nil && best < 280 {
				vx += (target.X - x) * .12 * dt
				vy += (target.Y - 20 - y) * .12 * dt
			}
		}
		if tick%3 == 0 {
			points = append(points, [2]float64{x, y})
		}
		if x < 0 || x >= float64(b.Width) || y >= float64(b.Height+20) {
			duration := min(4.0, max(.5, float64(tick)*dt*.5))
			return Trail{Points: points, Kind: w.Kind, Duration: duration, Projectile: w.Projectile}, Impact{}, false
		}
		hit := false
		for sub := 1; sub <= 4; sub++ {
			sx, sy := oldX+(x-oldX)*float64(sub)/4, oldY+(y-oldY)*float64(sub)/4
			if b.Terrain.solid(sx, sy) {
				x, y = sx, sy
				hit = true
				break
			}
		}
		if tick > 10 {
			for _, target := range b.Units {
				if target.HP > 0 && target.Seat != actor.Seat && math.Hypot(x-target.X, y-(target.Y-18)) < 17 {
					hit = true
					break
				}
			}
		}
		if hit && (w.Kind == "bounce" || w.Kind == "fire_bounce" || w.Kind == "ricochet") && bounces < 2 {
			vy = -math.Abs(vy) * .7
			vx *= .75
			y = oldY - 5
			x = oldX
			bounces++
			hit = false
		}
		if hit && w.Kind == "pierce" && pierced < 22 {
			pierced++
			hit = false
		}
		if hit {
			points = append(points, [2]float64{x, y})
			duration := min(4.0, max(.5, float64(tick)*dt*.5))
			return Trail{Points: points, Kind: w.Kind, Duration: duration, Projectile: w.Projectile}, Impact{X: x, Y: y, Radius: w.Radius, Kind: w.Kind, At: duration, Projectile: w.Projectile}, true
		}
	}
	return Trail{Points: points, Kind: w.Kind, Duration: 4, Projectile: w.Projectile}, Impact{}, false
}
func (b *Battle) impact(actor *Unit, w Weapon, impact Impact, shot *Shot) {
	impact.Projectile = w.Projectile
	if impact.Kind != "heal" && impact.Kind != "teleport" && impact.Kind != "stun" && impact.Kind != "blind" {
		hole := Hole{X: impact.X, Y: impact.Y, R: impact.Radius}
		if b.NativeAim {
			index, ok := nativeCraterIDs[w.Projectile]
			if w.Projectile == 14 && w.NativeID == 20 {
				index, ok = 6, true
			}
			if w.Projectile == 10 && w.NativeID == 10 {
				ok = false
			}
			if ok {
				hole.Mask = index + 1
				hole.R = float64(nativeCraters[index].W) / 2
			}
			if !ok {
				hole.R = 0
			}
		}
		if hole.R > 0 {
			b.Terrain.carve(hole)
			b.Holes = append(b.Holes, hole)
		}
	}
	shot.Impacts = append(shot.Impacts, impact)
	for _, target := range b.Units {
		if target.HP <= 0 {
			continue
		}
		targetY := target.Y - 15
		if b.NativeAim {
			targetY = target.Y
		}
		distance := math.Hypot(target.X-impact.X, targetY-impact.Y)
		if distance >= impact.Radius {
			continue
		}
		if impact.Kind == "heal" {
			heal := 70
			if w.Projectile == 60 {
				heal = max(1, int(float64(w.Damage)*vehicle(target.Vehicle).Armor+.5)*(int(impact.Radius)-int(distance))/int(impact.Radius))
			}
			target.HP = min(target.MaxHP, target.HP+heal)
			continue
		}
		if impact.Kind == "teleport" {
			continue
		}
		if impact.Kind == "stun" {
			target.Stun = 3
			target.Stealth = 0
			continue
		}
		if impact.Kind == "blind" {
			target.Blind = 3
			continue
		}
		rawDamage := w.Damage
		if b.NativeAim && actor.Power {
			// 00485af0 changes projectile raw damage before armor/falloff.
			rawDamage += rawDamage / 2
		}
		baseDamage := int(float64(rawDamage)*vehicle(target.Vehicle).Armor + .5)
		damage := max(1, baseDamage*(int(impact.Radius)-int(distance))/max(1, int(impact.Radius)))
		if actor.Power && !b.NativeAim {
			damage = int(float64(damage) * 1.5)
		}
		if target.Shield > 0 {
			if b.NativeAim {
				shot.Cues = append(shot.Cues, ShotCue{At: impact.At, Kind: "shield_hit", Seat: target.Seat, X: target.X, Y: target.Y})
				// 0052fd60 marks +2d8 as used; it does not clear +2cc.
				// The same shield blocks every pellet/wave in this shot.
				if shot.shielded == nil {
					shot.shielded = map[int]bool{}
				}
				shot.shielded[target.Seat] = true
			} else {
				target.Shield = 0
			}
			continue
		}
		dealt := min(target.HP, damage)
		actor.Damage += dealt
		target.HP = max(0, target.HP-damage)
		refund := max(1, int(float32(dealt)*float32(.9)))
		if b.NativeAim && w.Projectile == 20 {
			shot.refunds = append(shot.refunds, nativeRefund{target.X, target.Y, impact.heading + 180, refund, false})
		}
		if impact.Kind == "drain" {
			stolen := min(target.SP, refund)
			target.SP -= stolen
			if b.NativeAim && stolen > 0 {
				shot.refunds = append(shot.refunds, nativeRefund{target.X, target.Y, impact.heading + 180, stolen, true})
			} else if !b.NativeAim {
				actor.SP = min(200, actor.SP+stolen)
			}
		}
		if target.HP > 0 {
			switch impact.Kind {
			case "fire", "firewall", "fire_bounce":
				if !b.NativeAim {
					target.Burn = 2
				}
			case "poison":
				target.Poison = 3
			case "stun":
				target.Stun = 3
				target.Stealth = 0
			case "blind":
				target.Blind = 3
			}
		}
	}
	if impact.Kind == "teleport" {
		x := max(15, min(float64(b.Width-16), impact.X))
		if b.NativeAim {
			actor.X, actor.Y = x, impact.Y
			shot.Cues = append(shot.Cues, ShotCue{At: impact.At, Kind: "warp", Seat: actor.Seat, X: actor.X, Y: actor.Y})
			return
		}
		y := b.Terrain.ground(x, max(0, int(impact.Y)-80))
		if y < float64(b.Height-10) {
			actor.X, actor.Y = x, y
		}
	}
}
func (b *Battle) fire(angle, power float64, weaponIndex int) error {
	if angle < 5 || angle > 175 {
		return errors.New("角度、力度或武器参数无效")
	}
	return b.fireWorld(angle, power, weaponIndex, false)
}

func (b *Battle) fireWorld(angle, power float64, weaponIndex int, native bool) error {
	if math.IsNaN(angle) || math.IsNaN(power) || math.IsInf(angle, 0) || math.IsInf(power, 0) || power < 0 || power > 1 || weaponIndex < 0 || weaponIndex > 2 {
		return errors.New("角度、力度或武器参数无效")
	}
	u := b.active()
	if u == nil || u.HP <= 0 {
		return errors.New("没有可行动的战车")
	}
	w := vehicle(u.Vehicle).Weapons[weaponIndex]
	if u.ShotMode != 0 {
		w.Cost = 0
		w.Count = 1
		w.Delay = 0
		w.Wind = 1
		w.NativeID = 0
	}
	if u.SP < w.Cost {
		return errors.New("SP 不足")
	}
	next := b.copy()
	chargedSP := u.SP - w.Cost
	actor := next.active()
	actor.SP -= w.Cost
	actor.Aim = angle
	actor.Stealth = 0
	if !native {
		actor.Face = 1
		if angle > 90 {
			actor.Face = -1
		}
	}
	actor.Elevation = angle - actor.Slope
	if actor.Face < 0 {
		actor.Elevation = actor.Slope + 180 - angle
	}
	actor.Elevation = math.Mod(actor.Elevation+540, 360) - 180
	u.Elevation = actor.Elevation
	u.Aim, u.Face = actor.Aim, actor.Face
	switch actor.ShotMode {
	case 2:
		w.Kind = "normal"
		w.Radius = 55
		w.Damage = 105
		w.Projectile = 100
	case 3:
		w.Kind = "homing"
		w.Projectile = 101
		w.Damage = 55
		w.Radius = 60
	case 4:
		w.Kind = "teleport"
		w.Damage = 0
		w.Projectile = 102
	case 9:
		w.Kind = "stun"
		w.Projectile = 104
		w.Damage = 58
		w.Radius = 90
	case 16:
		w = Weapon{Kind: "heal", Projectile: itemHealProjectile, Radius: 50, Count: 1, Wind: 1}
	case 17:
		w = Weapon{Kind: "blind", Projectile: itemBlindProjectile, Radius: 50, Count: 1, Wind: 1}
	}
	b.shotID++
	shot := &Shot{ID: b.shotID, Actor: u.Seat, Overdrive: b.NativeAim && weaponIndex == 2 && u.ShotMode == 0, Trails: []Trail{}, Impacts: []Impact{}}
	if next.NativeAim {
		next.recordShotState(shot, 0)
	}
	count := min(20, max(1, w.Count))
	volleys := 1
	if actor.Double && weaponIndex != 2 {
		volleys = 2
	}
	for volley := 0; volley < volleys; volley++ {
		volleyStart := 0.0
		if volley > 0 {
			volleyStart = shot.Duration + .25
		}
		if next.NativeAim && nativeSimulatedWeapon(w) {
			next.nativeVolley(actor, angle, power, w, volleyStart, shot)
			continue
		}
		for i := 0; i < count; i++ {
			spread := 0.0
			shotPower := power
			if count > 1 && w.Delay == 0 {
				spread = (float64(i) - float64(count-1)/2) * 1.5
			}
			if nativeAngle, nativePower, ok := nativeShotParameters(w.NativeID, i, angle, power); ok {
				spread, shotPower = nativeAngle-angle, nativePower
			}
			start := volleyStart + float64(i)*w.Delay
			trail, impact, hit := next.trajectory(actor, angle+spread, shotPower, w)
			trail.Start = start
			impact.At += start
			shot.Trails = append(shot.Trails, trail)
			shot.Duration = max(shot.Duration, start+trail.Duration)
			if !hit {
				continue
			}
			next.impact(actor, w, impact, shot)
			if w.Kind == "cluster" {
				origin := *actor
				origin.X = impact.X
				origin.Y = impact.Y - 12
				child := Weapon{Kind: "normal", Damage: 41, Radius: 60, Count: 1, Wind: 1, Projectile: 4}
				for j := 0; j < 6; j++ {
					t, im, ok := next.trajectory(&origin, 35+float64(j)*22, .22, child)
					t.Start = impact.At + float64(j/2)*.08
					im.At += t.Start
					shot.Trails = append(shot.Trails, t)
					shot.Duration = max(shot.Duration, t.Start+t.Duration)
					if ok {
						next.impact(actor, child, im, shot)
					}
				}
			}
		}
	}
	actor.Power = false
	actor.Double = false
	actor.ShotMode = 0
	if next.NativeAim {
		// Original action-sync handlers consume the shields that were hit,
		// after the entire shot (including a double volley) has resolved.
		for _, target := range next.Units {
			if shot.shielded[target.Seat] {
				target.Shield = 0
			}
		}
	}
	if !next.NativeAim {
		next.settleFalls()
	}
	if len(shot.States) > 0 {
		next.recordShotState(shot, shot.Duration)
	}
	next.prepareShotVisuals(shot, len(b.Holes))
	b.Shot = shot
	u.SP = chargedSP
	u.Stealth = 0
	b.shotState = 0
	b.pending = next
	// Publish the completed shot before its native preparation begins. Both
	// playing clients receive the same muzzle time even if simulation was slow.
	ready := time.Now()
	windup := time.Duration(0)
	if b.NativeAim {
		ready = ready.Add(400 * time.Millisecond) // one 300 ms poll plus transport margin
		windup = 30 * time.Second / 60
		if shot.Overdrive {
			windup = 190 * time.Second / 60
		}
	}
	shot.Prepared = float64(ready.UnixMicro()) / 1e6
	muzzle := ready.Add(windup)
	shot.Started = float64(muzzle.UnixMicro()) / 1e6
	b.busyUntil = muzzle.Add(time.Duration((shot.Duration + .65) * float64(time.Second)))
	b.Deadline = 0
	return nil
}

// SupplyCue is a presentation event independent of the shot timeline.
type SupplyCue struct {
	ID     uint64  `json:"id"`
	At     float64 `json:"at"`
	Seat   int     `json:"seat"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Amount int     `json:"amount"`
	Fuel   bool    `json:"fuel,omitempty"`
	// The native item burst belongs to the user, including team supplies.
	ItemEffect bool `json:"item_effect"`
}

func (b *Battle) restoreSupply(u *Unit, amount int, fuel bool) {
	if fuel {
		u.SP = min(200, u.SP+amount)
	} else {
		u.HP = min(u.MaxHP, u.HP+amount)
	}
	at := nowSeconds()
	// Preserve the original nominal amount even when the resource is capped.
	b.supplyID++
	for len(b.Supplies) > 0 && at-b.Supplies[0].At > 4 {
		b.Supplies = b.Supplies[1:]
	}
	b.Supplies = append(b.Supplies, SupplyCue{ID: b.supplyID, At: at, Seat: u.Seat, X: u.X, Y: u.Y, Amount: amount, Fuel: fuel, ItemEffect: !fuel && u == b.active()})
}

func (b *Battle) useItem(id int) bool {
	u := b.active()
	switch id {
	case 1:
		u.Power = true
	case 2, 3, 4, 9, 16, 17:
		u.ShotMode = id
	case 5:
		b.restoreSupply(u, 50, false)
	case 6:
		b.restoreSupply(u, 100, false)
		return true
	case 7:
		for _, p := range b.Units {
			if p.Team == u.Team && p.HP > 0 {
				b.restoreSupply(p, 40, false)
			}
		}
		return true
	case 8:
		// Fuel preserves the movement cost already in effect this turn.
		b.restoreSupply(u, 40, true)
		if u.Stun == 0 && !b.moveBlocked {
			cost := vehicle(u.Vehicle).MoveCost
			if u.Economy {
				cost *= .5
			}
			u.Move = float64(u.SP) / cost
		}
	case 10:
		u.Shield = 1
	case 11:
		for _, p := range b.Units {
			if p.Team == u.Team && p.HP > 0 {
				b.restoreSupply(p, 20, true)
			}
		}
		return true
	case 12:
		u.Stealth = 3
	case 13:
		b.Wind = -b.Wind
	case 14:
		u.Double = true
	case 15:
		u.Economy = true
		if u.Stun == 0 && !b.moveBlocked {
			u.Move = float64(u.SP) / (vehicle(u.Vehicle).MoveCost * .5)
		}
	case 0:
	case -1:
	default:
	}
	return false
}
func (b *Battle) advance() {
	b.aiAction = nil
	old := b.active()
	if old != nil {
		old.SP = min(200, old.SP+80)
		old.Power = false
		old.Double = false
		old.ShotMode = 0
		old.Economy = false
		b.acted[old.Seat] = true
	}
	alive := []*Unit{}
	for _, u := range b.Units {
		if u.HP > 0 {
			alive = append(alive, u)
		}
	}
	sort.Slice(alive, func(i, j int) bool { return alive[i].Seat < alive[j].Seat })
	all := true
	for _, u := range alive {
		if !b.acted[u.Seat] {
			all = false
		}
	}
	if all {
		b.Round++
		b.acted = map[int]bool{}
		for _, u := range alive {
			if u.Poison > 0 {
				u.HP = max(0, u.HP-14)
				u.Poison--
			}
			if u.Burn > 0 {
				u.HP = max(0, u.HP-18)
				u.Burn--
			}
			u.Stealth = max(0, u.Stealth-1)
			u.Blind = max(0, u.Blind-1)
		}
	}
	for _, u := range alive {
		if u.HP > 0 && !b.acted[u.Seat] {
			b.Active = u.Seat
			u.Move = float64(u.SP) / vehicle(u.Vehicle).MoveCost
			b.moveBlocked = u.Stun > 0
			if b.moveBlocked {
				u.Move = 0
				u.Stun--
			}
			b.Deadline = nowSeconds() + 35
			b.Generation++
			b.aiAt = time.Now().Add(850 * time.Millisecond)
			b.Wind = rand.IntN(101) - 50
			return
		}
	}
	b.Deadline = 0
}
func (b *Battle) aiPlan() (float64, float64, int) {
	actor := b.active()
	v := vehicle(actor.Vehicle)
	weaponIndex := 0
	if actor.SP >= vehicle(actor.Vehicle).Weapons[2].Cost {
		weaponIndex = 2
	} else if actor.SP >= vehicle(actor.Vehicle).Weapons[1].Cost && rand.IntN(3) > 0 {
		weaponIndex = 1
	}
	w := vehicle(actor.Vehicle).Weapons[weaponIndex]
	best, angle, power := -1e9, 45.0, .65
	step := 8.0
	if actor.AI == 3 {
		step = 4
	}
	low, high := 12.0, 170.0
	if b.NativeAim {
		low, high = v.AimMin, v.AimMax
		angle = max(low, min(high, actor.Elevation))
	}
	for candidate := low; candidate <= high; candidate += step {
		a := candidate
		if b.NativeAim {
			a = actor.worldAngle(candidate)
		}
		for p := .2; p <= 1.001; p += .07 {
			_, hit, ok := b.trajectory(actor, a, p, w)
			if !ok {
				continue
			}
			score := -1000.0
			for _, u := range b.Units {
				if u.HP <= 0 || u.Stealth > 0 {
					continue
				}
				d := math.Hypot(u.X-hit.X, u.Y-18-hit.Y)
				if u.Team != actor.Team {
					score = max(score, 1000-d)
				}
			}
			for _, u := range b.Units {
				if u.HP > 0 && u.Team == actor.Team {
					d := math.Hypot(u.X-hit.X, u.Y-18-hit.Y)
					if d < w.Radius+24 {
						score -= 1400 * (1 - d/(w.Radius+24))
					}
				}
			}
			if score > best {
				best, angle, power = score, candidate, p
			}
		}
	}
	jitter := []float64{0, 6, 2, .35}[max(1, min(3, actor.AI))]
	b.planScore = best
	angle += (rand.Float64()*2 - 1) * jitter
	power += (rand.Float64()*2 - 1) * jitter * .006
	if !b.NativeAim {
		low, high = 5, 175
	}
	return max(low, min(high, angle)), max(.05, min(1, power)), weaponIndex
}

func (b *Battle) aiMove() float64 {
	u := b.active()
	if u == nil || u.HP <= 0 || u.Stun > 0 {
		return 0
	}
	var enemy *Unit
	distance := math.MaxFloat64
	for _, target := range b.Units {
		if target.HP > 0 && target.Team != u.Team && target.Stealth == 0 {
			d := math.Abs(target.X - u.X)
			if d < distance {
				enemy = target
				distance = d
			}
		}
	}
	if enemy == nil {
		return 0
	}
	u.Face = 1
	if enemy.X < u.X {
		u.Face = -1
	}
	u.Aim = u.worldAngle(u.Elevation)
	if distance < 170 {
		return 0
	}
	step := float64(10 + u.AI*8)
	if enemy.X < u.X {
		step = -step
	}
	before := u.X
	if e := b.move(step); e != nil {
		return 0
	}
	return u.X - before
}
func (b *Battle) description() string {
	return fmt.Sprintf("第 %d 轮 · %s 行动", b.Round, b.active().Name)
}
