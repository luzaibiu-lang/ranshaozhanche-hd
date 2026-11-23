extends Control

signal effect(kind: String, detail: int)
signal mouse_aim(elevation:float,face:int)

const NativeVehicle = preload("res://native_vehicle.gd")
var vehicles := {}
var overlay: Node2D
var reticle:Node2D
var scenery: Node2D
var battle: Dictionary = {}
var catalog:Dictionary={}
var player_id := 0
var clock: RefCounted
var background: Texture2D
var terrain_texture: ImageTexture
var terrain_image: Image
var terrain:RefCounted
var applied_holes := 0
var terrain_masks: Array = []
var map_id := 0
var texture_cache := {}
var tank_frames := {}
var render_positions := {}
var render_slopes := {}
var walking := {}
var projectile_frames := {}
var projectile_rules: Dictionary = {}
var movement_active:=false
var camera := Vector2.ZERO
var target_camera := Vector2.ZERO
var zoom := 1.0
var zoom_target := 1.0
var overview := 0.0
var manual_until := 0.0
var dragging := false
var zoom_locked := false
var angle := 45.0
var power := 0.65
var glow: Texture2D
var particles: Array[Dictionary] = []
var explosions: Array[Dictionary] = []
var shot_id := -1
var fired_impacts := {}
var fired_sounds := {}
var shake := 0.0
var shake_enabled := true
var quality := 1
var elapsed := 0.0
var my_team := -1
var screen_origin := Vector2.ZERO
var battle_id := ""
var source_battle:Dictionary={}
var visual_frame := -1
var visual_numbers:Array[Dictionary]=[]
var fired_numbers:Dictionary={}
var supply_numbers: Array[Dictionary] = []
var last_supply_id := 0
var source_units:Dictionary={}
var local_walk:RefCounted
var aiming_with_mouse:=false
var preview_face:=0
var action_layer:Node2D
var beam_layer:Node2D
var death_layer:Node2D
var failure_layer:Node2D
var recovery_layer: Node2D

