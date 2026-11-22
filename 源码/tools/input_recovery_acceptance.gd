extends SceneTree

const NETWORK = preload("res://net.gd")
const PASSWORD := "qa-only-895432"
var options: Dictionary = {}
var checks: Array[String] = []
var app: Control
var guest: RefCounted
var observe_frames:=false
var last_frame_time:=0
var max_network_frame_gap_ms:=0

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	process_frame.connect(func():
		var now:=Time.get_ticks_msec()
		if observe_frames and last_frame_time>0:max_network_frame_gap_ms=maxi(max_network_frame_gap_ms,now-last_frame_time)
		last_frame_time=now
	)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.output).path_join("profile"))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.output).path_join("vault"))
	if not str(options.get("qa-endpoint", "")).begins_with("http://127.0.0.1:"):
		push_error("Input recovery QA requires a local client endpoint")
		quit(2)
		return
	_run.call_deferred()

func check(ok: bool, message: String) -> bool:
	if ok:
		checks.append(message)
		return true
	push_error(message)
	root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
	quit(2)
	return false

func wait_for(condition: Callable, message: String, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return check(true, message)
		await create_timer(.03).timeout
	return check(false, message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func tap(code: Key) -> void:
	await key(code, true)
	await key(code, false)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name + ".png"))

func generation() -> int:
	return int(app._battle_data().get("generation", -1))

func next_player_turn() -> bool:
	var response: Dictionary = await guest.request("/api/command", {"action": "pass", "generation": generation()})
	if not check(response.has("profile"), "guest skips its authoritative turn"):
		return false
	return await wait_for(func(): return app._my_turn(), "polling delivers the next player turn")

func verify_low_sp() -> bool:
	if not await wait_for(func(): return not app.poll_busy, "state polling is idle before the SP fixture"):
		return false
	app.poll_busy = true
	var own: Dictionary = app._own_battle_unit()
	var before := generation()
	var previous_sp := int(own.sp)
	var previous_predicted_sp := int(app.walker.unit.sp)
	var previous_cost := int(app._weapon_cost(own, 2))
	await tap(KEY_F3)
	if not check(previous_cost == 125 and app.selected_weapon == 2, "F3 selected at its actual 125 SP cost"):
		return false
	# Use the screenshot's 105 SP in the displayed snapshots while the Go
	# service keeps its real state. The failed shot must stay client-side.
	own.sp = 105
	app.walker.unit.sp = 105
	var cue_count: int = app.sound.played_cues.count("effect02.wav")
	var requests: int = app.net.request_sequence
	await key(KEY_SPACE, true)
	await create_timer(.18).timeout
	await capture("insufficient-sp")
	if not check(app.toast_label.text == "SP 不足" and app.toast_label.get_theme_stylebox("normal") is StyleBoxEmpty,
			"insufficient SP uses a short unframed native notice"):
		return false
	if not check(app.toast_label.get_global_rect().end.y < app.battle_hud.wind_rect().position.y and
			app.toast_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"battle notice stays above the wind and power meters without intercepting input"):
		return false
	if not check(not app.charging and not app.battle_action_busy and not app.command_busy,
			"holding Space at 105 SP gives feedback without entering charge"):
		return false
	await key(KEY_SPACE, false)
	if not check(app.sound.played_cues.count("effect02.wav") == cue_count + 1,
			"Space failure plays the original sound once across press and release"):
		return false
	if not check(generation() == before and app.net.request_sequence == requests and app._battle_data().get("shot") == null,
			"failed attempt consumes neither turn nor network action"):
		return false
	own.sp=previous_sp
	await tap(KEY_SPACE)
	if not check(not app.charging and app.net.request_sequence==requests,
		"predicted movement fuel blocks F3 before a stale server fuel value can allow charging"):return false
	own.sp=105
	app.walker.unit.sp=previous_predicted_sp
	await key(KEY_SPACE,true)
	if not check(app.charging,"pre-confirmation fuel can begin charging"):return false
	await key(KEY_SPACE,false)
	if not check(not app.battle_action_busy and app.net.request_sequence==requests and app._battle_data().get("shot")==null,
		"fuel is checked again after movement confirmation without sending an unaffordable shot"):return false
	await tap(KEY_F1)
	await key(KEY_SPACE, true)
	if not check(app.selected_weapon == 0 and app.charging, "F1 immediately restores usable Space charging"):
		return false
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await key(KEY_SPACE, false)
	if not check(not app.charging and app.net.request_sequence == requests,
			"focus loss cancels charge without firing on release"):
		return false
	await key(KEY_SPACE, true)
	await tap(KEY_ESCAPE)
	if not check(app._modal_open() and not app.charging, "opening the battle menu cancels current charge"):
		return false
	await key(KEY_SPACE, false)
	await tap(KEY_SPACE)
	if not check(app.net.request_sequence == requests, "battle menu suppresses Space without submitting an action"):
		return false
	await tap(KEY_ESCAPE)
	if not check(not app._modal_open(), "closing the battle menu returns input to the game"):
		return false
	own.sp = previous_sp
	app.walker.unit.sp = previous_predicted_sp
	app.poll_busy = false
	return true

