package main

import (
	"encoding/binary"
	"fmt"
	"math"
	"math/rand/v2"
	"os"
	"path/filepath"
	"sort"
)

type Terrain struct {
	W, H  int
	Solid []byte
}
type Hole struct {
	X    float64 `json:"x"`
	Y    float64 `json:"y"`
	R    float64 `json:"r"`
	Mask int     `json:"mask,omitempty"`
}

func loadTerrain(root string, id int) (*Terrain, error) {
	b, e := os.ReadFile(filepath.Join(root, "maps", fmt.Sprint(id), "collision.bin"))
	if e != nil {
		return nil, e
	}
	if len(b) < 8 {
		return nil, fmt.Errorf("地图碰撞文件不完整")
	}
	w, h := int(binary.LittleEndian.Uint32(b)), int(binary.LittleEndian.Uint32(b[4:]))
	if w < 100 || w > 8192 || h < 100 || h > 8192 || len(b) != 8+w*h {
		return nil, fmt.Errorf("地图碰撞尺寸错误")
	}
	return &Terrain{w, h, b[8:]}, nil
}
func (t *Terrain) clone() *Terrain { return &Terrain{t.W, t.H, append([]byte(nil), t.Solid...)} }

// Original 004dd4b0 scans from the top and accepts any occupied pixel
// across the supplied width. Ground-burst weapons use this specific query.
func (t *Terrain) nativeGround(x float64, width int) float64 {
	left := int(x) - width/2
	for y := 0; y < t.H; y++ {
		for px := left; px < left+width; px++ {
			if px >= 0 && px < t.W && t.Solid[y*t.W+px] != 0 {
				return float64(y)
			}
		}
	}
	return float64(t.H + 100)
}
func (t *Terrain) solid(x, y float64) bool {
	ix, iy := int(math.Floor(x)), int(math.Floor(y))
	return ix >= 0 && ix < t.W && iy >= 0 && iy < t.H && t.Solid[iy*t.W+ix] != 0
}
func (t *Terrain) ground(x float64, from int) float64 {
	ix := int(x)
	if ix < 8 || ix >= t.W-8 {
		return float64(t.H + 200)
	}
	for y := max(0, from); y < t.H; y++ {
		support := 0
		for dx := -5; dx <= 5; dx++ {
			if t.Solid[y*t.W+ix+dx] != 0 {
				support++
			}
		}
		if support >= 5 && t.solid(x, float64(y)) && t.solid(x, float64(y+2)) {
			return float64(y)
		}
	}
	return float64(t.H + 200)
}
func (t *Terrain) carve(h Hole) {
	if h.Mask > 0 && h.Mask <= len(nativeCraters) {
		mask := nativeCraters[h.Mask-1]
		left, top := int(h.X)-mask.W/2, int(h.Y)-mask.H/2
		for y, span := range mask.Rows {
			py := top + y
			if py < 0 || py >= t.H || span[0] < 0 {
				continue
			}
			for x := max(0, left+span[0]); x <= min(t.W-1, left+span[1]); x++ {
				t.Solid[py*t.W+x] = 0
			}
		}
		return
	}
	for y := max(0, int(h.Y-h.R)); y <= min(t.H-1, int(h.Y+h.R)); y++ {
		span := math.Sqrt(max(0, h.R*h.R-math.Pow(float64(y)-h.Y, 2)))
		for x := max(0, int(h.X-span)); x <= min(t.W-1, int(h.X+span)); x++ {
			t.Solid[y*t.W+x] = 0
		}
	}
}
func (t *Terrain) spawns(n int) ([][2]float64, error) {
	// Cave maps contain an opaque roof. A ray from y=0 selects that roof,
	// not the playable floor. Use the original terrain's supported ledges
	// after a full tank of headroom, retaining the lowest suitable ledge.
	surface := make([]int, t.W)
	for x := 0; x < t.W; x++ {
		surface[x] = t.H
		clear := 0
		for y := 0; y < t.H-48; y++ {
			if t.Solid[y*t.W+x] == 0 {
				clear++
				continue
			}
			if clear >= 72 {
				supported := true
				for dy := 0; dy < 12; dy++ {
					if t.Solid[(y+dy)*t.W+x] == 0 {
						supported = false
						break
					}
				}
				if supported {
					surface[x] = y
				}
			}
			clear = 0
		}
	}
	candidates := [][2]float64{}
	for x := 64; x < t.W-64; x += 8 {
		low, high := t.H, 0
		for dx := -24; dx <= 24; dx++ {
			low = min(low, surface[x+dx])
			high = max(high, surface[x+dx])
		}
		if low >= 72 && high < t.H-48 && high-low <= 36 {
			candidates = append(candidates, [2]float64{float64(x), float64(surface[x])})
		}
	}
	// The original map set includes narrow platforms. Preserve safety while
	// reducing spacing only when necessary, as in the stable legacy service.
	count := len(candidates)
	for _, spacing := range []float64{130, 120, 96, 80, 64, 48, 40} {
		next := make([]int, count)
		capacity := make([]int, count+1)
		for i, point := range candidates {
			next[i] = sort.Search(count, func(j int) bool { return candidates[j][0] >= point[0]+spacing })
		}
		for i := count - 1; i >= 0; i-- {
			capacity[i] = max(capacity[i+1], 1+capacity[next[i]])
		}
		if capacity[0] < n {
			continue
		}
		chosen := make([][2]float64, 0, n)
		start := 0
		for remaining := n; remaining > 0; remaining-- {
			choices := []int{}
			for i := start; i < count; i++ {
				if capacity[next[i]] >= remaining-1 {
					choices = append(choices, i)
				}
			}
			index := choices[rand.IntN(len(choices))]
			chosen = append(chosen, candidates[index])
			start = next[index]
		}
		rand.Shuffle(len(chosen), func(i, j int) { chosen[i], chosen[j] = chosen[j], chosen[i] })
		return chosen, nil
	}
	return nil, fmt.Errorf("地图没有足够的安全出生位置")
}