func _ready() -> void:
	terrain_masks=JSON.parse_string(FileAccess.get_file_as_string("res://assets/terrain-masks.json")).masks
	terrain=preload("res://native_terrain.gd").new(terrain_masks)
	projectile_rules = JSON.parse_string(FileAccess.get_file_as_string("res://assets/projectiles/native-visuals.json")).projectiles
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_resize_camera)
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in range(96):
		for x in range(96):
			var a := exp(-Vector2(x - 48, y - 48).length_squared() / 350.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	glow = ImageTexture.create_from_image(image)
	for index in range(12):texture("res://assets/icons/Number1/%02d.png"%index)
	scenery = preload("res://native_scenery.gd").new()
	scenery.world = self
	add_child(scenery)
	overlay = Node2D.new()
	overlay.z_index = 1
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	reticle=Node2D.new()
	reticle.z_index=0
	var reticle_blend:=CanvasItemMaterial.new()
	reticle_blend.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	reticle.material=reticle_blend
	reticle.draw.connect(_draw_reticle)
	add_child(reticle)
	for additive in [true,false]:
		var projectiles := preload("res://native_projectile_layer.gd").new()
		projectiles.world = self
		projectiles.additive = additive
		projectiles.z_index = 2 if additive else 3
		add_child(projectiles)
	var flames:=preload("res://native_flame_layer.gd").new()
	flames.world=self
	flames.z_index=2
	add_child(flames)
	beam_layer=preload("res://native_beam_layer.gd").new()
	beam_layer.world=self
	beam_layer.z_index=2
	add_child(beam_layer)
	death_layer=preload("res://native_death_layer.gd").new()
	death_layer.world=self
	death_layer.z_index=4
	add_child(death_layer)
	action_layer=preload("res://native_action_layer.gd").new()
	action_layer.world=self
	action_layer.z_index=4
	add_child(action_layer)
	failure_layer = preload("res://native_failure_layer.gd").new()
	failure_layer.world = self
	failure_layer.z_index = 4
	add_child(failure_layer)
	recovery_layer = preload("res://native_recovery_layer.gd").new()
	recovery_layer.world = self
	recovery_layer.z_index = 4
	add_child(recovery_layer)
	call_deferred("_resize_camera")

func _resize_camera() -> void:
	if battle.is_empty() or size.x <= 0 or size.y <= 0:
		return
	zoom_target = maxf(0.6, size.y / 560.0)
	if overview > 0 or zoom <= 0.01:
		zoom = minf(size.x / float(battle.width), size.y / float(battle.height))

func texture(path: String) -> Texture2D:
	if not texture_cache.has(path):
		texture_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return texture_cache[path]

func set_battle(value: Dictionary) -> void:
	source_battle=value
	battle=value.duplicate()
	battle.units=value.get("units",[]).duplicate(true)
	source_units.clear()
	for unit:Dictionary in value.get("units",[]):source_units[int(unit.seat)]=unit
	visual_frame=-1
	if str(value.get("id",""))!=battle_id or int(value.get("map", 0)) != map_id:
		failure_layer.clear_smoke()
		recovery_layer.clear_effects()
		battle_id=str(value.get("id",""))
		map_id = int(value.map)
		render_positions.clear()
		render_slopes.clear()
		walking.clear()
		explosions.clear()
		particles.clear()
		visual_numbers.clear()
		fired_numbers.clear()
		supply_numbers.clear()
		last_supply_id = 0
		fired_impacts.clear()
		fired_sounds.clear()
		shot_id=-1
		my_team=-1
		manual_until=0
		dragging=false
		var backdrop_path := "res://assets/maps/%d/background.png" % map_id
		if not ResourceLoader.exists(backdrop_path):backdrop_path = "res://assets/maps/%d/background.jpg" % map_id
		background = texture(backdrop_path)
		scenery.reset(map_id, str(value.get("id", "")))
		var ground: Texture2D = texture("res://assets/maps/%d/terrain.png" % map_id)
		if ground:
			terrain.reset(ground.get_image())
			terrain_image=terrain.image
			terrain_texture=terrain.overview
		applied_holes = 0
		overview = 2.0
		camera = Vector2(float(value.width) / 2, float(value.height) / 2)
		target_camera = camera
		zoom = minf(size.x / float(value.width), size.y / float(value.height))
		zoom_target = maxf(0.6, size.y / 560.0)
		call_deferred("_resize_camera")
	for unit in value.get("units", []):
		if int(unit.player) == player_id:
			my_team = int(unit.team)
		var key := str(int(unit.seat))
		if not render_positions.has(key):
			render_positions[key] = Vector2(float(unit.x), float(unit.y))
		var id := int(unit.vehicle)
		NativeVehicle.prewarm(id)
		if not tank_frames.has(id):
			tank_frames[id] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tanks/%d/frames.json" % id))
	if value.get("shot") is Dictionary and int(value.shot.id) != shot_id:
		shot_id = int(value.shot.id)
		fired_impacts.clear()
		fired_sounds.clear()
		fired_numbers.clear()
		for trail: Dictionary in value.shot.get("trails",[]):
			var projectile := int(trail.get("projectile",0))
			var asset := str(projectile_rules.get(str(projectile),{}).get("sprite",str(projectile)))
			var metadata := "res://assets/projectiles/%s/frames.json" % asset
			if not projectile_frames.has(projectile) and FileAccess.file_exists(metadata):
				projectile_frames[projectile]=JSON.parse_string(FileAccess.get_file_as_string(metadata))

func _process(delta: float) -> void:
	elapsed += delta
	if battle.is_empty() or size.x < 1:
		_stop_movement()
		return
	_sync_visual_timeline()
	_sync_supply_numbers()
	var holes:Array=battle.get("holes",[])
	if terrain_image and holes.size()>applied_holes:
		for hole:Dictionary in holes.slice(applied_holes):terrain.carve(hole)
		terrain.flush()
		applied_holes=holes.size()
	var focus := camera
	_process_edge_pan(delta)
	var motion_poses:=_motion_poses()
	var moving_vehicle:=0
	for unit in battle.get("units", []):
		var key := str(int(unit.seat))
		var authoritative:Dictionary=source_units.get(int(unit.seat),unit)
		var target := Vector2(float(authoritative.x), float(authoritative.y))
		var animated:bool=motion_poses.has(int(unit.seat))
		var predicted:bool=local_walk!=null and local_walk.active and int(unit.player)==player_id and not local_walk.unit.is_empty() and not animated and float(battle.get("deadline",0))>0
		walking[key] = not animated and int(unit.hp)>0 and not bool(unit.get("falling",false)) and absf((render_positions.get(key,target) as Vector2).x-target.x)>0.4
		if predicted:
			for stat:String in ["x","y","slope","face","aim","sp","move","move_spent"]:unit[stat]=local_walk.unit.get(stat,unit.get(stat,0))
			render_positions[key]=Vector2(float(unit.x),float(unit.y))
			render_slopes[key]=float(unit.slope)
			walking[key]=bool(local_walk.moved_this_frame)
		elif animated:
			var pose:Array=motion_poses[int(unit.seat)]
			render_positions[key]=Vector2(float(pose[1]),float(pose[2]))
			render_slopes[key]=float(pose[3])
			unit.falling=float(pose[4])>0
		else:
			render_positions[key] = (render_positions.get(key, target) as Vector2).lerp(target, 1 - exp(-delta * 16))
			render_slopes[key]=lerp_angle(float(render_slopes.get(key,unit.get("slope",0)))*PI/180,float(unit.get("slope",0))*PI/180,1-exp(-delta*16))*180/PI
		var displayed:Vector2=render_positions[key]
		if int(unit.player)==player_id and preview_face!=0 and float(battle.get("deadline",0))>0:unit.face=preview_face
		unit.x=displayed.x
		unit.y=displayed.y
		if bool(authoritative.get("departed",false)):unit.hp=0
		if bool(walking[key]) and int(unit.hp)>0 and not bool(unit.get("falling",false)):moving_vehicle=int(unit.vehicle)
		if int(unit.seat) == int(battle.active):
			focus = (render_positions[key] as Vector2) - Vector2(0, 100)
	if moving_vehicle>0:
		effect.emit("move",moving_vehicle)
		movement_active=true
	elif movement_active:
		effect.emit("move_stop",0)
		movement_active=false
	var shot: Variant = battle.get("shot")
	if shot is Dictionary and clock:
		var t: float = clock.server_now() - float(shot.started)
		for index in range(shot.get("trails",[]).size()):
			var trail: Dictionary = shot.trails[index]
			var start := float(trail.get("start",0))
			if t>=start and t<start+0.35 and not fired_sounds.has(index):
				fired_sounds[index] = true
				effect.emit("fire",int(trail.get("projectile",0)))
		for index in range(shot.get("impacts", []).size()):
			var impact: Dictionary = shot.impacts[index]
			var key := "%d:%d" % [int(shot.id), index]
			if t >= float(impact.at) and t < float(shot.duration) + 1 and not fired_impacts.has(key):
				fired_impacts[key] = true
				explode(Vector2(float(impact.x), float(impact.y)), float(impact.radius), str(impact.kind), int(impact.get("projectile",0)), maxf(0,t-float(impact.at)))
		if t > 0 and t < float(shot.duration) and shot.get("trails", []).size() > 0:
			for trail: Dictionary in shot.trails:
				if str(trail.kind) not in ["warp_portal","hp_return","sp_return"] and t>=float(trail.get("start",0)) and t<=float(trail.get("start",0))+float(trail.duration):
					focus = point_on_trail(trail,t-float(trail.get("start",0)))
					break
	if overview > 0:
		overview -= delta
	else:
		zoom = lerpf(zoom, zoom_target, 1 - exp(-delta * 3))
		if elapsed > manual_until and not dragging:
			target_camera = focus
		var half := size / maxf(0.1, zoom) / 2
		target_camera.x = clampf(target_camera.x, minf(half.x, float(battle.width) / 2), maxf(float(battle.width) - half.x, float(battle.width) / 2))
		target_camera.y = clampf(target_camera.y, minf(half.y, float(battle.height) / 2), maxf(float(battle.height) - half.y, float(battle.height) / 2))
		camera = camera.lerp(target_camera, 1 - exp(-delta * 5))
	for number:Dictionary in visual_numbers:number.age+=delta
	visual_numbers = visual_numbers.filter(func(number: Dictionary) -> bool:
		return float(number.age) < _number_duration(int(number.delta)))
	for particle in particles:
		particle.life -= delta
		particle.velocity += Vector2(0, 270) * delta
		particle.position += particle.velocity * delta
	particles = particles.filter(func(p): return float(p.life) > 0)
	for explosion in explosions:
		explosion.age += delta
	explosions = explosions.filter(func(e): return float(e.age) < 4.0)
	shake = maxf(0, shake - delta * 22)
	screen_origin = size / 2 - camera * zoom
	if shake_enabled and shake > 0:
		# Continuous high-frequency motion avoids a new random camera jump
		# on every rendered frame and keeps 60/120 Hz impact feel consistent.
		screen_origin += Vector2(sin(elapsed*71)+.4*sin(elapsed*113),cos(elapsed*83)+.4*cos(elapsed*127))*shake*.6
	_update_vehicles(delta)
	queue_redraw()
	overlay.queue_redraw()
	reticle.queue_redraw()

func _stop_movement() -> void:
	if movement_active:
		effect.emit("move_stop",0)
		movement_active=false

# Original 004d3620 moves the map at the client edges and releases follow.
# Use viewport coordinates, so resizing/DPI never confines the mouse to 800x600.
func _edge_direction(at:Vector2,extent:Vector2=Vector2.ZERO) -> Vector2:
	if extent==Vector2.ZERO:extent=size
	if not Rect2(Vector2.ZERO,extent).has_point(at):return Vector2.ZERO
	var direction:=Vector2.ZERO
	if at.x<=3:direction.x=-1
	elif at.x>=extent.x-4:direction.x=1
	if at.y<=3:direction.y=-1
	elif at.y>=extent.y-4:direction.y=1
	return direction

func _process_edge_pan(delta:float) -> void:
	if dragging or aiming_with_mouse or not get_window().has_focus():return
	if _camera_input_blocked():return
	var outer:Vector2=get_viewport().get_visible_rect().size
	var pointer:Vector2=get_viewport().get_mouse_position()
	# The original also scrolls at the outer window edge above/below its HUD.
	if _edge_direction(pointer,outer)!=Vector2.ZERO:_pan_at_edge(delta,pointer,outer)
	elif get_viewport().gui_get_hovered_control()==self:_pan_at_edge(delta,get_local_mouse_position())

func _camera_input_blocked() -> bool:
	# The battle view lives inside a content panel, below the application node.
	var ancestor:Node=get_parent()
	while ancestor:
		if ancestor.has_method("_modal_open"):return bool(ancestor._modal_open())
		ancestor=ancestor.get_parent()
	return false

func _pan_at_edge(delta:float,at:Vector2,extent:Vector2=Vector2.ZERO) -> void:
	var direction:=_edge_direction(at,extent)
	if direction==Vector2.ZERO:return
	overview=0
	manual_until=INF
	target_camera+=direction*600*delta/maxf(.1,zoom)

func _notification(what:int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging=false
		aiming_with_mouse=false

func _exit_tree() -> void:
	_stop_movement()

func _sync_visual_timeline() -> void:
	var shot:Variant=battle.get("shot")
	if not shot is Dictionary or not clock or float(battle.get("deadline",0))>0 or battle.get("result") is Dictionary:return
	var frames:Array=shot.get("visuals",[])
	if frames.is_empty():return
	var t:float=maxf(0,clock.server_now()-float(shot.started))
	var index:=0
	for i in range(1,frames.size()):
		if float(frames[i].at)>t:break
		index=i
	if visual_frame!=index:
		visual_frame=index
		var frame:Dictionary=frames[index]
		var by_seat:Dictionary={}
		for stats:Dictionary in frame.units:by_seat[int(stats.seat)]=stats
		for unit:Dictionary in battle.get("units",[]):
			for key:String in by_seat.get(int(unit.seat),{}):
				unit[key]=by_seat[int(unit.seat)][key]
			if bool(source_units.get(int(unit.seat),{}).get("departed",false)):unit.hp=0
		var base:int=int(shot.get("hole_base",0))
		var cuts:Array=shot.get("cuts",[])
		battle.holes=source_battle.get("holes",[]).slice(0,base)+cuts.slice(0,int(frame.holes))
	for i in range(index+1):
		if fired_numbers.has(i):continue
		fired_numbers[i]=true
		var frame:Dictionary=frames[i]
		var age:=t-float(frame.at)
		if age < 0:continue
		if age<.4:
			for cue:Dictionary in frame.get("falls",[]):
				if not bool(source_units.get(int(cue.seat),{}).get("departed",false)):effect.emit("fall",int(cue.vehicle))
		for number:Dictionary in frame.get("numbers",[]):
			if age >= _number_duration(int(number.delta)):continue
			if _number_visible(int(number.seat)):visual_numbers.append({"seat":int(number.seat),"position":Vector2(float(number.x),float(number.y)-42),"delta":int(number.delta),"age":age})

func _number_visible(seat:int) -> bool:
	for unit:Dictionary in battle.get("units",[]):
		if int(unit.seat)==seat:return not bool(unit.get("departed",false)) and (int(unit.get("stealth",0))<=0 or int(unit.team)==my_team)
	return false

func _number_duration(delta: int) -> float:
	return (110.0 + delta) / 60.0 if delta > 0 else 1.2

func _sync_supply_numbers() -> void:
	if not clock:
		return
	var now: float = clock.server_now()
	for cue: Dictionary in source_battle.get("supplies", []):
		var id := int(cue.id)
		if id <= last_supply_id:
			continue
		last_supply_id = id
		recovery_layer.receive_supply(cue)
		var seat := int(cue.seat)
		supply_numbers = supply_numbers.filter(func(previous: Dictionary) -> bool: return int(previous.seat) != seat)
		if now - float(cue.at) < _number_duration(int(cue.amount)) and _number_visible(seat):
			supply_numbers.append(cue)
	supply_numbers = supply_numbers.filter(func(cue: Dictionary) -> bool:
		return now - float(cue.at) < _number_duration(int(cue.amount)))

func _draw_supply_number(font: Font, at: Vector2, amount: int, fuel: bool, ticks: float) -> void:
	# Original 00531125 draws +amount for 20 ticks at the recorded position
	# (tank y - 30), counts up, then rises by half a pixel per tick and fades.
	var paused := ticks < 20.0
	var count := mini(amount, maxi(0, int(ticks - 20.0)))
	var rising := maxf(0.0, ticks - 20.0 - amount)
	var color := Color.GREEN if fuel else Color.YELLOW
	color.a = clampf(1.0 - rising / 90.0, 0.0, 1.0)
	var scale := 0.5 + (20.0 - ticks) * 0.1 if paused else 1.0
	var font_size := maxi(10, roundi(15.0 * clampf(zoom, .8, 2.8) * scale))
	var label := "+%d" % (amount if paused else count)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var position := screen(at - Vector2(0, 30.0 + floorf(rising / 2.0)))
	position.x -= width / 2.0
	overlay.draw_string_outline(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0, 0, 0, color.a))
	overlay.draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _update_vehicles(delta: float) -> void:
	var present := {}
	for unit: Dictionary in battle.get("units", []):
		var seat := int(unit.seat)
		present[seat] = true
		if not vehicles.has(seat):
			var node := NativeVehicle.new()
			add_child(node)
			vehicles[seat] = node
		var node: Node2D = vehicles[seat]
		node.visible = int(unit.get("stealth", 0)) <= 0 or int(unit.team) == my_team
		var at: Vector2 = render_positions.get(str(seat), Vector2(float(unit.x), float(unit.y)))
		node.position = screen(at)
		node.scale = Vector2.ONE * zoom
		var pitch := float(unit.get("aim", 45))
		if int(unit.player) == player_id and seat == int(battle.active):
			pitch = angle
		# Legacy HD protocol supplies a world angle; native elevation is relative
		# to facing and ground. Accept the explicit native field when supplied.
		var slope := float(render_slopes.get(str(seat),unit.get("slope", 0)))
		var elevation := pitch - slope if int(unit.face) > 0 else 180 + slope - pitch
		if bool(battle.get("native_aim", false)):
			elevation = angle if int(unit.player) == player_id and seat == int(battle.active) else float(unit.elevation)
		node.pose(unit, elevation, slope, bool(walking.get(str(seat), false)), delta)
	for seat in vehicles.keys():
		if not present.has(seat):
			vehicles[seat].queue_free()
			vehicles.erase(seat)

func _motion_poses() -> Dictionary:
	var shot:Variant=battle.get("shot")
	if not shot is Dictionary or not clock:return {}
	var frames:Array=shot.get("motion",[])
	if frames.is_empty():return {}
	var t:float=clock.server_now()-float(shot.started)
	if t<0 or float(battle.get("deadline",0))>0 or battle.get("result") is Dictionary:return {}
	t=minf(t,float(shot.duration))
	var low:=0
	var high:=frames.size()-1
	while low<high:
		var mid: int=(low+high+1)/2
		if float(frames[mid].at)<=t:low=mid
		else:high=mid-1
	var a:Dictionary=frames[low]
	var b:Dictionary=frames[mini(low+1,frames.size()-1)]
	var blend:=clampf((t-float(a.at))/maxf(.0001,float(b.at)-float(a.at)),0,1)
	var next:Dictionary={}
	for pose:Array in b.poses:next[int(pose[0])]=pose
	var result:Dictionary={}
	for pose:Array in a.poses:
		var seat:=int(pose[0])
		if bool(source_units.get(seat,{}).get("departed",false)):continue
		var to:Array=next.get(seat,pose)
		result[seat]=[seat,lerpf(float(pose[1]),float(to[1]),blend),lerpf(float(pose[2]),float(to[2]),blend),rad_to_deg(lerp_angle(deg_to_rad(float(pose[3])),deg_to_rad(float(to[3])),blend)),pose[4]]
	return result

func point_on_trail(trail: Dictionary, t: float) -> Vector2:
	var points: Array = trail.get("points", [])
	if points.is_empty():
		return camera
	var fraction := clampf(t / maxf(0.01, float(trail.duration)), 0, 1) * (points.size() - 1)
	var index := mini(int(fraction), points.size() - 1)
	var a: Array = points[index]
	var b: Array = points[mini(index + 1, points.size() - 1)]
	return Vector2(float(a[0]), float(a[1])).lerp(Vector2(float(b[0]), float(b[1])), fraction - index)

func screen(point: Vector2) -> Vector2:
	return point * zoom + screen_origin

func explode(at: Vector2, radius: float, kind: String, projectile := 0, age := 0.0) -> void:
	if kind=="teleport":
		if age<.4:effect.emit("explosion",projectile)
		return
	if kind == "heal":
		recovery_layer.receive_impact(at, age)
		if age < .4: effect.emit("native", 56)
		return
	if age>=4:return
	explosions.append({"position": at, "radius": radius, "age": age, "kind": kind,"projectile":projectile})
	shake = maxf(shake,maxf(0,minf(8,radius/11)-age*22))
	if age<.4:effect.emit("explosion",projectile)
	if age>=1.1:return
	var count := 25 if quality == 0 else 65 if quality == 1 else 110
	for i in range(count):
		var velocity := Vector2.from_angle(randf() * TAU) * randf_range(45, radius * 4)
		velocity.y -= 60
		var life:=randf_range(.3,1.1)-age
		if life>0:particles.append({"position":at+velocity*age+Vector2(0,135*age*age),"velocity":velocity+Vector2(0,270*age),"life":life,"size":randf_range(1.5,4),"color":Color("ffc46b") if i%3==0 else Color("7d6253")})

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("18283c"))
	if battle.is_empty():
		return
	if background:
		var cover_scale := maxf(size.x/background.get_width(),size.y/background.get_height())
		var dimensions := background.get_size()*cover_scale
		draw_texture_rect(background, Rect2((size-dimensions)/2, dimensions), false)
	if terrain_image:terrain.draw_in(self,screen_origin,zoom)

