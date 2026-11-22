extends SceneTree

var view: Control
var layer: Node2D
var audio: Node
var out: String
var checks: Array[String] = []

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	out = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func check(passed: bool, name: String) -> bool:
	if not passed:
		push_error(name)
		quit(2)
		return false
	checks.append(name)
	return true

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not name.is_empty():
		image.save_png(out.path_join(name + ".png"))
	return image

func _run() -> void:
	var packs := OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):
				ProjectSettings.load_resource_pack(packs.path_join(file), false)
	root.size = Vector2i(1280, 800)
	view = load("res://world_view.gd").new()
	view.player_id = 1
	root.add_child(view)
	view.size = Vector2(1280, 800)
	view.set_process(false)
	view.scenery.hide()
	view.overlay.hide()
	view.reticle.hide()
	layer = view.failure_layer
	layer.set_process(false)
	audio = load("res://sound.gd").new()
	root.add_child(audio)
	view.effect.connect(func(kind: String, id: int): audio.play_effect(kind, id))
	var unit := {"seat": 0, "player": 1, "team": 0, "vehicle": 1, "hp": 300,
		"x": 768, "y": 512, "slope": 10, "face": 1, "elevation": 35}
	var battle := {"id": "misfire", "map": 9, "width": 1536, "height": 1024,
		"native_aim": true, "active": 0, "deadline": 130, "units": [unit]}
	view.set_battle(battle)
	await process_frame
	view.camera = Vector2(768, 512)
	view.zoom = 2.0
	view.screen_origin = view.size / 2.0 - view.camera * view.zoom
	var flat := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color("203850"))
	view.background = ImageTexture.create_from_image(flat)
	view.terrain_image = null
	view.queue_redraw()
	var baseline := await capture("")
	view.fire_failed(unit, 35, 1)
	if not check(audio.played_cues == ["effect02.wav"], "Original misfire sound reaches the production mixer once"): return
	var right: Vector2 = layer.puffs[0].muzzle
	if not check(right.distance_to(Vector2(776.5, 477.8)) < 2, "Right-facing sloped muzzle matches the original mount and barrel length"): return
	var image := await capture("misfire-puff")
	var center: Vector2 = view.screen(right)
	var bright := 0
	var dark := 0
	var changed_away := 0
	for y in range(floori(center.y) - 22, floori(center.y) + 22):
		for x in range(floori(center.x) - 22, floori(center.x) + 22):
			var previous := baseline.get_pixel(x, y)
			var after := image.get_pixel(x, y)
			if after.r > previous.r + 0.015:
				bright += 1
				if Vector2(x, y).distance_to(center) > 16:
					changed_away += 1
			if after.r < previous.r - 0.005 or after.g < previous.g - 0.005 or after.b < previous.b - 0.005:
				dark += 1
	if not check(bright > 10 and dark == 0 and changed_away == 0, "Original smoke is visible only near the muzzle with no dark rectangle"): return
	var emitted := 1
	for step in range(1, 10):
		layer._process(5.0 / 60.0)
		for puff: Dictionary in layer.puffs:
			if is_equal_approx(float(puff.born), float(step * 5)):
				emitted += 1
	if not check(emitted == 10 and layer.emitters.is_empty(), "Ten puffs are emitted at five-tick intervals"): return
	layer._process(23.0 / 60.0)
	if not check(layer.puffs.is_empty(), "All smoke expires after its native lifetime"): return
	unit.face = -1
	view.fire_failed(unit, 35, -1)
	var left: Vector2 = layer.puffs[0].muzzle
	if not check(left.x < 768 and left.y < 512, "Left-facing shot uses the mirrored muzzle"): return
	layer.clear_smoke()
	unit.face = 1
	view.preview_face = -1
	view.angle = 35
	view.fire_failed(unit, 35, -1)
	layer._process(5.0/60.0)
	if not check(layer.puffs.size()==2 and layer.puffs[1].muzzle.x<768,
		"following puffs retain the local aiming direction before server acknowledgement"):return
	for player in audio.players:
		player.stream=load("res://assets/audio/sound/shot01.wav")
		player.play()
	var sounds_before:int=audio.played_cues.size()
	audio.play_event(55)
	if not check(audio.played_cues.size()==sounds_before+1 and audio.played_cues.back()=="effect02.wav",
		"insufficient SP feedback remains audible when incidental sound channels are full"):return
	battle.id = "next-match"
	view.set_battle(battle)
	if not check(layer.puffs.is_empty() and layer.emitters.is_empty(), "Starting another battle clears the smoke"): return
	audio.shutdown()
	await audio.wait_for_shutdown()
	print("FAILURE_EFFECT_ACCEPTANCE " + JSON.stringify({"passed": true, "checks": checks}))
	quit(0)
