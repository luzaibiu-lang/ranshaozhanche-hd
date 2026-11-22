extends SceneTree
var app: Node
var options := {}
var checks := []
var captures := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	OS.set_environment("LOCALAPPDATA",str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT",str(options.profile).path_join("vault"))
	_run.call_deferred()

func check(value:bool,message:String) -> bool:
	if not value:
		push_error("VEHICLE_PICKER: "+message)
		root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
		quit(2)
		return false
	checks.append(message)
	return true

func wait_for(condition:Callable,message:String) -> bool:
	for attempt in range(100):
		if condition.call():return check(true,message)
		await create_timer(.08).timeout
	return check(false,message)

func click(control:Control) -> void:
	var point:=control.get_global_rect().get_center()
	var window:=control.get_viewport() as Window
	if window!=root:point+=Vector2(window.position)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event)
		await process_frame
	await create_timer(.09).timeout

func screenshot(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func capture_parts(picker:Control,id:int,dimensions:Vector2i) -> void:
	var button:Button=picker.buttons[id%9]
	var neutral:=InputEventMouseMotion.new()
	neutral.position=Vector2(5,5)
	root.push_input(neutral)
	picker.selection.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var areas:={"cell":button.get_global_rect(),"preview":picker.preview.get_global_rect()}
	var prefix:="%02d-%dx%d"%[id,dimensions.x,dimensions.y]
	var image:=root.get_texture().get_image()
	for kind in areas:
		image.get_region(Rect2i(areas[kind])).save_png(str(options.output).path_join(prefix+"-"+kind+".png"))
	var icon:=button.icon
	var preview:Texture2D=picker.preview.texture
	button.icon=null
	picker.preview.texture=null
	await RenderingServer.frame_post_draw
	image=root.get_texture().get_image()
	for kind in areas:
		image.get_region(Rect2i(areas[kind])).save_png(str(options.output).path_join(prefix+"-"+kind+"-empty.png"))
	button.icon=icon
	picker.preview.texture=preview
	picker.selection.show()
	var picker_origin:Vector2=picker.layout.get_global_transform().origin
	captures.append({"id":id,"window":[dimensions.x,dimensions.y],"prefix":prefix,"scale":picker.logical_scale,"cell_size":[button.size.x,button.size.y],"preview_size":[picker.preview.size.x,picker.preview.size.y],"cell_origin":[areas.cell.position.x,areas.cell.position.y],"preview_origin":[areas.preview.position.x,areas.preview.position.y],"picker_origin":[picker_origin.x,picker_origin.y]})

func _run() -> void:
	var bootstrap:Node=load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(.5).timeout
	app=bootstrap.get_child(0)
	if not await wait_for(func():return not app.catalog.is_empty(),"catalog loaded"):return
	await click(app.skin.find_child("ToggleRegistration",true,false))
	app.username.text=str(options.name)
	app.password.text="qa-only-picker-274813"
	app.confirmation.text="qa-only-picker-274813"
	await click(app.skin.find_child("Login",true,false))
	if not await wait_for(func():return app.scene=="lobby","actual registration enters lobby"):return
	await app._command({"action":"create","name":"原版选车居中核对","capacity":8,"map":1})
	if not await wait_for(func():return app.scene=="room","actual room is visible"):return
	var picker:Control=app.vehicle_picker
	for dimensions in [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.35).timeout
		for id in range(31):
			while picker.page_index!=id/9:await click(picker.right)
			await click(picker.buttons[id%9])
			if not await wait_for(func():return int(app._me().vehicle)==id and not app.command_busy,"actual cell selects vehicle "+str(id)+" at "+str(dimensions)):return
			await capture_parts(picker,id,dimensions)
			if id in [8,17,26,30]:await screenshot("page-%d-%dx%d"%[id/9,dimensions.x,dimensions.y])
		for index in range(4,9):
			if not check(not picker.buttons[index].visible,"final page hides nonexistent vehicle slot "+str(index)):return
	print("VEHICLE_PICKER_ACCEPTANCE "+JSON.stringify({"checks":checks,"captures":captures,"muted":true,"private_input_only":true}))
	await app._quit()