func _draw_overlay() -> void:
	if battle.is_empty():
		return
	var font := get_theme_default_font()
	for unit: Dictionary in battle.get("units", []):
		if int(unit.hp) <= 0:
			continue
		if int(unit.get("stealth", 0)) > 0 and int(unit.team) != my_team:
			continue
		var at: Vector2 = render_positions.get(str(int(unit.seat)), Vector2(float(unit.x), float(unit.y)))
		var pos := screen(at)
		var scale := clampf(size.y / 600, 0.8, 2.8)
		var bar_width := 64.0 * scale
		var bar := Rect2(pos + Vector2(-bar_width / 2, -68 * scale), Vector2(bar_width, 5 * scale))
		overlay.draw_style_box(_bar_background(), bar)
		var fraction := clampf(float(unit.hp) / float(unit.max_hp), 0, 1)
		overlay.draw_rect(Rect2(bar.position, Vector2(bar_width * fraction, bar.size.y)), Color("6cdaaa") if int(unit.team) == my_team else Color("f7877a"))
		overlay.draw_string(font, bar.position + Vector2(-35 * scale, -8 * scale), str(unit.name), HORIZONTAL_ALIGNMENT_CENTER, bar_width + 70 * scale, int(13 * scale), Color("f2f5fa"))
		if int(unit.seat) == int(battle.active):
			var arrow := pos + Vector2(0, -100 * scale + sin(elapsed * 4) * 3)
			overlay.draw_colored_polygon(PackedVector2Array([arrow, arrow + Vector2(-7, -10) * scale, arrow + Vector2(7, -10) * scale]), Color("f2bd65"))
	for particle in particles:
		var c: Color = particle.color
		c.a = minf(1, float(particle.life) * 2)
		overlay.draw_circle(screen(particle.position), float(particle.size) * zoom, c)

	for number:Dictionary in visual_numbers:
		if not _number_visible(int(number.seat)):continue
		var life:=float(number.age)
		if int(number.delta) > 0:
			_draw_supply_number(font, (number.position as Vector2) + Vector2(0, 42), int(number.delta), false, life * 60.0)
			continue
		var at:=screen(number.position as Vector2)+Vector2(0,-38*zoom*life)
		var factor:=clampf(zoom,.65,2.8)*.65
		var digits:=str(absi(int(number.delta)))
		var width:=float(digits.length()*22)*factor
		var color:=Color("ffdc8a")
		color.a=clampf((1.2-life)*4,0,1)
		var x:=at.x-width/2
		for digit in digits:
			var sprite:=texture("res://assets/icons/Number1/%02d.png"%int(digit))
			if sprite:overlay.draw_texture_rect(sprite,Rect2(Vector2(x,at.y),sprite.get_size()*factor),false,color)
			x+=22*factor
	if clock:
		var now: float = clock.server_now()
		for cue: Dictionary in supply_numbers:
			if _number_visible(int(cue.seat)):
				_draw_supply_number(font, Vector2(float(cue.x), float(cue.y)), int(cue.amount), bool(cue.get("fuel", false)), maxf(0.0, (now - float(cue.at)) * 60.0))

