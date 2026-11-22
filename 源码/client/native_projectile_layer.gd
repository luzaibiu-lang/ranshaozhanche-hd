extends Node2D
## Two real canvas layers preserve the original additive halo + opaque core.
var world: Control
var additive := false
var rules: Dictionary = {}
var effect_frames := {}

func _ready() -> void:
	rules = world.projectile_rules
	if additive:
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = blend
		# Load the small weapon atlases before battle playback. A first burst
		# must not synchronously import a new PNG on every animation frame.
		_prewarm_visuals()

func _prewarm_visuals() -> void:
	for key: String in rules:
		var rule: Dictionary = rules[key]
		var asset := str(rule.get("sprite",key))
		var metadata := "res://assets/projectiles/%s/frames.json" % asset
		if FileAccess.file_exists(metadata):
			var frames: Array = JSON.parse_string(FileAccess.get_file_as_string(metadata))
			world.projectile_frames[int(key)] = frames
			for frame: Dictionary in frames:
				world.texture("res://assets/projectiles/%s/%s" % [asset,str(frame.file)])
		for effect: Dictionary in rule.get("effects",[]):_prewarm_effect(str(effect.effect))
		for sequence: Array in rule.get("variant_effects",{}).values():
			for effect: Dictionary in sequence:_prewarm_effect(str(effect.effect))

func _prewarm_effect(name: String) -> void:
	if effect_frames.has(name):return
	var path := "res://assets/effects/%s/frames.json" % name
	var frames: Array = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else []
	effect_frames[name] = frames
	for frame: Dictionary in frames:world.texture("res://assets/effects/%s/%s" % [name,str(frame.file)])

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not world or world.battle.is_empty():return
	var shot: Variant = world.battle.get("shot")
	if shot is Dictionary and world.clock:
		var time: float = world.clock.server_now()-float(shot.started)
		for trail: Dictionary in shot.get("trails",[]):
			var local := time-float(trail.get("start",0))
			if local<0 or local>float(trail.duration):continue
			var id := int(trail.get("projectile",0))
			if id in [24,26,90,91,92]:continue # native_flame_layer keeps their original sprites.
			var frames: Array = world.projectile_frames.get(id,[])
			if frames.is_empty():continue
			if str(trail.get("kind",""))=="warp_portal":
				if additive:_draw_portal(trail,local,frames)
				continue
			var rule: Dictionary = rules.get(str(id),{"layers":[{"first":0,"count":1,"ticks":1,"blend":"mix"}]})
			if id==22:
				if additive:
					var frame:Dictionary=frames[1 if str(trail.kind)=="sp_return" else 0]
					var sprite:Texture2D=world.texture("res://assets/projectiles/22/%s"%str(frame.file))
					draw_set_transform(world.screen(world.point_on_trail(trail,local)),-deg_to_rad(local*360),Vector2.ONE*world.zoom*.4)
					draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])))
					draw_set_transform(Vector2.ZERO)
				continue
			var at: Vector2 = world.point_on_trail(trail,local)
			var direction: Vector2 = world.point_on_trail(trail,minf(float(trail.duration),local+1.0/60))-world.point_on_trail(trail,maxf(0,local-1.0/60))
			for layer: Dictionary in rule.get("layers",[]):
				if (str(layer.blend)=="add")!=additive:continue
				var index := int(layer.first)+(int(local*60)/maxi(1,int(layer.ticks)))%maxi(1,int(layer.count))
				if index<0 or index>=frames.size():continue
				var frame: Dictionary = frames[index]
				var sprite: Texture2D = world.texture("res://assets/projectiles/%s/%s"%[str(rule.get("sprite",str(id))),str(frame.file)])
				if not sprite:continue
				# Native SPR cores point right; their halo pivots put fire behind
				# the core. 00541b20 passes heading directly, without adding 180.
				# Positive native spin is counterclockwise in screen coordinates.
				var rotation := direction.angle() if bool(layer.get("align_velocity",true)) else 0.0
				rotation -= deg_to_rad(float(layer.get("spin_per_tick",0))*local*60)
				draw_set_transform(world.screen(at),rotation,Vector2.ONE*world.zoom)
				draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])))
				draw_set_transform(Vector2.ZERO)
	if not additive:return
	for explosion: Dictionary in world.explosions:
		var rule: Dictionary = rules.get(str(int(explosion.projectile)),{})
		var effects: Array = rule.get("variant_effects",{}).get(str(explosion.kind),rule.get("effects",[]))
		for effect: Dictionary in effects:
			if str(effect.get("renderer",""))=="orbital_column":continue
			var name := str(effect.effect)
			if not effect_frames.has(name):_prewarm_effect(name)
			var frames: Array = effect_frames[name]
			if effect.get("draw", "") == "sky_column":
				_draw_sky_column(explosion, name, frames)
				continue
			var index := int(float(explosion.age)*15)
			if index>=frames.size():continue
			var frame: Dictionary = frames[index]
			var sprite: Texture2D = world.texture("res://assets/effects/%s/%s"%[name,str(frame.file)])
			if not sprite:continue
			draw_set_transform(world.screen(explosion.position),0,Vector2.ONE*world.zoom*float(effect.scale))
			draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])))
			draw_set_transform(Vector2.ZERO)

