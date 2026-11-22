extends SceneTree
class FrozenClock extends RefCounted:
	var value := 100.0
	func server_now() -> float:return value

var options := {}
var checks := []
var timings := []
var events := []
var clock := FrozenClock.new()
var view: Control
var hud: Control
var fixture: Dictionary
var masks: Array
var source: Dictionary
var original: Image
var output := ""

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	output=str(options.output)
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		var failure := {"passed":false,"failure":message,"checks":checks,"timings":timings,"events":events}
		FileAccess.open(output.path_join("failure.json"),FileAccess.WRITE).store_string(JSON.stringify(failure))
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func capture(name: String) -> void:
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func expected_motion(t: float, seat: int) -> Vector2:
	var frames: Array=fixture.shot.motion
	var first: Dictionary=frames[0]
	var second: Dictionary=frames[0]
	for i in range(frames.size()):
		if float(frames[i].at)>t:
			second=frames[i]
			break
		first=frames[i]
		second=first
	var a: Array=[]
	var b: Array=[]
	for pose: Array in first.poses:
		if int(pose[0])==seat:a=pose
	for pose: Array in second.poses:
		if int(pose[0])==seat:b=pose
	var blend:=clampf((t-float(first.at))/maxf(.0001,float(second.at)-float(first.at)),0,1)
	return Vector2(float(a[1]),float(a[2])).lerp(Vector2(float(b[1]),float(b[2])),blend)

func oracle_carve(image: Image, hole: Dictionary) -> Image:
	# An independent span oracle: compare every RGBA byte, including all
	# untouched pixels, against the source-native mask definition.
	var expected: Image=image.duplicate()
	var bytes:=expected.get_data()
	var mask: Dictionary=masks[int(hole.mask)-1]
	var left:=int(hole.x)-int(mask.width)/2
	var top:=int(hole.y)-int(mask.height)/2
	for y in range(int(mask.height)):
		var span: Array=mask.rows[y]
		if int(span[0])<0 or top+y<0 or top+y>=image.get_height():continue
		for x in range(maxi(0,left+int(span[0])),mini(image.get_width(),left+int(span[1])+1)):
			var offset:=((top+y)*image.get_width()+x)*4
			for channel in range(4):bytes[offset+channel]=0
	expected.set_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,bytes)
	return expected