func aim_heading(unit:Dictionary,elevation:float) -> float:
	var slope:=float(render_slopes.get(str(int(unit.seat)),unit.get("slope",0)))
	return fposmod(slope+(180-elevation if int(unit.face)<0 else elevation),360)

func aim_center(unit:Dictionary) -> Vector2:
	var at:Vector2=render_positions.get(str(int(unit.seat)),Vector2(float(unit.x),float(unit.y)))
	var slope:=float(render_slopes.get(str(int(unit.seat)),unit.get("slope",0)))
	return at+NativeVehicle.mount_offset(int(unit.vehicle),int(unit.face),slope)

func fire_failed(unit: Dictionary, elevation: float, face: int) -> void:
	if battle.is_empty() or unit.is_empty() or not is_instance_valid(failure_layer):
		return
	failure_layer.emit_smoke(unit, elevation, face)
	effect.emit("native", 55)

func _draw_reticle() -> void:
	if battle.is_empty() or float(battle.get("deadline",0))<=0:return
	for unit:Dictionary in battle.get("units",[]):
		if int(unit.player)!=player_id or int(unit.hp)<=0 or int(unit.seat)!=int(battle.active):continue
		# 00533b50 draws at the barrel mount, not the vehicle's ground point.
		var center:=screen(aim_center(unit))
		var factor:=zoom
		var heading:=aim_heading(unit,angle)
		if not catalog.get("vehicles",[]).is_empty():
			var data:Dictionary=catalog.vehicles[int(unit.vehicle)-1]
			var minimum:=aim_heading(unit,float(data.aim_min))
			var maximum:=aim_heading(unit,float(data.aim_max))
			var arc:=PackedVector2Array([center])
			var low:=minf(minimum,maximum)
			var high:=maxf(minimum,maximum)
			if high-low>180:
				low=high
				high=minf(minimum,maximum)+360
			for i in range(33):arc.append(center+Vector2.from_angle(-deg_to_rad(lerpf(low,high,float(i)/32)))*47*factor)
			reticle.draw_colored_polygon(arc,Color(.6,.8,1,.15))
		# 004ceb70 draws the source ring, fixed crosshair, terrain reference
		# and the direction marker on the active tank, never on the power HUD.
		for index in [0,1,2]:
			var sprite:=texture("res://assets/icons/Interface/%02d.png"%index)
			var rotation:=-deg_to_rad(elapsed*168.75) if index==0 else -deg_to_rad(float(render_slopes.get(str(int(unit.seat)),unit.get("slope",0)))) if index==2 else 0.0
			reticle.draw_set_transform(center,rotation,Vector2.ONE*factor)
			reticle.draw_texture(sprite,-sprite.get_size()/2,Color(200.0/255,220.0/255,1,.45) if index==2 else Color(1,1,1,.35))
		var marker:=texture("res://assets/icons/Interface/04.png")
		reticle.draw_set_transform(center,-deg_to_rad(heading),Vector2.ONE*factor)
		reticle.draw_texture(marker,Vector2(0,-marker.get_height()/2.0))
		reticle.draw_set_transform(Vector2.ZERO)
		var label:="%d°"%int(round(angle))
		reticle.draw_string_outline(get_theme_default_font(),center+Vector2(43,-45)*factor,label,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(14,int(16*factor)),3,Color.BLACK)
		reticle.draw_string(get_theme_default_font(),center+Vector2(43,-45)*factor,label,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(14,int(16*factor)),Color("ffe9a5"))

