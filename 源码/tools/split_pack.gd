extends SceneTree
## Run in an empty project so only the exported PCK is visible to the walker.
var files: Array[String] = []
var groups := {}
var assignments := {}

func walk(path: String) -> void:
	var directory := DirAccess.open(path)
	directory.include_hidden = true
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			walk(child)
		else:
			files.append(child)
		name = directory.get_next()
	directory.list_dir_end()

func group_for(path: String) -> String:
	if path.begins_with("res://assets/app_icon.png"): return "core"
	if path.begins_with("res://assets/fonts/NotoSansSC-UI.otf"):return "font_ui"
	var parts := path.trim_prefix("res://assets/").split("/")
	if not path.begins_with("res://assets/"): return "core"
	if parts[0] in ["maps","tanks"] and parts.size()>1:
		return str(parts[0])+"_"+str(parts[1])
	if parts[0]=="audio" and parts.size()>2:
		return "music_"+str(parts[2]).get_basename() if parts[1]=="music" else "sound"
	return "interface"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3 or not ProjectSettings.load_resource_pack(args[0]):
		push_error("Expected exported pack and output directory")
		quit(2)
		return
	walk("res://")
	files.sort()
	for path in files:
		assignments[path] = group_for(path)
	for path in files:
		if path.ends_with(".remap") or path.ends_with(".import"):
			var config := ConfigFile.new()
			if config.parse(FileAccess.get_file_as_string(path))==OK:
				var destination: String = str(config.get_value("remap","path",""))
				if not destination.is_empty(): assignments[destination]=group_for(path)
	for path in files:
		var group: String = assignments.get(path,"core")
		if not groups.has(group): groups[group]=[]
		groups[group].append(path)
	DirAccess.make_dir_recursive_absolute(args[1].path_join("packs"))
	for name: String in groups:
		var output: String = args[1].path_join("Game.pck" if name=="core" else "packs/"+name+".pck")
		var pack := PCKPacker.new()
		assert(pack.pck_start(output)==OK)
		for path: String in groups[name]:
			assert(pack.add_file(path, path)==OK)
		if name=="core":
			assert(pack.add_file("res://assets/app_icon.png",args[2])==OK)
		assert(pack.flush()==OK)
	print(JSON.stringify({"split_packs":groups.size(),"files":files.size()}))
	quit()
