extends SceneTree
## Exercise actual form/buttons/input inside one isolated native game process.
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
		print("FIDELITY_UI_STATE " + JSON.stringify({"scene": app.scene, "toast": app.toast_label.text, "profile": app.profile, "busy": app.command_busy}))
		root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
		push_error("FIDELITY_UI: " + message)
		quit(2)
		return false
	checks.append(message)
	return true

func click(control: Control) -> void:
	if not check(is_instance_valid(control), "click target exists"):return
	var position := control.get_global_rect().get_center()
	var window := control.get_viewport() as Window
	if window != root:position += Vector2(window.position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await create_timer(0.12).timeout

func wait_for(condition: Callable, message: String) -> bool:
	for attempt in range(100):
		if condition.call():return check(true, message)
		await create_timer(0.1).timeout
	return check(false, message)

func button(hint: String) -> Button:
	for child in app.skin.get_children():
		if child is Button and child.tooltip_text == hint:return child
	return null

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name + ".png"))

func _run() -> void:
	var bootstrap:Node=load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(0.5).timeout
	app=bootstrap.get_child(0)
	if not await wait_for(func():return not app.catalog.is_empty(),"catalog loaded"):return
	await click(app.skin.find_child("ToggleRegistration",true,false))
	app.username.text=str(options.name)
	app.password.text="qa-only-895432"
	app.confirmation.text="qa-only-895432"
	await click(app.skin.find_child("Login",true,false))
	if not await wait_for(func():return app.scene=="lobby","registered through real form"):return
	var guest:=preload("res://net.gd").new(app)
	guest.endpoint=app.net.endpoint
	var response:Dictionary=await guest.request("/api/register",{"name":str(options.name)+"b","password":"qa-only-895432"})
	if not check(response.has("token"),"second human test participant registered"):return
	guest.token=str(response.token)
	await click(button("道具商店"))
	if not await wait_for(func():return app.scene=="shop","real combat shop opened"):return
	var supplies: bool = options.has("supplies")
	var item_ids := [5, 6, 7] if supplies else [2, 3, 4, 9]
	for i in range(item_ids.size()):
		var shop:Control=app.native_shop
		if not shop.item_buttons[item_ids[i]].visible:
			for attempt in range(5):
				await click(shop.layout.get_node("ShopPage2Right"))
				if shop.item_buttons[item_ids[i]].visible:break
		await click(shop.item_buttons[item_ids[i]])
		await click(shop.buy_button)
		if not await wait_for(func():return int(app.profile.inventory[i])==item_ids[i],"actual purchase equips item "+str(item_ids[i])):return
	await click(button("返回"))
	await click(button("创建房间"))
	var form:ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:form=child
	await click(form.get_ok_button())
	if not await wait_for(func():return app.scene=="room","room created"):return
	await app._command({"action":"settings","map":9})
	response=await guest.request("/api/command",{"action":"join","room":int(app.snapshot.room.id)})
	if not check(response.get("room") is Dictionary,"second human joined"):return
	await app._poll()
	await click(app.start_button)
	if not await wait_for(func():return app.scene=="battle","actual start enters battle"):return
	for slot in range(item_ids.size()):
		for attempt in range(500):
			await app._poll()
			var battle:Dictionary=app._battle_data()
			if app._my_turn():break
			if float(battle.get("deadline",0))>0:
				var active:Dictionary=app._active()
				if int(active.get("player",0))!=int(app.profile.id):
					await guest.request("/api/command",{"action":"pass","generation":int(battle.generation)})
			await create_timer(0.08).timeout
		if not check(app._my_turn(),"turn reached item "+str(item_ids[slot])):return
		var focused:=root.gui_get_focus_owner()
		if focused:focused.release_focus()
		var key:=InputEventKey.new()
		key.physical_keycode=KEY_F5+slot
		key.pressed=true
		root.push_input(key)
		if not await wait_for(func():return int(app.profile.inventory[slot])==0,"actual F-key consumes item "+str(item_ids[slot])):return
		if supplies:
			var amount: int = [50, 100, 40][slot]
			if not await wait_for(func():return app.view.supply_numbers.any(func(cue: Dictionary) -> bool: return int(cue.amount) == amount), "live battle rendered supply +" + str(amount)):return
			if not check(app.view.supply_numbers.size() == 1, "the newest supply number replaces the old one for this tank"):return
			await screenshot("supply-" + str(amount))
			continue
		await app._battle_command({"action":"fire","angle":float(app.aim),"aim_mode":"native","power":0.1 if slot==2 else 0.45,"weapon":0})
		var projectile:int=[100,101,102,104][slot]
		if not await wait_for(func():return app._battle_data().get("shot") is Dictionary and int(app._battle_data().shot.trails[0].projectile)==projectile,"item emits correct native projectile "+str(projectile)):return
		if not await wait_for(func():return app.view.projectile_frames.has(projectile),"item projectile has actual loaded native frames "+str(projectile)):return
		if slot==0 and not check(is_equal_approx(float(app._battle_data().shot.trails[0].duration),3.5),"grenade retains 210-tick fuse in live match"):return
		if slot==2:
			var shot:Dictionary=app._battle_data().shot
			var portal:Dictionary={}
			for trail:Dictionary in shot.trails:
				if str(trail.kind)=="warp_portal":portal=trail
			if not check(not portal.is_empty(),"native Warp landing has opening and fading portal"):return
			while app.net.server_now()<float(shot.started)+float(portal.start)+0.12:
				await create_timer(0.03).timeout
			await screenshot("warp-opening")
			await create_timer(0.6).timeout
			await screenshot("warp-fading")
		await screenshot("item-"+str(projectile))
	await create_timer(0.4).timeout
	print("FIDELITY_UI_ACCEPTANCE "+JSON.stringify({"checks":checks,"normal_ui":true,"private_input_only":true}))
	await guest.request("/api/logout",{})
	await app._quit()
