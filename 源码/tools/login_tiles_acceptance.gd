extends SceneTree
var options := {}
var screen: Control
var checks: Array[String] = []
var motion_frames: Array[Dictionary] = []
var cues: Array[int] = []

func move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:options[pair[0]] = pair[1]
	_run.call_deferred()
func expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true
func picture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name + ".png"))
func motion_picture(index: int, point: Vector2) -> void:
	await create_timer(.065).timeout
	var label := "motion-%02d" % index
	await picture(label)
	motion_frames.append({"file":label+".png","cursor":[point.x,point.y]})
func _run() -> void:
	if OS.has_feature("windows"):
		var packs := OS.get_executable_path().get_base_dir().path_join("packs")
		if DirAccess.dir_exists_absolute(packs):
			for file in DirAccess.get_files_at(packs):
				if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file), false)
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	screen = load("res://native_login_page.gd").new()
	var theme := Theme.new()
	theme.default_font = load("res://game_platform.gd").ui_font()
	screen.theme = theme
	root.add_child(screen)
	await create_timer(.5).timeout
	if not expect(screen.tiles.size() > 30, "full-screen original background split into tiles"):return
	await picture("login-idle")
	var field_rect: Rect2 = screen.username.get_global_rect()
	var cell: Dictionary = {}
	for candidate: Dictionary in screen.tiles:
		if Rect2(40, 100, 250, 500).has_point(candidate.center):
			cell = candidate
			break
	if not expect(not cell.is_empty(), "visible background tile selected"):return
	cell.node.rotate_solid(Vector3.UP, PI / 2)
	await picture("login-edge-on")
	var image := root.get_texture().get_image()
	var middle := Vector2i(cell.center)
	var core := image.get_pixelv(middle)
	if not expect(core.r > 0.45 and absf(core.r-core.g) < 0.03 and absf(core.g-core.b) < 0.03, "edge-on tile shows neutral core in actual rendered frame"):return
	var thickness := 0
	for dx in range(-roundi(screen.tile_size/4),roundi(screen.tile_size/4)):
		var pixel := image.get_pixelv(middle + Vector2i(dx,0))
		if maxf(pixel.r,maxf(pixel.g,pixel.b)) > 0.08:thickness += 1
	if not expect(absf(thickness - screen.tile_size*20/128) <= 2, "edge-on rendered silhouette has original 20/128 thickness"):return
	cell.node.rotate_solid(Vector3.UP, PI * 0.35)
	await picture("login-solid")
	cell.node.rotate_solid(Vector3.UP, 0)
	screen.cue_requested.connect(func(id: int):cues.append(id))
	move_pointer(cell.center + Vector2(screen.tile_size, 0))
	move_pointer(cell.center)
	if not expect(cues.count(2) == 1, "crossing a tile starts one hover sound"):return
	await create_timer(.1).timeout
	if not expect(absf(cell.angle) > .35 and cell.node.polygon != cell.base, "crossing drives a visible 3D swing"):return
	var started: float = cell.started
	move_pointer(cell.center + Vector2(3,0))
	if not expect(cues.count(2) == 1 and cell.started == started, "motion within a tile does not retrigger"):return
	for index in range(8):await motion_picture(index, cell.center)
	if not expect(screen.username.get_global_rect() == field_rect, "background never moves the input field"):return
	if not expect(screen.tiles.all(func(t):return t == cell or is_zero_approx(t.angle)), "unvisited neighbors stay still"):return
	await picture("login-hover")
	move_pointer(cell.center)
	var next_point: Vector2 = cell.center + Vector2(screen.tile_size,0)
	move_pointer(next_point)
	if not expect(cues.count(2) == 2, "crossing another tile produces its own sound"):return
	for index in range(8):await motion_picture(index+8, next_point)
	move_pointer(Vector2(-100, -100))
	for index in range(10):await motion_picture(index+16, Vector2(-100,-100))
	if not expect(is_zero_approx(cell.angle) and cell.node.polygon == cell.base, "completed swing restores the tile"):return
	for dimensions in [Vector2i(1000,650), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(430,900)]:
		root.size = dimensions
		await create_timer(.2).timeout
		for field in [screen.username,screen.password,screen.submit,screen.mode_button]:
			if not expect(Rect2(Vector2.ZERO, screen.size).encloses(field.get_global_rect()), "form stays in viewport at " + str(dimensions)):return
		await picture("login-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1440,900)
	screen.queue_free()
	await process_frame
	screen = load("res://native_login_page.gd").new()
	screen.registering = true
	screen.theme = theme
	root.add_child(screen)
	await create_timer(.3).timeout
	if not expect(screen.confirmation.visible and not screen.remember.visible, "registration uses the same layout with password confirmation"):return
	await picture("registration")
	screen.begin_exit()
	await create_timer(.5).timeout
	if not expect(screen.form.modulate.a < .01 and screen.submit.disabled, "leaving screen fades only the form and stops input"):return
	FileAccess.open(str(options.output).path_join("tiles-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks,"hover_cues":cues,"input_stable":true}))
	FileAccess.open(str(options.output).path_join("motion-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(motion_frames))
	quit()
