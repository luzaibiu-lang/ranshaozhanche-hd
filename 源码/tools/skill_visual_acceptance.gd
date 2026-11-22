extends SceneTree
class FrozenClock extends RefCounted:
	var now:=100.0
	func server_now() -> float:return now
var clock:=FrozenClock.new()
var view:Control
var out:=""
var checks:Array[String]=[]
var sounds:Array=[]
var audio:Node
var flames:Node2D

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	out=OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func check(ok:bool,label:String) -> bool:
	if not ok:push_error(label);quit(2);return false
	checks.append(label)
	return true

func capture(name:String) -> Image:
	view.queue_redraw()
	for child in view.get_children():
		if child is CanvasItem:child.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image()
	if not name.is_empty():img.save_png(out.path_join(name+".png"))
	return img

func shot(id:int) -> Dictionary:
	return {"id":id,"actor":0,"started":100.0,"duration":5.0,"trails":[],"impacts":[],"cues":[]}

func set_shot(value:Variant) -> void:
	var b:Dictionary=view.source_battle.duplicate(true)
	b.shot=value
	view.set_battle(b)
	view._process(0)
	view.death_layer._process(0)
	view.action_layer._process(0)
	flames._process(0)

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1280,800)
	view=load("res://world_view.gd").new();view.clock=clock;view.shake_enabled=false
	root.add_child(view);view.size=Vector2(1280,800);view.set_process(false)
	for child in view.get_children():
		child.set_process(false)
		if child.get_script()!=null and child.get_script().resource_path.ends_with("native_flame_layer.gd"):flames=child
	view.effect.connect(func(kind:String,detail:int):sounds.append([kind,detail]))
	audio=load("res://sound.gd").new();root.add_child(audio)
	view.effect.connect(func(kind:String,detail:int):audio.play_effect(kind,detail))
	var b:Dictionary={"id":"skill-018","map":9,"width":1536,"height":1024,"native_aim":true,"active":0,"round":1,"generation":1,"wind":0,"deadline":0.0,"units":[],"holes":[],"shot":null,"result":null}
	view.set_battle(b);view.overview=0;view.manual_until=INF;view.camera=Vector2(768,512);view.target_camera=view.camera;view.zoom=1;view.zoom_target=1
	var flat:=Image.create(4,4,false,Image.FORMAT_RGBA8);flat.fill(Color("608090"))
	view.background=ImageTexture.create_from_image(flat);view.terrain_image=null;view.scenery.visible=false
	view.overlay.visible=false;view.reticle.visible=false
	view._process(0)
	var baseline:=await capture("")
	for id in [5,9,10,15,16,17,20,21,22,24,25,26,28,59,60,81,90,91,92]:
		var s:=shot(id)
		s.trails=[{"projectile":id,"kind":"normal","start":0.0,"duration":2.0,"points":[[768,512],[768,512]]}]
		clock.now=100.4;set_shot(s)
		var img:=await capture("blue-flame" if id==92 else "orange-flame" if id==26 else "")
		var dark:=0
		var lit:=0
		for y in range(220,580,4):
			for x in range(400,880,4):
				var c:=img.get_pixel(x,y);var old:=baseline.get_pixel(x,y)
				if c.r<old.r-.012 or c.g<old.g-.012 or c.b<old.b-.012:dark+=1
				if c.r>old.r+.025 or c.g>old.g+.025 or c.b>old.b+.025:lit+=1
		if not check(dark==0,"energy %d has no opaque black rectangle or border"%id):return
		if not check(lit>0,"energy %d is visible after additive composition"%id):return
	var s:=shot(92);s.trails=[{"projectile":92,"kind":"normal","start":0.0,"duration":2.0,"points":[[768,512],[768,512]]}]
	clock.now=100.4;set_shot(s);var a:=await capture("flame-flow-a")
	clock.now=100.42;set_shot(s);var c:=await capture("flame-flow-b")
	if not check(a.get_data()!=c.get_data(),"flame flows between original flipbook frames"):return
	if not check(flames.flame_samples(s.trails[0],.42).size()>0,"fire carries a continuous ember trail"):return
	if not check(flames.flame_samples(s.trails[0],2.23).is_empty(),"fire tail expires after impact"):return
	s=shot(100);s.impacts=[]
	for i in range(7):s.impacts.append({"projectile":5,"at":.2+i*.3,"x":768.0+i*8,"y":650.0,"radius":45.0,"kind":"normal"})
	clock.now=100.21;set_shot(s);var beam:=await capture("ufo-sky-column")
	var bright:=0
	for y in range(20,500):
		if beam.get_pixel(640,y).b>baseline.get_pixel(640,y).b+.05:bright+=1
	if not check(bright>300,"UFO wave draws a continuous column from sky to impact"):return
	if not check(view.beam_layer.active_beams(s,100.51).size()==2,"consecutive UFO impacts keep separate overlapping columns"):return
	if not check(view.beam_layer.active_beams(s,102.9).is_empty(),"UFO columns fade out after the last wave"):return
	s=shot(101);s.cues=[{"kind":"lock","seat":4,"x":900.0,"y":650.0,"at":.5}]
	sounds.clear();clock.now=100.85;set_shot(s)
	if not check(sounds.has(["native",54]),"lock sound survives a normal 350ms late snapshot"):return
	var n:=sounds.size();view.action_layer._process(0)
	if not check(sounds.size()==n,"repeated lock snapshot never repeats sound"):return
	s=shot(102);s.cues=[{"kind":"lock","seat":4,"x":900.0,"y":650.0,"at":.5}]
	sounds.clear();clock.now=102.0;set_shot(s)
	if not check(not sounds.has(["native",54]),"reconnection does not replay an obsolete lock"):return
	for player in audio.players:player.stop()
	for i in range(audio.players.size()):audio.play_cue("exp12.wav")
	var before:int=audio.played_cues.size()
	audio.play_event(54)
	if not check(audio.played_cues.size()==before+1 and audio.played_cues.back()=="effect01.wav","lock announcement survives twelve occupied explosion channels"):return
	for player in audio.players:player.stop()
	s=shot(103);s.cues=[{"kind":"death","seat":4,"x":768.0,"y":560.0,"at":.2}]
	sounds.clear();clock.now=100.2;set_shot(s)
	for i in range(13):
		clock.now=100.2+float(i)*10/60
		view.death_layer._process(0)
		if i in [0,3,6,12]:await capture("death-pulse-%02d"%i)
		await create_timer(.17).timeout
	var pulses:=0
	for cue:Array in sounds:
		if cue==["native",39]:pulses+=1
	if not check(pulses==13,"fatal damage plays all thirteen native explosion pulses"):return
	if not check(sounds.has(["native",49]),"fatal damage finishes with native final explosion sound"):return
	if not check(audio.played_cues.has("exp02.wav") and audio.played_cues.has("exp12.wav"),"actual AudioStreamPlayers load both destruction sounds"):return
	clock.now=103.2;view.death_layer._process(0);await capture("death-final-flash")
	set_shot(s)
	if not check(view.death_layer.events.size()==1,"repeated death snapshots do not duplicate explosions"):return
	clock.now=104.22;view.death_layer._process(0)
	if not check(view.death_layer.events.is_empty(),"destruction finishes and leaves no repeating effects"):return
	print("SKILL_VISUAL_ACCEPTANCE "+JSON.stringify({"passed":true,"checks":checks,"silent":true,"private_desktop":true}))
	audio.shutdown();await audio.wait_for_shutdown();audio.queue_free();view.queue_free();await process_frame
	quit()
