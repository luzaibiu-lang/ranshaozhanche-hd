package main

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func flatBattle() *Battle {
	terrain := &Terrain{W: 1920, H: 1000, Solid: make([]byte, 1920*1000)}
	for y := 600; y < 1000; y++ {
		for x := 0; x < 1920; x++ {
			terrain.Solid[y*1920+x] = 1
		}
	}
	return &Battle{ID: "fixture", Map: 1, Width: 1920, Height: 1000, Terrain: terrain, Round: 1, Active: 0, Wind: 0, Generation: 1, acted: map[int]bool{}, Deadline: nowSeconds() + 35, Holes: []Hole{}, Units: []*Unit{
		{Seat: 0, Player: 1, Name: "human", Team: 0, Vehicle: 1, X: 300, Y: 600, HP: 300, MaxHP: 300, SP: 150, Move: 90, Face: 1},
		{Seat: 4, Player: -5, Name: "AI", Team: 1, Vehicle: 4, AI: 3, X: 900, Y: 600, HP: 370, MaxHP: 370, SP: 150, Move: 65, Face: -1},
	}}
}
func TestProjectileReturnsFromAboveAndExpiresAtSides(t *testing.T) {
	b := flatBattle()
	w := vehicle(1).Weapons[0]
	trail, hit, ok := b.trajectory(b.active(), 80, 1, w)
	if !ok || hit.Y < 580 {
		t.Fatalf("high shot did not return: %+v", hit)
	}
	above := false
	for _, p := range trail.Points {
		above = above || p[1] < 0
	}
	if !above {
		t.Fatal("fixture never crossed the top")
	}
	b.Units[0].X = 20
	trail, _, ok = b.trajectory(b.active(), 175, 1, w)
	if ok {
		t.Fatal("left out-of-map shot collided after leaving")
	}
	for _, p := range trail.Points {
		if p[0] > 1800 {
			t.Fatal("projectile wrapped to opposite side")
		}
	}
}
func TestInvalidFireAndSPAreAtomic(t *testing.T) {
	b := flatBattle()
	for _, angle := range []float64{math.NaN(), math.Inf(1), -3, 180} {
		if b.fire(angle, .5, 0) == nil {
			t.Fatal("invalid angle accepted")
		}
	}
	b.active().SP = vehicle(1).Weapons[2].Cost - 1
	before := b.active().SP
	if b.fire(45, .5, 2) == nil {
		t.Fatal("ultimate accepted without enough SP")
	}
	if b.active().SP != before || b.pending != nil {
		t.Fatal("rejected action mutated battle")
	}
	b.active().SP = 150
	if e := b.fire(45, .5, 0); e != nil {
		t.Fatal(e)
	}
	if b.pending.active().SP != 150 {
		t.Fatal("basic cannon consumed SP")
	}
	if b.pending.Terrain == b.Terrain {
		t.Fatal("unresolved shot mutated live terrain")
	}
}
func TestCompleteRoundCountsEveryLivingParticipant(t *testing.T) {
	b := flatBattle()
	b.Units = nil
	for i := 0; i < 8; i++ {
		b.Units = append(b.Units, &Unit{Seat: i, Player: int64(i + 1), Team: i % 4, Vehicle: 1, HP: 300, MaxHP: 300, SP: 0})
	}
	seen := map[int]bool{}
	for i := 0; i < 8; i++ {
		if seen[b.Active] {
			t.Fatal("same actor repeated within round")
		}
		seen[b.Active] = true
		if b.Round != 1 {
			t.Fatal("round incremented early")
		}
		b.advance()
	}
	if b.Round != 2 || len(seen) != 8 {
		t.Fatal("complete round not counted")
	}
	for _, u := range b.Units {
		if u.SP != 80 {
			t.Fatal("SP recovery is not once per action")
		}
	}
	b.Units[0].HP = 0
	b.Active = 0
	b.advance()
	if b.Active == 0 {
		t.Fatal("dead actor stalled round")
	}
}
func TestCliffMovementAndDeathNeverCreateIdleMovement(t *testing.T) {
	b := flatBattle()
	for y := 0; y < b.Height; y++ {
		for x := 325; x < 700; x++ {
			b.Terrain.Solid[y*b.Width+x] = 0
		}
	}
	if e := b.move(45); e != nil {
		t.Fatal(e)
	}
	if b.active().X >= 325 {
		t.Fatal("AI/human safety walk crossed cliff")
	}
	b.active().HP = 0
	if b.move(10) == nil {
		t.Fatal("dead unit moved")
	}
}
func TestAllVehiclesAndWeaponsHaveWorkingShotResolution(t *testing.T) {
	for id := 1; id <= 30; id++ {
		for weaponIndex := 0; weaponIndex < 3; weaponIndex++ {
			b := flatBattle()
			b.NativeAim = true
			b.Units[0].Vehicle = id
			b.Units[0].SP = 200
			if e := b.fire(50, .7, weaponIndex); e != nil {
				t.Fatalf("vehicle %d weapon %d: %v", id, weaponIndex, e)
			}
			if b.pending == nil || b.Shot == nil || len(b.Shot.Trails) == 0 || b.busyUntil.IsZero() {
				t.Fatalf("missing shot resolution %d/%d", id, weaponIndex)
			}
			for _, u := range b.pending.Units {
				if u.HP < 0 || u.HP > u.MaxHP || u.SP < 0 || u.SP > 200 {
					t.Fatal("unit bounds violated")
				}
			}
		}
	}
}
func TestAICanAimAndAdvanceAfterHumanDies(t *testing.T) {
	b := flatBattle()
	b.Units = append(b.Units, &Unit{Seat: 8, Player: -9, Name: "second AI", Team: 2, Vehicle: 6, AI: 3, X: 1400, Y: 600, HP: 300, MaxHP: 300, SP: 200})
	b.Units[0].HP = 0
	b.Active = 4
	b.aiAt = time.Now().Add(-time.Second)
	store, e := openStore(filepath.Join(t.TempDir(), "game.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer store.db.Close()
	w := &World{store: store, rooms: map[int]*Room{1: {ID: 1, Owner: 1, Battle: b, Members: []*Member{{ID: -5, AI: 3}, {ID: -9, AI: 3}}}}, sessions: map[string]Session{}}
	for turn := 0; turn < 6; turn++ {
		b.aiAt = time.Now().Add(-time.Second)
		w.tick()
		finishAIWalkForTest(t, w, b)
		if b.Shot == nil || b.pending == nil {
			t.Fatal("AI failed to shoot without a living human")
		}
		b.busyUntil = time.Now().Add(-time.Second)
		w.tick()
		if b.Result != nil {
			break
		}
		if b.Active == 0 {
			t.Fatal("dead human scheduled")
		}
	}
}
func TestOriginalMapsSupportSafeEightPlayerSpawns(t *testing.T) {
	for id := 1; id <= 19; id++ {
		terrain, e := loadTerrain("../client/assets", id)
		if e != nil {
			t.Fatal(e)
		}
		for n := 2; n <= 8; n++ {
			points, e := terrain.spawns(n)
			if e != nil {
				t.Fatalf("map %d players %d: %v", id, n, e)
			}
			if len(points) != n {
				t.Fatal("wrong spawn count")
			}
			for _, p := range points {
				if !terrain.solid(p[0], p[1]+2) {
					t.Fatalf("unsafe airborne spawn on map %d: %+v", id, p)
				}
			}
		}
	}
}
func TestAuthShopGMAndRoomIsolation(t *testing.T) {
	store, e := openStore(filepath.Join(t.TempDir(), "game.sqlite3"))
	if e != nil {
		t.Fatal(e)
	}
	defer store.db.Close()
	w, e := newWorld(store, "../client/assets")
	if e != nil {
		t.Fatal(e)
	}
	handler := newHandler(w, "test-admin-key-872949293")
	request := func(path, body, auth string) (int, map[string]any) {
		r := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
		if body == "" {
			r.Method = http.MethodGet
		}
		if auth != "" {
			r.Header.Set("Authorization", "Bearer "+auth)
		}
		rw := httptest.NewRecorder()
		handler.ServeHTTP(rw, r)
		var out map[string]any
		json.Unmarshal(rw.Body.Bytes(), &out)
		return rw.Code, out
	}
	status, j := request("/api/register", `{"name":"tester_a","password":"strong-test-895432"}`, "")
	if status != 200 {
		t.Fatalf("register: %v", j)
	}
	auth := j["token"].(string)
	status, j = request("/api/command", `{"action":"buy","item":1,"slot":0}`, auth)
	if status != 200 {
		t.Fatal(j)
	}
	p := j["profile"].(map[string]any)
	if int(p["gold"].(float64)) != 18200 {
		t.Fatal("shop price wrong")
	}
	status, _ = request("/api/command", `{"action":"buy","item":2,"slot":0}`, auth)
	if status == 200 {
		t.Fatal("occupied inventory slot overwritten")
	}
	status, j = request("/api/command", `{"action":"create","map":1,"capacity":8}`, auth)
	if status != 200 {
		t.Fatal(j)
	}
	room := j["room"].(map[string]any)
	rid := int(room["id"].(float64))
	if rid != 101 {
		t.Fatal("room id unexpected")
	}
	bots := make([]BotChoice, 16)
	for i := range bots {
		bots[i] = BotChoice{Seat: i}
		if i == 4 || i == 8 || i == 12 {
			bots[i].Level = 3
		}
	}
	payload, _ := json.Marshal(Command{Action: "bots", Bots: bots})
	status, j = request("/api/command", string(payload), auth)
	if status != 200 {
		t.Fatal(j)
	}
	status, j = request("/api/command", `{"action":"start"}`, auth)
	if status != 200 {
		t.Fatal(j)
	}
	battle := j["room"].(map[string]any)["battle"].(map[string]any)
	generation := int(battle["generation"].(float64))
	status, _ = request("/api/command", `{"action":"pass","generation":9999}`, auth)
	if status == 200 {
		t.Fatal("stale action accepted")
	}
	status, _ = request("/api/command", fmtCommand("pass", generation), auth)
	if status != 200 {
		t.Fatal("valid action rejected")
	}
	status, _ = request("/gm/api/action", `{"action":"add_gold","player":1,"amount":1000}`, auth)
	if status != 401 {
		t.Fatal("player token authorized GM")
	}
	status, j = request("/gm/api/action", `{"action":"add_gold","player":1,"amount":1000}`, "test-admin-key-872949293")
	if status != 200 {
		t.Fatal(j)
	}
	p2, _ := store.profile(1)
	if p2.Gold != 19200 {
		t.Fatal("GM gold not saved")
	}
	for id := range w.rooms {
		w.finish(w.rooms[id], 0, "test settlement")
	}
	p3, _ := store.profile(1)
	for id := range w.rooms {
		w.finish(w.rooms[id], 0, "duplicate")
	}
	p4, _ := store.profile(1)
	if p3.Gold != p4.Gold || p3.Games != 1 {
		t.Fatal("duplicate settlement paid twice")
	}
	status, j = request("/api/command", `{"action":"return"}`, auth)
	if status != 200 || j["room"].(map[string]any)["battle"] != nil {
		t.Fatal("return to room failed")
	}
}
func fmtCommand(action string, generation int) string {
	b, _ := json.Marshal(Command{Action: action, Generation: uint64(generation)})
	return string(b)
}
