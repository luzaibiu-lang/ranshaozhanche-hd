extends SceneTree
## Render real native vehicle nodes and retain a sequence, not a static mockup.
var portraits := []
var stage: Control
var output := ""
var checks := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	output = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	stage = Control.new()
	root.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("333d4b")
	background.size = Vector2(1600, 1000)
	stage.add_child(background)
	for id in range(1, 31):
		var vehicle := load("res://native_vehicle.gd").new() as Node2D
		vehicle.position = Vector2(130 + (id - 1) % 6 * 265, 145 + (id - 1) / 6 * 180)
		vehicle.scale = Vector2.ONE * 2.8
		stage.add_child(vehicle)
		portraits.append(vehicle)
		var title := Label.new()
		title.text = str(id)
		title.position = vehicle.position - Vector2(100, 135)
		stage.add_child(title)
	var seen := {}
	for frame in range(36):
		for index in range(30):
			var id := index + 1
			var unit := {"vehicle": id, "face": -1 if frame < 18 else 1, "hp": 300, "shield": 0, "stun": 0, "stealth": 0}
			if frame >= 30:unit.hp = 0
			portraits[index].pose(unit, 25, 0, frame >= 6 and frame < 30, 1.0 / 15)
			var layer_files := []
			for layer in portraits[index].layers:
				if layer.visible:
					assert(layer.texture != null, "Missing original layer")
					layer_files.append(layer.texture.resource_path)
			var key := str(id)
			if not seen.has(key):seen[key] = {}
			seen[key][str(layer_files)] = true
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("vehicles-%02d.png" % frame))
	for id in range(1, 31):
		var minimum := 3 if (id - 1) % 10 == 6 else 4
		if seen[str(id)].size() < minimum:
			push_error("Vehicle %d did not animate: %d native poses" % [id, seen[str(id)].size()])
			quit(2)
			return
	checks.append("30 vehicles rendered idle, walking, both directions and native death frames")
	print("NATIVE_VEHICLE_ACCEPTANCE " + JSON.stringify({"checks": checks, "frames": 36, "vehicles": 30}))
	quit()
