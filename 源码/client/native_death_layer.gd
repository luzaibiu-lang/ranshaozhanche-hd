extends Node2D
## CTank 00538020 starts the sequence once on fatal damage. 005359b0
## emits 13 blasts, followed by the centered Effect55 on the last pulse.
const FINAL_TICK := 120
const END_TICK := 240
const INTERVAL := 10
const BLASTS := ["Effect13", "Effect14", "Effect15"]
const FLASH := "Effect55"

var world: Control
var frames := {}
var battle_id := ""
var shot_id := -1
var events: Array[Dictionary] = []

func _ready() -> void:
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	for name_ in BLASTS + [FLASH]:
		var path := "res://assets/effects/%s/" % name_
		var sequence: Array = JSON.parse_string(FileAccess.get_file_as_string(path + "frames.json"))
		for frame: Dictionary in sequence:
			frame.texture = world.texture(path + str(frame.file))
		frames[name_] = sequence

func _process(_delta: float) -> void:
	if not world or not world.clock:
		return
	var current_id := str(world.battle.get("id", ""))
	if current_id != battle_id or world.battle.is_empty():
		battle_id = current_id
		shot_id = -1
		events.clear()
		queue_redraw()
	if world.battle.is_empty():
		return
	var shot: Variant = world.battle.get("shot")
	if shot is Dictionary and int(shot.id) != shot_id:
		shot_id = int(shot.id)
		for cue: Dictionary in shot.get("cues", []):
			if str(cue.kind) == "death":
				_add_event(shot, cue)
	var now: float = world.clock.server_now()
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		var tick := _tick(event, now)
		if tick > END_TICK:
			events.remove_at(index)
			queue_redraw()
			continue
		if tick < 0:
			continue
		var pulse := mini(tick, FINAL_TICK) / INTERVAL
		if pulse > int(event.last_pulse):
			event.last_pulse = pulse
			# After a stalled or resumed frame play only the current pulse.
			if tick - pulse * INTERVAL < INTERVAL:
				world.effect.emit("native", 39)
				if pulse * INTERVAL == FINAL_TICK:
					world.effect.emit("native", 49)
		queue_redraw()

func _add_event(shot: Dictionary, cue: Dictionary) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = ("%s:%s:%s" % [battle_id, shot.id, cue.seat]).hash()
	var blasts: Array[Dictionary] = []
	for tick in range(0, FINAL_TICK + 1, INTERVAL):
		var offset := Vector2(random.randi_range(-50, 49), random.randi_range(-50, 49))
		blasts.append({"offset": offset, "name": BLASTS[random.randi_range(0, 2)], "tick": tick})
	events.append({"start": float(shot.started) + float(cue.at), "origin": Vector2(cue.x, cue.y),
		"seat": int(cue.seat), "slope": float(cue.get("slope", 0)), "blasts": blasts, "last_pulse": -1})

func _tick(event: Dictionary, now: float) -> int:
	return floori((now - float(event.start)) * 60.0 + 0.00001)

func _draw() -> void:
	if not world or not world.clock:
		return
	var now: float = world.clock.server_now()
	for event: Dictionary in events:
		var tick := _tick(event, now)
		if tick < 0 or tick > END_TICK:
			continue
		for blast: Dictionary in event.blasts:
			var age := tick - int(blast.tick)
			if age < 0:
				break
			var sequence: Array = frames[blast.name]
			var frame_index := age / 4
			if frame_index < sequence.size():
				_sprite(sequence[frame_index], event.origin + blast.offset, Vector2.ONE, 0, 1)
		if tick >= FINAL_TICK:
			# 004b8170 expands Effect55 with half-sine easing for another 120 ticks.
			var progress := float(tick - FINAL_TICK) / FINAL_TICK
			var radius := 5.0 * sin(progress * PI / 2.0)
			var slope: float = float(world.render_slopes.get(str(event.seat), event.slope))
			_sprite(frames[FLASH][0], event.origin, Vector2(3.0, 1.0) * radius,
				-deg_to_rad(slope), 0.5 * (1.0 - progress))
	draw_set_transform(Vector2.ZERO)

func _sprite(frame: Dictionary, at: Vector2, sprite_scale: Vector2, angle: float, alpha: float) -> void:
	if alpha <= 0 or sprite_scale.y <= 0:
		return
	draw_set_transform(world.screen(at), angle, sprite_scale * world.zoom)
	draw_texture(frame.texture, -Vector2(frame.pivot[0], frame.pivot[1]), Color(1, 1, 1, alpha))
