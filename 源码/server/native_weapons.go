package main

// Native logical IDs and projectile statistics are recorded in
// docs/original-shots.json. Damage is +0xcc and falloff radius is +0xd0.
// Repeated streams come from CTank::update (005359b0), rather than giving
// every vehicle the same guessed second weapon.
type nativeWeapon struct {
	projectile, damage int
	radius             float64
	count              int
	kind               string
	delay              float64
}

var nativeWeapons = map[int]nativeWeapon{
	0:  {1, 62, 55, 1, "normal", 0},
	1:  {13, 16, 45, 6, "normal", 15.0 / 60},
	2:  {3, 65, 80, 1, "cluster", 0},
	3:  {6, 62, 53, 1, "beam", 0},
	4:  {19, 63, 54, 1, "normal", 0},
	5:  {5, 40, 50, 1, "ricochet", 0},
	6:  {7, 38, 72, 1, "normal", 0},
	7:  {8, 95, 36, 1, "normal", 0},
	8:  {2, 28, 43, 3, "normal", 0},
	9:  {9, 63, 55, 1, "fire", 0},
	10: {10, 25, 30, 1, "fire_bounce", 0},
	11: {10, 40, 65, 1, "firewall", 0},
	12: {11, 95, 130, 1, "nuke", 0},
	13: {12, 29, 47, 3, "normal", 0},
	14: {12, 30, 50, 6, "normal", 15.0 / 60},
	15: {14, 37, 50, 2, "beam", 0},
	16: {15, 25, 33, 4, "normal", 5.0 / 60},
	17: {16, 79, 46, 1, "normal", 0},
	18: {17, 60, 55, 1, "normal", 0},
	19: {6, 57, 52, 3, "beam", 0},
	20: {14, 35, 62, 4, "beam", 0},
	21: {18, 26, 55, 5, "homing", 0},
	22: {20, 41, 50, 1, "normal", 0},
	23: {21, 43, 50, 1, "drain", 0},
	24: {24, 85, 50, 1, "fire", 0},
	25: {25, 55, 40, 1, "fire_bounce", 0},
	26: {26, 230, 80, 1, "fire", 0},
	27: {27, 10, 20, 20, "normal", 5.0 / 60},
	28: {28, 30, 30, 1, "normal", 0},
	29: {29, 250, 25, 1, "lightning", 0},
	42: {42, 30, 60, 1, "cluster", 0},
	43: {43, 45, 80, 1, "cluster", 0},
	47: {47, 62, 55, 1, "normal", 0},
	48: {48, 12, 40, 8, "normal", 5.0 / 60},
	49: {49, 15, 40, 16, "normal", 5.0 / 60},
	58: {58, 41, 60, 1, "normal", 0},
	59: {59, 65, 65, 1, "pierce", 0},
	60: {59, 65, 65, 3, "pierce", 0},
	71: {72, 65, 80, 1, "cluster", 0},
	72: {72, 65, 80, 1, "cluster", 0},
	78: {78, 105, 55, 1, "normal", 0},
	79: {79, 95, 130, 1, "nuke", 0},
	81: {81, 47, 50, 4, "beam", 0},
	82: {81, 45, 62, 6, "beam", 0},
	90: {90, 85, 50, 1, "fire", 0},
	91: {91, 55, 40, 1, "fire_bounce", 0},
	92: {92, 80, 60, 1, "lightning", 0},
}

func nativeLoadout(index int) [3]Weapon {
	var out [3]Weapon
	for slot, id := range originalWeaponIDs[index] {
		n, ok := nativeWeapons[id]
		if !ok {
			panic("missing native weapon")
		}
		cost := originalWeaponCosts[index][slot]
		if slot == 0 {
			cost = 0
		}
		name := []string{"主武器", "副武器", "必杀技"}[slot]
		out[slot] = Weapon{Name: name, Kind: n.kind, Cost: cost, Damage: n.damage, Radius: n.radius, Count: n.count, Wind: 1, NativeID: id, Projectile: n.projectile, Delay: n.delay}
	}
	return out
}
