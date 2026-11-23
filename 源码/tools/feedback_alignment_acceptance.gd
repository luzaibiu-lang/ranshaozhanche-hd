extends SceneTree
class FrozenClock extends RefCounted:
	var now:=100.0
	func server_now() -> float:return now
var options:Dictionary={}
var checks:Array[String]=[]
var clock:=FrozenClock.new()
var sounds:Array=[]
var slot_clicks:=0
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	_run.call_deferred()
func check(ok:bool,message:String) -> bool:
	if not ok:push_error(message);quit(2);return false
	checks.append(message)
	return true
func capture(name:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))
func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.catalog)))
	var shop:Control=load("res://native_shop.gd").new()
	shop.catalog=catalog;shop.profile={"gold":10000,"inventory":[1,4,10,17]}
	root.add_child(shop)
	for dimensions:Vector2 in [Vector2(800,307),Vector2(1280,430),Vector2(1366,500)]:
		shop.size=dimensions;shop._reflow()
		for index in range(4):
			var icon:TextureRect=shop.backpack_icons[index]
			var expected:Vector2=Vector2(594+shop.logical_width-800+index*51,211)*shop.layout.scale
			if not check(icon.get_global_rect().position.distance_to(expected)<.01,"inventory inset follows original frame at %s slot %d"%[dimensions,index]):return
			if not check(icon.get_global_rect().size.distance_to(Vector2(31,31)*shop.layout.scale)<.01,"inventory icon preserves native 31px size slot%d"%index):return
			if not check(icon.mouse_filter==Control.MOUSE_FILTER_IGNORE and shop.backpack[index].icon==null,"inventory child retains button hit testing slot%d"%index):return
		await capture("shop-%d"%int(dimensions.y))
	shop.size=Vector2(1280,430);shop._reflow()
	await capture("shop-unselected")
	var unselected:Image=root.get_texture().get_image()
	for index in range(4):
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.position=shop.backpack_icons[index].get_global_rect().get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event)
			await process_frame
		if not check(shop.selected_slot==index,"actual click through inventory icon selects slot%d"%index):return
		var leave:=InputEventMouseMotion.new();leave.position=Vector2(5,700);root.push_input(leave)
		await capture("shop-selected%d"%index)
		var selected:Image=root.get_texture().get_image()
		for other in range(4):
			var rect:Rect2i=Rect2i(shop.backpack_icons[other].get_global_rect())
			var changed:=0
			for y in range(rect.position.y,rect.end.y):
				for x in range(rect.position.x,rect.end.x):
					if selected.get_pixel(x,y)!=unselected.get_pixel(x,y):changed+=1
			if not check(changed>20 if other==index else changed==0,"inventory tint remains visible after pointer leaves; selecting%d updates slot%d"%[index,other]):return
	shop.queue_free();await process_frame
	var picker:Control=load("res://native_vehicle_picker.gd").new()
	picker.catalog=catalog;root.add_child(picker)
	for selected in [0,1,13,23,30]:
		picker.size=Vector2(249,296);picker._reflow();picker.set_selected(selected)
		if not check(picker.ability.get_global_rect()==Rect2(34,17,93,93),"native ability patch aligns without duplicate ring for vehicle%d"%selected):return
		await capture("radar-%d"%selected)
	picker.queue_free();await process_frame
	var view:Control=load("res://world_view.gd").new();view.clock=clock;view.shake_enabled=false;view.player_id=99;view.catalog=catalog
	root.add_child(view);view.size=Vector2(1366,768);view.set_process(false)
	for child in view.get_children():child.set_process(false)
	view.effect.connect(func(kind:String,detail:int):sounds.append([kind,detail]))
	var own:Dictionary={"seat":0,"player":1,"team":0,"name":"坡面测试","vehicle":3,"hp":300,"max_hp":300,"sp":150,"move":100,"face":1,"aim":35,"elevation":35,"slope":0,"falling":false,"shield":0,"stun":0,"stealth":0,"damage":0,"x":100.0,"y":120.0}
	var data:Dictionary={"id":"feedback-path","map":9,"width":1536,"height":1024,"native_aim":true,"active":0,"generation":1,"round":1,"wind":0,"deadline":200.0,"units":[own],"holes":[],"shot":null}
	view.set_battle(data);view.overview=0;view.manual_until=10000;view.camera=Vector2(140,110);view.target_camera=view.camera;view.zoom=4;view.zoom_target=4
	var ridge:=Image.create(256,240,false,Image.FORMAT_RGBA8)
	for x in range(256):
		var y:=120-clampi(mini(x-100,180-x),0,40)
		ridge.fill_rect(Rect2i(x,y,1,240-y),Color(.32,.55,.2,1))
	view.terrain.reset(ridge);view.terrain_image=view.terrain.image;view.terrain_texture=view.terrain.overview
	own.x=180.0;view.set_battle(data)
	view._process(log(2.0)/16.0)
	var middle:Vector2=view.render_positions["0"]
	if not check(absf(middle.x-140)<.02 and absf(middle.y-80)<=2.01,"remote walking follows full crest instead of cutting a straight line through terrain"):return
	await capture("walking-crest")
	for tick in range(20):
		view._process(1.0/60)
		var at:Vector2=view.render_positions["0"]
		var expected:=120-clampi(mini(int(at.x)-100,180-int(at.x)),0,40)
		if not check(absf(at.y-expected)<=2.01,"remote walking stays supported after crest tick%d"%tick):return
	data.deadline=0.0;own.x=100.0;own.y=120.0
	data.shot={"id":2,"started":100.0,"duration":3.0,"trails":[],"impacts":[],"cues":[{"kind":"warp","seat":0,"at":2.0,"x":180,"y":100}],"motion":[{"at":0.0,"poses":[[0,100,120,0,0]]},{"at":2.0,"poses":[[0,180,100,0,0]]},{"at":3.0,"poses":[[0,180,140,0,1]]}]}
	view.set_battle(data)
	for t in [100.1,101.0,101.99]:
		clock.now=t;view._process(0)
		if not check((view.render_positions["0"] as Vector2).distance_to(Vector2(100,120))<.01,"warp holds launch position until exact portal event at%f"%t):return
	clock.now=102;view._process(0)
	if not check((view.render_positions["0"] as Vector2).distance_to(Vector2(180,100))<.01,"warp changes position instantly at event"):return
	clock.now=102.5;view._process(0)
	if not check((view.render_positions["0"] as Vector2).distance_to(Vector2(180,120))<.01,"normal falling remains smoothly interpolated after warp"):return
	data.shot={"id":3,"started":100.0,"duration":3.0,"trails":[],"impacts":[],"cues":[{"kind":"shield_hit","seat":0,"at":1.0},{"kind":"shield_hit","seat":4,"at":1.0},{"kind":"shield_hit","seat":0,"at":1.3}]}
	view.set_battle(data);sounds.clear()
	for t in [100.9,101.0,101.0,101.05,101.3,101.3]:
		clock.now=t;view.action_layer._process(0)
	if not check(sounds.count(["native",63])==2,"native shield sound fires once per simultaneous hit group and again for next hit"):return
	data.shot.id=4;view.set_battle(data);sounds.clear();clock.now=102.5;view.action_layer._process(0)
	if not check(sounds.is_empty(),"late shield snapshot does not replay stale audio"):return
	var binding:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/native-audio.json"))
	if not check(str(binding.sounds["63"])=="effect10.wav","shield uses original effect10.wav binding"):return
	var audio:Node=load("res://sound.gd").new();root.add_child(audio)
	for index in range(12):audio.play_event(38)
	if not check(audio.players.all(func(player):return player.playing),"dense volley fills twelve actual effects channels"):return
	audio.play_event(63)
	if not check(audio.played_cues.back()=="effect10.wav","shield sound retains priority even when all effects channels are occupied"):return
	audio.shutdown();await audio.wait_for_shutdown();audio.queue_free()
	view.queue_free();await process_frame
	var report:Dictionary={"passed":true,"checks":checks,"private_desktop":true,"audio_driver":"Dummy"}
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("FEEDBACK_ALIGNMENT_ACCEPTANCE "+JSON.stringify({"passed":true,"checks":checks.size()}));quit()
