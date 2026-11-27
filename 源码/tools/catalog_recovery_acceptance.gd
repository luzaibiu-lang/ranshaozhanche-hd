extends SceneTree

var app: Node
var options: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.output).path_join("profile"))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.output).path_join("vault"))
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()

func wait_for(condition: Callable, label: String) -> bool:
	for attempt in range(240):
		if condition.call():
			return true
		await create_timer(.1).timeout
	push_error(label)
	await screenshot("failure")
	quit(2)
	return false

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join("windows-" + label + ".png"))

func dialog() -> ConfirmationDialog:
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:
			return child
	return null

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await process_frame
	app = bootstrap.get_child(0)
	if not str(app.net.endpoint).begins_with("http://127.0.0.1:"):
		quit(3)
		return
	await create_timer(.5).timeout
	app.username.text = str(options.name)
	app.password.text = "qa-only-895432"
	app.skin.find_child("Login", true, false).pressed.emit()
	if not await wait_for(func(): return app.catalog_ready and not app.catalog_loading, "catalog automatically recovered"): return
	if app.scene == "login":
		app.skin.find_child("Login", true, false).pressed.emit()
	if not await wait_for(func(): return is_instance_valid(app.channel_gate), "catalog and login did not recover"): return
	if not await wait_for(func(): return app.channel_gate.phase == "select", "channel gate ready"): return
	app.channel_gate._select()
	app.channel_gate._request_enter()
	if not await wait_for(func(): return app.scene == "lobby" and not is_instance_valid(app.channel_gate), "lobby"): return
	app._create_dialog()
	var form := dialog()
	if not await wait_for(func(): return form != null and is_instance_valid(form.name_field), "create form"): return
	if not await wait_for(func(): return form.name_field.text == str(options.name) + "的战场" and form.name_field.get_theme_font("font").has_char("战".unicode_at(0)), "Chinese room name font"): return
	await screenshot("create")
	form.get_ok_button().pressed.emit()
	if not await wait_for(func(): return app.scene == "room" and is_instance_valid(app.vehicle_picker), "room entry"): return
	app.find_child("VehicleCell1", true, false).pressed.emit()
	if not await wait_for(func(): return app.vehicle_picker.caption.text == "烈火", "actual vehicle caption"): return
	if not await wait_for(func(): return not app.command_busy and not is_instance_valid(app.page_transition), "room ready for seat selection"): return
	app.room_grid.get_node("RoomSeat12").get_child(0).pressed.emit()
	if not await wait_for(func(): return int(app._me().seat) == 12, "D1 seat"): return
	app.skin.get_node("AIPractice").pressed.emit()
	var ai := dialog()
	var level := ai.find_child("AIDifficulty04", true, false) as OptionButton
	var vehicle := ai.find_child("AIVehicle04", true, false) as OptionButton
	var human := ai.find_child("AIVehicle12", true, false) as OptionButton
	if not await wait_for(func(): return human.disabled and human.text == "烈火" and vehicle.item_count == 31, "complete human and AI vehicle options"): return
	level.select(3)
	level.item_selected.emit(3)
	if not await wait_for(func(): return not vehicle.disabled and vehicle.get_selected_id() == 0, "B1 hard AI random"): return
	await screenshot("ai")
	# Exercise the original stale disabled control even after a successful reload.
	human.clear()
	var ai_ref := weakref(ai)
	ai.get_ok_button().pressed.emit()
	if not await wait_for(func(): return app.snapshot.room.members.size() == 2 and ai_ref.get_ref() == null, "AI submission with disabled field cleared"): return
	app.start_button.pressed.emit()
	if not await wait_for(func(): return app.scene == "battle", "start game"): return
	await screenshot("battle")
	await app._quit()
