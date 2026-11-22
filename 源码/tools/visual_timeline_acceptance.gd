extends SceneTree
## Behavioral regressions for production shot playback, using local fixtures.
## No player registration, commands, saves, or production writes.
class FrozenClock extends RefCounted:
	var now:=100.0
	func server_now() -> float:return now

var clock:=FrozenClock.new()
var checks:Array[String]=[]
var observations:Dictionary={}
var options:Dictionary={}
var view:Control
var sounds:Array=[]

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	_run.call_deferred()

func check(ok:bool,message:String) -> bool:
	if not ok:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func capture(name:String) -> void:
	view.queue_redraw();view.overlay.queue_redraw();view.reticle.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func stats(seat:int,hp:int,sp:int,stealth:int,damage:int=0) -> Dictionary:
	return {"seat":seat,"hp":hp,"sp":sp,"move":100.0,"shield":0,"stun":0,"blind":0,"stealth":stealth,"poison":0,"burn":0,"damage":damage}

func fixture(id:String,stealth:int=0) -> Dictionary:
	var own:Dictionary={"seat":0,"player":1,"name":"时间轴检查","team":0,"vehicle":1,"hp":300,"max_hp":300,"sp":150,"move":100.0,"face":1,"aim":35.0,"elevation":35.0,"slope":0.0,"falling":false,"shield":0,"stun":0,"stealth":0,"blind":0,"poison":0,"burn":0,"damage":0,"x":700.0,"y":806.0}
	var enemy:Dictionary=own.duplicate(true)
	enemy.seat=4;enemy.player=2;enemy.team=1;enemy.stealth=stealth;enemy.x=1200.0;enemy.y=756.0
	var shot:Dictionary={"id":1,"started":100.0,"duration":1.0,"hole_base":0,"cuts":[{"x":1200,"y":770,"r":10,"mask":3},{"x":1200,"y":780,"r":10,"mask":3}],"trails":[],"impacts":[],"motion":[{"at":0.0,"poses":[[0,700,806,0,0],[4,1200,756,0,0]]},{"at":1.0,"poses":[[0,700,826,0,0],[4,1200,800,0,0]]}],"visuals":[{"at":0.0,"holes":0,"units":[stats(0,300,150,0),stats(4,300,150,stealth)]},{"at":0.5,"holes":1,"units":[stats(0,300,150,0,50),stats(4,250,150,stealth)],"numbers":[{"seat":4,"x":1200,"y":756,"delta":-50}]},{"at":0.6,"holes":2,"units":[stats(0,300,150,0,80),stats(4,220,150,stealth)],"numbers":[{"seat":4,"x":1200,"y":766,"delta":-30}]}]}
	return {"id":id,"map":9,"width":1536,"height":1024,"native_aim":true,"active":0,"round":1,"generation":1,"wind":0,"deadline":0.0,"units":[own,enemy],"holes":[],"shot":shot,"result":null}