func verify_late_item_reply() -> bool:
	var armed: Dictionary = await app.net.request("/qa/late-item-reply")
	if not check(bool(armed.get("ok", false)), "late item error is armed after an applied item"):
		return false
	var before := generation()
	var cue := str(app.sound.native_audio.get("sounds", {}).get("13", ""))
	var cue_count: int = app.sound.played_cues.count(cue)
	await tap(KEY_F5)
	if not await wait_for(func(): return int(app.profile.inventory[0]) == 0 and not app.command_busy and not app.battle_action_busy,
			"polled item consumption releases the controls before the delayed reply", 1.0):
		return false
	if not check(app.sound.played_cues.count(cue) == cue_count + 1, "confirmed item plays the original sound once"):
		return false
	await key(KEY_SPACE, true)
	if not check(generation() == before and app.charging, "Space charges immediately in the same turn after F5"):
		return false
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await key(KEY_SPACE, false)
	await create_timer(1.2).timeout
	return check(not app.command_busy and not app.battle_action_busy and not app.charging and
		not "QA late item" in app.toast_label.text and app.sound.played_cues.count(cue) == cue_count + 1,
		"late item error leaves input and feedback intact without replaying the sound")

func verify_late_move_error() -> bool:
	var walker: RefCounted = app.walker
	var initial: Dictionary = walker.unit.duplicate(true)
	var direction := 1
	var best := 0
	for candidate in [-1, 1]:
		walker.unit = initial.duplicate(true)
		var moved: int = walker._move(candidate * 20)
		if moved > best:
			best = moved
			direction = candidate
	walker.unit = initial.duplicate(true)
	if not check(best >= 5, "map supports the late-reply movement case"):return false
	var armed: Dictionary = await app.net.request("/qa/late-move-error")
	if not check(bool(armed.get("ok", false)), "late error is armed after an applied move"):return false
	var before := generation()
	var arrow := KEY_RIGHT if direction > 0 else KEY_LEFT
	await key(arrow, true)
	if not await wait_for(func():return walker.in_flight, "move awaits its delayed reply", 1.0):return false
	await key(arrow, false)
	var began := Time.get_ticks_msec()
	await tap(KEY_F9)
	if not await wait_for(func():return generation()>before, "polled acknowledgement releases F9 before the move reply", 1.0):return false
	if not check(Time.get_ticks_msec()-began<1000, "confirmed movement never waits for its stale HTTP reply"):return false
	if not await next_player_turn():return false
	await key(KEY_SPACE, true)
	await create_timer(1.2).timeout
	if not check(app.charging and not app.walker.failed and not app.battle_action_busy,
		"late error cannot cancel a new turn or its Space charge"):return false
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await key(KEY_SPACE, false)
	return true

