extends SceneTree

var app: Control
var options := {}
var checks:Array[String]=[]

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: options[pair[0]] = pair[1]
	var folder := str(options.output).path_join(str(options.name))
	OS.set_environment("LOCALAPPDATA", folder)
	OS.set_environment("BCHD_VAULT_ROOT", folder.path_join("vault"))
	_run.call_deferred()

func expect(condition: bool, message: String) -> bool:
	if condition:
		checks.append(message)
		return true
	push_error(message)
	quit(2)
	return false

func wait_for(condition: Callable, message: String) -> bool:
	for i in range(220):
		if condition.call(): return expect(true,message)
		await create_timer(.075).timeout
	return expect(false, message)

func key(code: int, unicode := 0) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.unicode = unicode if pressed else 0
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await process_frame
	app = bootstrap.get_child(0)
	if not await wait_for(func(): return not app.catalog.is_empty(), "catalog"): return
	if not expect(str(app.net.endpoint).begins_with("http://127.0.0.1:"), "test endpoint"): return
	var auth: Dictionary = await app.net.request("/api/login", {"name": options.name, "password": "qa-only-895432"})
	if not expect(auth.has("token"), "fixture login"): return
	app.net.token = auth.token
	app.channel_accepted = true
	await app._poll()
	if not await wait_for(func(): return app.scene == "battle", "battle entry"): return
	await process_frame
	var movement_top: float = app.size.y - 109 * app.battle_hud.scale_factor
	if not expect(app.chat_input.get_global_rect().end.y < movement_top, "message field clears movement HUD"): return
	if not expect(app.chat_label.text.contains("开局前"), "room history retained at battle entry"): return
	var mine := "甲 在战斗中" if options.role == "a" else "乙 已收到"
	var peer := "乙 已收到" if options.role == "a" else "甲 在战斗中"
	await key(KEY_ENTER)
	if not expect(app.chat_input.has_focus(), "Enter opens battle chat"): return
	app.chat_input.insert_text_at_caret("草稿")
	await key(KEY_ESCAPE)
	if not expect(not app.chat_input.has_focus() and app.chat_input.text.is_empty() and not app._modal_open(), "Esc cancels only chat"): return
	if options.role == "b":
		if not await wait_for(func(): return app.chat_label.text.contains(peer), "guest receives host text"): return
	var active: int = app._battle_data().generation
	var selected: int = app.selected_weapon
	await key(KEY_ENTER)
	app.chat_input.insert_text_at_caret(mine.left(1))
	await key(KEY_SPACE, 32)
	await key(KEY_F2)
	await key(KEY_F9)
	app.chat_input.insert_text_at_caret(mine.substr(2))
	if not expect(app.chat_input.text == mine and not app.charging and active == int(app._battle_data().generation) and app.selected_weapon == selected, "chat text and battle shortcuts isolated"): return
	await key(KEY_ENTER)
	if not await wait_for(func(): return app.chat_label.text.contains(mine) and not app.chat_input.has_focus() and app.chat_input.text.is_empty(), "submit acknowledges and releases chat"): return
	if not await wait_for(func(): return app.chat_label.text.contains(peer), "received peer text in battlefield"): return
	var count := 0
	for message: Dictionary in app.snapshot.room.chat:
		if str(message.text) == mine: count += 1
	if not expect(count == 1, "message delivered once"): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(str(options.role) + ".png"))
	var marker := FileAccess.open(str(options.output).path_join(str(options.role) + ".ok"), FileAccess.WRITE)
	marker.close()
	var peer_marker := str(options.output).path_join(("b" if options.role == "a" else "a") + ".ok")
	if not await wait_for(func(): return FileAccess.file_exists(peer_marker), "both clients received"): return
	if options.role == "a":
		await app._battle_command({"action":"fire","aim_mode":"native","angle":app.aim,"power":.8,"weapon":0})
		if not expect(float(app._battle_data().deadline)==0 and app._battle_data().shot is Dictionary,"ordinary shot is playing before chat"):return
		await key(KEY_ENTER)
		app.chat_input.insert_text_at_caret("射击时也能聊天")
		await key(KEY_ENTER)
	if not await wait_for(func():return app.chat_label.text.contains("射击时也能聊天"),"chat delivered while shot is playing"):return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(str(options.role)+"-during-shot.png"))
	FileAccess.open(str(options.output).path_join(str(options.role)+"-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks,"private_desktop":true,"audio_driver":"Dummy","ime_hardware_not_tested":true}))
	FileAccess.open(str(options.output).path_join(str(options.role)+"-shot.ok"),FileAccess.WRITE).close()
	if not await wait_for(func():return FileAccess.file_exists(str(options.output).path_join(("b" if options.role=="a" else "a")+"-shot.ok")),"both clients received during shot"):return
	print("BATTLE_CHAT_ACCEPTANCE " + str(options.role))
	await app._quit()
