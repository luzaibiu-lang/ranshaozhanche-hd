extends Node2D
## Native supply presentation: 0053d450 -> 004b56f0 / 004b7740.
## Effect30 is a ten-frame additive ring, five native ticks per frame.
## Its twenty Effect54 sparks are independent polar-motion particles.
const RING := "Effect30"
const SPARK := "Effect54"
const SCATTER := "Effect03"
const SCATTER_TICKS := 150.0
const TICKS := 60.0
const SPARK_COUNT := 20
const RING_SCALE := 1.6
const MAX_SECONDS := 3.05

var world: Control
var sequences: Dictionary = {}
var bursts: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var normal_layer: Node2D

func _ready() -> void:
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	normal_layer = Node2D.new()
	normal_layer.draw.connect(func(): _draw_samples(normal_layer, false))
	add_child(normal_layer)
	for name: String in [RING, SPARK, SCATTER]:
		var path := "res://assets/effects/%s/frames.json" % name
		sequences[name] = JSON.parse_string(FileAccess.get_file_as_string(path))
		for frame: Dictionary in sequences[name]:
			world.texture("res://assets/effects/%s/%s" % [name, frame.file])

func clear_effects() -> void:
	bursts.clear()
	impacts.clear()
	queue_redraw()
	normal_layer.queue_redraw()

func receive_supply(cue: Dictionary) -> void:
	if not world.clock or bool(cue.get("fuel", false)):
		return
	# New servers distinguish the team item's user from its other recipients.
	# Older servers still get a recovery burst instead of silently losing it.
	if not bool(cue.get("item_effect", true)):
		return
	var seat := int(cue.seat)
	if not world._number_visible(seat):
		return
	var age: float = world.clock.server_now() - float(cue.at)
	if age >= MAX_SECONDS:
		return
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:supply:%s" % [world.battle_id, cue.id])
	var sparks: Array[Dictionary] = []
	for index in range(SPARK_COUNT):
		var distance := float(random.randi_range(20, 139))
		var speed := float(random.randi_range(0, 99)) / 100.0 + 0.5
		var scale := float(random.randi_range(0, 49)) / 100.0 + 0.1
		var offset := Vector2(random.randi_range(-30, 29), random.randi_range(-20, 19))
		sparks.append({"distance": distance, "speed": speed, "scale": scale,
			"offset": offset, "duration": float(int(90.0 / speed))})
	bursts.append({"id": int(cue.id), "seat": seat, "at": float(cue.at),
		"position": Vector2(float(cue.x), float(cue.y)), "sparks": sparks})
	queue_redraw()

func _process(_delta: float) -> void:
	if not world.clock or (bursts.is_empty() and impacts.is_empty()):
		return
	var now: float = world.clock.server_now()
	bursts = bursts.filter(func(burst: Dictionary) -> bool:
		return now - float(burst.at) < MAX_SECONDS)
	impacts = impacts.filter(func(impact: Dictionary) -> bool:
		return now - float(impact.at) < SCATTER_TICKS / TICKS)
	queue_redraw()
	normal_layer.queue_redraw()

func receive_impact(at: Vector2, age: float) -> void:
	# 00560830 creates twenty independent 004ae920(0) particles, not
	# a flipbook explosion. The dedicated rescue item shares this feedback.
	if not world.clock or age >= SCATTER_TICKS / TICKS:
		return
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:heal:%d:%s" % [world.battle_id, world.shot_id, at])
	var sparks: Array[Dictionary] = []
	for index in range(20):
		var heading := deg_to_rad(float(random.randi_range(75, 104)))
		var speed := snappedf(float(random.randi_range(0, 99)) / 15.0, 0.001)
		sparks.append({"frame": random.randi_range(0, 4), "scale": float(random.randi_range(0, 49)) / 100.0 + 0.7,
			"offset": Vector2(random.randi_range(-50, 49), random.randi_range(-50, 49)),
			"velocity": Vector2(cos(heading), -sin(heading)) * speed})
	impacts.append({"position": at, "at": world.clock.server_now() - age, "sparks": sparks})
	queue_redraw()
	normal_layer.queue_redraw()

func visible_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if not world.clock or world.battle.is_empty():
		return samples
	var now: float = world.clock.server_now()
	for burst: Dictionary in bursts:
		if not world._number_visible(int(burst.seat)):
			continue
		var tick := (now - float(burst.at)) * TICKS
		if tick < 0.0 or tick >= MAX_SECONDS * TICKS:
			continue
		var frame := int(tick) / 5
		if frame < (sequences[RING] as Array).size():
			samples.append({"effect": RING, "frame": frame, "position": burst.position,
				"scale": RING_SCALE, "alpha": 1.0, "rotation": 0.0})
		for spark: Dictionary in burst.sparks:
			var duration := float(spark.duration)
			if tick > duration:
				continue
			var progress := clampf(tick / duration, 0.0, 1.0)
			# 00480e70 passes easing=1: 00480130 uses sine of 0..90 degrees.
			var travel := sin(deg_to_rad(minf(tick * float(spark.speed), 90.0))) * float(spark.distance)
			samples.append({"effect": SPARK, "frame": 0,
				"position": (burst.position as Vector2) + (spark.offset as Vector2) - Vector2(0, travel),
				"scale": float(spark.scale) * (1.0 - 0.9 * progress),
				"alpha": 1.0 - progress, "rotation": -PI / 2.0})
	for impact: Dictionary in impacts:
		var tick := (now - float(impact.at)) * TICKS
		if tick < 0 or tick >= SCATTER_TICKS:
			continue
		var remaining := 1.0 - tick / SCATTER_TICKS
		for index in range((impact.sparks as Array).size()):
			var spark: Dictionary = impact.sparks[index]
			var velocity: Vector2 = spark.velocity
			var at: Vector2 = impact.position + spark.offset + velocity * tick + Vector2(0, 0.09 * tick * maxf(0, tick - 1))
			var direction := velocity + Vector2(0, 0.18 * tick)
			var frame := int(spark.frame)
			samples.append({"effect": SCATTER, "frame": frame, "position": at, "scale": float(spark.scale) * remaining,
				"alpha": remaining, "rotation": direction.angle(), "additive": frame != 4,
				"copies": 2 if posmod(hash(Vector3i(index, int(tick), int(impact.position.x))), 2) == 0 else 1})
	return samples

func _draw() -> void:
	_draw_samples(self, true)

func _draw_samples(layer: Node2D, additive: bool) -> void:
	for sample: Dictionary in visible_samples():
		if bool(sample.get("additive", true)) != additive:
			continue
		var name := str(sample.effect)
		var frame: Dictionary = sequences[name][int(sample.frame)]
		var sprite: Texture2D = world.texture("res://assets/effects/%s/%s" % [name, frame.file])
		if not sprite:
			continue
		layer.draw_set_transform(world.screen(sample.position), float(sample.rotation),
			Vector2.ONE * float(sample.scale) * world.zoom)
		for copy in range(int(sample.get("copies", 1))):
			layer.draw_texture(sprite, -Vector2(float(frame.pivot[0]), float(frame.pivot[1])),
				Color(1, 1, 1, float(sample.alpha)))
	layer.draw_set_transform(Vector2.ZERO)
