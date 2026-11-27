package main

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"
)

type Member struct {
	ID             int64     `json:"id"`
	Name           string    `json:"name"`
	Seat           int       `json:"seat"`
	Vehicle        int       `json:"vehicle"`
	AI             int       `json:"ai"`
	Ready          bool      `json:"ready"`
	Returned       bool      `json:"returned"`
	Seen           time.Time `json:"-"`
	LoadingBarrier bool      `json:"-"`
}
type Chat struct {
	Name string  `json:"name"`
	Text string  `json:"text"`
	Time float64 `json:"time"`
}
type Room struct {
	ID           int       `json:"id"`
	Name         string    `json:"name"`
	Owner        int64     `json:"owner"`
	Map          int       `json:"map"`
	Capacity     int       `json:"capacity"`
	Members      []*Member `json:"members"`
	Chat         []Chat    `json:"chat"`
	Battle       *Battle   `json:"battle"`
	Locked       bool      `json:"locked"`
	PasswordHash [32]byte  `json:"-"`
}
type Session struct {
	Player  int64
	Expires time.Time
}
type World struct {
	mu        sync.Mutex
	store     *Store
	rooms     map[int]*Room
	sessions  map[string]Session
	terrain   map[int]*Terrain
	nextRoom  int
	version   uint64
	epoch     string
	lobbyChat []Chat
	presence  map[int64]*Presence
	invites   map[int64]Invitation
	whispers  map[int64][]Chat
}
type Invitation struct {
	Room     int     `json:"room"`
	RoomName string  `json:"room_name"`
	From     string  `json:"from"`
	Expires  float64 `json:"expires"`
}
type Presence struct {
	ID   int64     `json:"id"`
	Name string    `json:"name"`
	Room int       `json:"room"`
	Seen time.Time `json:"-"`
}
type Snapshot struct {
	Epoch      string           `json:"epoch"`
	Profile    *Profile         `json:"profile"`
	Rooms      []map[string]any `json:"rooms"`
	Room       *Room            `json:"room"`
	Version    uint64           `json:"version"`
	ServerTime float64          `json:"server_time"`
	Chat       []Chat           `json:"chat"`
	Players    []Presence       `json:"players"`
	Invitation *Invitation      `json:"invitation,omitempty"`
	Whispers   []Chat           `json:"whispers"`
}
type Command struct {
	Action         string      `json:"action"`
	Room           int         `json:"room"`
	Name           string      `json:"name"`
	Map            int         `json:"map"`
	Capacity       int         `json:"capacity"`
	Seat           int         `json:"seat"`
	Vehicle        int         `json:"vehicle"`
	Ready          bool        `json:"ready"`
	Bots           []BotChoice `json:"bots"`
	Text           string      `json:"text"`
	Distance       float64     `json:"distance"`
	MoveSequence   uint64      `json:"move_sequence"`
	Angle          float64     `json:"angle"`
	AimMode        string      `json:"aim_mode"`
	AimFace        int         `json:"aim_face"`
	Power          float64     `json:"power"`
	Weapon         int         `json:"weapon"`
	Item           int         `json:"item"`
	Slot           int         `json:"slot"`
	Outfit         int         `json:"outfit"`
	Generation     uint64      `json:"generation"`
	LoadingBarrier bool        `json:"loading_barrier"`
	BattleID       string      `json:"battle_id"`
	Password       string      `json:"password"`
	Private        bool        `json:"private"`
	Player         int64       `json:"player"`
	RejectPrivate  bool        `json:"reject_private"`
	RejectInvites  bool        `json:"reject_invites"`
}
type BotChoice struct {
	Seat    int `json:"seat"`
	Level   int `json:"level"`
	Vehicle int `json:"vehicle"`
}

