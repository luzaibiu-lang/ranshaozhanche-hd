extends Node2D
## Empty shot: 00537ee0 starts ten puffs, emitted every five native ticks
## at the current muzzle by 005359b0. 004b5ac0 draws Effect50 frame zero.
const PUFF_COUNT := 10
const PUFF_GAP := 5
const PUFF_LIFETIME := 22
const PATH := "res://assets/effects/Effect50/00.png"
const BARREL_LENGTHS := [18, 15, 6, 10, 10, 23, 5, 15, 15, 15]
const NativeVehicle = preload("res://native_vehicle.gd")

var world: Control
var smoke: Texture2D
var pivot: Vector2
var tick := 0.0
var emitters: Dictionary = {}
var puffs: Array[Dictionary] = []

func _ready() -> void:
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	smoke = world.texture(PATH)
	var frames: Array = JSON.parse_string(FileAccess.get_file_as_string(PATH.get_base_dir() + "/frames.json"))
	pivot = Vector2(frames[0].pivot[0], frames[0].pivot[1])

func clear_smoke() -> void:
	tick = 0.0
	emitters.clear()
	puffs.clear()
	queue_redraw()

func emit_smoke(unit: Dictionary, elevation: float, face: int) -> void:
	var seat := int(unit.seat)
	_spawn(unit, elevation, face, tick)
	emitters[seat] = {"remaining": PUFF_COUNT - 1, "next": tick + PUFF_GAP,
		"unit": unit, "elevation": elevation, "face": face}
	queue_redraw()

func _process(delta: float) -> void:
	if emitters.is_empty() and puffs.is_empty():
		return
	tick += delta * 60.0
	for seat: int in emitters.keys():
		var emitter: Dictionary = emitters[seat]
		var current: Dictionary = emitter.unit
		var elevation := float(emitter.elevation)
		var face := int(emitter.face)
		for unit: Dictionary in world.battle.get("units", []):
			if int(unit.seat) == seat:
				current = unit
				if int(unit.player) == world.player_id and seat == int(world.battle.active):
					elevation = world.angle
					face = world.preview_face if world.preview_face != 0 else int(unit.get("face", face))
				else:
					elevation = float(unit.get("elevation", elevation))
					face = int(unit.get("face", face))
				break
		while int(emitter.remaining) > 0 and tick >= float(emitter.next):
			if tick - float(emitter.next) <= PUFF_LIFETIME:
				_spawn(current, elevation, face, float(emitter.next))
			emitter.remaining -= 1
			emitter.next += PUFF_GAP
		if int(emitter.remaining) == 0:
			emitters.erase(seat)
	for index in range(puffs.size() - 1, -1, -1):
		if tick - float(puffs[index].born) > PUFF_LIFETIME:
			puffs.remove_at(index)
	queue_redraw()

func _spawn(unit: Dictionary, elevation: float, face: int, born: float) -> void:
	var key := str(int(unit.seat))
	var slope := float(world.render_slopes.get(key, unit.get("slope", 0)))
	var heading := slope + (180.0 - elevation if face < 0 else elevation)
	if not bool(world.battle.get("native_aim", false)):
		heading = elevation
	var position_now: Vector2 = world.render_positions.get(key, Vector2(unit.x, unit.y))
	var vehicle := int(unit.vehicle)
	var length := float(BARREL_LENGTHS[(vehicle - 1) % BARREL_LENGTHS.size()])
	var mount := NativeVehicle.mount_offset(vehicle, face, slope)
	var barrel := Vector2.from_angle(-deg_to_rad(heading)) * length
	var muzzle := position_now + mount + barrel
	var smoke_angle := -deg_to_rad(heading + randi_range(-10, 9))
	var drift := Vector2.from_angle(smoke_angle)
	puffs.append({"born": born, "muzzle": muzzle, "drift": drift,
		"rotation": smoke_angle, "travel": float(randi_range(30, 49))})

func _draw() -> void:
	for puff: Dictionary in puffs:
		var age := clampf(tick - float(puff.born), 0.0, PUFF_LIFETIME)
		var progress := age / PUFF_LIFETIME
		# 00480e70 starts a type-3 linear polar motion at four degrees per tick.
		var travel := minf(age * 4.0 / 90.0, 1.0) * float(puff.travel)
		var at: Vector2 = puff.muzzle + puff.drift * travel
		draw_set_transform(world.screen(at), float(puff.rotation), Vector2.ONE * (0.1 + 0.3 * progress) * world.zoom)
		draw_texture(smoke, -pivot, Color(1, 1, 1, maxf(0.8 - progress, 0.0)))
	draw_set_transform(Vector2.ZERO)
