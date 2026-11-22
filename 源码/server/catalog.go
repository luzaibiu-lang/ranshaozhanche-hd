package main

import "fmt"

type Weapon struct {
	Name       string  `json:"name"`
	Kind       string  `json:"kind"`
	Cost       int     `json:"cost"`
	Damage     int     `json:"damage"`
	Radius     float64 `json:"radius"`
	Count      int     `json:"count"`
	Wind       float64 `json:"wind"`
	NativeID   int     `json:"native_id"`
	Projectile int     `json:"projectile"`
	Delay      float64 `json:"delay"`
}
type Vehicle struct {
	ID       int       `json:"id"`
	Name     string    `json:"name"`
	Role     string    `json:"role"`
	HP       int       `json:"hp"`
	Armor    float64   `json:"armor"`
	Move     float64   `json:"move"`
	MoveCost float64   `json:"move_cost"`
	AimMin   float64   `json:"aim_min"`
	AimMax   float64   `json:"aim_max"`
	Weapons  [3]Weapon `json:"weapons"`
}
type Item struct {
	ID          int    `json:"id"`
	Name        string `json:"name"`
	Price       int    `json:"price"`
	Description string `json:"description"`
}
type MapInfo struct {
	ID     int    `json:"id"`
	Name   string `json:"name"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

var vehicleNames = []string{"烈火", "赤焰", "蜘蛛", "奥丁", "贝贝", "兰登", "旋风", "托儿", "红龙", "金刚", "黑犀牛", "毒蛇", "金蜘蛛", "魔术大师", "骑士", "战神", "幽灵", "铁壳", "绿龙", "紫金刚", "灰烈火", "蓝赤焰", "银蜘蛛", "复制专家", "黑骑士", "白兰登", "幻影", "蓝托儿", "蓝龙", "绿金刚"}
var mapNames = originalMapNames
var vehicles = func() []Vehicle {
	out := make([]Vehicle, 30)
	for i, name := range vehicleNames {
		out[i] = Vehicle{ID: i + 1, Name: name, Role: "原版战车", HP: 300, Armor: originalArmor[i], Move: 150 / originalMoveCosts[i], MoveCost: originalMoveCosts[i], Weapons: nativeLoadout(i)}
		out[i].AimMin, out[i].AimMax = originalAimRanges[i][0], originalAimRanges[i][1]
	}
	return out
}()
var items = func() []Item {
	prices := []int{1800, 1600, 1600, 1600, 800, 1600, 2000, 1400, 800, 1600, 1800, 1000, 800, 2200, 800, 800, 1800}
	out := make([]Item, len(prices))
	for i, price := range prices {
		out[i] = Item{i + 1, originalItemNames[i], price, originalItemDescriptions[i]}
	}
	return out
}()

func vehicle(id int) Vehicle {
	if id < 1 || id > len(vehicles) {
		id = 1
	}
	return vehicles[id-1]
}
func item(id int) (Item, error) {
	if id < 1 || id > len(items) {
		return Item{}, fmt.Errorf("道具不存在")
	}
	return items[id-1], nil
}