func _draw_sky_column(explosion: Dictionary, name: String, frames: Array) -> void:
	# 004aed00 draws frame 1 bottom-anchored, then frame 0 at the impact.
	var tick := floori(float(explosion.age) * 60)
	var at: Vector2 = explosion.position
	if tick < 0 or tick > 50 or frames.size() < 2 or at.y <= 0:
		return
	var remaining := 1.0 - tick / 50.0
	var width := remaining * 0.8
	var column: Texture2D = world.texture("res://assets/effects/%s/%s" % [name, frames[1].file])
	var flare: Texture2D = world.texture("res://assets/effects/%s/%s" % [name, frames[0].file])
	var anchor: Vector2 = world.screen(at)
	if remaining > 0:
		draw_set_transform(anchor, 0, Vector2(width, at.y / column.get_height()) * world.zoom)
		draw_texture(column, Vector2(-column.get_width() * 0.5, -column.get_height()), Color(1, 1, 1, remaining))
	# Native rand()%10 flickers the base. Derive the sample from the strike
	# and tick so both clients and held replay frames show the same flare.
	var flicker := posmod(hash(Vector3i(roundi(at.x), roundi(at.y), tick)), 10) * 0.06
	var scale_xy := Vector2(width * 0.4 + 1.1 + flicker, width * 0.4 + 0.8)
	draw_set_transform(anchor, 0, scale_xy * world.zoom)
	draw_texture(flare, -flare.get_size() * 0.5, Color(1, 1, 1, minf(1, remaining + 0.3)))
	draw_set_transform(Vector2.ZERO)

func _portal_sprite(index:int,at:Vector2,scale:Vector2,rotation:float,alpha:float,frames:Array) -> void:
	if alpha<=0 or scale.x<=0 or scale.y<=0:return
	var frame:Dictionary=frames[index]
	var sprite:Texture2D=world.texture("res://assets/projectiles/native/data_witem_warp/%s"%str(frame.file))
	draw_set_transform(world.screen(at),rotation,scale*world.zoom)
	draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])),Color(1,1,1,alpha))
	draw_set_transform(Vector2.ZERO)

func _draw_portal(trail:Dictionary,local:float,frames:Array) -> void:
	# 00570890/00570fa0: five opening frames at five ticks each,
	# followed by the original expanding columns and spinning rings.
	var tick:=int(local*60)
	var at:Vector2=world.point_on_trail(trail,local)
	if tick<25:
		_portal_sprite(0,at,Vector2.ONE,0,1,frames)
		_portal_sprite(1+tick/5,at,Vector2.ONE*.8,0,1,frames)
		return
	var phase:=float(tick-25)
	var alpha:=clampf(1-phase/120,0,1)
	_portal_sprite(6,at,Vector2((1-phase/60)*.8,at.y/32),0,alpha,frames)
	for offset:float in [0,90]:
		_portal_sprite(7,at,Vector2(4.5,.2),deg_to_rad(phase*2+offset),alpha,frames)
	_portal_sprite(7,at,Vector2.ONE*2.5,deg_to_rad(phase),alpha/3,frames)
	_portal_sprite(8,at,Vector2.ONE,0,alpha,frames)
