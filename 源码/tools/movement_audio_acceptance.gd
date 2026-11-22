extends SceneTree

class Clock extends RefCounted:
	func server_now() -> float:return 100.0

var options:Dictionary={}
var checks:Array=[]
var sound:Node
var view:Control
var fixture:Dictionary

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()==2:options[pair[0]]=pair[1]
	_run.call_deferred()

func check(ok:bool,message:String) -> bool:
	if not ok:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func general_channels() -> int:
	var count:=0
	for player:AudioStreamPlayer in sound.players:
		if player.playing:count+=1
	return count

func begin_walk(unit_index:=0) -> void:
	view.set_battle(fixture.duplicate(true))
	for unit:Dictionary in view.battle.units:
		view.render_positions[str(int(unit.seat))]=Vector2(float(unit.x),float(unit.y))
	var active:Dictionary=view.battle.units[unit_index]
	view.render_positions[str(int(active.seat))]=Vector2(float(active.x)-25,float(active.y))
	view._process(1.0/120)

func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	sound=load("res://sound.gd").new()
	root.add_child(sound)
	sound.apply_volume()
	if not check(AudioServer.is_bus_mute(0),"master bus is muted while real AudioStreamPlayers execute"):return
	var samples:Array=[]
	for vehicle in range(1,31):
		sound.stop_movement()
		var before:int=sound.movement_starts
		sound.play_effect("move",vehicle)
		var cue:String=sound.movement_cue
		var expected:String=str(sound.native_audio.movement[str((vehicle-1)%10+1)])
		if not check(sound.movement.playing and cue==expected,"vehicle %d starts its original movement family cue"%vehicle):return
		for repeat in range(120):sound.play_effect("move",vehicle)
		if not check(sound.movement_starts==before+1 and general_channels()==0,"vehicle %d repeated movement never allocates overlapping effect channels"%vehicle):return
		samples.append({"vehicle":vehicle,"cue":cue,"duration":sound.movement.stream.get_length()})
		sound.play_effect("move_stop")
		if not check(not sound.movement.playing and sound.movement_cue.is_empty(),"vehicle %d stop ends the movement cue immediately"%vehicle):return
	# Run across actual clip boundaries; repeated notifications must neither
	# restart a playing sample nor build up 0.18-second overlapping channels.
	var before:int=sound.movement_starts
	var duration:=1.8
	var elapsed:=0.0
	while elapsed<duration:
		sound.play_effect("move",2)
		if not check(sound.movement.playing and general_channels()==0,"continuous movement remains on its single dedicated voice at %.2f seconds"%elapsed):return
		await create_timer(.05).timeout
		elapsed+=.05
	var starts:int=sound.movement_starts-before
	if not check(starts>=2 and starts<=5,"continuous walk naturally repeats finished samples without frame-by-frame restarts"):return
	var old:AudioStreamPlayer=sound.movement
	sound.play_effect("move",3)
	if not check(sound.movement==old and sound.movement_cue=="move03.wav" and general_channels()==0,"changing vehicle sound replaces the cue on the same voice"):return
	sound.effects_volume=0
	sound.apply_volume()
	sound.play_effect("move",1)
	if not check(not sound.movement.playing,"zero effects volume stops movement and prevents restart"):return
	sound.effects_volume=.75
	sound.apply_volume()
	sound.play_effect("move",1)
	sound.silent=true
	sound.apply_volume()
	sound.play_effect("move_stop")
	if not check(not sound.movement.playing,"silent mode and move_stop stop an already playing movement cue"):return
	sound.silent=false
	sound.apply_volume()
	sound.play_effect("move",1)
	sound.set_scene("room")
	if not check(not sound.movement.playing,"changing music scene also stops movement immediately"):return
	sound.music.stop()

	fixture=JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
	fixture.shot=null
	fixture.holes=[]
	fixture.deadline=120
	fixture.result=null
	view=load("res://world_view.gd").new()
	view.clock=Clock.new()
	view.player_id=1
	view.size=Vector2(1366,768)
	root.add_child(view)
	view.set_process(false)
	view.effect.connect(func(kind:String,detail:int):sound.play_effect(kind,detail))
	begin_walk(1)
	if not check(int(view.battle.units[1].ai)>0 and sound.movement.playing and sound.movement_cue=="move02.wav","real AI unit walking uses its original cue on the dedicated movement voice"):return
	var ai_dead:Dictionary=fixture.duplicate(true)
	ai_dead.units[1].hp=0
	view.set_battle(ai_dead)
	view._process(.01)
	if not check(not sound.movement.playing,"real AI death stops its movement voice without lingering footsteps"):return
	begin_walk()
	if not check(sound.movement.playing and view.movement_active,"real world movement starts the dedicated cue"):return
	for repeat in range(6):view._process(.01)
	if not check(general_channels()==0,"repeated real world frames leave all shared effect channels free"):return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join("movement-world.png"))
	var state:Dictionary=fixture.duplicate(true)
	state.units[0].hp=0
	view.set_battle(state)
	view._process(.01)
	if not check(not sound.movement.playing and not view.movement_active,"death snapshot stops movement before any trailing sample continues"):return
	begin_walk()
	state=fixture.duplicate(true)
	state.units[0].falling=true
	view.set_battle(state)
	view._process(.01)
	if not check(not sound.movement.playing,"falling snapshot stops the walking sound"):return
	begin_walk()
	state=fixture.duplicate(true)
	state.units[0].departed=true
	view.set_battle(state)
	view._process(.01)
	if not check(not sound.movement.playing,"departed player stops the walking sound"):return
	begin_walk()
	for unit:Dictionary in view.battle.units:
		var authoritative:Dictionary=view.source_units[int(unit.seat)]
		view.render_positions[str(int(unit.seat))]=Vector2(float(authoritative.x),float(authoritative.y))
	view._process(.01)
	if not check(not sound.movement.playing,"reaching the authoritative position stops the walking sound"):return
	begin_walk()
	view.battle={}
	view._process(.01)
	if not check(not sound.movement.playing,"empty battle stops the walking sound"):return
	begin_walk()
	view.size=Vector2.ZERO
	view._process(.01)
	if not check(not sound.movement.playing,"zero-sized removed viewport does not leave movement running"):return
	view.size=Vector2(1366,768)
	begin_walk()
	root.remove_child(view)
	if not check(not sound.movement.playing,"world exit-tree stops movement immediately"):return
	root.add_child(view)
	view.set_process(false)
	begin_walk()
	# Resolve the real page only after release split packs have been mounted.
	var app_script:=GDScript.new()
	app_script.source_code="extends \"res://main.gd\"\nfunc _ready() -> void:\n\tset_process(false)\n\tset_process_input(false)\n\tset_process_unhandled_input(false)\n"
	if not check(app_script.reload()==OK,"real main page-clear harness resolves after release packs mount"):return
	var app:Node=app_script.new()
	root.add_child(app)
	app.sound=sound
	app.content=Control.new()
	app.add_child(app.content)
	view.reparent(app.content)
	app.view=view
	app._clear()
	if not check(not sound.movement.playing,"real main page-clear stops movement synchronously before queued view deletion"):return
	await process_frame
	app.sound=null
	app.queue_free()
	sound.shutdown()
	if not check(not sound.movement.playing,"shutdown stops the dedicated movement voice"):return
	sound.stream_cache.clear()
	sound.queue_free()
	await process_frame
	await process_frame
	# The Dummy audio mixer still releases stopped sample playback on its own
	# tick. Give it that tick before exiting the entire engine process.
	await create_timer(.15).timeout
	var report:Dictionary={"passed":true,"checks":checks,"vehicles":samples,"continuous_starts":starts,"dummy_audio":true,"master_muted":true,"no_network":true,"no_accounts_created":true}
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("MOVEMENT_AUDIO_ACCEPTANCE "+JSON.stringify(report))
	quit()
