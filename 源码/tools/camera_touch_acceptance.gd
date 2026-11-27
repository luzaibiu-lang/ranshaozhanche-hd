extends SceneTree
var world: Control
var checks: Array[String] = []
var output := ""
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	output=OS.get_cmdline_user_args()[0]
	_run.call_deferred()
func check(ok:bool,message:String) -> bool:
	if not ok:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true
func motion(index:int,at:Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=index
	event.position=at
	root.push_input(event)
	await process_frame
func touch(index:int,at:Vector2,pressed:bool) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.position=at
	event.pressed=pressed
	root.push_input(event)
	await process_frame
func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1280,720)
	world=load("res://world_view.gd").new()
	root.add_child(world)
	world.size=Vector2(1280,720)
	world.set_process(false)
	world.set_process_input(true)
	await process_frame
	world.battle={"width":3000,"height":1800}
	world.camera=Vector2(1500,900)
	world.target_camera=world.camera
	world.zoom=1.5
	world.zoom_target=1.5
	if not check(world._edge_direction(Vector2(30,360))==Vector2.LEFT,"map pans within 30 pixels of the left edge"):return
	if not check(world._edge_direction(Vector2(1250,360))==Vector2.RIGHT,"map pans within 30 pixels of the right edge"):return
	if not check(world._edge_direction(Vector2(640,30))==Vector2.UP,"map pans within 30 pixels of the top edge"):return
	if not check(world._edge_direction(Vector2(640,690))==Vector2.DOWN,"map pans within 30 pixels of the bottom edge"):return
	if not check(world._edge_direction(Vector2(100,100))==Vector2.ZERO,"central play area never edge-pans"):return
	world._pan_at_edge(.1,Vector2(30,360))
	var entry_speed:float=1500-world.target_camera.x
	world.target_camera=Vector2(1500,900)
	world._pan_at_edge(.1,Vector2(1,360))
	if not check(1500-world.target_camera.x>entry_speed and entry_speed>20,"speed increases towards edge without pixel hunting"):return
	world.camera=Vector2(1500,900)
	world.target_camera=world.camera
	await touch(0,Vector2(400,300),true)
	if not check(world.map_touches.size()==1,"one map finger captured"):return
	await motion(0,Vector2(490,330))
	if not check(world.camera.distance_to(Vector2(1440,880))<.1,"one-finger drag pans camera at matching world scale"):return
	await touch(1,Vector2(700,330),true)
	var anchor:Vector2=world.camera+(Vector2(595,330)-world.size/2)/world.zoom
	await motion(1,Vector2(805,330))
	if not check(world.zoom>1.5 and is_equal_approx(world.zoom,world.zoom_target),"spreading two fingers zooms in immediately"):return
	var anchored:Vector2=world.camera+(Vector2(647.5,330)-world.size/2)/world.zoom
	if not check(anchor.distance_to(anchored)<.01,"pinch keeps world point beneath finger centroid"):return
	await motion(1,Vector2(650,330))
	if not check(world.zoom<1.5,"pinching fingers together zooms out"):return
	world.zoom_locked=true
	var locked:float=world.zoom
	await motion(1,Vector2(850,330))
	if not check(is_equal_approx(world.zoom,locked),"zoom lock retains magnification during pinch"):return
	await touch(1,Vector2(850,330),false)
	var before:Vector2=world.camera
	await motion(0,Vector2(510,340))
	if not check(world.camera.distance_to(before+Vector2(-20,-10)/world.zoom)<.01,"lifting one finger resumes drag without a jump"):return
	await touch(0,Vector2(510,340),false)
	before=world.camera
	await motion(0,Vector2(650,400))
	if not check(world.map_touches.is_empty() and before==world.camera,"finger release stops map movement"):return
	await touch(2,Vector2(450,300),true)
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not check(world.map_touches.is_empty() and not world.dragging,"focus loss cancels every map touch"):return
	await touch(3,Vector2(450,300),true)
	world._resize_camera()
	if not check(world.map_touches.is_empty(),"rotation or viewport resize clears map fingers"):return
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks}))
	world.battle={}
	world.queue_free()
	await process_frame
	quit()