func set_fixture(data:Dictionary,time:float) -> void:
	clock.now=time
	view.set_battle(data)
	view.overview=0;view.manual_until=10000
	view.camera=Vector2(900,740);view.target_camera=view.camera
	view.zoom=1.2;view.zoom_target=1.2
	view._process(0)

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	view=load("res://world_view.gd").new()
	view.player_id=1;view.clock=clock;view.shake_enabled=false
	var began:=Time.get_ticks_usec()
	root.add_child(view)
	observations.world_ready_milliseconds=(Time.get_ticks_usec()-began)/1000.0
	view.set_process(false)
	view.size=Vector2(1366,768)
	view.effect.connect(func(kind:String,detail:int):sounds.append([kind,detail]))
	# Freeze cosmetic weather so pixel comparisons isolate hit-number rendering.
	for child in view.get_children():child.set_process(false)
	var data:=fixture("late-batch")
	data.holes=data.shot.cuts.duplicate(true)
	set_fixture(data,100.49)
	if not check(view.applied_holes==0 and view.visual_numbers.is_empty(),"a newer snapshot cannot show a crater or hit number before its playback time"):return
	if not check(int(view.battle.units[1].hp)==300,"the pre-impact frame keeps pre-impact HP"):return
	clock.now=100.95;view._process(0)
	if not check(view.applied_holes==2 and view.visual_numbers.size()==2,"one late frame catches up both crater and damage events"):return
	if not check(int(view.battle.units[1].hp)==220 and int(view.battle.units[0].damage)==80,"HP and damage score use the same sparse visual frame"):return
	if not check(is_zero_approx(view.terrain.image.get_pixel(1200,770).a),"the cut is present in the actual native terrain image"):return
	if not check(int(data.units[1].hp)==300 and int(data.units[0].damage)==0,"presentation does not mutate the authoritative snapshot"):return
	await capture("late-batch")
	view.set_battle(data);view._process(0)
	if not check(view.applied_holes==2 and view.visual_numbers.size()==2,"repeated snapshots do not duplicate craters or hit numbers"):return
	for number:Dictionary in view.visual_numbers:
		if not check(int(number.seat)==4,"each hit number retains the target seat"):return
	clock.now=101.8;view._process(0)
	if not check(is_equal_approx(float(view.render_positions["0"].y),826.0),"a sparse final snapshot cannot pull the tank back up after landing"):return
	if not check(not bool(view.walking["0"]),"holding the final fall pose does not start footsteps"):return
	data=fixture("enemy-stealth",3);set_fixture(data,100.95)
	if not check(not bool(view.vehicles[4].visible) and view.visual_numbers.is_empty(),"an invisible enemy does not reveal its position through new damage numbers"):return
	data=fixture("friendly-stealth",3);data.units[1].team=0;set_fixture(data,100.95)
	if not check(bool(view.vehicles[4].visible) and view.visual_numbers.size()==2,"friendly stealth keeps the allied vehicle and its damage feedback visible"):return
	data=fixture("midlife-stealth");set_fixture(data,100.95)
	if not check(view.visual_numbers.size()==2,"the midlife visibility fixture starts with visible damage feedback"):return
	data.deadline=135.0;data.units[1].stealth=3
	view.set_battle(data);view._process(0)
	if not check(not view._number_visible(4) and view.visual_numbers.size()==2,"existing damage feedback is hidden when its enemy becomes invisible"):return
	await capture("stealth-with-history")
	view.visual_numbers.clear()
	await capture("stealth-baseline")
	data=fixture("next-turn");data.deadline=135.0;data.units[0].hp=290;data.units[0].sp=180;data.units[0].damage=100;data.units[0].poison=1
	set_fixture(data,101.8)
	if not check(int(view.battle.units[0].hp)==290 and int(view.battle.units[0].sp)==180 and int(view.battle.units[0].damage)==100 and int(view.battle.units[0].poison)==1,"an old shot cannot overwrite next-turn health, SP, score or status"):return
	if not check(view._motion_poses().is_empty(),"a retained old shot cannot lock movement on the next turn"):return
	data.result={"team":0};data.deadline=0.0;view.set_battle(data);view._process(0)
	if not check(int(view.battle.units[0].hp)==290 and int(view.battle.units[0].sp)==180 and int(view.battle.units[0].damage)==100 and int(view.battle.units[0].poison)==1,"a result snapshot keeps post-shot damage, recovery and status changes"):return
	if not check(view._motion_poses().is_empty(),"a result snapshot does not replay old unit motion"):return
	data=fixture("departed");data.units[1].hp=0;data.units[1].departed=true
	set_fixture(data,100.95)
	if not check(int(view.battle.units[1].hp)==0 and bool(view.battle.units[1].departed),"explicit departure cannot be resurrected by precomputed visual HP"):return
	if not check(not view._motion_poses().has(4) and view._motion_poses().has(0),"departure stops only the departed seat's recorded motion"):return
	if not check(not view._number_visible(4) and view.visual_numbers.is_empty(),"a departed player receives no old damage-number playback"):return
	data=fixture("old-explosion");data.shot.duration=8.0
	data.shot.impacts=[{"at":0.5,"x":1200,"y":770,"radius":50,"kind":"normal","projectile":1}]
	sounds.clear();set_fixture(data,106.0)
	if not check(view.particles.is_empty() and view.explosions.is_empty() and is_zero_approx(view.shake) and sounds.is_empty(),"an expired explosion creates no fresh debris, flash, shake or sound"):return
	if not check(view.applied_holes==2 and int(view.battle.units[1].hp)==220,"expired visual effects still apply their terrain and HP outcomes"):return
	if not check(view.fired_impacts.size()==1,"the expired event is consumed exactly once"):return
	data=fixture("partially-aged-explosion");set_fixture(data,100.0)
	sounds.clear();seed(13579)
	var at:=Vector2(1200,770)
	view.explode(at,50,"normal",1,.6)
	if not check(not view.particles.is_empty() and is_zero_approx(view.shake) and sounds.is_empty(),"a partially aged explosion keeps only its surviving visual tail"):return
	for particle:Dictionary in view.particles:
		if not check(float(particle.life)<=.50001 and (particle.position as Vector2).distance_to(at)>.001,"late debris has aged lifetime and motion instead of spawning at the muzzle"):return
	data=fixture("restart-same-map");data.shot=null;set_fixture(data,100.0)
	if not check(view.applied_holes==0 and view.visual_numbers.is_empty() and view.particles.is_empty(),"a new match on the same map clears old cuts, numbers and debris"):return
	if not check(view.terrain.image.get_pixel(1200,770).a>0,"same-map restart restores the original solid terrain pixel"):return
	await capture("same-map-restart")
	data = fixture("team-supply", 3)
	data.shot = null
	data.deadline = 135.0
	data.units[0].hp = 270
	data.supplies = [
		{"id": 1, "at": 100.0, "seat": 0, "x": 700.0, "y": 806.0, "amount": 40},
		{"id": 2, "at": 100.0, "seat": 4, "x": 1200.0, "y": 756.0, "amount": 40, "fuel": true},
	]
	set_fixture(data, 100.08)
	if not check(view.battle.units[0].hp == 270 and view.supply_numbers.size() == 1 and view.supply_numbers[0].amount == 40,
			"team supply displays the nominal increase without revealing a hidden enemy"):return
	await capture("team-supply")
	set_fixture(data, 100.08)
	if not check(view.supply_numbers.size() == 1, "polling the same supply event does not replay it"):return
	clock.now = 103.0
	view._process(0)
	if not check(view.supply_numbers.is_empty(), "the supply number expires after the native animation"):return
	await capture("team-supply-expired")
	data.id = "new-match-after-supply"
	data.supplies = []
	set_fixture(data, 103.0)
	if not check(view.supply_numbers.is_empty() and view.last_supply_id == 0, "the next match starts with no retained supply feedback"):return
	observations.checks=checks
	observations.private_desktop=true;observations.silent=true;observations.no_accounts_created=true
	print("VISUAL_TIMELINE_ACCEPTANCE "+JSON.stringify(observations))
	quit()
