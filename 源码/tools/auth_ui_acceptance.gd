extends SceneTree
## Runs the normal release UI: no --qa flag, no direct auth API, real DPAPI.

var app: Node
var options := {}
var checks := []

func _initialize() -> void:
	# Mute only this process, before any game stream is loaded. This also
	# allows verification of the real Windows audio backend without sound.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	for argument in OS.get_cmdline_user_args():
		if "=" in argument:
			var pair := argument.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	OS.set_environment("LOCALAPPDATA",str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT",str(options.profile).path_join("vault"))
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		if is_instance_valid(app):
			root.get_texture().get_image().save_png(str(options.screenshot).trim_suffix(".png")+".failure.png")
			print("AUTH_UI failure scene="+str(app.scene)+" toast="+str(app.toast_label.text))
		push_error("AUTH_UI: "+message)
		quit(2)
		return false
	checks.append(message)
	return true

func click(control: Control) -> void:
	if not check(is_instance_valid(control),"click target exists"):return
	var point := control.get_global_rect().get_center()
	var viewport := control.get_viewport()
	if viewport is Window and viewport!=root:point+=Vector2((viewport as Window).position)
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
	await create_timer(0.1).timeout

func enter(field: LineEdit) -> void:
	field.grab_focus()
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode=KEY_ENTER
		event.physical_keycode=KEY_ENTER
		event.pressed=pressed
		field.get_viewport().push_input(event)
		await process_frame
	await create_timer(0.1).timeout

func wait_scene(expected: String) -> bool:
	for attempt in range(160):
		if app.scene==expected and not app.auth_busy and not app.command_busy:
			await process_frame
			return check(true,"reached "+expected)
		await create_timer(0.1).timeout
	return check(false,"expected "+expected+", actual "+app.scene)

func wait_idle() -> bool:
	for attempt in range(160):
		if not app.auth_busy and not app.command_busy:return true
		await create_timer(0.1).timeout
	return check(false,"request did not finish")

func toggle() -> void:
	await click(app.skin.find_child("ToggleRegistration",true,false))

func fill_form(secret: String, confirm := "") -> void:
	app.username.text=str(options.name)
	app.password.text=secret
	if app.register_mode:app.confirmation.text=confirm

func tooltip_button(hint: String) -> Button:
	for child in app.skin.get_children():
		if child is Button and child.tooltip_text==hint:return child
	return null

func visible_dialog() -> ConfirmationDialog:
	var dialog: ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:dialog=child
	return dialog

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(1.0).timeout
	app=bootstrap.get_child(0)
	for attempt in range(160):
		if app.catalog.has("vehicles"):break
		await create_timer(0.1).timeout
	if not check(app.catalog.has("vehicles"),"public catalog loaded"):return
	var stage := str(options.stage)
	if not await wait_scene("lobby" if stage=="resume" else "login"):return
	if stage=="register":
		for index in range(12):await toggle()
		if not check(not app.register_mode,"12 registration/login switches survived"):return
		await toggle()
		fill_form("qa-only-895432","mismatch")
		await click(app.skin.find_child("Login",true,false))
		if not check(app.scene=="login" and app.toast_label.text.contains("两次输入"),"password mismatch remains in form"):return
		fill_form("qa-only-895432","qa-only-895432")
		await click(app.skin.find_child("Login",true,false))
		if not await wait_scene("lobby"):return
		if not check(str(app.profile.name)==str(options.name),"registered through actual form"):return
		await click(app.skin.find_child("Logout",true,false))
		if not await wait_scene("login"):return
		await toggle()
		fill_form("qa-only-895432","qa-only-895432")
		await click(app.skin.find_child("Login",true,false))
		if not await wait_idle():return
		if not check(app.scene=="login" and app.toast_label.text.contains("已存在"),"duplicate registration reports existing account"):return
		await toggle()
		fill_form("incorrect-895432")
		await enter(app.password)
		if not await wait_idle():return
		if not check(app.scene=="login" and app.toast_label.text.contains("账号或密码错误"),"wrong password remains recoverable"):return
		fill_form("qa-only-895432")
		await click(app.remember)
		if not check(app.remember.button_pressed,"remember login selected by click"):return
		await enter(app.password)
		if not await wait_scene("lobby"):return
		if not check(FileAccess.file_exists(str(options.profile).path_join("vault/session.dat")),"actual DPAPI helper saved session"):return
	elif stage=="resume":
		if not check(str(app.profile.name)==str(options.name),"automatic login restored same account"):return
		await click(tooltip_button("道具商店"))
		if not await wait_scene("shop"):return
		if not check(app.native_shop.item_buttons.size()==17,"native shop contains all 17 items after real login"):return
		await click(tooltip_button("返回"))
		if not await wait_scene("lobby"):return
		await click(tooltip_button("创建房间"))
		var dialog := visible_dialog()
		if not check(is_instance_valid(dialog),"create room dialog opened"):return
		await click(dialog.get_ok_button())
		if not await wait_scene("room"):return
		await click(app.skin.find_child("AIPractice",true,false))
		dialog=visible_dialog()
		if not check(is_instance_valid(dialog),"integrated AI dialog opened"):return
		var difficulty := app.find_child("AIDifficulty04",true,false) as OptionButton
		if not check(is_instance_valid(difficulty),"AI group B seat exists"):return
		difficulty.select(2)
		difficulty.item_selected.emit(2)
		await click(dialog.get_ok_button())
		if not await wait_idle():return
		if not check(app.snapshot.room.members.size()==2,"AI room configuration applied"):return
		await click(app.start_button)
		if not await wait_scene("battle"):return
		await create_timer(0.8).timeout
		await click(app.hud_buttons.menu)
		var menu: Control = app.content.get_node("NativeMenu")
		if not check(is_instance_valid(menu),"native battle menu opened"):return
		await click(menu.panel.get_node("LeaveMatch"))
		await process_frame
		dialog=visible_dialog()
		if not check(is_instance_valid(dialog),"leave battle confirmation opened"):return
		await click(dialog.get_ok_button())
		if not await wait_scene("lobby"):return
		await click(app.skin.find_child("Logout",true,false))
		if not await wait_scene("login"):return
		if not check(not FileAccess.file_exists(str(options.profile).path_join("vault/session.dat")),"logout removed encrypted credential"):return
	elif stage=="after-logout":
		if not check(app.net.token.is_empty(),"restart after logout stays at login"):return
		fill_form("qa-only-895432")
		if app.remember.button_pressed:await click(app.remember)
		await click(app.skin.find_child("Login",true,false))
		if not await wait_scene("lobby"):return
		if not check(not FileAccess.file_exists(str(options.profile).path_join("vault/session.dat")),"unchecked remember leaves no credential"):return
	elif stage=="not-remembered":
		if not check(app.net.token.is_empty(),"unremembered account stays logged out on restart"):return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(str(options.screenshot))
	print("AUTH_UI_ACCEPTANCE "+JSON.stringify({"stage":stage,"normal_ui":not app.qa,"checks":checks,"scene":app.scene}))
	app._quit()
