package main

import (
	"errors"
	"strings"
	"time"
)

func (w *World) whisper(sender int64, text string) error {
	parts := strings.SplitN(strings.TrimSpace(text[3:]), " ", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[1]) == "" {
		return errors.New("私聊格式：/w 玩家名 消息")
	}
	var target int64
	if e := w.store.db.QueryRow("SELECT id FROM players WHERE name=?", parts[0]).Scan(&target); e != nil {
		return errors.New("玩家不存在")
	}
	online := w.presence[target]
	if online == nil || time.Since(online.Seen) > 75*time.Second {
		return errors.New("玩家已离线")
	}
	p, e := w.store.profile(target)
	if e != nil {
		return e
	}
	if p.RejectPrivate && sender != target {
		return errors.New("该玩家已拒绝私聊")
	}
	if w.whispers == nil {
		w.whispers = map[int64][]Chat{}
	}
	message := Chat{"私聊 " + w.mustProfile(sender).Name + " → " + p.Name, strings.TrimSpace(parts[1]), nowSeconds()}
	recipients := []int64{sender}
	if target != sender {
		recipients = append(recipients, target)
	}
	for _, id := range recipients {
		w.whispers[id] = append(w.whispers[id], message)
		if len(w.whispers[id]) > 60 {
			w.whispers[id] = w.whispers[id][len(w.whispers[id])-60:]
		}
	}
	return nil
}