func _bar_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.07, 0.9)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed:aiming_with_mouse=false
			elif float(battle.get("deadline",0))>0:
				for unit:Dictionary in battle.get("units",[]):
					if int(unit.player)==player_id and int(unit.seat)==int(battle.active) and int(unit.hp)>0 and event.position.distance_to(screen(aim_center(unit)))<80*zoom:
						aiming_with_mouse=true
						_update_mouse_aim(event.position,unit)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			manual_until = elapsed + 8
		elif event.pressed and not zoom_locked and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_target = clampf(zoom_target * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9), minf(size.x / maxf(1, float(battle.get("width", 1920))), size.y / maxf(1, float(battle.get("height", 1200)))), 4.0)
			overview = 0
	if event is InputEventMouseMotion and dragging:
		target_camera -= event.relative / maxf(0.1, zoom)
		manual_until = elapsed + 8
	if event is InputEventMouseMotion and aiming_with_mouse:
		for unit:Dictionary in battle.get("units",[]):
			if int(unit.player)==player_id and int(unit.seat)==int(battle.active):_update_mouse_aim(event.position,unit)

func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:aiming_with_mouse=false

func _update_mouse_aim(at:Vector2,unit:Dictionary) -> void:
	var center:=screen(aim_center(unit))
	var offset:=at-center
	if offset.length()<2:return
	var relative:=fposmod(-rad_to_deg(offset.angle())-float(unit.get("slope",0)),360)
	var facing:=int(unit.face)
	# Original 004d3620 uses 75/285 and 105/255 degree hysteresis.
	if facing<0 and (relative<=75 or relative>=285):facing=1
	elif facing>0 and relative>=105 and relative<=255:facing=-1
	var elevation:=180-relative if facing<0 else relative
	if elevation>180:elevation-=360
	var data:Dictionary=catalog.vehicles[int(unit.vehicle)-1]
	elevation=clampf(elevation,float(data.aim_min),float(data.aim_max))
	preview_face=facing
	mouse_aim.emit(elevation,facing)

func reset_camera() -> void:
	manual_until = 0
	zoom_target = maxf(0.6, size.y / 560)

func show_whole_map() -> void:
	camera = Vector2(float(battle.get("width", 1920)) / 2, float(battle.get("height", 1200)) / 2)
	target_camera = camera
	zoom_target = minf(size.x / float(battle.get("width", 1920)), size.y / float(battle.get("height", 1200)))
	manual_until = elapsed + 15
