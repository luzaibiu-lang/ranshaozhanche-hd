extends SceneTree
## Actual room input and rendered UI, isolated from the player's desktop.
var app: Node
var options := {}
var checks := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.profile).path_join("vault"))
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		push_error("ROOM_UI: " + message)
		root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
		quit(2)
		return false
	checks.append(message)
	return true

func wait_for(condition: Callable, message: String) -> bool:
	for attempt in range(100):
		if condition.call():return check(true, message)
		await create_timer(.1).timeout
	return check(false, message)

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var window := control.get_viewport() as Window
	if window != root:point += Vector2(window.position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await create_timer(.12).timeout

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func active_dialog() -> ConfirmationDialog:
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:return child
	return null

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(.5).timeout
	app = bootstrap.get_child(0)
	if not await wait_for(func():return not app.catalog.is_empty(), "catalog loaded"):return
	await click(app.skin.find_child("ToggleRegistration", true, false))
	app.username.text = str(options.name)
	app.password.text = "qa-only-room-895432"
	app.confirmation.text = "qa-only-room-895432"
	await click(app.skin.find_child("Login", true, false))
	if not await wait_for(func():return app.scene=="lobby", "registration entered actual lobby"):return
	await app._command({"action":"create", "name":"高清房间界面对比", "capacity":8, "map":1})
	if not await wait_for(func():return app.scene=="room", "room opened"):return
	for dimensions in [Vector2i(960,600), Vector2i(1440,900)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.3).timeout
		app.skin.reflow()
		await process_frame
		var practice: Button = app.skin.get_node("AIPractice")
		if not check(practice.get_global_rect().size.y>=29 and practice.is_visible_in_tree(), "clear AI action visible at "+str(dimensions)):return
		await click(practice)
		var dialog := active_dialog()
		if not check(dialog!=null, "actual AI button opened native dialog at "+str(dimensions)):return
		var locked: OptionButton = app.find_child("AIDifficulty00",true,false)
		if not check(locked.disabled, "human seat locked at "+str(dimensions)):return
		await screenshot("ai-dialog-%dx%d"%[dimensions.x,dimensions.y])
		for seat in [1,4,8,12]:
			var level: OptionButton = app.find_child("AIDifficulty%02d"%seat,true,false)
			level.select(2)
			level.item_selected.emit(2)
		await click(dialog.get_ok_button())
		if not await wait_for(func():return app.snapshot.room.members.size()==5, "confirmed four distinct AI seats"):return
		await process_frame
		for slot in app.room_grid.get_children():
			var child: Control = slot.get_child(0)
			if not child is Button and not check(child.size.is_equal_approx(slot.size), "human/AI card fills slot at "+str(dimensions)):return
		var empty: Control = app.room_grid.get_node("RoomSeat02").get_child(0)
		var region := Rect2i(empty.get_global_rect())
		await RenderingServer.frame_post_draw
		var lane_before := root.get_texture().get_image().get_region(region).get_data()
		var motion := InputEventMouseMotion.new()
		motion.position = empty.get_global_rect().get_center()
		root.push_input(motion)
		empty.grab_focus()
		await create_timer(.15).timeout
		await RenderingServer.frame_post_draw
		if not check(root.get_texture().get_image().get_region(region).get_data()==lane_before,"hover and focus preserve rendered native lane at "+str(dimensions)):return
		await screenshot("room-hover-%dx%d"%[dimensions.x,dimensions.y])
		var press := InputEventMouseButton.new()
		press.position = motion.position
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press)
		await RenderingServer.frame_post_draw
		if not check(root.get_texture().get_image().get_region(region).get_data()==lane_before,"pressed empty seat preserves rendered native lane at "+str(dimensions)):return
		press.pressed = false
		root.push_input(press)
		await process_frame
		if not await wait_for(func():return int(app._me().seat)==2, "empty slot click moves real player"):return
		await app._command({"action":"seat","seat":0})
		if not await wait_for(func():return int(app._me().seat)==0, "player returns to original seat"):return
		await screenshot("room-%dx%d"%[dimensions.x,dimensions.y])
	await app._command({"action":"leave"})
	await app._command({"action":"create","name":"四人房回归","capacity":4,"map":1})
	await click(app.skin.get_node("AIPractice"))
	var limited := active_dialog()
	if not check(limited != null and "4 人" in limited.title, "AI dialog uses actual four-player capacity"):return
	for seat in [1,4,8,12]:
		var level: OptionButton = limited.find_child("AIDifficulty%02d"%seat,true,false)
		level.select(2)
		level.item_selected.emit(2)
	if not check(limited.get_ok_button().disabled, "over-capacity confirmation disabled before sending"):return
	var extra: OptionButton = limited.find_child("AIDifficulty12",true,false)
	var retained: OptionButton = limited.find_child("AIVehicle04",true,false)
	retained.select(retained.get_item_index(22))
	extra.select(0)
	extra.item_selected.emit(0)
	if not check(not limited.get_ok_button().disabled and retained.get_selected_id()==22, "correcting over-capacity retains chosen vehicles"):return
	await click(limited.get_ok_button())
	if not await wait_for(func():return app.snapshot.room.members.size()==4 and active_dialog()==null, "valid corrected choices saved"):return
	var map_action := {"action":"settings","map":2}
	app._command(map_action)
	app.chat_input.text = "换图期间发送"
	app._send_chat()
	app._send_chat()
	if not await wait_for(func():return app.chat_input.text=="" and int(app.snapshot.room.map)==2, "busy chat sent after map update"):return
	var matches := 0
	for line: Dictionary in app.snapshot.room.chat:
		if line.text=="换图期间发送":matches+=1
	if not check(matches==1,"duplicate Enter sends only once"):return
	app.chat_input.text="/w no_such_test_user test"
	await app._send_chat()
	if not check(app.chat_input.text=="/w no_such_test_user test","failed whisper keeps original input"):return
	app.chat_input.clear()
	await app._command({"action":"leave"})
	await app._command({"action":"create","name":"结算返回回归","capacity":4,"map":1})
	var room_id := int(app.snapshot.room.id)
	var friend: RefCounted = preload("res://net.gd").new(app)
	var enemy: RefCounted = preload("res://net.gd").new(app)
	for pair in [[friend,"f"],[enemy,"e"]]:
		var net: RefCounted=pair[0]
		net.endpoint=app.net.endpoint
		var auth: Dictionary=await net.request("/api/register",{"name":str(options.name)+str(pair[1]),"password":"qa-only-room-895432"})
		if not check(auth.has("token"),"second player session "+str(pair[1])):return
		net.token=auth.token
		var joined: Dictionary=await net.request("/api/command",{"action":"join","room":room_id})
		if not check(joined.has("profile"),"joined room "+str(pair[1])):return
		if pair[1]=="f":
			await net.request("/api/command",{"action":"seat","seat":1})
	await app._command({"action":"start"})
	if not check(app.scene=="battle", "registered players started match"):return
	await enemy.request("/api/command",{"action":"leave"})
	if not await wait_for(func():return is_instance_valid(app.result_layer), "match reaches settlement"):return
	await app._command({"action":"return"})
	if not await wait_for(func():return app.scene=="room", "first player returns before friend"):return
	if not check(app.start_button.disabled and app.map_choice.disabled and app.vehicle_picker.buttons[0].disabled and app.skin.get_node("AIPractice").disabled and "1 位" in app.room_title.text,"waiting room shows pending player and locks unavailable controls"):return
	await create_timer(.6).timeout
	await screenshot("waiting-room")
	await friend.request("/api/command",{"action":"leave"})
	if not await wait_for(func():return not app.start_button.disabled and not app.map_choice.disabled and not app.vehicle_picker.buttons[0].disabled, "last unreturned player leaving reopens room"):return
	await app._command({"action":"vehicle","vehicle":29})
	if not check(int(app._me().vehicle)==29,"server accepts vehicle after pending player leaves"):return
	await app._command({"action":"leave"})
	print("ROOM_UI_ACCEPTANCE "+JSON.stringify({"checks":checks,"private_input_only":true,"muted":true}))
	await app._quit()
