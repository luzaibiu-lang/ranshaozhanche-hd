extends SceneTree

var app: Control
var options: Dictionary = {}
var directory: String
var serial := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	directory = str(options.output)
	OS.set_environment("LOCALAPPDATA", directory.path_join("profile"))
	OS.set_environment("BCHD_VAULT_ROOT", directory.path_join("vault"))
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await process_frame
	app = bootstrap.get_child(0)
	while app.catalog.is_empty():
		await create_timer(.1).timeout
	if not str(app.net.endpoint).begins_with("http://127.0.0.1:"):
		quit(2)
		return
	var auth: Dictionary = await app.net.request("/api/login", {"name": options.name, "password": "qa-only-895432"})
	if not auth.has("token"):
		quit(3)
		return
	app.net.token = auth.token
	app.channel_accepted = true
	await app._poll()
	while not FileAccess.file_exists(directory.path_join("finish")):
		var path := directory.path_join("cmd-%d.json" % (serial + 1))
		if FileAccess.file_exists(path):
			var cmd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			match str(cmd.action):
				"chat":
					app.chat_input.text = cmd.text
					await app._send_chat()
				"fire":
					await app._battle_command({"action":"fire", "aim_mode":"native", "angle":45, "power":.65, "weapon":0})
				"screenshot":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(directory.path_join(str(cmd.name) + ".png"))
				"return":
					var button := app.find_child("ReturnToRoom", true, false) as Button
					if button:
						button.pressed.emit()
				_:
					await app._command(cmd)
			serial += 1
		var state := {"serial": serial, "scene": app.scene, "version": app.snapshot.get("version"), "room": app.snapshot.get("room"), "visible_chat": ""}
		if is_instance_valid(app.chat_label):
			state.visible_chat = app.chat_label.get_parsed_text()
		var temp := directory.path_join("state.tmp")
		var file := FileAccess.open(temp, FileAccess.WRITE)
		file.store_string(JSON.stringify(state))
		file.close()
		DirAccess.rename_absolute(temp, directory.path_join("state.json"))
		await create_timer(.2).timeout
	await app._quit()
