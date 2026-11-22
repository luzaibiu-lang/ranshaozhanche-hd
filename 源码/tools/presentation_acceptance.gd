extends SceneTree
class FrozenClock extends RefCounted:
	var value:=100.0
	func server_now() -> float:return value

var options:Dictionary={}
var checks:Array=[]
var clock:=FrozenClock.new()
var view:Control
var hud:Control
var battle:Dictionary

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	_run.call_deferred()

func check(value:bool,message:String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func capture(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	var holder:=Control.new()
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var api:RefCounted=load("res://net.gd").new(holder)
	api.endpoint=str(options.endpoint)
	var catalog:Dictionary=await api.request("/api/catalog")
	if not check(catalog.has("vehicles"),"read catalog without creating business data"):return
	view=load("res://world_view.gd").new()
	view.player_id=1
	view.catalog=catalog
	view.clock=clock
	view.shake_enabled=false
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud=load("res://battle_hud.gd").new()
	hud.player_id=1
	hud.clock=clock
	hud.catalog=catalog
	holder.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var own:Dictionary={"seat":0,"player":1,"name":"瞄准演示","team":0,"vehicle":1,"hp":300,"max_hp":300,"sp":150,"move":100,"face":1,"aim":35,"elevation":35,"slope":0,"falling":false,"shield":0,"stun":0,"stealth":0,"damage":0}
	battle={"id":"presentation-fixture","map":9,"width":1920,"height":1200,"native_aim":true,"active":0,"round":1,"generation":1,"wind":35,"deadline":135.0,"units":[own],"holes":[],"shot":null}
	own.x=960.0;own.y=700.0
	view.set_battle(battle)
	view.overview=0
	view.manual_until=10000
	view.camera=Vector2(960,600)
	view.target_camera=view.camera
	view.zoom=1.2
	view.zoom_target=1.2
	hud.battle=battle
	for sample in [[1,0.0,25.0,35],[1,15.0,55.0,-35],[-1,-12.0,35.0,0]]:
		own.face=sample[0];own.slope=sample[1]
		view.render_slopes["0"]=sample[1]
		view.angle=sample[2];hud.angle=sample[2];battle.wind=sample[3]
		await process_frame
		var expected:float=fposmod(float(sample[1])+(180-float(sample[2])if int(sample[0])<0 else float(sample[2])),360)
		if not check(is_equal_approx(view.aim_heading(own,float(sample[2])),expected),"reticle heading includes facing and terrain slope "+str(sample)):return
		await capture("aim-wind-"+str(sample[3]))
		if not check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(hud.wind_rect()),"native horizontal wind bar stays within the window"):return
	own.face=1;own.slope=0.0
	view.render_slopes["0"]=0.0
	var frames:Array=[]
	for tick in range(61):frames.append({"at":float(tick)/60,"poses":[[0,960.0,500.0+float(tick)*5,0,1]]})
	battle.shot={"id":1,"started":100.0,"duration":1.0,"trails":[],"impacts":[],"motion":frames}
	battle.deadline=0.0
	var positions:Array=[]
	for tick in range(61):
		clock.value=100.0+float(tick)/60
		# Mimic the actual 300 ms HTTP cadence. Source pose is deliberately
		# coarse; rendered motion must still follow every authoritative frame.
		if tick%18==0:
			own.y=500.0+float(tick)*5
			view.set_battle(battle)
		await process_frame
		await process_frame
		var at:Vector2=view.render_positions["0"]
		positions.append(at.y)
		if not check(absf(at.y-(500+tick*5))<.01,"continuous fall pose at tick "+str(tick)):return
		if not check(not bool(view.walking["0"]),"falling does not trigger footsteps at tick "+str(tick)):return
		if tick==30:await capture("fall-middle")
	for i in range(1,positions.size()):
		if not check(absf(float(positions[i])-float(positions[i-1])-5)<.01,"fall velocity remains stable across sparse snapshots"):return
	var timer:RefCounted=load("res://net.gd").new(holder)
	var now:=Time.get_ticks_usec()/1000000.0
	timer._sync_clock(1000,now-.04,now)
	var before:float=timer.server_now()
	timer._sync_clock(900,now-.04,now)
	if not check(timer.server_now()>=before,"clock correction cannot rewind animations"):return
	print("PRESENTATION_ACCEPTANCE "+JSON.stringify({"checks":checks,"sparse_snapshot_interval":.3,"motion_ticks":60,"rendered_positions":positions,"private_desktop":true,"silent":true}))
	quit()
