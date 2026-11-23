extends SceneTree
## Normal auth UI, native channel controls and real state requests on a private desktop.

var app: Node
var options := {}
var checks: Array[String] = []
var failed := false
var timings := {}

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for argument in OS.get_cmdline_user_args():
		if "=" in argument:
			var pair := argument.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.profile).path_join("vault"))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("CHANNEL_GATE: " + message)
		quit(2)
	checks.append(message)

func wait_until(predicate: Callable, message: String, seconds := 15.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	check(bool(predicate.call()), message)

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name + ".png"))

func click(control: Control, double := false) -> void:
	check(is_instance_valid(control), "mouse target exists")
	if failed: return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.pressed = pressed
		event.double_click = double
		event.button_index = MOUSE_BUTTON_LEFT
		root.push_input(event)
		await process_frame

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await wait_until(func(): return bootstrap.get_child_count() > 0, "game instantiated")
	app = bootstrap.get_child(0)
	await wait_until(func(): return app.scene == "login" and app.catalog.has("vehicles"), "normal login and catalog ready")
	if failed: return
	await create_timer(0.5).timeout
	await click(app.skin.find_child("ToggleRegistration", true, false))
	await wait_until(func(): return app.register_mode, "actual register toggle receives click")
	if failed: return
	app.username.text = str(options.name)
	app.password.text = "qa-only-895432"
	app.confirmation.text = "qa-only-895432"
	var began := Time.get_ticks_msec()
	await click(app.skin.find_child("Login", true, false))
	await wait_until(func(): return app.scene == "channel", "registration leads to channel, not lobby")
	if failed: return
	var gate: Control = app.channel_gate
	await wait_until(func(): return gate.phase == "intro_in" and gate.intro_alpha > 0.2, "intro visibly fades in")
	check(gate.enter_button.disabled and gate.row.disabled, "intro blocks channel controls")
	await screenshot("01-fade-in")
	await wait_until(func(): return gate.phase == "intro_hold", "intro has an explicit hold")
	check(is_equal_approx(gate.intro_alpha, 1.0), "held intro is fully visible")
	await screenshot("02-intro")
	await create_timer(0.5).timeout
	check(gate.phase == "intro_hold", "fast network cannot flash through the hold")
	await wait_until(func(): return gate.phase == "intro_out" and gate.intro_alpha < 0.8, "intro visibly fades out")
	await screenshot("03-fade-out")
	await wait_until(func(): return gate.phase == "closing" and gate.closed > 0.25 and gate.closed < 0.95, "both door leaves close progressively")
	await screenshot("04-closing")
	await wait_until(func(): return gate.phase == "latch", "door has a separate latch effect")
	await screenshot("05-latch")
	await wait_until(func(): return gate.phase == "select", "channel opens for selection only after closing")
	timings["intro_and_close_ms"] = Time.get_ticks_msec() - began
	check(int(timings.intro_and_close_ms) >= 3000, "intro and closure are independent of network speed")
	check(gate.cue_events.count(11) == 1 and gate.cue_events.count(12) == 1, "close motor and latch emit once each")
	check(not gate.row.disabled and gate.enter_button.disabled, "online channel selectable; enter requires selection")
	await create_timer(0.8).timeout
	check(app.scene == "channel" and app.channel_gate == gate, "state polling cannot bypass channel chooser")
	await screenshot("06-channel")
	# Exercise layout and real hit tests at both a wide and a tall window.
	for dimensions in [Vector2i(1680, 945), Vector2i(1000, 900), Vector2i(1366, 768)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(0.18).timeout
		for control in [gate.row, gate.enter_button, gate.refresh_button, gate.details]:
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()), "channel control inside " + str(dimensions))
		await screenshot("layout-%dx%d" % [dimensions.x, dimensions.y])
	await click(gate.row)
	check(gate.selected and gate.row.button_pressed and not gate.enter_button.disabled, "real mouse click selects and enables enter")
	var saved_token: String = app.net.token
	app.net.token = ""
	await click(gate.refresh_button)
	check(app.scene == "channel" and not app.auth_busy, "refresh before auth is ready cannot log out or bypass chooser")
	app.net.token = saved_token
	var endpoint: String = app.net.endpoint
	# Keep the intentional entry failure separate from an unrelated background
	# outage notification; verify successful real polling explicitly below.
	app.poll_elapsed = -5.0
	await wait_until(func(): return not app.poll_busy, "background state request settled before failure probe")
	app.net.endpoint = "http://127.0.0.1:1"
	await click(gate.enter_button)
	await wait_until(func(): return gate.phase == "select", "failed entry returns to selectable channel")
	check(app.scene == "channel" and gate.cue_events.count(10) == 0, "connection failure never opens the door")
	app.net.endpoint = endpoint
	var failure_notice: String = gate.status
	await app._poll()
	check(gate.status == failure_notice, "successful background polls preserve entry failure feedback")
	gate.set_refreshing(true)
	await app._poll()
	check(gate.refresh_button.disabled, "polling cannot enable a refresh still in progress")
	gate.set_refreshing(false)
	app.poll_elapsed = 0
	await click(gate.refresh_button)
	await wait_until(func(): return not app.channel_refreshing, "refresh finishes")
	check(gate.online and gate.selected, "refresh preserves selected real channel")
	# A double click exercises the alternative entry path and duplicate guard.
	await click(gate.row, true)
	await wait_until(func(): return gate.phase == "opening", "double click validates the session and opens door")
	check(app.scene == "lobby" and app.channel_accepted, "lobby is prepared underneath the opening gate")
	check(gate.cue_events.count(10) == 1, "open cue occurs once")
	await create_timer(0.2).timeout
	check(gate.closed > 0 and gate.closed < 1, "opening is animated, not a frame switch")
	await screenshot("07-opening")
	var history: Array = gate.phase_history.duplicate()
	await wait_until(func(): return not is_instance_valid(app.channel_gate), "finished gate releases its input overlay")
	check(app.scene == "lobby", "lobby remains after transition")
	await screenshot("08-lobby")
	var created: bool = await app._command({"action": "create", "name": "Channel QA", "map": 4, "capacity": 8})
	check(created and app.scene == "room", "normal room creation works after channel entry")
	var left: bool = await app._command({"action": "leave"})
	check(left and app.scene == "lobby" and not is_instance_valid(app.channel_gate), "leaving room does not replay opening or channel")
	check(not failed, "all channel checks passed")
	var report := {"passed": not failed, "checks": checks, "timings": timings, "phases": history, "private_desktop": true, "silent": true}
	var file := FileAccess.open(str(options.output).path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("CHANNEL_GATE_ACCEPTANCE " + JSON.stringify(report))
	await app._quit()
