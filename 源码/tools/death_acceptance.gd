extends SceneTree

class FrozenClock extends RefCounted:
	var now := 100.0
	func server_now() -> float: return now

var view: Control
var layer: Node2D
var audio: Node
var clock := FrozenClock.new()
var cues: Array[int] = []
var checks: Array[String] = []
var destination := ""

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	destination = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	if not ok:
		push_error(label)
		quit(2)
		return false
	checks.append(label)
	return true

func tick(value: int) -> void:
	clock.now = 100.5 + float(value) / 60.0
	layer._process(0.0)

func capture(label: String) -> void:
	for enabled in [true, false]:
		layer.visible = enabled
		layer.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var suffix := "on" if enabled else "off"
		root.get_texture().get_image().save_png(destination.path_join(label + "-" + suffix + ".png"))
	layer.visible = true

func _run() -> void:
	var packs := OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):
				ProjectSettings.load_resource_pack(packs.path_join(file), false)
	root.size = Vector2i(1366, 768)
	view = load("res://world_view.gd").new()
	view.clock = clock
	view.player_id = 1
	view.shake_enabled = false
	root.add_child(view)
	view.size = root.size
	view.set_process(false)
	for child in view.get_children():
		child.set_process(false)
		if child.get_script() and child.get_script().resource_path == "res://native_death_layer.gd":
			layer = child
	if not check(layer != null, "production battle creates death layer"): return
	audio = load("res://sound.gd").new()
	root.add_child(audio)
	view.effect.connect(func(kind: String, id: int):
		if kind == "native":
			cues.append(id)
			audio.play_effect(kind, id))
	var unit := {"seat": 4, "player": 1, "name": "Target", "team": 0, "vehicle": 1,
		"hp": 0, "max_hp": 300, "sp": 150, "move": 0.0, "face": 1, "aim": 35.0,
		"elevation": 35.0, "slope": 0.0, "falling": false, "shield": 0, "stun": 0,
		"stealth": 0, "blind": 0, "poison": 0, "burn": 0, "damage": 0, "x": 700.0, "y": 806.0}
	var death := {"kind": "death", "seat": 4, "at": 0.5, "x": 700.0, "y": 806.0}
	var shot := {"id": 1, "actor": 0, "started": 100.0, "duration": 5.0, "trails": [],
		"impacts": [], "cues": [death]}
	var battle := {"id": "death-qa", "map": 9, "width": 1536, "height": 1024, "native_aim": true,
		"active": 0, "round": 1, "generation": 1, "wind": 0, "deadline": 0.0,
		"units": [unit], "holes": [], "shot": shot, "result": null}
	view.set_battle(battle)
	view.overview = 0
	view.manual_until = INF
	view.camera = Vector2(700, 806)
	view.target_camera = view.camera
	view.zoom = 1.2
	view.zoom_target = 1.2
	view._process(0.0)
	tick(-1)
	if not check(cues.is_empty() and layer.events.size() == 1, "scheduled death stays silent before impact"): return
	for t in range(0, 121):
		tick(t)
		tick(t)
		if t == 36: await capture("pulse")
		if t == 41:
			battle.shot = shot.duplicate(true)
			battle.shot.id = 2
			battle.shot.cues = []
			view.set_battle(battle)
		if t % 10 == 0:
			if not check(cues.count(39) == t / 10 + 1, "one native pulse at tick %d" % t): return
			# Give the real audio mixer wall time to retire streams as it does at 60 Hz.
			await create_timer(10.0 / 60.0).timeout
	if not check(cues.count(49) == 1 and cues.size() == 14, "13 exp02 pulses and one exp12 finale"): return
	if not check(audio.played_cues.count("exp02.wav") == 13 and audio.played_cues.count("exp12.wav") == 1,
		"production mixer played every original sound"): return
	tick(180)
	await capture("flash")
	tick(241)
	await capture("expired")
	if not check(layer.events.is_empty(), "death flash expires after four seconds"): return
	battle.shot.id = 3
	battle.shot.cues = [death]
	view.set_battle(battle)
	tick(300)
	if not check(layer.events.is_empty() and cues.size() == 14, "late snapshot never replays expired death"): return
	var second := death.duplicate()
	second.seat = 7
	second.x = 850.0
	battle.shot.id = 4
	battle.shot.cues = [death, second, {"kind":"lock"}]
	view.set_battle(battle)
	tick(0)
	if not check(layer.events.size() == 2 and cues.count(39) == 15, "simultaneous deaths play independently"): return
	battle.id = "next-battle"
	battle.shot = null
	view.set_battle(battle)
	tick(1)
	if not check(layer.events.is_empty(), "new battle clears old explosions"): return
	print("DEATH_ACCEPTANCE " + JSON.stringify({"checks": checks, "sounds": cues}))
	audio.shutdown()
	await audio.wait_for_shutdown()
	audio.queue_free()
	view.queue_free()
	await process_frame
	quit()
