extends Node2D
## Original CTank animation and draw order (00537390 / 00532210).
## Frame origins belong to the reference frame, not to the displayed frame.

const DEATH := [13, 13, 23, 13, 16, 20, 5, 13, 41, 25]
const WALK_TICKS := [4, 4, 3, 4, 3, 4, 6, 3, 4, 3]
const MOUNTS := [Vector2(-1, -22), Vector2(-2, -20), Vector2(5, -18), Vector2(4, -23), Vector2(2, -23), Vector2(-6, -19), Vector2(0, -25), Vector2(0, -20), Vector2(16, -24), Vector2(0, -20)]
# Isolated original runtime: 59.10 / 59.76 ticks per second, sampled at 25 ms.
const TICK_SECONDS := 1.0 / 60.0
const NATIVE_RADIANS_PER_DEGREE := 0.017453288659453392
const STATE_NAMES := ["StateShield", "StateEShock", "StateStealth"]
static var frame_cache := {}
static var texture_cache := {}
var vehicle := 0
var family := 1
var frames: Array = []
var layers: Array[Sprite2D] = []
var tick := 0
var remainder := 0.0
var phase := 0
var idle_phase := 0
var was_walking := false
var mirrored := false
var additive: CanvasItemMaterial
var states := {}
static var state_frames := {}

static func warmup_paths(ids: Dictionary) -> Dictionary:
	var paths := {}
	for id: int in ids:
		for frame: Dictionary in _vehicle_frames(id):
			var key := "%d/%s" % [id, str(frame.file)]
			if not texture_cache.has(key):paths[key] = "res://assets/tanks/" + key
	for name: String in STATE_NAMES:
		for frame: Dictionary in _state_frames(name):
			var key := "%s/%s" % [name, str(frame.file)]
			if not texture_cache.has(key):paths[key] = "res://assets/effects/" + key
	return paths

static func _vehicle_frames(id: int) -> Array:
	if not frame_cache.has(id):
		frame_cache[id] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tanks/%d/frames.json" % id))
	return frame_cache[id]

static func _state_frames(name: String) -> Array:
	if not state_frames.has(name):
		state_frames[name] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/%s/frames.json" % name))
	return state_frames[name]

static func mount_offset(id: int, face: int, slope: float) -> Vector2:
	# 005343c0 -> 00534c40 -> 00534180: the aiming ring and barrel
	# share this per-family mount, including the native integer polar setup.
	var source: Vector2 = MOUNTS[(clampi(id, 1, 30) - 1) % 10]
	var degrees := float(int(rad_to_deg(atan2(-source.y, source.x))))
	if face < 0:degrees = 180 - degrees
	var radians := (slope + degrees) * NATIVE_RADIANS_PER_DEGREE
	var distance := float(int(source.length()))
	return Vector2(floorf((cos(radians) * distance + 0.0005) * 1000) / 1000, -floorf((sin(radians) * distance + 0.0005) * 1000) / 1000)

func _init() -> void:
	additive = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in range(5):
		var layer := Sprite2D.new()
		layer.centered = false
		add_child(layer)
		layers.append(layer)
	for name in STATE_NAMES:
		var layer := Sprite2D.new()
		layer.centered = false
		layer.material = additive
		add_child(layer)
		states[name] = layer

func set_vehicle(id: int) -> void:
	if id == vehicle:
		return
	vehicle = clampi(id, 1, 30)
	family = (vehicle - 1) % 10 + 1
	frames = _vehicle_frames(vehicle)
	tick = 0
	phase = 0
	idle_phase = 0
	remainder = 0
	was_walking = false

func advance(delta: float, moving: bool) -> void:
	if not moving:
		phase = 0
	if moving != was_walking:
		phase = 0
	was_walking = moving
	remainder += delta
	while remainder >= TICK_SECONDS:
		remainder -= TICK_SECONDS
		if moving and tick % int(WALK_TICKS[family - 1]) == 0:
			phase += 1
		if family == 9 and not moving and tick % 8 == 0:
			idle_phase = (idle_phase + 1) % 11
		tick += 1