func verify_tiles(terrain: RefCounted, expected: Image, label: String) -> bool:
	if not check(terrain.image.get_data()==expected.get_data(),label+" complete terrain bytes match native span oracle"):return false
	for tile: Dictionary in terrain.tiles:
		var region:=expected.get_region(tile.area)
		if not check((tile.image as Image).get_data()==region.get_data(),label+" CPU tile "+str(tile.area)):return false
		if not check((tile.texture as ImageTexture).get_image().get_data()==region.get_data(),label+" GPU texture "+str(tile.area)):return false
	return true

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	fixture=JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
	source=fixture.duplicate(true)
	masks=JSON.parse_string(FileAccess.get_file_as_string("res://assets/terrain-masks.json")).masks
	var holder:=Control.new()
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var api: RefCounted=load("res://net.gd").new(holder)
	api.endpoint=str(options.endpoint)
	var catalog: Dictionary=await api.request("/api/catalog")
	if not check(catalog.has("vehicles"),"read-only catalog is available"):return
	view=load("res://world_view.gd").new()
	view.catalog=catalog
	view.clock=clock
	view.player_id=1
	view.shake_enabled=false
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_process(false)
	view.effect.connect(func(kind: String, detail: int):events.append({"kind":kind,"detail":detail,"time":clock.value-100}))
	hud=load("res://battle_hud.gd").new()
	hud.catalog=catalog
	hud.clock=clock
	hud.player_id=1
	holder.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.set_process(false)
	view.set_battle(source)
	original=view.terrain_image.duplicate()
	view.overview=0
	view.manual_until=10000
	view.camera=Vector2(900,750)
	view.target_camera=view.camera
	view.zoom=1.7
	view.zoom_target=1.7
	await process_frame
	await process_frame
	var impact: float=fixture.shot.impacts[0].at
	var last: float=fixture.shot.duration
	var expected_terrain:=oracle_carve(original,fixture.shot.cuts[0])
	var captured := {}
	for tick in range(151):
		var t:=float(tick)/60+.000001
		clock.value=100+t
		var poll_us:=0
		if tick%18==0:
			var began:=Time.get_ticks_usec()
			# Deliberately old HP, holes and pose throughout the shot.
			view.set_battle(source.duplicate(true))
			poll_us=Time.get_ticks_usec()-began
		var textures_before: int=view.texture_cache.size()
		var began:=Time.get_ticks_usec()
		view._process(1.0/60)
		var process_us:=Time.get_ticks_usec()-began
		hud.battle=view.battle
		hud.minimap_ground=view.terrain_texture
		hud.minimap_map=int(view.battle.map)
		hud.camera_rect=Rect2(view.camera-view.size/view.zoom/2,view.size/view.zoom)
		hud._process(1.0/60)
		var should_hit:=t>=impact
		if not check(int(view.battle.units[1].hp)==(318 if should_hit else 370),"HP follows shot time at tick "+str(tick)):return
		if not check(int(view.battle.units[0].damage)==(52 if should_hit else 0),"cumulative damage uses same impact clock at tick "+str(tick)):return
		if not check(view.battle.holes.size()==(1 if should_hit else 0) and view.applied_holes==(1 if should_hit else 0),"crater visible on hit tick "+str(tick)):return
		if not check(view.explosions.size()==(1 if should_hit else 0),"explosion follows same hit tick "+str(tick)):return
		if t<impact+1.1:
			if not check(view.visual_numbers.size()==(1 if should_hit else 0),"damage number follows same hit tick "+str(tick)):return
		if should_hit and t<impact+1.1:
			if not check(int(view.visual_numbers[0].delta)==-52,"native damage is -52 at tick "+str(tick)):return
		for seat in [0,4]:
			var position: Vector2=view.render_positions[str(seat)]
			if not check(position.distance_to(expected_motion(minf(t,last),seat))<.001,"continuous authoritative pose seat=%d tick=%d"%[seat,tick]):return
			if not check(not bool(view.walking[str(seat)]),"fall never requests walk animation seat=%d tick=%d"%[seat,tick]):return
		if not check(int(source.units[1].hp)==370 and source.holes.is_empty() and float(source.units[1].y)==819,"visual playback does not modify the network snapshot tick "+str(tick)):return
		var draw_start:=Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var frame_us:=Time.get_ticks_usec()-draw_start
		if not check(view.texture_cache.size()==textures_before,"no first-use texture loading during shot at tick "+str(tick)):return
		timings.append({"tick":tick,"time":t,"poll_us":poll_us,"process_us":process_us,"frame_wait_us":frame_us,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"upload_bytes":view.terrain.last_upload_bytes,"new_textures":view.texture_cache.size()-textures_before})
		var name: String="before-impact"if tick==52 else "impact"if tick==53 else "falling"if tick==65 else "landed"if tick==77 else ""
		if not name.is_empty():
			capture(name)
			captured[name]=tick
			if tick==53:
				if not verify_tiles(view.terrain,expected_terrain,"actual native impact"):return
	if not check(events.filter(func(event):return event.kind=="move").is_empty(),"no footsteps emitted throughout falling and stale snapshots"):return
	if not check(events.filter(func(event):return event.kind=="explosion").size()==1,"one explosion sound only despite repeated stale snapshots"):return
	if not check(view.visual_numbers.is_empty(),"damage numbers expire without being duplicated by polling"):return
	var ready:=source.duplicate(true)
	ready.holes=fixture.shot.cuts.duplicate(true)
	ready.units[1].hp=318
	for unit: Dictionary in ready.units:
		var at:=expected_motion(last,int(unit.seat))
		unit.x=at.x
		unit.y=at.y
	ready.deadline=135.0
	ready.generation=2
	ready.units[0].x+=20
	var before: Vector2=view.render_positions["0"]
	view.set_battle(ready)
	view._process(1.0/60)
	if not check(view._motion_poses().is_empty(),"next turn releases old shot animation"):return
	if not check((view.render_positions["0"]as Vector2).x>before.x,"normal movement is accepted on the next turn"):return
	var new_battle:=fixture.duplicate(true)
	new_battle.id="fresh-room-same-map"
	new_battle.shot=null
	new_battle.deadline=135.0
	new_battle.units[0].x=420.0
	new_battle.units[1].x=950.0
	view.set_battle(new_battle)
	view._process(1.0/60)
	if not check(view.battle.holes.is_empty() and view.applied_holes==0 and view.terrain_image.get_data()==original.get_data(),"new battle on same map restores every terrain pixel"):return
	if not check(view.explosions.is_empty()and view.visual_numbers.is_empty()and view.fired_impacts.is_empty()and view.shot_id==-1,"new battle resets shot, numbers and impacts"):return
	if not check((view.render_positions["0"]as Vector2).distance_to(Vector2(420,806))<.001,"same-map new battle starts at new spawn"):return
	# Exercise every original native crater shape across all four tile corners.
	var terrain: RefCounted=load("res://native_terrain.gd").new(masks)
	var opaque:=Image.create(512,512,false,Image.FORMAT_RGBA8)
	opaque.fill(Color(.25,.5,.75,1))
	for id in range(1,masks.size()+1):
		terrain.reset(opaque)
		var hole: Dictionary={"x":256,"y":256,"r":0,"mask":id}
		terrain.carve(hole)
		terrain.flush()
		if not verify_tiles(terrain,oracle_carve(opaque,hole),"native mask %d"%id):return
	var report: Dictionary={"passed":true,"checks":checks,"timings":timings,"events":events,"screenshots":captured,"masks":masks.size(),"snapshot_seconds":.3,"silent":true,"private_desktop":true}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("IMPACT_TIMELINE_ACCEPTANCE "+JSON.stringify({"passed":true,"checks":checks.size(),"masks":masks.size(),"output":output}))
	quit()