func newWorld(store *Store, assets string) (*World, error) {
	w := &World{store: store, rooms: map[int]*Room{}, sessions: map[string]Session{}, terrain: map[int]*Terrain{}, nextRoom: 100, version: 1, epoch: token()[:16], lobbyChat: []Chat{}}
	for i := 1; i <= 19; i++ {
		t, e := loadTerrain(assets, i)
		if e != nil {
			return nil, fmt.Errorf("地图 %d: %w", i, e)
		}
		w.terrain[i] = t
	}
	return w, nil
}
func (w *World) roomFor(id int64) (*Room, *Member) {
	for _, r := range w.rooms {
		for _, m := range r.Members {
			if m.ID == id && m.AI == 0 {
				return r, m
			}
		}
	}
	return nil, nil
}
func (w *World) snapshot(id int64) (*Snapshot, error) {
	p, e := w.store.profile(id)
	if e != nil {
		return nil, e
	}
	w.touchPresence(id)
	r, m := w.roomFor(id)
	if m != nil {
		m.Seen = time.Now()
	}
	list := []map[string]any{}
	for _, v := range w.rooms {
		ownerName := ""
		phase := "waiting"
		if v.Battle != nil {
			phase = "battle"
			if v.Battle.Result != nil {
				phase = "settlement"
			}
		}
		waitingReturns := 0
		for _, m := range v.Members {
			if phase == "settlement" && m.AI == 0 && !m.Returned {
				waitingReturns++
			}
			if m.ID == v.Owner {
				ownerName = m.Name
			}
		}
		list = append(list, map[string]any{"id": v.ID, "name": v.Name, "map": v.Map, "owner_name": ownerName, "capacity": v.Capacity, "players": len(v.Members), "started": v.Battle != nil, "phase": phase, "waiting_returns": waitingReturns, "locked": v.Locked})
	}
	sort.Slice(list, func(i, j int) bool { return list[i]["id"].(int) < list[j]["id"].(int) })
	if m != nil && m.Returned && r.Battle != nil {
		v := *r
		v.Battle = nil
		r = &v
	}
	players := []Presence{}
	for _, online := range w.presence {
		entry := *online
		if room, _ := w.roomFor(entry.ID); room != nil {
			entry.Room = room.ID
		}
		players = append(players, entry)
	}
	sort.Slice(players, func(i, j int) bool { return players[i].ID < players[j].ID })
	state := &Snapshot{Epoch: w.epoch, Profile: p, Rooms: list, Room: r, Version: w.version, ServerTime: nowSeconds(), Chat: w.lobbyChat, Players: players}
	state.Whispers = append([]Chat{}, w.whispers[id]...)
	if invitation, ok := w.invites[id]; ok && invitation.Expires > nowSeconds() && r == nil {
		if target := w.rooms[invitation.Room]; target != nil && target.Battle == nil && len(target.Members) < target.Capacity {
			state.Invitation = &invitation
		}
	}
	return state, nil
}

func (w *World) touchPresence(id int64) {
	if w.presence == nil {
		w.presence = map[int64]*Presence{}
	}
	if player := w.presence[id]; player != nil {
		player.Seen = time.Now()
		return
	}
	profile, e := w.store.profile(id)
	if e != nil {
		return
	}
	w.presence[id] = &Presence{ID: id, Name: profile.Name, Seen: time.Now()}
	w.version++
}
func (w *World) leave(id int64) {
	r, m := w.roomFor(id)
	if r == nil {
		return
	}
	for i, p := range r.Members {
		if p == m {
			r.Members = append(r.Members[:i], r.Members[i+1:]...)
			break
		}
	}
	if r.Battle != nil && r.Battle.Loading {
		r.cancelLoading("有玩家离开，已取消本次开局。")
	}
	if r.Battle != nil && r.Battle.Result == nil {
		for _, u := range r.Battle.Units {
			if u.Player == id {
				u.HP = 0
				u.Departed = true
			}
		}
		if r.Battle.pending != nil {
			for _, u := range r.Battle.pending.Units {
				if u.Player == id {
					u.HP = 0
					u.Departed = true
				}
			}
		}
		if r.Battle.Shot != nil {
			for _, state := range r.Battle.Shot.States {
				for _, u := range state.Units {
					if u.Player == id {
						u.HP = 0
						u.Departed = true
					}
				}
			}
		}
	}
	humans := []*Member{}
	for _, p := range r.Members {
		if p.AI == 0 {
			humans = append(humans, p)
		}
	}
	if len(humans) == 0 {
		delete(w.rooms, r.ID)
	} else {
		if r.Owner == id {
			r.Owner = humans[0].ID
		}
		r.finishReturning()
	}
	w.version++
}

