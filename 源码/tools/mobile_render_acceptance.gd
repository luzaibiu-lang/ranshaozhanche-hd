extends SceneTree

const SIZE := Vector2i(1536, 1024)
const TANK := preload("res://native_vehicle.gd")
const WORLD := preload("res://world_view.gd")
const TERRAIN := preload("res://native_terrain.gd")

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()

func _run() -> void:
	var packs := OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file), false)
	var checks := 0
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/terrain-masks.json")).masks
	var terrain := TERRAIN.new(definitions)
	for dimensions: Vector2i in [SIZE, Vector2i(1535, 1023), Vector2i(512, 512), Vector2i(240, 120), Vector2i(239, 257)]:
		var original := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		original.fill(Color(.25,.5,.75,1))
		terrain.reset(original)
		for id in range(1, definitions.size() + 1):
			var x := (id * 111) % dimensions.x
			var y := (id * 71) % dimensions.y
			terrain.carve({"mask": id, "x": x, "y": y})
			if id % 5 == 1:
				terrain.carve({"mask": id, "x": 0, "y": dimensions.y - 1})
			if id % 5 == 2:
				terrain.carve({"mask": id, "x": dimensions.x - 1, "y": 1})
			if id % 5 == 4:
				terrain.carve({"r": 15.5, "x": x + .7, "y": y - .8})
			terrain.flush()
			var expected: Image = terrain.image.duplicate()
			expected.resize(terrain.overview_image.get_width(), terrain.overview_image.get_height(), Image.INTERPOLATE_NEAREST)
			if expected.get_data() != terrain.overview_image.get_data() or expected.get_data() != terrain.overview.get_image().get_data():
				push_error("Minimap mismatch %s mask %d" % [dimensions, id])
				quit(2)
				return
			checks += 1
	var view := WORLD.new()
	view.size = Vector2(1024, 600)
	root.add_child(view)
	view.catalog = {"vehicles": [{"id": 1, "weapons": [{"projectile": 3}, {"projectile": 20}, {"projectile": 72}]}, {"id": 2, "weapons": [{"projectile": 49}]}]}
	var unit := {"name": "QA", "player": 1, "team": 0, "seat": 0, "vehicle": 1, "x": 500.0, "y": 760.0, "hp": 370, "max_hp": 370, "face": 1}
	var battle := {"id": "native-prewarm-028", "map": 4, "width": SIZE.x, "height": SIZE.y, "units": [unit], "loading": true, "active": 0, "deadline": 0, "holes": [], "shot": null}
	view.set_battle(battle)
	var cold_size: int = view.texture_cache.size()
	var start := Time.get_ticks_usec()
	await view.prepare_for_play()
	for id: int in [3, 4, 20, 22, 72, 71, 100, 101, 102, 104, 105, 106]:
		if not view.projectile_frames.has(id) or view.projectile_frames[id].is_empty():
			push_error("Missing active projectile %d" % id)
			quit(3)
			return
		checks += 1
	if view.projectile_frames.has(49):
		push_error("Unselected vehicle's projectile was warmed")
		quit(4)
		return
	checks += 1
	for frame: Dictionary in TANK.frame_cache[1]:
		if not TANK.texture_cache.has("1/%s" % frame.file):
			push_error("Vehicle animation not warmed")
			quit(5)
			return
		checks += 1
	var warm_size: int = view.texture_cache.size()
	battle.shot = {"id": 1, "trails": [{"projectile": 3}, {"projectile": 4}], "impacts": [{"projectile": 4}]}
	view.set_battle(battle)
	if view.texture_cache.size() != warm_size:
		push_error("Selected cluster rounds imported textures during the shot")
		quit(6)
		return
	checks += 1
	battle.shot = {"id": 2, "trails": [{"projectile": 49}], "impacts": [{"projectile": 49}]}
	view.set_battle(battle)
	if view.projectile_frames[49].is_empty() or view.texture_cache.size() <= warm_size:
		push_error("Unanticipated shot failed to load")
		quit(7)
		return
	checks += 1
	view.queue_free()
	await process_frame
	print("RENDER028 " + JSON.stringify({"checks": checks, "before": cold_size, "after": warm_size, "elapsed_us": Time.get_ticks_usec()-start, "minimap_comparisons": definitions.size()*5}))
	quit()
