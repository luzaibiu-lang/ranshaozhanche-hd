package main

// VisualFrame is a sparse presentation checkpoint, not a commandable game
// state. The shot already sends complete trajectories and impacts. Sending
// their corresponding craters and health changes lets a renderer play an
// explosion, its damage and its ensuing fall on exactly the same clock even
// between HTTP polls. Private simulation checkpoints remain server-only.
type VisualFrame struct {
	At      float64      `json:"at"`
	Units   []VisualUnit `json:"units"`
	Holes   int          `json:"holes"` // count within Shot.Cuts
	Numbers []HitNumber  `json:"numbers,omitempty"`
	Falls   []FallCue    `json:"falls,omitempty"`
}

type VisualUnit struct {
	Seat    int     `json:"seat"`
	HP      int     `json:"hp"`
	SP      int     `json:"sp"`
	Move    float64 `json:"move"`
	Shield  int     `json:"shield"`
	Stun    int     `json:"stun"`
	Blind   int     `json:"blind"`
	Stealth int     `json:"stealth"`
	Poison  int     `json:"poison"`
	Burn    int     `json:"burn"`
	Damage  int     `json:"damage"`
}

type HitNumber struct {
	Seat  int     `json:"seat"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	Delta int     `json:"delta"`
}

type FallCue struct {
	Seat    int `json:"seat"`
	Vehicle int `json:"vehicle"`
}

func visualUnit(u *Unit) VisualUnit {
	return VisualUnit{u.Seat, u.HP, u.SP, u.Move, u.Shield, u.Stun, u.Blind, u.Stealth, u.Poison, u.Burn, u.Damage}
}

func (b *Battle) prepareShotVisuals(shot *Shot, base int) {
	shot.HoleBase = base
	shot.Cuts = append([]Hole(nil), b.Holes[base:]...)
	shot.Visuals = nil
	cues := shot.Cues[:0]
	for _, cue := range shot.Cues {
		if cue.Kind != "death" {
			cues = append(cues, cue)
		}
	}
	shot.Cues = cues
	previous := map[int]VisualUnit{}
	lastHoles := -1
	for _, state := range shot.States {
		frame := VisualFrame{At: state.At, Holes: max(0, state.Holes-base)}
		changed := frame.Holes != lastHoles
		for _, u := range state.Units {
			v := visualUnit(u)
			old, known := previous[u.Seat]
			if !known || old != v {
				changed = true
			}
			if known && old.HP != v.HP {
				if old.HP > 0 && v.HP == 0 && !u.Departed && u.X >= 0 && u.X < float64(b.Width) && u.Y <= float64(b.Height) {
					shot.Cues = append(shot.Cues, ShotCue{At: state.At, Kind: "death", Seat: u.Seat, X: u.X, Y: u.Y})
					// CTank's thirteen pulses and final expanding flash share this
					// clock. Do not switch turns/results before they have played.
					shot.Duration = max(shot.Duration, state.At+4)
				}
				if old.HP > 0 && v.HP == 0 && (u.Y > float64(b.Height) || u.X < 0 || u.X >= float64(b.Width)) {
					frame.Falls = append(frame.Falls, FallCue{u.Seat, u.Vehicle})
				} else {
					frame.Numbers = append(frame.Numbers, HitNumber{u.Seat, u.X, u.Y, v.HP - old.HP})
				}
			}
			frame.Units = append(frame.Units, v)
			previous[u.Seat] = v
		}
		if changed {
			shot.Visuals = append(shot.Visuals, frame)
			lastHoles = frame.Holes
		}
	}
}
