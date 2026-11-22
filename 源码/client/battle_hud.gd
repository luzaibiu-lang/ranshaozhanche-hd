extends Control
## Native HUD sprites and composition. Coordinates adapt to the actual window.
var battle: Dictionary = {}
var catalog: Dictionary = {}
var player_id := 0
var clock: RefCounted
var angle := 45.0
var charge := 0.0
var selected_weapon := 0
var textures := {}
var scale_factor := 1.0
var elapsed := 0.0
var turn_stamp := ""
var turn_notice := 0.0
var previous_charge := 0.0
var minimap_ground: Texture2D
var minimap_map := -1
var camera_rect := Rect2()
var sun_layer: Node2D
var blind := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	sun_layer = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sun_layer.material = material
	sun_layer.draw.connect(_draw_sun)
	add_child(sun_layer)

func _process(delta: float) -> void:
	elapsed += delta
	scale_factor = clampf(minf(size.x / 800, size.y / 600), 0.8, 3.0)
	var stamp := "%s:%s:%s" % [str(battle.get("id", "")), str(battle.get("generation", 0)), str(battle.get("active", -1))]
	if stamp != turn_stamp:
		turn_stamp = stamp
		turn_notice = 1.6
	turn_notice = maxf(0, turn_notice - delta)
	queue_redraw()
	sun_layer.queue_redraw()

func _draw_sun() -> void:
	var s := scale_factor
	# The reference shows the sun for both positive and negative wind. The
	# moon sprite is not a direction indicator.
	var image := tex("WindGage",3)
	if image:sun_layer.draw_texture_rect(image,Rect2(Vector2(size.x/2-100*s,3*s),image.get_size()*s),false)

func tex(name: String, frame := 0) -> Texture2D:
	var path := "res://assets/icons/%s/%02d.png" % [name,frame]
	if not textures.has(path):textures[path] = load(path) if ResourceLoader.exists(path) else null
	return textures[path]

func art(name: String, position: Vector2, frame := 0, tint := Color.WHITE) -> void:
	var image := tex(name,frame)
	if image:draw_texture_rect(image,Rect2(position,image.get_size()*scale_factor),false,tint)

func text(value: String, position: Vector2, font_size := 12, color := Color.WHITE) -> void:
	draw_string_outline(get_theme_default_font(),position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,int(font_size*scale_factor),int(2*scale_factor),Color(0,0,0,.9))
	draw_string(get_theme_default_font(),position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,int(font_size*scale_factor),color)

func rect_for(kind: String, index := 0) -> Rect2:
	var s := scale_factor
	match kind:
		"weapon": return Rect2(Vector2((9+index*36)*s,size.y-84*s),Vector2(34,22)*s)
		"fire": return Rect2(Vector2(size.x/2+180*s,size.y-30*s),Vector2(42,22)*s)
		"skip": return Rect2(Vector2(size.x-62*s,size.y-52*s),Vector2(57,22)*s)
		"menu": return Rect2(Vector2(size.x-62*s,size.y-27*s),Vector2(57,22)*s)
		"overview": return Rect2(Vector2(10,55)*s,Vector2(340,100)*s)
		"follow": return Rect2(Vector2(size.x-80*s,114*s),Vector2(72,25)*s)
	return Rect2()

func own_unit() -> Dictionary:
	for unit: Dictionary in battle.get("units",[]):
		if int(unit.player)==player_id:return unit
	return {}

func _digits(value: int, at: Vector2, group := "Number1", tint := Color.WHITE) -> void:
	var cursor := at
	for character in str(value):
		art(group, cursor, int(character), tint)
		cursor.x += (24 if group == "Number1" else 27) * scale_factor

