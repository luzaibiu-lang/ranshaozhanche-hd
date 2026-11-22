extends Node

var music: AudioStreamPlayer
var players: Array[AudioStreamPlayer] = []
var effects: Array[String] = []
var tracks: Array[String] = []
var music_volume := 0.45
var effects_volume := 0.75
var silent := false
var scene := ""
var native_audio: Dictionary = {}
var stream_cache := {}
var played_cues: Array[String] = []
var movement:AudioStreamPlayer
var movement_cue:=""
var movement_starts:=0
var shutting_down := false
var retiring_playbacks: Array[WeakRef] = []

func _ready() -> void:
	music = AudioStreamPlayer.new()
	add_child(music)
	movement=AudioStreamPlayer.new()
	add_child(movement)
	music.finished.connect(func():
		if not shutting_down and not silent and music.stream!=null:music.play()
	)
	for i in range(12):
		var player := AudioStreamPlayer.new()
		players.append(player)
		add_child(player)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	for path: String in manifest.get("music", []):
		tracks.append(path)
	for path: String in manifest.get("sound", []):
		effects.append(path)
	tracks.sort()
	effects.sort()
	native_audio = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/native-audio.json"))

func shutdown() -> void:
	if shutting_down:return
	shutting_down=true
	silent=true
	var all_players := players.duplicate()
	all_players.append(music)
	all_players.append(movement)
	for player in all_players:
		if player.has_stream_playback():
			retiring_playbacks.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream=null
		player.queue_free()
	players.clear()
	stream_cache.clear()

func wait_for_shutdown() -> void:
	# stop() queues disposal on the mixer. Its last reference is released on a later frame.
	var deadline := Time.get_ticks_msec()+2000
	while not retiring_playbacks.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		for index in range(retiring_playbacks.size()-1,-1,-1):
			if retiring_playbacks[index].get_ref()==null:
				retiring_playbacks.remove_at(index)
	if not retiring_playbacks.is_empty():
		push_warning("Audio mixer shutdown timed out with %d active playback(s)" % retiring_playbacks.size())

func set_scene(value: String, map_id := 0) -> void:
	if shutting_down:return
	var key := value+str(map_id)
	if scene == key or tracks.is_empty():
		return
	scene = key
	stop_movement()
	var chosen: String = tracks[0]
	var wanted := "stage%02d.ogg" % map_id if value=="battle" and map_id>0 else "gamewait.ogg"
	for path in tracks:
		var name_lower := path.to_lower()
		if path.get_file().to_lower()==wanted:
			chosen = path
			break
	if value == "battle" and chosen == tracks[0] and tracks.size() > 2:
		chosen = tracks[2]
	music.stream = load(chosen)
	apply_volume()
	if not silent:
		music.play()

func apply_volume() -> void:
	if shutting_down:return
	music.volume_db = linear_to_db(maxf(0.0001, music_volume))
	music.stream_paused = silent or music_volume <= 0.0
	movement.volume_db=linear_to_db(maxf(.0001,effects_volume))
	if silent or effects_volume<=0:stop_movement()
	for player in players:
		player.volume_db = linear_to_db(maxf(0.0001, effects_volume))
		player.stream_paused = silent or effects_volume <= 0.0

func play_cue(filename: String, priority:=false) -> void:
	if silent or effects_volume<=0 or filename.is_empty():return
	var path := "res://assets/audio/sound/"+filename
	if not ResourceLoader.exists(path):return
	if not stream_cache.has(path):stream_cache[path] = load(path)
	var available:AudioStreamPlayer=null
	for player in players:
		if not player.playing:
			available=player
			break
	# Dense multi-hit volleys may fill all twelve effects channels. The lock
	# announcement must still sound; replace one incidental burst if needed.
	if available==null and priority and not players.is_empty():
		available=players.back()
		available.stop()
	if available==null:return
	available.stream = stream_cache[path]
	available.pitch_scale = 1.0
	available.play()
	played_cues.append(filename)
	if played_cues.size()>32:played_cues.pop_front()

func play_event(id: int) -> void:
	play_cue(str(native_audio.get("sounds",{}).get(str(id),"")),id in [54,55])

func play_effect(kind: String, detail := 0) -> void:
	if kind=="native":play_event(detail);return
	if kind=="move_stop":stop_movement();return
	if silent or effects.is_empty() or effects_volume <= 0:
		return
	if kind=="fall":
		play_event(6)
		return
	if kind=="move" and detail>0:
		var filename:=str(native_audio.get("movement",{}).get(str((detail-1)%10+1),""))
		if filename.is_empty():stop_movement();return
		if movement.playing and movement_cue==filename:return
		var path:="res://assets/audio/sound/"+filename
		if not stream_cache.has(path):stream_cache[path]=load(path)
		movement.stop()
		movement_cue=filename
		movement.stream=stream_cache[path]
		movement.pitch_scale=1
		movement.play()
		movement_starts+=1
		return
	if kind in ["fire","explosion"] and detail>0:
		var native: Dictionary = native_audio.get("projectiles",{}).get(str(detail),{})
		var cue := str(native.get("fire" if kind=="fire" else "impact",""))
		if not native.is_empty():
			play_cue(cue)
			return
	var keywords: Array = ["fire", "shot", "weapon"] if kind == "fire" else ["exp", "bomb", "hit"]
	if kind == "click":
		keywords = ["click", "button", "select"]
	if kind == "move":
		keywords = ["move", "walk"]
	var chosen: String = ""
	for keyword in keywords:
		for path in effects:
			if keyword in path.to_lower():
				chosen = path
				break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		if kind=="move": return
		chosen = effects[mini(3 if kind == "fire" else 6, effects.size() - 1)]
	play_cue(chosen.get_file())

func stop_movement() -> void:
	if is_instance_valid(movement):movement.stop()
	movement_cue=""