func pose(unit: Dictionary, elevation: float, slope: float, moving: bool, delta: float) -> void:
	set_vehicle(int(unit.vehicle))
	advance(delta, moving)
	for layer in layers:
		layer.visible = false
	mirrored = int(unit.get("face", 1)) < 0
	modulate = Color(1, 1, 1, 0.5 if int(unit.get("stealth", 0)) > 0 else 1.0)
	var body_angle := -deg_to_rad(slope)
	var gun_angle := -deg_to_rad(slope + (-elevation if mirrored else elevation))
	# 00534c40 derives integer polar mount coordinates from 005343c0's
	# per-family offsets. The mount is not universally (0,-20).
	var mount := mount_offset(vehicle, int(unit.get("face", 1)), slope)
	_state("StateShield", int(unit.get("shield", 0)) > 0 and int(unit.get("hp", 1)) > 0, body_angle)
	_state("StateEShock", int(unit.get("stun", 0)) > 0 and int(unit.get("hp", 1)) > 0, body_angle)
	_state("StateStealth", int(unit.get("stealth", 0)) > 0 and int(unit.get("hp", 1)) > 0, body_angle)
	if int(unit.get("hp", 1)) <= 0:
		_layer(0, DEATH[family - 1], 0, Vector2.ZERO, body_angle)
		return
	var p := phase % 10
	var main := 1 if moving and p in [1, 6] else 0
	match family:
		1, 2, 4, 8:
			_layer(0, (p + 6) % 10 + 3 if moving else 2, 0, Vector2.ZERO, body_angle, Color(0.6, 0.6, 0.6))
			_layer(1, main, 1, mount, gun_angle)
			_layer(2, p + 3 if moving else 3, 0, Vector2.ZERO, body_angle)
		3:
			_layer(0, p + 13 if moving else 13, 0, Vector2.ZERO, body_angle)
			_layer(1, 2, 2, mount, gun_angle)
			_layer(2, main, 0, Vector2.ZERO, body_angle)
			_layer(3, p + 3 if moving else 3, 0, Vector2.ZERO, body_angle)
		5:
			_layer(0, (p + 6) % 10 + 5 if moving else 4, 0, Vector2.ZERO, body_angle, Color(0.6, 0.6, 0.6))
			_layer(1, main + 2, 2, mount, gun_angle)
			_layer(2, main, 0, Vector2.ZERO, body_angle)
			_layer(3, p + 5 if moving else 5, 0, Vector2.ZERO, body_angle)
		6:
			_layer(0, (p + 6) % 10 + 4 if moving else 3, 0, Vector2.ZERO, body_angle, Color(0.6, 0.6, 0.6))
			_layer(1, 2, 2, mount, gun_angle)
			_layer(2, main, 0, Vector2.ZERO, body_angle)
			_layer(3, p + 4 if moving else 4, 0, Vector2.ZERO, body_angle)
		7:
			_layer(0, 1, 0, Vector2.ZERO, body_angle)
			# Native flags 0x40: additive, with independently animated opacity.
			_layer(1, 0, 0, Vector2.ZERO, body_angle, Color(1, 1, 1, 0.5 - float(tick % 30) * 0.01), true)
			_layer(2, 4, 4, mount, -deg_to_rad(float(tick % 180) * 2), Color(150.0 / 255, 150.0 / 255, 1, 1 - float(tick % 30) * 0.01), true)
			_layer(3, 2 + (tick / 6) % 2, 0, Vector2.ZERO, body_angle)
		9:
			_layer(0, 29 + phase % 6 if moving else 12 + idle_phase, 0, Vector2.ZERO, body_angle)
			_layer(1, 23 + phase % 6 if moving else 1 + idle_phase, 1, mount, gun_angle)
		10:
			var step := phase % 8 if moving else 0
			_layer(0, 9 + step, 0, Vector2.ZERO, body_angle, Color(0.6, 0.6, 0.6))
			_layer(1, 1 + step, 1, mount, gun_angle)
			_layer(2, 17 + step, 0, Vector2.ZERO, body_angle)

func _layer(slot: int, index: int, reference: int, anchor: Vector2, angle: float, tint := Color.WHITE, add := false) -> void:
	if index < 0 or index >= frames.size():
		return
	var frame: Dictionary = frames[index]
	var origin: Dictionary = frames[reference]
	var key := "%d/%s" % [vehicle, str(frame.file)]
	if not texture_cache.has(key):
		texture_cache[key] = load("res://assets/tanks/" + key)
	var layer := layers[slot]
	layer.texture = texture_cache[key]
	layer.position = anchor
	layer.rotation = angle
	layer.flip_h = mirrored
	var pivot := Vector2(float(origin.pivot[0]), float(origin.pivot[1]))
	if mirrored:
		pivot.x = float(origin.size[0]) - 1 - pivot.x
	layer.offset = -pivot
	layer.modulate = tint
	layer.material = additive if add else null
	layer.visible = true

func _state(name: String, enabled: bool, angle: float) -> void:
	var layer: Sprite2D = states[name]
	layer.visible = enabled
	if not enabled:return
	var sequence := _state_frames(name)
	if sequence.is_empty():return
	var frame: Dictionary = sequence[(tick / 4) % sequence.size()]
	var key := "%s/%s" % [name, str(frame.file)]
	if not texture_cache.has(key):texture_cache[key] = load("res://assets/effects/" + key)
	layer.texture = texture_cache[key]
	layer.offset = -Vector2(float(frame.pivot[0]), float(frame.pivot[1]))
	layer.rotation = angle
	layer.modulate.a = 0.5 if name == "StateStealth" else 1.0