func _draw() -> void:
	if battle.is_empty():return
	var s := scale_factor
	var own := own_unit()
	if own.is_empty():return
	var active := {}
	for unit: Dictionary in battle.get("units", []):
		if int(unit.seat) == int(battle.get("active", -1)):active = unit
	# Original life / fuel housing. SP fuels weapons and movement.
	art("EnergyGage", Vector2.ZERO)
	var hp := clampf(float(own.hp) / maxf(1, float(own.max_hp)), 0, 1)
	draw_texture_rect(tex("EnergyGage", 1), Rect2(Vector2(72,12)*s, Vector2(173*hp,9)*s), false)
	draw_texture_rect(tex("FuelGage", 1), Rect2(Vector2(72,29)*s, Vector2(173*clampf(float(own.sp)/200,0,1),9)*s), false)
	text("%d%%" % int(hp*100), Vector2(151,22)*s, 10)
	text(str(int(own.sp)), Vector2(151,39)*s, 10)
	# Wind sun/moon, native countdown digits and round label.
	var center := size.x/2
	var wind := int(battle.get("wind", 0))
	var deadline := float(battle.get("deadline", 0))
	var remaining := maxi(0,int(ceil(deadline-clock.server_now()))) if clock else 0
	_digits(remaining, Vector2(center-24*s,7*s), "Number1", Color("c4e9b2"))
	text("风力: %+.1f" % (floorf((float(wind)/9.5+.05)*10)/10), Vector2(center+54*s,21*s), 11)
	text("角度: %.0f" % angle, Vector2(center+54*s,40*s), 11)
	text("力度: %.2f" % (charge*300), Vector2(center+54*s,59*s), 11)
	art("InterfaceEtc", Vector2(center-39*s,103*s), 2)
	_digits(int(battle.get("round",1)),Vector2(center+57*s,105*s),"Number2")
	_draw_minimap()
	art("InterfaceEtc", Vector2(size.x-244*s,8*s), 3)
	text("玩家                 伤害", Vector2(size.x-239*s,73*s), 11)
	var line := 0
	for unit: Dictionary in battle.get("units", []):
		var color: Color = [Color("ff756d"),Color("ffe274"),Color("93f65a"),Color("72a9ff")][int(unit.team)]
		text(str(unit.name).left(14), Vector2(size.x-239*s,(92+line*15)*s),10,color)
		if unit.has("damage"):text(str(int(unit.damage)), Vector2(size.x-120*s,(92+line*15)*s),10,color)
		line += 1
	if int(own.hp)<=0:
		text("观战中", Vector2(size.x-84*s,42*s),18,Color("ff6d63"))
	else:
		text("%s 行动" % str(active.get("name", "")), Vector2(12,174)*s, 11, Color("c6f7aa"))
	if turn_notice>0 and deadline>0:
		var message := "轮到你了" if int(active.get("player",0))==player_id else "%s 的回合" % str(active.get("name",""))
		text(message,Vector2(center-80*s,178*s),19,Color(1,1,0.6,minf(1,turn_notice*2)))
	# Native weapon card / costs and angle compass beneath the power meter.
	var bottom := Vector2(4*s,size.y-87*s)
	art("WeaponTab",bottom,selected_weapon)
	for i in range(3):art("F%dBtn"%(i+1),bottom+Vector2(8+i*36,4)*s,4 if i==selected_weapon else 0)
	var vehicle: Dictionary = catalog.vehicles[int(own.vehicle)-1] if not catalog.get("vehicles",[]).is_empty() else {}
	if not vehicle.is_empty():
		var weapon: Dictionary = vehicle.weapons[selected_weapon]
		text(str(0 if int(own.get("shot_mode",0)) != 0 else int(weapon.cost)),bottom+Vector2(43,65)*s,12)
		art("vehicles/"+str(int(own.vehicle)),bottom+Vector2(76,25)*s,selected_weapon)
	art("InterfaceEtc", Vector2(11*s,size.y-109*s), 1)
	text(str(int(own.move)),Vector2(83*s,size.y-92*s),12)
	var power_at := Vector2(center-151*s,size.y-34*s)
	# 004d0200: full native base, red fill frame 3, scale marks frame 2,
	# outer housing frame 1. Frame 0 is never the charged fill.
	var fill_at:=power_at+Vector2(13,6)*s
	draw_texture_rect(tex("PowerGage",0),Rect2(fill_at,Vector2(300,15)*s),false)
	if charge>0:draw_texture_rect(tex("PowerGage",3),Rect2(fill_at,Vector2(300*clampf(charge,0,1),15)*s),false)
	draw_texture_rect(tex("PowerGage",2),Rect2(fill_at,Vector2(300,15)*s),false)
	art("PowerGage",power_at,1)
	for marker in range(49,int(charge*300),50):art("PowerGage",fill_at+Vector2(marker,0)*s,5)
	if previous_charge>0:draw_line(power_at+Vector2(13+300*previous_charge,6)*s,power_at+Vector2(13+300*previous_charge,21)*s,Color("ffd864"),2*s)
	_draw_wind(power_at+Vector2(13,-17)*s,wind)
	if int(own.get("blind",0))>0 and int(own.hp)>0:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.82))
		text("受到致盲 · 剩余 %d 轮" % int(own.blind),size/2,22)

func wind_rect() -> Rect2:
	var s:=scale_factor
	return Rect2(Vector2(size.x/2-138*s,size.y-51*s),Vector2(101,10)*s)

func _draw_wind(at:Vector2,wind:int) -> void:
	# Native 004d1320: 101x10 bar, fixed center divider, blue fill
	# extends left/right from the center by the absolute raw wind value.
	var s:=scale_factor
	var area:=Rect2(at,Vector2(101,10)*s)
	draw_texture_rect(tex("WindGage",2),area,false,Color(1,1,1,.5))
	var width:=minf(50,absf(float(wind)))
	if width>0:
		var x:=50-width if wind<0 else 51.0
		draw_texture_rect(tex("WindGage",1),Rect2(at+Vector2(x,0)*s,Vector2(width,10)*s),false,Color(1,1,1,.8))
	draw_rect(area.grow(s),Color(1,1,1,.8),false,s)
	draw_line(at+Vector2(50,-1)*s,at+Vector2(50,11)*s,Color(1,1,1,.8),s)
	art("WindGage",at+Vector2(99,-2)*s,0)

func _draw_minimap() -> void:
	var map := int(battle.get("map", 0))
	if minimap_map != map:
		minimap_map = map
		if not minimap_ground:minimap_ground = load("res://assets/maps/%d/terrain.png" % map)
	var area := rect_for("overview")
	draw_rect(area,Color(0,0,0,0.27))
	draw_rect(area,Color("d2d0c8"),false,scale_factor)
	var ratio := minf(area.size.x/float(battle.width),area.size.y/float(battle.height))
	var dimensions := Vector2(float(battle.width),float(battle.height))*ratio
	var origin := area.position+(area.size-dimensions)/2
	if minimap_ground:draw_texture_rect(minimap_ground,Rect2(origin,dimensions),false,Color(1,1,1,0.85))
	for unit: Dictionary in battle.get("units",[]):
		if int(unit.hp)<=0:continue
		if int(unit.get("stealth",0))>0 and int(unit.team)!=int(own_unit().get("team",-1)):continue
		var color: Color = [Color("ff6962"),Color("ffe274"),Color("93f65a"),Color("72a9ff")][int(unit.team)]
		draw_circle(origin+Vector2(float(unit.x),float(unit.y))*ratio,2.5*scale_factor,color)
	if camera_rect.has_area():draw_rect(Rect2(origin+camera_rect.position*ratio,camera_rect.size*ratio),Color(1,1,1,0.55),false,scale_factor)
