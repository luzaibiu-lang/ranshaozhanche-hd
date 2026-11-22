extends SceneTree
class Clock extends RefCounted:
	var value:=100.0
	func server_now() -> float:return value
var clock:=Clock.new()
var options:Dictionary={}
var checks:Array=[]
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.trim_prefix("--").split("=",true,1)
		if pair.size()==2:options[pair[0]]=pair[1]
	_run.call_deferred()
func check(ok:bool,message:String) -> bool:
	if not ok:push_error(message);quit(2);return false
	checks.append(message)
	return true
func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	var battle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
	var sound:Node=load("res://sound.gd").new()
	root.add_child(sound)
	var view:Control=load("res://world_view.gd").new()
	view.clock=clock
	view.player_id=1
	view.size=Vector2(1366,768)
	root.add_child(view)
	view.set_process(false)
	view.effect.connect(func(kind:String,detail:int):sound.play_effect(kind,detail))
	view.set_battle(battle)
	var at:=0.0
	for frame:Dictionary in battle.shot.visuals:
		if not frame.get("falls",[]).is_empty():at=float(frame.at);break
	if not check(at>0,"actual Go fall fixture has a timed native fallout cue"):return
	clock.value=100+at-.001
	view._process(0)
	if not check(sound.played_cues.count("dropping.wav")==0,"fallout sound does not play before native death boundary"):return
	clock.value=100+at+.001
	view._process(0)
	if not check(sound.played_cues.count("dropping.wav")==1,"native dropping.wav really starts on fallout frame"):return
	view.set_battle(battle.duplicate(true))
	view._process(0)
	if not check(sound.played_cues.count("dropping.wav")==1,"repeated snapshot does not repeat fallout sound"):return
	var late:=battle.duplicate(true)
	late.id="late-fall-fixture"
	clock.value=100+at+2
	view.set_battle(late)
	view._process(0)
	if not check(sound.played_cues.count("dropping.wav")==1,"late state catchup does not replay expired fallout sound"):return
	var report:Dictionary={"checks":checks,"passed":true,"dummy_audio":true,"master_muted":true,"played_cue":"dropping.wav"}
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("FALL_AUDIO_ACCEPTANCE "+JSON.stringify(report))
	sound.shutdown()
	sound.stream_cache.clear()
	sound.queue_free()
	view.queue_free()
	await process_frame
	await process_frame
	quit()