func (r *Room) canConfigure(m *Member) bool {
	return r.Battle == nil || (r.Battle.Result != nil && m.Returned)
}

func (r *Room) finishReturning() {
	if r.Battle == nil || r.Battle.Result == nil {
		return
	}
	for _, member := range r.Members {
		if member.AI == 0 && !member.Returned {
			return
		}
	}
	r.Battle = nil
	for _, member := range r.Members {
		member.Returned = false
	}
}

func (r *Room) cancelLoading(reason string) {
	r.Battle = nil
	r.Chat = append(r.Chat, Chat{Name: "系统", Text: reason, Time: nowSeconds()})
	if len(r.Chat) > 60 {
		r.Chat = r.Chat[len(r.Chat)-60:]
	}
}

func (w *World) command(id int64, c Command) error {
	w.touchPresence(id)
	r, m := w.roomFor(id)
	if m != nil {
		m.Seen = time.Now()
		m.LoadingBarrier = m.LoadingBarrier || c.LoadingBarrier
	}
	switch c.Action {
	case "create":
		if r != nil {
			return errors.New("请先离开当前房间")
		}
		name := strings.TrimSpace(c.Name)
		if len([]rune(name)) < 1 {
			name = "好友的战场"
		}
		if len([]rune(name)) > 24 {
			return errors.New("房间名称过长")
		}
		capacity := c.Capacity
		if capacity == 0 {
			capacity = 8
		}
		if capacity < 2 || capacity > 8 || c.Map < 0 || c.Map > 19 {
			return errors.New("房间设置无效")
		}
		w.nextRoom++
		if len([]rune(c.Password)) > 16 || c.Private && c.Password == "" {
			return errors.New("私人房间需设置 1～16 字密码")
		}
		r = &Room{ID: w.nextRoom, Name: name, Owner: id, Map: c.Map, Capacity: capacity, Members: []*Member{{ID: id, Name: w.mustProfile(id).Name, Seat: 0, Vehicle: 1, Ready: true, Seen: time.Now(), LoadingBarrier: c.LoadingBarrier}}, Chat: []Chat{}, Locked: c.Private || c.Password != ""}
		if r.Locked {
			r.PasswordHash = sha256.Sum256([]byte(c.Password))
		}
		w.rooms[r.ID] = r
	case "join", "accept_invite":
		if r != nil {
			return errors.New("请先离开当前房间")
		}
		r = w.rooms[c.Room]
		if r == nil {
			return errors.New("房间已关闭")
		}
		if r.Battle != nil {
			return errors.New("对局正在进行")
		}
		if len(r.Members) >= r.Capacity {
			return errors.New("房间已满")
		}
		invited := false
		if c.Action == "accept_invite" {
			v, ok := w.invites[id]
			invited = ok && v.Room == r.ID && v.Expires > nowSeconds()
			if !invited {
				return errors.New("邀请已过期")
			}
		}
		if r.Locked && !invited && r.PasswordHash != sha256.Sum256([]byte(c.Password)) {
			return errors.New("房间密码错误")
		}
		seat := -1
		for _, candidate := range []int{4, 1, 5, 8, 9, 12, 13, 2, 6, 10, 14, 3, 7, 11, 15, 0} {
			used := false
			for _, p := range r.Members {
				used = used || p.Seat == candidate
			}
			if !used {
				seat = candidate
				break
			}
		}
		r.Members = append(r.Members, &Member{ID: id, Name: w.mustProfile(id).Name, Seat: seat, Vehicle: 1, Ready: true, Seen: time.Now(), LoadingBarrier: c.LoadingBarrier})
		delete(w.invites, id)
	case "decline_invite":
		delete(w.invites, id)
	case "preferences":
		_, e := w.store.db.Exec("INSERT INTO preferences(player,reject_private,reject_invites) VALUES(?,?,?) ON CONFLICT(player) DO UPDATE SET reject_private=excluded.reject_private,reject_invites=excluded.reject_invites", id, c.RejectPrivate, c.RejectInvites)
		if e != nil {
			return e
		}
		if c.RejectInvites {
			delete(w.invites, id)
		}
	case "leave":
		w.leave(id)
		return nil
	case "chat":
		text := strings.TrimSpace(c.Text)
		if len([]rune(text)) < 1 || len([]rune(text)) > 200 {
			return errors.New("消息需为 1～200 个字符")
		}
		if strings.HasPrefix(strings.ToLower(text), "/w ") {
			if e := w.whisper(id, text); e != nil {
				return e
			}
			w.version++
			return nil
		}
		msg := Chat{w.mustProfile(id).Name, text, nowSeconds()}
		if r == nil {
			w.lobbyChat = append(w.lobbyChat, msg)
			if len(w.lobbyChat) > 60 {
				w.lobbyChat = w.lobbyChat[len(w.lobbyChat)-60:]
			}
		} else {
			r.Chat = append(r.Chat, msg)
			if len(r.Chat) > 60 {
				r.Chat = r.Chat[len(r.Chat)-60:]
			}
		}
	case "buy", "sell", "outfit":
		if r != nil && !r.canConfigure(m) {
			return errors.New("请在对局结束后操作商城")
		}
		var e error
		if c.Action == "outfit" {
			_, e = w.store.outfit(id, c.Outfit)
		} else {
			_, e = w.store.buy(id, c.Item, c.Slot, c.Action == "sell")
		}
		if e != nil {
			return e
		}
		if r != nil && r.Owner != id {
			m.Ready = false
		}
	default:
		if r == nil {
			return errors.New("尚未进入房间")
		}
		switch c.Action {
		case "invite":
			if r.Battle != nil || len(r.Members) >= r.Capacity {
				return errors.New("请在未满员的等候房间邀请")
			}
			if c.Player == id {
				return errors.New("请选择其他玩家")
			}
			if target, _ := w.roomFor(c.Player); target != nil {
				return errors.New("该玩家已在房间内")
			}
			online := w.presence[c.Player]
			if online == nil || time.Since(online.Seen) > 75*time.Second {
				return errors.New("玩家已离线")
			}
			targetProfile, e := w.store.profile(c.Player)
			if e != nil {
				return e
			}
			if targetProfile.RejectInvites {
				return errors.New("该玩家已拒绝邀请")
			}
			if w.invites == nil {
				w.invites = map[int64]Invitation{}
			}
			if previous, ok := w.invites[c.Player]; ok && previous.Expires > nowSeconds()+45 {
				return errors.New("已发送邀请，请稍候")
			}
			w.invites[c.Player] = Invitation{r.ID, r.Name, m.Name, nowSeconds() + 60}
		case "settings":
			if r.Owner != id || !r.canConfigure(m) {
				return errors.New("仅房主可在开局前修改")
			}
			if c.Map < 0 || c.Map > 19 {
				return errors.New("地图不存在")
			}
			r.Map = c.Map
		case "seat":
			if !r.canConfigure(m) {
				return errors.New("对局中无法换组")
			}
			if c.Seat < 0 || c.Seat > 15 {
				return errors.New("位置无效")
			}
			for _, p := range r.Members {
				if p.Seat == c.Seat && p != m {
					return errors.New("此位置已有人")
				}
			}
			if c.Seat != m.Seat && r.Owner != id {
				m.Ready = false
			}
			m.Seat = c.Seat
		case "vehicle":
			if !r.canConfigure(m) {
				return errors.New("对局中无法换车")
			}
			if c.Vehicle < 0 || c.Vehicle > 30 {
				return errors.New("战车不存在")
			}
			if c.Vehicle != m.Vehicle && r.Owner != id {
				m.Ready = false
			}
			m.Vehicle = c.Vehicle
		case "ready":
			if !r.canConfigure(m) {
				return errors.New("已开始对局")
			}
			m.Ready = c.Ready
		case "bots":
			if r.Owner != id || !r.canConfigure(m) {
				return errors.New("仅房主可在开局前设置 AI")
			}
			if len(c.Bots) != 16 {
				return errors.New("AI 配置必须包含 16 个位置")
			}
			humans := map[int]*Member{}
			next := []*Member{}
			for _, p := range r.Members {
				if p.AI == 0 {
					humans[p.Seat] = p
					next = append(next, p)
				}
			}
			seen := map[int]bool{}
			for _, v := range c.Bots {
				if v.Seat < 0 || v.Seat > 15 || seen[v.Seat] || v.Level < 0 || v.Level > 3 || v.Vehicle < 0 || v.Vehicle > 30 {
					return errors.New("AI 配置无效")
				}
				seen[v.Seat] = true
				if humans[v.Seat] != nil {
					continue
				}
				if v.Level > 0 {
					next = append(next, &Member{ID: -int64(v.Seat + 1), Name: fmt.Sprintf("%sAI-%d", []string{"", "简单", "中等", "困难"}[v.Level], v.Seat+1), Seat: v.Seat, Vehicle: v.Vehicle, AI: v.Level, Ready: true})
				}
			}
			if len(next) > r.Capacity {
				return fmt.Errorf("总人数不能超过 %d 人", r.Capacity)
			}
			sort.Slice(next, func(i, j int) bool { return next[i].Seat < next[j].Seat })
			r.Members = next
		case "start":
			if r.Owner != id {
				return errors.New("仅房主可以开始")
			}
			if r.Battle != nil {
				return errors.New("请等待所有玩家返回房间")
			}
			if len(r.Members) < 2 {
				return errors.New("请加入玩家或设置 AI 陪练")
			}
			teams := map[int]bool{}
			for _, p := range r.Members {
				teams[p.Seat/4] = true
				if !p.Ready && p.ID != id {
					return errors.New("还有玩家未准备")
				}
			}
			if len(teams) < 2 {
				return errors.New("至少需要两个不同组")
			}
			mapID := r.Map
			if mapID == 0 {
				mapID = 1 + rand.IntN(19)
			}
			terrain := w.terrain[mapID].clone()
			spawns, e := terrain.spawns(len(r.Members))
			if e != nil {
				return e
			}
			battle := &Battle{ID: token(), Map: mapID, Width: terrain.W, Height: terrain.H, Terrain: terrain, Units: []*Unit{}, Holes: []Hole{}, Round: 1, Wind: rand.IntN(101) - 50, Generation: 1, acted: map[int]bool{}}
			for i, p := range r.Members {
				unitID := p.Vehicle
				if unitID == 0 {
					unitID = 1 + rand.IntN(30)
				}
				v := vehicle(unitID)
				face := 1
				aim := 45.0
				if spawns[i][0] > float64(terrain.W)/2 {
					face = -1
					aim = 135
				}
				u := &Unit{Seat: p.Seat, Player: p.ID, Name: p.Name, Team: p.Seat / 4, Vehicle: unitID, AI: p.AI, X: spawns[i][0], Y: spawns[i][1], HP: v.HP, MaxHP: v.HP, SP: 150, Move: v.Move, Face: face, Aim: aim, Elevation: math.Trunc((v.AimMax-v.AimMin)/2) + v.AimMin}
				u.updateSlope(terrain)
				battle.Units = append(battle.Units, u)
				p.Returned = false
				if p.AI == 0 && p.LoadingBarrier {
					battle.LoadingSeats = append(battle.LoadingSeats, p.Seat)
				}
			}
			battle.Active = battle.Units[0].Seat
			battle.NativeAim = true
			if len(battle.LoadingSeats) > 0 {
				battle.Loading = true
				battle.LoadingDeadline = nowSeconds() + 180
			} else {
				battle.startFirstTurn(time.Now())
			}
			r.Battle = battle
		case "battle_loaded":
			b := r.Battle
			if b == nil || b.ID != c.BattleID {
				return errors.New("开局状态已更新")
			}
			index := slices.Index(b.LoadingSeats, m.Seat)
			if index < 0 {
				return nil
			}
			if nowSeconds() >= b.LoadingDeadline {
				r.cancelLoading("战场加载超时，已取消本次开局。")
				break
			}
			b.LoadingSeats = slices.Delete(b.LoadingSeats, index, index+1)
			if len(b.LoadingSeats) == 0 {
				b.startFirstTurn(time.Now())
			}
		case "return":
			if r.Battle == nil || r.Battle.Result == nil {
				return errors.New("对局尚未结束")
			}
			if !m.Returned {
				m.Returned = true
				m.Ready = true
			}
			r.finishReturning()
		case "move", "fire", "pass", "item":
			b := r.Battle
			if b == nil || b.Result != nil || b.pending != nil {
				return errors.New("当前不能行动")
			}
			if b.Loading {
				return errors.New("战场正在加载")
			}
			if b.Deadline <= nowSeconds() {
				return errors.New("本次行动时间已结束")
			}
			u := b.active()
			if u == nil || u.Player != id || u.AI != 0 {
				return errors.New("尚未轮到你行动")
			}
			if c.Generation != b.Generation {
				return errors.New("行动已经切换，请重试")
			}
			switch c.Action {
			case "move":
				if c.MoveSequence > 0 && c.MoveSequence <= u.MoveSequence {
					return nil
				}
				if e := b.move(c.Distance); e != nil {
					return e
				}
				if c.MoveSequence > 0 {
					u.MoveSequence = c.MoveSequence
				}
			case "fire":
				var e error
				if c.AimMode == "native" {
					if c.AimFace != 0 && c.AimFace != 1 && c.AimFace != -1 {
						return errors.New("战车朝向无效")
					}
					previousFace := u.Face
					if c.AimFace != 0 {
						u.Face = c.AimFace
					}
					e = b.fireNative(c.Angle, c.Power, c.Weapon)
					if e != nil {
						u.Face = previousFace
					}
				} else {
					e = b.fire(c.Angle, c.Power, c.Weapon)
				}
				if e != nil {
					return e
				}
			case "pass":
				b.advance()
			case "item":
				if c.Slot < 0 || c.Slot > 3 {
					return errors.New("位置无效")
				}
				itemID, e := w.store.consume(id, c.Slot)
				if e != nil {
					return e
				}
				if b.useItem(itemID) {
					b.advance()
				}
			}
		default:
			return errors.New("未知操作")
		}
	}
	w.version++
	return nil
}
func (w *World) mustProfile(id int64) *Profile {
	p, e := w.store.profile(id)
	if e != nil {
		panic(e)
	}
	return p
}
func (w *World) finish(r *Room, team int, reason string) {
	b := r.Battle
	if b == nil || b.Result != nil {
		return
	}
	if b.Loading {
		r.cancelLoading(reason)
		return
	}
	rewards := map[string]int{}
	for _, m := range r.Members {
		if m.AI != 0 {
			continue
		}
		win := m.Seat/4 == team
		amount := 100
		if win {
			amount = 300
		}
		if e := w.store.reward(b.ID, m.ID, win); e != nil {
			continue
		}
		rewards[fmt.Sprint(m.ID)] = amount
	}
	b.Result = &Result{team, reason, rewards}
	b.Deadline = 0
	b.pending = nil
}
func (w *World) tick() {
	w.mu.Lock()
	type aiWork struct {
		room       int
		live       *Battle
		copy       *Battle
		generation uint64
	}
	plans := []aiWork{}
	changed := false
	now := time.Now()
	for _, r := range w.rooms {
		b := r.Battle
		if b != nil && b.Loading && float64(now.UnixMilli())/1000 >= b.LoadingDeadline {
			r.cancelLoading("战场加载超时，已取消本次开局。")
			b = nil
			changed = true
		}
		if b != nil && b.Result == nil && !b.Loading {
			if b.advanceShot(float64(now.UnixMilli()) / 1000) {
				changed = true
			}
			if b.pending != nil && now.After(b.busyUntil) {
				pending := b.pending
				b.Units = pending.Units
				b.Holes = pending.Holes
				b.Terrain = pending.Terrain
				b.pending = nil
				b.advance()
				changed = true
			}
			teams := b.aliveTeams()
			if len(teams) <= 1 && b.pending == nil {
				team := -1
				for t := range teams {
					team = t
				}
				w.finish(r, team, "最后存活的队伍获胜")
				changed = true
				continue
			}
			if b.Round > 100 {
				w.finish(r, -1, "达到回合上限，双方握手言和")
				changed = true
				continue
			}
			if b.pending == nil {
				u := b.active()
				if u == nil || u.HP <= 0 {
					b.advance()
					changed = true
				} else if b.Deadline > 0 && nowSeconds() > b.Deadline {
					b.advance()
					changed = true
				} else if u.AI > 0 && !now.Before(b.aiAt) && b.aiAction != nil {
					b.stepAIAction(now)
					changed = true
				} else if u.AI > 0 && now.After(b.aiAt) && !b.planning {
					b.planning = true
					plans = append(plans, aiWork{r.ID, b, b.copy(), b.Generation})
				}
			}
		}
		stale := []int64{}
		for _, m := range r.Members {
			if m.AI == 0 && now.Sub(m.Seen) > 75*time.Second {
				stale = append(stale, m.ID)
			}
		}
		for _, id := range stale {
			w.leave(id)
			changed = true
		}
	}
	for t, s := range w.sessions {
		if now.After(s.Expires) {
			delete(w.sessions, t)
		}
	}
	for id, player := range w.presence {
		if now.Sub(player.Seen) > 75*time.Second {
			delete(w.presence, id)
			changed = true
		}
	}
	for id, invitation := range w.invites {
		if invitation.Expires <= nowSeconds() || w.rooms[invitation.Room] == nil {
			delete(w.invites, id)
			changed = true
		}
	}
	if changed {
		w.version++
	}
	w.mu.Unlock()
	// Aim on an immutable snapshot without blocking authentication, polling,
	// other rooms or GM. Commit only if the same live turn still exists.
	for _, job := range plans {
		distance := job.copy.aiMove()
		a, p, k := job.copy.aiPlan()
		w.mu.Lock()
		r := w.rooms[job.room]
		b := job.live
		b.planning = false
		if r != nil && r.Battle == b && b.Result == nil && b.pending == nil && b.Generation == job.generation && b.active() != nil && b.active().HP > 0 {
			b.aiAction = &aiTurnAction{generation: b.Generation, remaining: int(distance), face: job.copy.active().Face, angle: a, power: p, weapon: k, pass: job.copy.planScore < 0}
			b.aiAt = time.Now()
			b.stepAIAction(b.aiAt)
			w.version++
		}
		w.mu.Unlock()
	}
}
