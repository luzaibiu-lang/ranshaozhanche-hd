extends SceneTree
var options := {}
var screen: Control
var checks: Array[String] = []
var motion_frames: Array[Dictionary] = []
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
	var before: Vector2 = cell.node.position
	var motion := InputEventMouseMotion.new()
	motion.position = cell.center
	root.push_input(motion)
	for index in range(8):await motion_picture(index, cell.center)
	if not expect(float(cell.amount) > .9, "hover activates the pointed tile"):return
	if not expect(cell.node.position.distance_to(before) > 4, "pointed tile visibly lifts"):return
	if not expect(screen.username.get_global_rect() == field_rect, "background never moves the input field"):return
	if not expect(screen.tiles.any(func(t):return t != cell and float(t.amount) > .01), "neighboring tiles respond"):return
	await picture("login-hover")
	motion = InputEventMouseMotion.new()
	motion.position = cell.center + Vector2(screen.tile_size,0)
	root.push_input(motion)
	for index in range(8):await motion_picture(index+8, motion.position)
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(-100, -100)
	root.push_input(motion)
	for index in range(10):await motion_picture(index+16, Vector2(-100,-100))
	if not expect(float(cell.amount) < .002, "pointer exit smoothly resets hover"):return
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
	FileAccess.open(str(options.output).path_join("tiles-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks,"hover":true,"neighbor_response":true,"input_stable":true}))
	FileAccess.open(str(options.output).path_join("motion-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(motion_frames))
	quit()
