extends SceneTree
var app: Control
var options := {}
var checks: Array[String] = []
func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size()==2:options[pair[0]]=pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.profile).path_join("vault"))
	_run.call_deferred()
func expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true
func wait_for(condition: Callable, message: String) -> bool:
	for attempt in range(240):
		if condition.call():return expect(true,message)
		await create_timer(.075).timeout
	return expect(false,message)
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event)
		await process_frame
	await create_timer(.12).timeout
func enter(field: LineEdit) -> void:
	field.grab_focus()
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode=KEY_ENTER
		event.physical_keycode=KEY_ENTER
		event.pressed=pressed
		root.push_input(event)
		await process_frame
func picture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(str(options.stage)+"-"+label+".png"))
func wait_channel() -> bool:
	if not await wait_for(func():return is_instance_valid(app.channel_gate), "login reaches channel transition"):return false
	if str(options.stage)=="register" and app.channel_gate.phase=="closing":
		if not expect(is_instance_valid(app.login_transition) and not app.channel_gate.opaque_backdrop,"login remains under the closing mechanical doors"):return false
		await picture("door-closing")
	if not await wait_for(func():return app.channel_gate.phase=="select","channel selector ready"):return false
	if not expect(not is_instance_valid(app.login_transition),"covered login is released after the doors close"):return false
	await picture("channel")
	return true
func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await process_frame
	app=bootstrap.get_child(0)
	root.size=Vector2i(1440,900)
	if not await wait_for(func():return app.catalog_ready and app.scene=="login","normal startup reaches the tile login"):return
	if not expect(str(app.net.endpoint).begins_with("http://127.0.0.1:"),"isolated local service"):return
	await create_timer(1.5).timeout
	if not expect(app.scene=="login" and app.net.token.is_empty() and app.profile.is_empty() and not is_instance_valid(app.channel_gate),"startup waits for manual login even with remembered credentials or a legacy ticket"):return
	if OS.get_name()=="Windows":
		if not expect(not load("res://game_platform.gd").mobile_ui(),"Windows uses desktop UI independently of touchscreen capabilities"):return
		if not expect(not load("res://mobile_battle_controls.gd").touch_device(),"Windows does not create mobile battle controls"):return
	if not expect(FileAccess.file_exists("res://device_profile.js"),"shared browser profile is included in the exported game pack"):return
	for variant in range(7):
		var path := "res://assets/audio/sound/ui_screentile_00@%d.wav" % variant
		if not expect(ResourceLoader.exists(path) and load(path).get_length()>0,"original tile audio variant %d decodes" % variant):return
	app.sound.played_cues.clear()
	app.login_page._reset_pointer()
	app.login_page._track_pointer(Vector2(20,220))
	app.login_page._track_pointer(Vector2(250,220))
	if not expect(app.sound.played_cues.size()==1 and str(app.sound.played_cues[0]).begins_with("ui_screentile_00@"),"real login hover uses original variant instead of a generic beep"):return
	var secret := "qa-联机-895432"
	if options.stage=="register":
		await picture("login")
		await click(app.login_page.mode_button)
		app.username.text=options.name
		app.password.text=secret
		app.confirmation.text="different-password"
		await click(app.login_page.submit)
		if not expect(app.scene=="login" and app.login_page.notice.text.contains("两次输入"),"password mismatch is shown within the form"):return
		app.confirmation.text=secret
		await picture("registration")
		await click(app.login_page.submit)
		if not await wait_channel():return
		await click(app.channel_gate.row)
		await click(app.channel_gate.enter_button)
		if not await wait_for(func():return app.scene=="lobby" and not is_instance_valid(app.channel_gate),"selector opens into original lobby"):return
		await click(app.skin.get_node("Logout"))
		if not await wait_for(func():return app.scene=="login" and not app.auth_busy,"logout returns to the same login design"):return
		app.password.text="incorrect-password"
		await enter(app.password)
		if not await wait_for(func():return not app.auth_busy and app.login_page.notice.text.contains("账号或密码错误"),"wrong password remains recoverable"):return
		app.password.text=secret
		await click(app.remember)
		await enter(app.password)
		if not await wait_channel():return
		if not expect(FileAccess.file_exists(str(options.profile).path_join("vault/account.dat")),"remember account uses actual Windows encrypted helper"):return
	elif options.stage=="remembered":
		if not expect(app.username.text==str(options.name) and app.password.text==secret and app.remember.button_pressed,"encrypted saved account prefills the new form after restart"):return
		await picture("prefilled")
		await click(app.remember)
		if not expect(not FileAccess.file_exists(str(options.profile).path_join("vault/account.dat")),"unchecking remember clears the encrypted account"):return
		await enter(app.password)
		if not await wait_channel():return
	else:
		if not expect(app.password.text.is_empty() and not app.remember.button_pressed and app.net.token.is_empty(),"restart without remember remains at empty-password login"):return
	if options.stage=="handoff":
		if not expect(not FileAccess.file_exists(str(options.profile).path_join("vault/handoff/"+str(options.ticket)+".dat")),"valid legacy ticket is consumed without authenticating startup"):return
	FileAccess.open(str(options.output).path_join(str(options.stage)+"-flow.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"stage":options.stage,"checks":checks,"normal_ui":not app.qa}))
	await app._quit()
