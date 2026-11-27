extends Node

func _ready() -> void:
	if OS.has_feature("web"):
		var resources := preload("res://web_resources.gd").new()
		resources.name="WebResources"
		get_tree().root.add_child.call_deferred(resources)
		await get_tree().process_frame
	# Release resources are independent packs, so changing code does not
	# force players to download all maps, music and vehicles again.
	if OS.has_feature("windows"):
		var directory := OS.get_executable_path().get_base_dir().path_join("packs")
		if DirAccess.dir_exists_absolute(directory):
			for file in DirAccess.get_files_at(directory):
				if file.ends_with(".pck") and not ProjectSettings.load_resource_pack(directory.path_join(file), false):
					push_error("无法加载游戏资源："+file)
					get_tree().quit(3)
					return
	var game: PackedScene = load("res://main.tscn")
	add_child(game.instantiate())
