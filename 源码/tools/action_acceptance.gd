extends SceneTree
class FrozenClock extends RefCounted:
	var now:=100.0
	func server_now() -> float:return now
class ModalHost extends Control:
	var blocked:=false
	func _modal_open() -> bool:return blocked
var clock:=FrozenClock.new()
var view:Control
var checks:Array[String]=[]
var sounds:Array=[]
var audio:Node
var out:=""
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	out=OS.get_cmdline_user_args()[0]
	_run.call_deferred()
func check(ok:bool,label:String) -> bool:
	if not ok:push_error(label);quit(2);return false
	checks.append(label)
	return true
func capture(name:String) -> void:
	view.queue_redraw();view.overlay.queue_redraw();view.reticle.queue_redraw();view.action_layer.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	view=load("res://world_view.gd").new();view.clock=clock;view.player_id=1;view.shake_enabled=false
	root.add_child(view);view.size=Vector2(1366,768);view.set_process(false)
	for child in view.get_children():child.set_process(false)
	view.effect.connect(func(kind:String,detail:int):sounds.append([kind,detail]))
	audio=load("res://sound.gd").new();root.add_child(audio)
	view.effect.connect(func(kind:String,detail:int):audio.play_effect(kind,detail))
	var unit:Dictionary={"seat":0,"player":1,"name":"原版发射核对","team":0,"vehicle":1,"hp":300,"max_hp":300,"sp":150,"move":100.0,"face":1,"aim":35.0,"elevation":35.0,"slope":0.0,"falling":false,"shield":0,"stun":0,"stealth":0,"blind":0,"poison":0,"burn":0,"damage":0,"x":700.0,"y":806.0}
	var enemy:Dictionary=unit.duplicate(true);enemy.seat=4;enemy.player=2;enemy.team=1;enemy.x=1100.0;enemy.y=756.0
	var shot:Dictionary={"id":1,"actor":0,"prepared":100.0,"overdrive":true,"started":100+190.0/60,"duration":5.0,"trails":[],"impacts":[],"cues":[{"kind":"lock","seat":4,"x":1100.0,"y":756.0,"at":.6}]}
	var battle:Dictionary={"id":"actions","map":9,"width":1536,"height":1024,"native_aim":true,"active":0,"round":1,"generation":1,"wind":0,"deadline":0.0,"units":[unit,enemy],"holes":[],"shot":shot,"result":null}
	view.set_battle(battle);view.overview=0;view.manual_until=INF;view.camera=Vector2(850,690);view.target_camera=view.camera;view.zoom=1.2;view.zoom_target=1.2
	for point:Array in [[99.9,0],[100.0,1],[100.5,4],[101.45,9],[102.0,9],[102.85,9],[103.1,9],[103.2,0]]:
		clock.now=float(point[0]);view._process(0);view.action_layer._process(0)
		if not check(view.action_layer.overdrive_letters(shot,clock.now).size()==int(point[1]),"OVER DRIVE native letter phase at %.2f"%clock.now):return
		await capture("overdrive-%.2f"%clock.now)
	clock.now=101.45
	var letters:Array=view.action_layer.overdrive_letters(shot,clock.now)
	for i in range(9):
		if not check(int(letters[i].frame)==[0,1,2,3,4,3,5,1,2][i],"original OVER DRIVE sprite order %d"%i):return
	var before:=sounds.size();view.action_layer._process(0);view.action_layer._process(0)
	if not check(sounds.size()==before,"repeated snapshots never duplicate preparation sound"):return
	clock.now=float(shot.started)+.6;view._process(0);view.action_layer._process(0)
	if not check(sounds.has(["native",54]),"lock acquisition emits original effect01 cue"):return
	if not check(view.action_layer.active_marks(shot,clock.now).size()==1,"lock acquisition draws original target marker"):return
	for cue:String in ["effect01.wav","effect04.wav","effect05.wav","effect06.wav"]:
		if not check(audio.played_cues.has(cue),"actual production AudioStreamPlayer loads "+cue):return
	await capture("homing-lock")
	clock.now+=2.5
	var marks:Array=view.action_layer.active_marks(shot,clock.now)
	if not check(marks.size()==1 and is_equal_approx(float(marks[0].alpha),.5),"native target marker fades after 120 ticks"):return
	await capture("homing-lock-fade")
	clock.now+=.51
	if not check(view.action_layer.active_marks(shot,clock.now).is_empty(),"native target marker expires after 180 ticks"):return
	var s:=view.size
	for pair:Array in [[Vector2(0,s.y/2),Vector2.LEFT],[Vector2(s.x-1,s.y/2),Vector2.RIGHT],[Vector2(s.x/2,0),Vector2.UP],[Vector2(s.x/2,s.y-1),Vector2.DOWN],[s/2,Vector2.ZERO],[Vector2(-1,0),Vector2.ZERO],[s+Vector2.ONE,Vector2.ZERO]]:
		if not check(view._edge_direction(pair[0])==pair[1],"map edge direction %s"%str(pair[0])):return
	view.size=Vector2(1920,1080)
	if not check(view._edge_direction(Vector2(1919,540))==Vector2.RIGHT,"maximized map edge uses actual width"):return
	var previous:Vector2=view.target_camera
	view._pan_at_edge(.1,Vector2(1919,540))
	if not check(view.target_camera.x>previous.x and is_inf(view.manual_until),"edge pan moves map and releases automatic follow"):return
	view.reset_camera()
	if not check(view.manual_until==0,"follow button restores automatic camera"):return
	view.dragging=true;view.aiming_with_mouse=true;view._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not check(not view.dragging and not view.aiming_with_mouse,"focus loss clears drag and aim state"):return
	var host:=ModalHost.new();root.add_child(host)
	var content:=Control.new();host.add_child(content);view.reparent(content)
	host.blocked=true
	if not check(view._camera_input_blocked(),"application modal blocks edge pan through the content parent"):return
	host.blocked=false
	if not check(not view._camera_input_blocked(),"closing the modal restores edge pan"):return
	print("ACTION_ACCEPTANCE "+JSON.stringify({"checks":checks,"passed":true,"sounds":sounds,"silent":true,"private_desktop":true}))
	audio.shutdown();await audio.wait_for_shutdown()
	audio.queue_free();host.queue_free();await process_frame
	quit()
