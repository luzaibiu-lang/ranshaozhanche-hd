package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	_ "modernc.org/sqlite"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

type Profile struct {
	ID            int64  `json:"id"`
	Name          string `json:"name"`
	Gold          int    `json:"gold"`
	Wins          int    `json:"wins"`
	Games         int    `json:"games"`
	XP            int    `json:"xp"`
	Inventory     [4]int `json:"inventory"`
	Outfit        int    `json:"outfit"`
	Outfits       []int  `json:"outfits"`
	RejectPrivate bool   `json:"reject_private"`
	RejectInvites bool   `json:"reject_invites"`
}
type Store struct{ db *sql.DB }

func openStore(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	db, e := sql.Open("sqlite", path)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	_, e = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
 CREATE TABLE IF NOT EXISTS players(id INTEGER PRIMARY KEY,name TEXT NOT NULL COLLATE NOCASE UNIQUE,salt TEXT NOT NULL,password TEXT NOT NULL,gold INTEGER NOT NULL DEFAULT 20000,wins INTEGER NOT NULL DEFAULT 0,games INTEGER NOT NULL DEFAULT 0,xp INTEGER NOT NULL DEFAULT 0,inventory TEXT NOT NULL DEFAULT '[0,0,0,0]',outfit INTEGER NOT NULL DEFAULT 0,outfits TEXT NOT NULL DEFAULT '[0]');
 CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,player INTEGER NOT NULL,expires INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS sessions_player ON sessions(player);
 CREATE TABLE IF NOT EXISTS rewards(match TEXT NOT NULL,player INTEGER NOT NULL,PRIMARY KEY(match,player));
 CREATE TABLE IF NOT EXISTS preferences(player INTEGER PRIMARY KEY,reject_private INTEGER NOT NULL DEFAULT 0,reject_invites INTEGER NOT NULL DEFAULT 0);
 CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY,created TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,action TEXT NOT NULL,player INTEGER,amount INTEGER);`)
	if e != nil {
		db.Close()
		return nil, e
	}
	// Existing installations may contain several active logins per player.
	// Keep the newest valid credential and preserve revoked hashes for a
	// specific replacement message; bearer tokens are never persisted.
	var hasRevoked int
	if e = db.QueryRow("SELECT count(*) FROM pragma_table_info('sessions') WHERE name='revoked'").Scan(&hasRevoked); e == nil && hasRevoked == 0 {
		_, e = db.Exec("ALTER TABLE sessions ADD COLUMN revoked INTEGER NOT NULL DEFAULT 0")
	}
	if e == nil {
		_, e = db.Exec(`UPDATE sessions SET revoked=1 WHERE revoked=0 AND rowid IN (
 SELECT rowid FROM (SELECT rowid,ROW_NUMBER() OVER(PARTITION BY player ORDER BY expires DESC,rowid DESC) AS position FROM sessions WHERE revoked=0) WHERE position>1);
 CREATE UNIQUE INDEX IF NOT EXISTS sessions_one_active ON sessions(player) WHERE revoked=0;`)
	}
	if e != nil {
		db.Close()
		return nil, e
	}
	return &Store{db}, nil
}
func token() string {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return hex.EncodeToString(b)
}

func sessionHash(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}
func (s *Store) createSession(raw string, player int64, expires time.Time) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if _, e = tx.Exec("UPDATE sessions SET revoked=1 WHERE player=? AND revoked=0", player); e != nil {
		return e
	}
	if _, e = tx.Exec("INSERT INTO sessions(hash,player,expires,revoked) VALUES(?,?,?,0)", sessionHash(raw), player, expires.Unix()); e != nil {
		return e
	}
	return tx.Commit()
}
func (s *Store) sessionReplaced(raw string) bool {
	if len(raw) != 64 {
		return false
	}
	var count int
	return s.db.QueryRow("SELECT count(*) FROM sessions WHERE hash=? AND revoked=1 AND expires>?", sessionHash(raw), time.Now().Unix()).Scan(&count) == nil && count > 0
}
func (s *Store) session(raw string) (Session, bool) {
	var result Session
	var expires int64
	e := s.db.QueryRow("SELECT player,expires FROM sessions WHERE hash=? AND revoked=0 AND expires>?", sessionHash(raw), time.Now().Unix()).Scan(&result.Player, &expires)
	result.Expires = time.Unix(expires, 0)
	return result, e == nil
}
func (s *Store) revokeSession(raw string) error {
	_, e := s.db.Exec("DELETE FROM sessions WHERE hash=?", sessionHash(raw))
	return e
}
func derive(password, salt string) string {
	// PBKDF2-HMAC-SHA256, one 32-byte block. Passwords never leave this module.
	m := hmac.New(sha256.New, []byte(password))
	m.Write([]byte(salt))
	m.Write([]byte{0, 0, 0, 1})
	u := m.Sum(nil)
	out := append([]byte(nil), u...)
	for i := 1; i < 180000; i++ {
		m.Reset()
		m.Write(u)
		u = m.Sum(u[:0])
		for j := range out {
			out[j] ^= u[j]
		}
	}
	return hex.EncodeToString(out)
}
func validName(name string) bool {
	if utf8.RuneCountInString(name) < 2 || utf8.RuneCountInString(name) > 16 {
		return false
	}
	for _, r := range name {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r >= 0x4e00 && r <= 0x9fff) {
			return false
		}
	}
	return true
}
func (s *Store) register(name, password string) (*Profile, error) {
	name = strings.TrimSpace(name)
	if !validName(name) {
		return nil, errors.New("账号需为 2～16 位中文、字母、数字或下划线")
	}
	if len(password) < 6 || len(password) > 72 {
		return nil, errors.New("密码需为 6～72 个字节")
	}
	salt := token()
	r, e := s.db.Exec("INSERT INTO players(name,salt,password) VALUES(?,?,?)", name, salt, derive(password, salt))
	if e != nil {
		return nil, errors.New("账号已存在或暂时无法注册")
	}
	id, e := r.LastInsertId()
	if e != nil {
		return nil, e
	}
	return s.profile(id)
}
func (s *Store) login(name, password string) (*Profile, error) {
	var id int64
	var salt, want string
	e := s.db.QueryRow("SELECT id,salt,password FROM players WHERE name=?", strings.TrimSpace(name)).Scan(&id, &salt, &want)
	if e != nil {
		return nil, errors.New("账号或密码错误")
	}
	if !hmac.Equal([]byte(want), []byte(derive(password, salt))) {
		return nil, errors.New("账号或密码错误")
	}
	return s.profile(id)
}
func (s *Store) profile(id int64) (*Profile, error) {
	p := &Profile{}
	var inventory, outfits string
	e := s.db.QueryRow("SELECT id,name,gold,wins,games,xp,inventory,outfit,outfits FROM players WHERE id=?", id).Scan(&p.ID, &p.Name, &p.Gold, &p.Wins, &p.Games, &p.XP, &inventory, &p.Outfit, &outfits)
	if e != nil {
		return nil, e
	}
	if e = json.Unmarshal([]byte(inventory), &p.Inventory); e != nil {
		return nil, e
	}
	if e = json.Unmarshal([]byte(outfits), &p.Outfits); e != nil {
		return nil, e
	}
	e = s.db.QueryRow("SELECT reject_private,reject_invites FROM preferences WHERE player=?", id).Scan(&p.RejectPrivate, &p.RejectInvites)
	if e != nil && e != sql.ErrNoRows {
		return nil, e
	}
	return p, nil
}
func (s *Store) buy(id int64, itemID, slot int, sell bool) (*Profile, error) {
	if slot < 0 || slot > 3 {
		return nil, errors.New("携带位置不存在")
	}
	p, e := s.profile(id)
	if e != nil {
		return nil, e
	}
	amount := 0
	if sell {
		if p.Inventory[slot] == 0 {
			return nil, errors.New("此位置没有道具")
		}
		v, _ := item(p.Inventory[slot])
		amount = v.Price / 2
		p.Inventory[slot] = 0
	} else {
		v, e := item(itemID)
		if e != nil {
			return nil, e
		}
		if p.Inventory[slot] != 0 {
			return nil, errors.New("请先出售此位置的道具")
		}
		amount = -v.Price
		if p.Gold+amount < 0 {
			return nil, errors.New("金币不足")
		}
		p.Inventory[slot] = itemID
	}
	inv, _ := json.Marshal(p.Inventory)
	r, e := s.db.Exec("UPDATE players SET gold=gold+?,inventory=? WHERE id=? AND gold+?>=0", amount, string(inv), id, amount)
	if e != nil {
		return nil, e
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return nil, errors.New("交易未完成")
	}
	return s.profile(id)
}
func (s *Store) consume(id int64, slot int) (int, error) {
	p, e := s.profile(id)
	if e != nil {
		return 0, e
	}
	if slot < 0 || slot > 3 || p.Inventory[slot] == 0 {
		return 0, errors.New("此位置没有道具")
	}
	v := p.Inventory[slot]
	p.Inventory[slot] = 0
	b, _ := json.Marshal(p.Inventory)
	_, e = s.db.Exec("UPDATE players SET inventory=? WHERE id=?", string(b), id)
	return v, e
}
func (s *Store) outfit(id int64, value int) (*Profile, error) {
	if value < 0 || value > 4 {
		return nil, errors.New("装扮不存在")
	}
	p, e := s.profile(id)
	if e != nil {
		return nil, e
	}
	owned := false
	for _, x := range p.Outfits {
		owned = owned || x == value
	}
	price := 0
	if !owned {
		price = 1200 + value*200
		if p.Gold < price {
			return nil, errors.New("金币不足")
		}
		p.Outfits = append(p.Outfits, value)
	}
	b, _ := json.Marshal(p.Outfits)
	_, e = s.db.Exec("UPDATE players SET gold=gold-?,outfit=?,outfits=? WHERE id=? AND gold>=?", price, value, string(b), id, price)
	if e != nil {
		return nil, e
	}
	return s.profile(id)
}
func (s *Store) reward(match string, id int64, win bool) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	r, e := tx.Exec("INSERT OR IGNORE INTO rewards(match,player) VALUES(?,?)", match, id)
	if e != nil {
		return e
	}
	n, _ := r.RowsAffected()
	if n == 0 {
		return nil
	}
	gold, wins := 100, 0
	if win {
		gold, wins = 300, 1
	}
	_, e = tx.Exec("UPDATE players SET gold=gold+?,games=games+1,wins=wins+?,xp=xp+? WHERE id=?", gold, wins, gold/5, id)
	if e != nil {
		return e
	}
	return tx.Commit()
}
func (s *Store) addGold(id int64, amount int) error {
	if amount < 0 || amount > 10000000 {
		return fmt.Errorf("金额超出范围")
	}
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	r, e := tx.Exec("UPDATE players SET gold=gold+? WHERE id=?", amount, id)
	if e != nil {
		return e
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return errors.New("玩家不存在")
	}
	_, e = tx.Exec("INSERT INTO audit(action,player,amount) VALUES('add_gold',?,?)", id, amount)
	if e != nil {
		return e
	}
	return tx.Commit()
}
