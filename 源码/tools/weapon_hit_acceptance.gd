extends SceneTree
class FrozenClock extends RefCounted:
	var value := 100.0
	func server_now() -> float:return value

var options := {}
var clock := FrozenClock.new()
var view: Control
var fixtures: Array
var checks := 0
var report := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks+=1
	return true

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1280,800)
	fixtures=JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
	view=load("res://world_view.gd").new()
	view.clock=clock
	view.player_id=1
	view.shake_enabled=false
	root.add_child(view)
	view.size=Vector2(1280,800)
	view.set_process(false)
	var ground:=Image.create(1800,1600,false,Image.FORMAT_RGBA8)
	ground.fill_rect(Rect2i(0,800,1800,800),Color("705a44"))
	for row: Dictionary in fixtures:
		var battle: Dictionary=row.battle
		battle.id="hit-%02d-%d"%[int(row.Vehicle),int(row.Slot)]
		view.set_battle(battle)
		view.terrain.reset(ground)
		view.terrain_image=view.terrain.image
		view.terrain_texture=view.terrain.overview
		view.applied_holes=0
		view.overview=0
		view.manual_until=1000000
		view.zoom=1.6
		view.zoom_target=1.6
		view.camera=Vector2(float(row.TargetX)-90,690)
		view.target_camera=view.camera
		var focus_frame: Dictionary={}
		for frame: Dictionary in battle.shot.visuals:
			if frame.get("numbers",[]).any(func(number):return int(number.seat)==4 and int(number.delta)<0):
				focus_frame=frame
				break
		if not check(not focus_frame.is_empty(),"damage frame vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		var before:=maxf(0,float(focus_frame.at)-.001)
		clock.value=100+before
		view._process(0.0)
		var sky_before: Image
		if int(row.Projectile) == 5:
			await process_frame
			await RenderingServer.frame_post_draw
			sky_before = root.get_texture().get_image()
		var hp_before: int=view.battle.units[1].hp
		var process_us:=0
		clock.value=100+float(focus_frame.at)+.000001
		var start:=Time.get_ticks_usec()
		view._process(0.0)
		process_us=Time.get_ticks_usec()-start
		if not check(int(view.battle.units[1].hp)<hp_before,"HP changes at impact vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		if not check(view.visual_numbers.any(func(number):return int(number.delta)<0),"render damage at impact vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		if not check(view.explosions.size()>0,"explosion at impact vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		if not check(view.applied_holes==int(focus_frame.holes),"crater at impact vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: String="vehicle-%02d-slot%d.png"%[int(row.Vehicle),int(row.Slot)]
		root.get_texture().get_image().save_png(str(options.output).path_join(screenshot))
		if sky_before and not await _check_sky_columns(row, sky_before):
			return
		clock.value=100+float(battle.shot.duration)+.000001
		view._process(0.0)
		if not check(int(view.battle.units[1].hp)==1000000-int(row.Damage),"final HP agrees with Go vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		if not check(view.applied_holes==int(row.Holes),"final crater count agrees with Go vehicle%d slot%d"%[int(row.Vehicle),int(row.Slot)]):return
		report.append({"vehicle":row.Vehicle,"slot":row.Slot,"logical":row.Logical,"projectile":row.Projectile,"damage":row.Damage,"impacts":row.Impacts,"holes":row.Holes,"fall_frames":row.FallFrames,"process_us":process_us,"image":screenshot})
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"weapons":report,"private_desktop":true,"silent":true}))
	print("WEAPON_HIT_ACCEPTANCE "+JSON.stringify({"passed":true,"checks":checks,"weapons":report.size()}))
	quit()

func _check_sky_columns(row: Dictionary, sky_before: Image) -> bool:
	var impacts: Array = row.battle.shot.impacts
	if not check(impacts.size() == 7, "seven sky strikes vehicle%d" % int(row.Vehicle)):
		return false
	for impact: Dictionary in impacts:
		var strike_time := 100.0 + float(impact.at) + 0.000001
		_advance_sky_clock(strike_time)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var x := roundi(view.screen(Vector2(impact.x, impact.y)).x)
		for y in [50, 280]:
			var core := frame.get_pixel(x, y)
			if not check(core.b > sky_before.get_pixel(x, y).b + 0.3, "sky column at %s,%s above impact %s vehicle%d" % [x, y, impact.at, int(row.Vehicle)]):
				return false
	_advance_sky_clock(clock.value + 52.0 / 60.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var cleared := root.get_texture().get_image()
	for impact: Dictionary in impacts:
		var x := roundi(view.screen(Vector2(impact.x, impact.y)).x)
		if not check(absf(cleared.get_pixel(x, 280).b - sky_before.get_pixel(x, 280).b) < 0.04, "sky clears after last strike vehicle%d" % int(row.Vehicle)):
			return false
	return true

func _advance_sky_clock(to_time: float) -> void:
	while to_time - clock.value > 0.000001:
		var delta := minf(1.0 / 60.0, to_time - clock.value)
		clock.value += delta
		view._process(delta)