func verify_lost_move() -> bool:
	var before := generation()
	var walker: RefCounted = app.walker
	var initial: Dictionary = walker.unit.duplicate(true)
	var direction := 1
	var best := 0
	for candidate in [-1, 1]:
		walker.unit = initial.duplicate(true)
		var moved: int = walker._move(candidate * 20)
		if moved > best:
			best = moved
			direction = candidate
	walker.unit = initial.duplicate(true)
	if not check(best >= 5, "real map spawn exposes a supported walking segment"):
		return false
	var armed: Dictionary = await app.net.request("/qa/drop-move-ack")
	if not check(bool(armed.get("ok", false)), "lost movement acknowledgement is armed on the relay"):
		return false
	var arrow := KEY_RIGHT if direction > 0 else KEY_LEFT
	observe_frames=true
	await key(arrow, true)
	if not await wait_for(func(): return walker.in_flight and absf(float(walker.unit.x) - float(initial.x)) > 0,
			"local movement works before confirmation", 1.5):
		return false
	await key(arrow, false)
	var began := Time.get_ticks_msec()
	await tap(KEY_F9)
	var recovery_deadline := began + 4500
	while Time.get_ticks_msec() < recovery_deadline and generation() == before:
		await create_timer(.03).timeout
	if not check(generation() > before and not app.battle_action_busy and not app.command_busy,
			"F9 survives a lost movement reply: %s" % JSON.stringify({
				"elapsed": Time.get_ticks_msec() - began,
				"pending": walker.pending,
				"flight": walker.in_flight,
				"active": walker.active,
				"failed": walker.failed,
				"generation": generation(),
				"busy": app.battle_action_busy,
				"toast": app.toast_label.text,
			})):
		return false
	var elapsed := Time.get_ticks_msec() - began
	if not check(elapsed < 4200, "movement recovery avoids the former eleven-second lock"):
		return false
	observe_frames=false
	if not check(max_network_frame_gap_ms<250,"render/input frames continue through network timeout and retry: %d ms"%max_network_frame_gap_ms):return false
	if not await next_player_turn():
		return false
	var second_turn := generation()
	var delayed_fire:Dictionary=await app.net.request("/qa/late-fire-reply")
	if not check(bool(delayed_fire.get("ok",false)),"late fire reply is armed after actual server execution"):return false
	await key(KEY_SPACE, true)
	await create_timer(.23).timeout
	if not check(app.charging and float(app.charge) > .045, "Space still charges in the new turn after movement recovery"):
		return false
	await key(KEY_SPACE, false)
	if not await wait_for(func(): return app._battle_data().get("shot") is Dictionary, "Space release sends one real shot"):
		return false
	if not check(not app.command_busy,"published shot releases command input before its missing original reply"):return false
	await tap(KEY_SPACE)
	if not await wait_for(func(): return generation() > second_turn and not app.battle_action_busy,
			"authoritative shot resolves and leaves the next turn playable", 14.0):
		return false
	await capture("after-shot")
	if not await next_player_turn():
		return false
	await create_timer(6.1).timeout
	if not check(not app.command_busy and not app.battle_action_busy and not "QA late fire" in app.toast_label.text,
		"late fire error cannot relock a subsequent turn or replace current feedback"):return false
	return check(not app.command_busy and not app.battle_action_busy and not app.charging,
		"late reply does not carry a movement or charging lock into the next turn")

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(.25).timeout
	app = bootstrap.get_child(0)
	if not check(app.net.endpoint == str(options["qa-endpoint"]), "client is connected to the isolated relay"):
		return
	if not await wait_for(func(): return not app.catalog.is_empty(), "normal startup loads the real catalog"):
		return
	app.register_mode = true
	app._show_login()
	app.username.text = str(options.name)
	app.password.text = PASSWORD
	app.confirmation.text = PASSWORD
	app._login()
	if not await wait_for(func(): return not app.auth_busy, "local registration request completes"):
		return
	if not check(app.scene == "lobby", "normal registration enters the lobby: " + app.toast_label.text):
		return
	var bought: bool = await app._command({"action": "buy", "item": 1, "slot": 0})
	if not check(bought and int(app.profile.inventory[0]) == 1, "player buys a real item in F5 slot before entering battle"):
		return
	guest = NETWORK.new(app)
	guest.endpoint = str(options.upstream)
	var response: Dictionary = await guest.request("/api/register", {"name": str(options.name) + "b", "password": PASSWORD})
	if not check(response.has("token"), "second player registers on the local Go service"):
		return
	guest.token = str(response.token)
	var created: bool = await app._command({"action": "create", "name": "输入恢复验收", "map": 9, "capacity": 8})
	if not check(created, "first player creates a real room"):
		return
	response = await guest.request("/api/command", {"action": "join", "room": int(app.snapshot.room.id)})
	if not check(response.has("profile"), "second player joins the room"):
		return
	await app._command({"action": "vehicle", "vehicle": 1})
	await app._command({"action": "start"})
	if not await wait_for(func(): return app.scene == "battle" and app._my_turn(), "both players enter a real battle"):
		return
	var focus := root.gui_get_focus_owner()
	if focus:
		focus.release_focus()
	if not await verify_low_sp():
		return
	if not await verify_late_item_reply():
		return
	if not await verify_late_move_error():
		return
	if not await verify_lost_move():
		return
	await guest.request("/api/command", {"action": "leave"})
	guest.root = null
	guest = null
	var report := {"passed": true, "checks": checks, "private_desktop": true, "silent": true,"max_network_frame_gap_ms":max_network_frame_gap_ms}
	FileAccess.open(str(options.output).path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	await app._quit()
