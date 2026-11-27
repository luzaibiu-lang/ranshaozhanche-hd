extends SceneTree

var files: Array[String] = []
var groups := {}
var assigned := {}
var forced := {}

func walk(path: String) -> void:
	var dir := DirAccess.open(path)
	dir.include_hidden = true
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():walk(child)
		else:files.append(child)
		name = dir.get_next()
	dir.list_dir_end()

func group_for(path: String) -> String:
	if forced.has(path):return "core"
	if path.begins_with("res://assets/fonts/NotoSansSC-Regular.otf"):return "font_full"
	if path.begins_with("res://assets/audio/music/"):
		return "music_"+path.get_file().trim_suffix(".import")
	if path.begins_with("res://assets/maps/"):
		return "map_"+path.trim_prefix("res://assets/maps/").get_slice("/",0)
	if path.begins_with("res://assets/scenery/") or path.begins_with("res://assets/projectiles/"):
		return "battle_fx"
	if path.begins_with("res://assets/effects/") and not path.begins_with("res://assets/effects/PrevMap") and not path.begins_with("res://assets/effects/TotUnit269/"):
		return "battle_fx"
	return "core"

func pack(paths: Array, destination: String, manifest := "") -> void:
	var pck := PCKPacker.new()
	assert(pck.pck_start(destination)==OK)
	for path: String in paths:assert(pck.add_file(path,path)==OK)
	if not manifest.is_empty():assert(pck.add_file("res://web-stream.json",manifest)==OK)
	assert(pck.flush()==OK)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()==5)
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[4]))
	for path: String in settings.get("core",[]):forced[path]=true
	assert(ProjectSettings.load_resource_pack(args[0]))
	walk("res://")
	files.sort()
	for path in files:assigned[path]=group_for(path)
	for path in files:
		if path.ends_with(".import") or path.ends_with(".remap"):
			var config := ConfigFile.new()
			if config.parse(FileAccess.get_file_as_string(path))==OK:
				var target := str(config.get_value("remap","path",""))
				if not target.is_empty():assigned[target]=group_for(path)
	for path in files:
		var group: String = assigned.get(path,"core")
		if not groups.has(group):groups[group]=[]
		groups[group].append(path)
	DirAccess.make_dir_recursive_absolute(args[1])
	var manifest := {"version":str(settings.version),"groups":{}}
	for group: String in groups:
		if group=="core":continue
		var pending := args[1].path_join(group+".pck")
		pack(groups[group],pending)
		var digest := FileAccess.get_sha256(pending)
		var target := args[1].path_join(digest+".pck")
		assert(DirAccess.rename_absolute(pending,target)==OK)
		manifest.groups[group]={"url":args[2]+"/"+digest+".pck","sha256":digest,"size":FileAccess.get_file_as_bytes(target).size()}
	var json_path := args[1].path_join("stream.json")
	var json_file := FileAccess.open(json_path,FileAccess.WRITE)
	json_file.store_string(JSON.stringify(manifest))
	json_file.close()
	assert(JSON.parse_string(FileAccess.get_file_as_string(json_path)) is Dictionary)
	pack(groups.core,args[3],json_path)
	print(JSON.stringify({"groups":groups.size(),"core_bytes":FileAccess.get_file_as_bytes(args[3]).size(),"files":files.size()}))
	quit()
