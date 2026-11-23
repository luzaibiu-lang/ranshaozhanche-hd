extends Control

const OriginalSkin = preload("res://original_skin.gd")
const LoginArt = preload("res://login_art.gd")

const Network = preload("res://net.gd")
const Sound = preload("res://sound.gd")
const WorldView = preload("res://world_view.gd")
const BG := Color("0c1420")
const PAPER := Color("101018")
const MUTED := Color("363645")
const GOLD := Color("003e85")
const TEAMS := [Color("ff4438"), Color("efc138"), Color("83c83b"), Color("4288ef")]

var net: RefCounted
var sound: Node
var catalog: Dictionary = {}
var snapshot: Dictionary = {}
var profile: Dictionary = {}
var config: Dictionary = {}
var data_root := ""
var scene := ""
var ui_scale := 1.0
var content: Control
var header: HBoxContainer
var account_label: Label
var toast_label: Label
var toast_timer := 0.0
var toast_battle_mode := false
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var remember: CheckBox
var register_mode := false
var poll_busy := false
var command_busy := false
var command_serial:=0
var command_context:Dictionary={}
var poll_elapsed := 0.0
var chat_label: RichTextLabel
var chat_input: LineEdit
var sending_chat: LineEdit
var battle_chat: Control
var room_list: VBoxContainer
var player_list: VBoxContainer
var invitation_stamp := ""
var selected_room_id := 0
var selected_lobby_player_id := 0
var lobby_player_query := ""
var lobby_player_search: LineEdit
var room_grid: Control
var room_title: Label
var room_status: Label
var map_choice: OptionButton
var map_previous: Button
var map_next: Button
var vehicle_choice: OptionButton
var room_preview: Control
var vehicle_picker: Control
var start_button: Button
var ready_button: Button
var view: Control
var battle_status: Label
var battle_detail: Label
var charge_bar: ProgressBar
var fire_button: Button
var weapon_buttons: Array[Button] = []
var result_layer: Control
var selected_weapon := 0
var sound_turn_stamp := ""
var aim := 45.0
var aim_face:=0
var charge := 0.0
var charge_ticks:=0.0
var charging := false
var charge_generation := -1
var move_elapsed := 0.0
var walker:RefCounted
var battle_action_busy:=false
var battle_action_serial:=0
var battle_input_stamp:=""
var last_room_stamp := ""
var last_lobby_stamp := ""
var last_chat_stamp := ""
var last_inventory_stamp := ""
var shop_grid: GridContainer
var native_shop: Control
var launcher_ticket:=""
var launched_session:=false
var reveal_tween:Tween
var reveal_layer:ColorRect
var shop_room_id := 0
var inventory_row: HBoxContainer
var full_screen := false
var old_size := Vector2i(1280, 800)
var old_position := Vector2i.ZERO
var old_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var qa := false
var qa_options := {}
var network_failures := 0
var skin: Control
var aim_slider: HSlider
var battle_hud: Control
var hud_buttons := {}
var ui_font: SystemFont
var shop_gold: Label
var quitting := false
var auth_busy := false
var auth_generation := 0
var channel_gate: Control
var channel_accepted := false
var channel_refreshing := false
var page_transition: Control
var page_transition_applying := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_quit)
	for argument in OS.get_cmdline_user_args():
		if argument == "--qa":
			qa = true
		elif argument.begins_with("--qa-") and "=" in argument:
			var pair := argument.substr(5).split("=", true, 1)
			qa_options[pair[0]] = pair[1]
		elif argument.begins_with("--launcher-ticket="):
			launcher_ticket=argument.trim_prefix("--launcher-ticket=")
	if not qa and launcher_ticket.is_empty() and OS.get_executable_path().get_file()=="Game.exe" and not "--script" in OS.get_cmdline_args():
		_return_to_launcher()
		return
	data_root = OS.get_environment("LOCALAPPDATA").path_join("BurningChariotHD") if OS.has_feature("windows") else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(data_root)
	var path := data_root.path_join("settings.json")
	if FileAccess.file_exists(path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary:
			config = saved
	if qa:
		config = {"endpoint": "http://127.0.0.1:18180", "music": 0.0, "effects": 0.0}
	var connection_file := OS.get_executable_path().get_base_dir().path_join("connection.json")
	if FileAccess.file_exists(connection_file) and not qa:
		var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(connection_file))
		if settings is Dictionary and settings.has("endpoint"):
			config.endpoint = settings.endpoint
	if qa_options.has("endpoint"):
		config.endpoint = qa_options.endpoint
	net = Network.new(self)
	net.endpoint = str(config.get("endpoint", "http://127.0.0.1:18180"))
	sound = Sound.new()
	add_child(sound)
	sound.silent = qa
	sound.music_volume = float(config.get("music", 0.45))
	sound.effects_volume = float(config.get("effects", 0.75))
	sound.apply_volume()
	_setup_window()
	_apply_theme()
	_build_shell()
	if launcher_ticket.is_empty():_show_login()
	else:_show_launch_loading()
	toast("正在连接高清版服务…", 20)
	await _ensure_server()
	var response: Dictionary = await net.request("/api/catalog")
	if response.has("vehicles"):
		catalog = response
		toast("准备就绪", 2)
	else:
		toast("暂时无法连接服务，可在设置中检查服务器地址", 8)
	if qa:
		await _qa_run()
	else:
		var startup_generation := auth_generation
		var saved_token := _vault("consume-handoff",launcher_ticket) if not launcher_ticket.is_empty() else _vault("read", "") if not auth_busy and auth_generation==0 else ""
		if not saved_token.is_empty():
			auth_busy=true
			_set_login_busy(true)
			net.token = saved_token
			var state: Dictionary = await net.request("/api/state")
			if quitting or startup_generation!=auth_generation:return
			if state.has("profile"):
				launched_session=not launcher_ticket.is_empty()
				_accept_state(state)
				if launched_session and qa_options.has("proof") and net.endpoint.begins_with("http://127.0.0.1:"):
					# Launcher QA now verifies the real chooser, not a page
					# that skipped it on the first successful state reply.
					while is_instance_valid(channel_gate) and channel_gate.phase != "select" and not quitting:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var proof:=str(qa_options.proof)
					get_viewport().get_texture().get_image().save_png(proof+".png")
					var report:=FileAccess.open(proof,FileAccess.WRITE)
					report.store_string(JSON.stringify({"scene":scene,"username":str(profile.name),"handoff_consumed":true,"viewport":str(get_viewport_rect().size)}))
			else:
				net.token = ""
			auth_busy=false
			_set_login_busy(false)
		if not launcher_ticket.is_empty() and not launched_session:_return_to_launcher()

func _return_to_launcher() -> void:
	var host:=OS.get_executable_path().get_base_dir().path_join("LauncherHost.exe")
	if FileAccess.file_exists(host):OS.create_process(host,PackedStringArray(["--wait-game="+str(OS.get_process_id())]))
	if is_instance_valid(sound):
		await _quit()
	else:
		get_tree().quit()

func _show_launch_loading() -> void:
	_show_channel_gate()

func _show_channel_gate() -> void:
	if is_instance_valid(channel_gate): return
	_clear()
	skin = null
	scene = "channel"
	sound.set_scene("lobby")
	channel_gate = preload("res://native_channel_gate.gd").new()
	add_child(channel_gate)
	move_child(channel_gate, toast_label.get_index())
	channel_gate.cue_requested.connect(func(id: int): sound.play_event(id))
	channel_gate.enter_requested.connect(_enter_channel)
	channel_gate.refresh_requested.connect(_refresh_channels)
	channel_gate.settings_requested.connect(_settings)
	channel_gate.fullscreen_requested.connect(_toggle_fullscreen)
	channel_gate.exit_requested.connect(_quit)
	channel_gate.opened.connect(func():
		if not is_instance_valid(channel_gate): return
		channel_gate.queue_free()
		channel_gate = null
	)

func _cancel_channel_gate() -> void:
	if is_instance_valid(channel_gate):
		channel_gate.hide()
		channel_gate.queue_free()
	channel_gate = null
	channel_accepted = false
	channel_refreshing = false

func _cancel_page_transition() -> void:
	if is_instance_valid(page_transition):
		page_transition.hide()
		page_transition.queue_free()
	page_transition = null
	page_transition_applying = false

func _begin_page_transition() -> void:
	if is_instance_valid(page_transition) or quitting: return
	get_viewport().gui_release_focus()
	for child in get_children():
		if child is Window: child.hide()
	page_transition = preload("res://native_page_transition.gd").new()
	page_transition.z_index = 100
	add_child(page_transition)
	var door := page_transition
	var generation := auth_generation
	door.cue_requested.connect(func(id: int): sound.play_event(id))
	door.covered.connect(func():
		if quitting or generation != auth_generation or door != page_transition: return
		# Keep displaying the old page until the metal leaves fully cover it.
		# Use the newest buffered snapshot, including changes during closing.
		page_transition_applying = true
		_accept_state(snapshot)
		page_transition_applying = false
		if is_instance_valid(door) and door == page_transition: door.begin_open()
	)
	door.opened.connect(func():
		if door != page_transition: return
		door.hide()
		door.queue_free()
		page_transition = null
		# A room may disappear while its door is opening. Finish revealing
		# this page, then apply the newest destination through its own door.
		_accept_state(snapshot)
	)

func _enter_channel() -> void:
	if quitting or not is_instance_valid(channel_gate): return
	if auth_busy:
		channel_gate.reject_enter("登录正在确认，请稍后重试")
		return
	var gate := channel_gate
	var generation := auth_generation
	var requested_token: String = net.token
	var state: Dictionary = await net.request("/api/state")
	if quitting or generation != auth_generation or gate != channel_gate or not is_instance_valid(gate) or net.token != requested_token: return
	if not state.has("profile"):
		gate.reject_enter(str(state.get("error", "频道连接失败，请重试")))
		if int(state.get("status", 0)) == 401: _logout()
		return
	# Buffer the newest authoritative snapshot while the gate is closed.
	# Polls can update it, but cannot select a channel or skip the animation.
	_accept_state(state)
	channel_accepted = true
	_accept_state(snapshot)
	gate.begin_open()

func _refresh_channels() -> void:
	if quitting or auth_busy or channel_refreshing or not is_instance_valid(channel_gate): return
	if net.token.is_empty():
		channel_gate.show_notice("正在确认登录，请稍候")
		return
	var gate := channel_gate
	var generation := auth_generation
	channel_refreshing = true
	gate.set_refreshing(true)
	var state: Dictionary = await net.request("/api/state")
	if quitting or generation != auth_generation or gate != channel_gate or not is_instance_valid(gate): return
	channel_refreshing = false
	gate.set_refreshing(false)
	if state.has("profile"): _accept_state(state)
	else:
		gate.show_notice(str(state.get("error", "频道刷新失败，请重试")))
		if int(state.get("status", 0)) == 401: _logout()

func _setup_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var work := DisplayServer.screen_get_usable_rect(screen)
	var target := Vector2i(int(work.size.x * 0.88), int(work.size.y * 0.88))
	if config.has("window_size") and not qa:
		target = Vector2i(int(config.window_size[0]), int(config.window_size[1]))
	target = target.clamp(Vector2i(mini(1000, work.size.x), mini(650, work.size.y)), work.size - Vector2i(24, 48))
	if qa and qa_options.has("size"):
		var parts: PackedStringArray = str(qa_options.size).split("x")
		target = Vector2i(int(parts[0]), int(parts[1]))
	DisplayServer.window_set_min_size(Vector2i(mini(960, work.size.x - 40), mini(600, work.size.y - 80)))
	DisplayServer.window_set_size(target)
	DisplayServer.window_set_position(work.position + (work.size - target) / 2)
	DisplayServer.window_set_title("燃烧战车 · 高清重制版")
	ui_scale = clampf(float(target.y) / 900.0, 0.8, 2.25)
	Engine.max_fps = int(config.get("fps", 120))
	get_viewport().size_changed.connect(_on_resize)

func _on_resize() -> void:
	var next_scale := clampf(size.y / 900.0, 0.8, 2.25)
	if absf(next_scale - ui_scale) > 0.05:
		ui_scale = next_scale
		_apply_theme()
	if not full_screen:
		var dimensions := DisplayServer.window_get_size()
		config.window_size = [dimensions.x, dimensions.y]
	_layout_toast()

func _style(color: Color, border := Color("2c4056"), padding := 12.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(int(7 * ui_scale))
	box.content_margin_left = padding * ui_scale
	box.content_margin_right = padding * ui_scale
	box.content_margin_top = padding * ui_scale
	box.content_margin_bottom = padding * ui_scale
	return box

func _apply_theme() -> void:
	var value := Theme.new()
	if ui_font == null:
		ui_font = SystemFont.new()
		ui_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	value.default_font = ui_font
	value.default_font_size = maxi(12, int(15*ui_scale))
	for type in ["Button", "OptionButton"]:
		value.set_stylebox("normal", type, OriginalSkin.metal_style(0))
		value.set_stylebox("hover", type, OriginalSkin.metal_style(1))
		value.set_stylebox("pressed", type, OriginalSkin.metal_style(2))
		value.set_stylebox("disabled", type, OriginalSkin.metal_style(2))
		value.set_color("font_color", type, Color.BLACK)
		value.set_color("font_disabled_color", type, Color("55555d"))
	value.set_stylebox("normal", "LineEdit", OriginalSkin.box(Color("0068bf"), Color("003b75")))
	value.set_stylebox("focus", "LineEdit", OriginalSkin.box(Color("087bd1"), Color("c6dcec")))
	value.set_color("font_color", "LineEdit", Color.WHITE)
	value.set_stylebox("panel", "PanelContainer", OriginalSkin.box(Color("bfbfc7"), Color("55555c")))
	value.set_stylebox("panel", "PopupMenu", OriginalSkin.box(Color("005cb1"), Color("ccccd2")))
	value.set_color("font_color", "PopupMenu", Color.WHITE)
	value.set_color("font_color", "Label", Color.BLACK)
	value.set_color("default_color", "RichTextLabel", Color.BLACK)
	value.set_stylebox("background", "ProgressBar", OriginalSkin.box(Color("55555b"), Color("333333")))
	value.set_stylebox("fill", "ProgressBar", OriginalSkin.box(Color("e4c52b"), Color("c99e00")))
	for type in ["HBoxContainer", "VBoxContainer"]:
		value.set_constant("separation", type, maxi(4, int(7*ui_scale)))
	theme = value

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color.BLACK
	_fill(background)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	account_label = Label.new()
	account_label.visible = false
	add_child(account_label)
	content = Control.new()
	_fill(content)
	add_child(content)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.add_theme_stylebox_override("normal", _style(Color(0.08, 0.1, 0.15, 0.97), Color("c0c0c8")))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -48
	toast_label.offset_bottom = -10
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.visible = false
	add_child(toast_label)

func _original_page(background := "") -> void:
	_clear()
	skin = OriginalSkin.new()
	skin.click_sound.connect(func(): sound.play_event(65))
	skin.page = "room" if background == "GameBack" else "lobby"
	content.add_child(skin)
	_fill(skin)
	if not background.is_empty():
		skin.background(background)

func _original_chat() -> void:
	chat_label = RichTextLabel.new()
	chat_label.bbcode_enabled = false
	chat_label.scroll_following = true
	chat_label.add_theme_color_override("default_color", Color.BLACK)
	skin.place(chat_label, Rect2(14, 405, 512, 159), 12)
	chat_input = skin.entry(Rect2(12, 572, 489, 20))
	chat_input.max_length = 200
	chat_input.placeholder_text = ""
	chat_input.text_submitted.connect(func(_text): _send_chat())

func _original_profile() -> void:
	var avatar:=preload("res://native_avatar.gd").new()
	avatar.name="NativeAvatar"
	skin.place(avatar,Rect2(570,391,75,126))
	skin.label("", Rect2(655, 419, 132, 20), 12, Color.BLACK).name="ProfileName"
	skin.label("",Rect2(655,438,132,18),12,Color.BLACK).name="ProfileLevel"
	skin.label("",Rect2(655,456,132,18),12,Color.BLACK).name="ProfileWins"
	skin.label("",Rect2(655,474,132,18),12,Color.BLACK).name="ProfileGames"
	skin.label("",Rect2(655,492,132,18),12,Color.BLACK).name="ProfileXP"
	skin.label("", Rect2(655,510,132,18),12,Color.BLACK).name="ProfileGold"
	_update_profile_labels()

func _update_profile_labels() -> void:
	if not is_instance_valid(skin):return
	var games:=int(profile.get("games",0))
	var wins:=int(profile.get("wins",0))
	for pair in [["ProfileName","名称："+str(profile.get("name",""))],["ProfileLevel","等级：%d"%int(int(profile.get("xp",0))/1000)],["ProfileGold","金币：%d G"%int(profile.get("gold",0))],["ProfileWins","战绩：%d胜 %d败"%[wins,maxi(0,games-wins)]],["ProfileGames","胜率：%.1f%%"%(float(wins)*100/maxi(1,games))],["ProfileXP","积分：%d"%int(profile.get("xp",0))]]:
		var node := skin.get_node_or_null(str(pair[0])) as Label
		if node:node.text=str(pair[1])

func _label(text: String, parent: Node, points := 17, color := PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(points * ui_scale))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _panel(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _clear() -> void:
	if is_instance_valid(toast_label):toast_label.hide()
	toast_timer = 0.0
	if sound:sound.stop_movement()
	if walker:walker.cancel()
	walker=null
	battle_action_serial+=1
	battle_action_busy=false
	battle_input_stamp=""
	for child in get_children():
		if child is Window:
			child.hide()
			child.queue_free()
	for child in content.get_children():
		# A page can be replaced by a button's own pressed/text_submitted
		# handler. It must survive until Godot finishes dispatching that event.
		if child is CanvasItem:child.hide()
		child.queue_free()
	chat_label = null
	chat_input = null
	sending_chat = null
	battle_chat = null
	view = null
	native_shop = null
	vehicle_picker = null
	result_layer = null
	last_room_stamp = ""
	last_lobby_stamp = ""
	sound_turn_stamp = ""
	last_chat_stamp = ""
	last_inventory_stamp = ""

func toast(message: String, seconds := 4.0) -> void:
	if is_instance_valid(channel_gate):
		channel_gate.show_notice(message)
		return
	if not is_instance_valid(toast_label):
		return
	toast_label.text = message
	_layout_toast()
	toast_label.visible = true
	toast_timer = seconds

func _layout_toast() -> void:
	if not is_instance_valid(toast_label):return
	var in_battle := scene == "battle"
	if in_battle != toast_battle_mode:
		toast_battle_mode = in_battle
		toast_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new() if in_battle else _style(Color(0.08, 0.1, 0.15, 0.97), Color("c0c0c8")))
		toast_label.clip_text = in_battle
		toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if in_battle:
		# Native battle feedback is a short, unframed line above the wind and
		# power meters. Keep the actual controls and terrain unobstructed.
		var s := clampf(minf(size.x / 800.0, size.y / 600.0), 0.8, 3.0)
		var width := minf(size.x - 24.0 * s, 540.0 * s)
		toast_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		toast_label.position = Vector2((size.x - width) / 2.0, size.y - 82.0 * s)
		toast_label.size = Vector2(width, 24.0 * s)
		toast_label.add_theme_font_size_override("font_size", maxi(11, int(13.0 * s)))
		toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		toast_label.add_theme_constant_override("outline_size", maxi(1, int(2.0 * s)))
	else:
		toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		toast_label.offset_top = -48
		toast_label.offset_bottom = -10
		toast_label.remove_theme_font_size_override("font_size")
		toast_label.add_theme_constant_override("outline_size", 0)

func _show_login() -> void:
	_cancel_page_transition()
	_cancel_channel_gate()
	_original_page()
	scene = "login"
	skin.page = "login"
	sound.set_scene("lobby")
	skin.design_size = Vector2(760, 525 if register_mode else 510)
	var fill := ColorRect.new()
	fill.color = Color("121821")
	skin.place(fill, Rect2(0, 0, 760, 525 if register_mode else 510))
	var art := LoginArt.new()
	skin.place(art, Rect2(0, 0, 345, 510))
	var paper := Color("e2e7ed")
	var muted := Color("8f9cab")
	skin.label("炮火就绪，等你归队", Rect2(48, 365, 287, 37), 22, paper)
	skin.label("原生战车 · 回合对战 · 好友联机", Rect2(49, 410, 285, 25), 13, muted)
	skin.label("燃烧战车", Rect2(390, 43, 310, 44), 33, paper)
	skin.label("集结好友，下一发由你决定。", Rect2(393, 96, 315, 25), 13, muted)
	skin.label("账号", Rect2(395, 151, 300, 24), 13, paper)
	username = skin.entry(Rect2(395, 181, 300, 30))
	username.name = "Username"
	username.text = str(config.get("username", ""))
	username.max_length = 16
	skin.label("密码", Rect2(395, 226, 300, 24), 13, paper)
	password = skin.entry(Rect2(395, 256, 300, 30), true)
	password.name = "Password"
	for field in [username, password]:
		field.add_theme_stylebox_override("normal", OriginalSkin.box(Color("1e2733"), Color("344457")))
		field.add_theme_stylebox_override("focus", OriginalSkin.box(Color("1e2733"), Color("607080")))
		field.add_theme_color_override("font_color", paper)
	if register_mode:
		skin.label("确认密码", Rect2(395, 300, 300, 24), 13, paper)
		confirmation = skin.entry(Rect2(395, 329, 300, 30), true)
		confirmation.name="Confirmation"
		confirmation.add_theme_stylebox_override("normal", OriginalSkin.box(Color("1e2733"), Color("344457")))
	remember = CheckBox.new()
	remember.text = "记住登录（仅本机）"
	remember.button_pressed = bool(config.get("remember", false))
	remember.add_theme_color_override("font_color", muted)
	remember.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	remember.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	remember.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	skin.place(remember, Rect2(395, 299, 300, 25), 13)
	remember.visible = not register_mode
	var submit: Button = skin.text_button("创 建 账 号" if register_mode else "登 录 游 戏", Rect2(395, 380 if register_mode else 337, 300, 43), _login)
	submit.name = "Login"
	submit.add_theme_stylebox_override("normal", OriginalSkin.box(Color("f6ae3f"), Color("f6ae3f")))
	submit.add_theme_stylebox_override("hover", OriginalSkin.box(Color("ffc16c"), Color("ffc16c")))
	var toggle: Button = skin.text_button("已有账号，返回登录" if register_mode else "还没有账号？立即注册", Rect2(395, 430 if register_mode else 389, 300, 32), func():
		if auth_busy:return
		register_mode = not register_mode
		_show_login()
	)
	toggle.name="ToggleRegistration"
	toggle.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	toggle.add_theme_color_override("font_color", muted)
	password.text_submitted.connect(func(_value): _login())
	if register_mode:
		confirmation.text_submitted.connect(func(_value): _login())
	username.grab_focus()

func _login() -> void:
	if command_busy or auth_busy or quitting:
		return
	if register_mode and password.text != confirmation.text:
		toast("两次输入的密码不一致")
		return
	if username.text.strip_edges().is_empty() or password.text.is_empty():
		toast("请输入账号和密码")
		return
	var submitted_name := username.text.strip_edges()
	var submitted_password := password.text
	var remember_login := remember.button_pressed
	var registering := register_mode
	auth_generation+=1
	var generation := auth_generation
	auth_busy=true
	command_busy=true
	_set_login_busy(true)
	toast("正在注册…" if registering else "正在登录…", 15)
	var response: Dictionary = await net.request("/api/register" if registering else "/api/login", {"name": submitted_name, "password": submitted_password})
	if quitting or generation!=auth_generation:return
	if response.has("token"):
		net.token = response.token
		net.etag=""
		var state: Dictionary = await net.request("/api/state")
		if quitting or generation!=auth_generation:return
		if state.has("profile"):
			config.username=submitted_name
			config.remember=remember_login
			_vault("write" if remember_login else "clear",net.token if remember_login else "")
			_save_config()
			_accept_state(state)
			toast("欢迎归队，" + str(profile.name), 3)
		else:
			net.token=""
			toast(("账号已创建，请返回登录后重试。" if registering else "")+str(state.get("error","无法进入大厅，请重试")))
	else:
		toast(str(response.get("error", "登录失败")))
	auth_busy=false
	command_busy=false
	_set_login_busy(false)

func _set_login_busy(busy: bool) -> void:
	if scene!="login":return
	for node in [username,password,confirmation]:
		if is_instance_valid(node):node.editable=not busy
	if is_instance_valid(remember):remember.disabled=busy
	for node_name in ["Login","ToggleRegistration"]:
		var button := skin.find_child(node_name,true,false) as Button
		if button:button.disabled=busy

func _show_lobby() -> void:
	_original_page("LobyBack")
	scene = "lobby"
	sound.set_scene("lobby")
	skin.button("l_exit", Rect2(10, 9, 89, 44), _logout, "退出账号").name="Logout"
	skin.button("l_info", Rect2(123, 8, 89, 44), _room_info, "房间信息")
	skin.button("l_join", Rect2(234, 8, 89, 44), _join_first_room, "自动找位")
	skin.button("l_make", Rect2(344, 8, 89, 44), _create_dialog, "创建房间")
	skin.button("l_shop", Rect2(460, 8, 89, 44), _show_shop, "道具商店")
	skin.button("btn_gameitem", Rect2(560, 545, 117, 48), _show_game_items, "游戏物品")
	skin.button("l_full", Rect2(680, 545, 114, 48), _toggle_fullscreen, "全屏 / 窗口")
	var scroll := ScrollContainer.new()
	scroll.resized.connect(func():
		if scene=="lobby":_update_lobby.call_deferred()
	)
	var rooms_table:=preload("res://original_lobby_table.gd").new()
	rooms_table.name="OriginalRoomTable"
	rooms_table.headings=["No","道具","模式","地图","标题","房主","人员","密室","状态",""]
	rooms_table.column_widths=[43,53,53,89,100,45,40,50,40,20]
	rooms_table.grow_column=4
	skin.place(rooms_table,Rect2(9,82,539,277))
	skin.place(scroll, Rect2(10,101,537,257))
	room_list = VBoxContainer.new()
	room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_list.add_theme_constant_override("separation", 0)
	scroll.add_child(room_list)
	var players := ScrollContainer.new()
	var players_table:=preload("res://original_lobby_table.gd").new()
	players_table.name="OriginalPlayerTable"
	players_table.headings=["账号","性别","位置",""]
	players_table.column_widths=[114,36,53,20]
	players_table.logical_height=239
	players_table.grid_lines=true
	players_table.grow_column=0
	skin.place(players_table,Rect2(551,79,225,239))
	skin.place(players, Rect2(552,98,223,219))
	player_list = VBoxContainer.new()
	player_list.add_theme_constant_override("separation", 0)
	player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.add_child(player_list)
	lobby_player_query=""
	selected_lobby_player_id=0
	lobby_player_search=LineEdit.new()
	lobby_player_search.name="LobbyPlayerSearch"
	lobby_player_search.text=lobby_player_query
	lobby_player_search.max_length=16
	lobby_player_search.tooltip_text="查找在线玩家"
	for state in ["normal","focus"]:lobby_player_search.add_theme_stylebox_override(state,OriginalSkin.box(Color.WHITE,Color("808080")))
	lobby_player_search.add_theme_color_override("font_color",Color.BLACK)
	lobby_player_search.text_changed.connect(func(value:String):lobby_player_query=value;selected_lobby_player_id=0;_update_lobby())
	lobby_player_search.text_submitted.connect(func(_value):_search_lobby_player())
	skin.place(lobby_player_search,Rect2(571,332,87,20),12)
	skin.button("l_search",Rect2(666,330,27,27),_search_lobby_player,"查找在线玩家").name="SearchLobbyPlayer"
	for setting in [["RejectPrivate","reject_private",324],["RejectInvites","reject_invites",344]]:
		var toggle:=preload("res://original_toggle.gd").new()
		toggle.name=setting[0]
		toggle.button_pressed=bool(profile.get(setting[1],false))
		toggle.tooltip_text="拒绝私聊" if setting[1]=="reject_private" else "拒绝邀请"
		toggle.toggled.connect(func(value:bool):
			var rejects_private:=value if setting[1]=="reject_private" else bool(profile.get("reject_private",false))
			var rejects_invites:=value if setting[1]=="reject_invites" else bool(profile.get("reject_invites",false))
			await _command({"action":"preferences","reject_private":rejects_private,"reject_invites":rejects_invites})
		)
		skin.place(toggle,Rect2(706,setting[2],18,18))
	_original_chat()
	_original_profile()
	_update_lobby()

func _join_first_room() -> void:
	for room: Dictionary in snapshot.get("rooms", []):
		if not bool(room.started) and not bool(room.get("locked",false)) and int(room.players) < int(room.capacity):
			await _command({"action": "join", "room": int(room.id)})
			return
	toast("暂时没有可加入的房间")

func _join_room(id: int) -> void:
	var locked:=false
	for room:Dictionary in snapshot.get("rooms",[]):
		if int(room.id)==id:locked=bool(room.get("locked",false))
	if not locked:
		await _command({"action":"join","room":id})
		return
	var dialog:=_dialog("房间密码",Vector2(380,230))
	_label("请输入房间密码",dialog.get_meta("body"),16)
	var field:=LineEdit.new()
	field.name="JoinRoomPassword"
	field.secret=true
	field.max_length=16
	dialog.get_meta("body").add_child(field)
	dialog.confirmed.connect(func():await _command({"action":"join","room":id,"password":field.text}))
	dialog.popup_centered()
	field.grab_focus()

func _update_lobby() -> void:
	if is_instance_valid(page_transition) and not page_transition_applying: return
	var stamp := JSON.stringify([snapshot.get("rooms", []), snapshot.get("players", []), selected_room_id, selected_lobby_player_id, lobby_player_query, skin.pixel_scale])
	if stamp == last_lobby_stamp:return
	last_lobby_stamp = stamp
	for child in room_list.get_children():
		child.hide()
		child.queue_free()
	for room: Dictionary in snapshot.get("rooms", []):
		var row := preload("res://original_table_row.gd").new()
		var phase := str(room.get("phase", "battle" if bool(room.started) else "waiting"))
		var phase_text := "结算中" if phase=="settlement" else "对战中" if phase=="battle" else "等待"
		row.configure(["%03d"%int(room.id),"全部","普通",_map_name(int(room.map)),str(room.name),str(room.get("owner_name","")),"%d/%d"%[int(room.players),int(room.capacity)],"是" if bool(room.get("locked",false)) else "否",phase_text,""],[43,53,53,89,100,45,40,50,40,20],skin.pixel_scale,4)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text=str(room.name)
		row.toggle_mode = true
		row.button_pressed = selected_room_id == int(room.id)
		row.pressed.connect(func(): selected_room_id = int(room.id); _update_lobby.call_deferred())
		row.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.double_click:
				await _join_room(int(room.id))
		)
		room_list.add_child(row)
	if is_instance_valid(player_list):
		for child in player_list.get_children():
			child.hide()
			child.queue_free()
		for player: Dictionary in snapshot.get("players", []):
			if not lobby_player_query.strip_edges().is_empty() and not str(player.name).to_lower().contains(lobby_player_query.strip_edges().to_lower()):continue
			var row := preload("res://original_table_row.gd").new()
			row.configure([str(player.name),"","大厅" if int(player.get("room",0))==0 else "#%d"%int(player.room),""],[114,36,53,20],skin.pixel_scale,0)
			row.set_leading_icon(preload("res://assets/icons/Level/00.png"))
			row.set_meta("player_id",int(player.id))
			row.toggle_mode=true
			row.button_pressed=selected_lobby_player_id==int(player.id)
			row.mouse_default_cursor_shape=Control.CURSOR_ARROW
			row.tooltip_text="点击私聊 "+str(player.name)
			row.pressed.connect(func():selected_lobby_player_id=int(player.id);chat_input.text="/w "+str(player.name)+" ";chat_input.grab_focus();chat_input.caret_column=chat_input.text.length();_update_lobby.call_deferred())
			player_list.add_child(row)

func _search_lobby_player() -> void:
	var query:=lobby_player_query.strip_edges().to_lower()
	selected_lobby_player_id=0
	for player:Dictionary in snapshot.get("players",[]):
		if not query.is_empty() and str(player.name).to_lower().contains(query):
			selected_lobby_player_id=int(player.id)
			break
	_update_lobby()
	if not query.is_empty() and selected_lobby_player_id==0:toast("没有找到在线玩家",3)

func _room_info() -> void:
	var rooms: Array = snapshot.get("rooms", [])
	if rooms.is_empty():
		toast("当前没有房间")
		return
	var room: Dictionary = rooms[0]
	for candidate: Dictionary in rooms:
		if int(candidate.id) == selected_room_id:room = candidate
	var dialog := _dialog("房间信息", Vector2(440, 290))
	var body: VBoxContainer = dialog.get_meta("body")
	_label(str(room.name), body, 20)
	_label("地图：%s" % _map_name(int(room.map)), body, 15)
	_label("房主：%s" % str(room.get("owner_name", "")), body, 15)
	_label("人数：%d / %d" % [int(room.players), int(room.capacity)], body, 15)
	_label("对战中" if bool(room.started) else "等待开始", body, 15)
	dialog.get_ok_button().text = "加入房间"
	dialog.get_ok_button().disabled = bool(room.started) or int(room.players) >= int(room.capacity)
	dialog.confirmed.connect(func(): await _join_room(int(room.id)))
	dialog.popup_centered()

func _create_dialog() -> void:
	var dialog:=preload("res://native_room_form.gd").new()
	dialog.room_name=str(profile.get("name","好友"))+"的战场"
	dialog.pixel_scale=skin.pixel_scale
	dialog.size=Vector2i(Vector2(312,311)*dialog.pixel_scale)
	dialog.min_size=dialog.size
	add_child(dialog)
	dialog.confirmed.connect(func():await _command({"action":"create","name":dialog.name_field.text,"map":0,"capacity":dialog.capacity_field.get_selected_id(),"private":dialog.public_field.get_selected_id()==1,"password":dialog.password_field.text});dialog.queue_free())
	dialog.canceled.connect(func():dialog.queue_free())
	dialog.popup_centered()

func _chat(parent: Node, height: int) -> void:
	var box := _panel(parent)
	chat_label = RichTextLabel.new()
	chat_label.bbcode_enabled = false
	chat_label.custom_minimum_size.y = height * ui_scale
	chat_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_label.scroll_following = true
	box.add_child(chat_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "与好友聊两句…"
	chat_input.max_length = 200
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chat_input)
	chat_input.text_submitted.connect(func(_text): _send_chat())
	_button("发送", row, _send_chat)

func _send_chat() -> void:
	var field := chat_input
	if not is_instance_valid(field) or field == sending_chat:
		return
	if field.text.strip_edges().is_empty():
		if scene == "battle":
			field.clear()
			field.release_focus()
		return
	var message := field.text
	var session: String = net.token
	sending_chat = field
	var reply: Dictionary = await net.request("/api/command", {"action": "chat", "text": message})
	if not is_instance_valid(field) or field != chat_input or field != sending_chat:
		return
	sending_chat = null
	if quitting or auth_busy or net.token != session:
		return
	if reply.has("profile"):
		if field.text == message:
			field.clear()
			if scene == "battle":
				field.release_focus()
		_accept_state(reply)
	else:
		toast(str(reply.get("error", "消息发送失败")))

func _show_room() -> void:
	_original_page("GameBack")
	scene = "room"
	sound.set_scene("lobby")
	skin.button("gl_exit", Rect2(10, 8, 89, 44), func(): await _command({"action": "leave"}), "返回大厅")
	skin.button("gl_invitation", Rect2(123, 8, 89, 44), _invite_dialog, "邀请玩家").name = "RoomInvite"
	start_button = skin.button("gl_start", Rect2(278, 10, 106, 40), func(): await _command({"action": "start"}), "开始")
	start_button.name = "StartMatch"
	ready_button = skin.button("gl_ready", Rect2(278, 10, 106, 40), func():
		await _command({"action": "ready", "ready": not bool(_me().get("ready", true))})
	)
	skin.button("gl_shop", Rect2(460, 8, 89, 44), _show_shop, "道具商店").name = "RoomShop"
	skin.button("btn_gameitem", Rect2(560, 545, 117, 48), _show_game_items, "游戏物品").name = "RoomItems"
	skin.button("gl_full", Rect2(680, 545, 114, 48), _toggle_fullscreen, "全屏 / 窗口")
	room_title = skin.label("", Rect2(565, 8, 157, 18), 12)
	var practice: Button = skin.blue_button("AI陪练", Rect2(565, 29, 116, 29), _bot_dialog)
	practice.name = "AIPractice"
	practice.tooltip_text = "设置 AI 难度与战车"
	skin.text_button("房间设置", Rect2(698, 29, 90, 29), _create_room_settings).name = "RoomSettings"
	var room_back := preload("res://room_back.gd").new()
	room_back.name = "RoomLanes"
	skin.place(room_back,Rect2(0,62,568,307))
	vehicle_picker = preload("res://native_vehicle_picker.gd").new()
	vehicle_picker.name = "NativeVehiclePicker"
	vehicle_picker.catalog = catalog
	vehicle_picker.vehicle_selected.connect(func(id: int): sound.play_event(5); await _command({"action": "vehicle", "vehicle": id}))
	skin.place(vehicle_picker, Rect2(551,73,249,296))
	room_grid = Control.new()
	room_grid.name="RoomSeats"
	room_grid.resized.connect(func():
		if scene=="room":_update_room.call_deferred()
	)
	skin.place(room_grid, Rect2(50, 95, 480, 260))
	room_status = skin.label("", Rect2(725, 8, 63, 18), 11)
	vehicle_choice = _vehicle_options(skin, true)
	skin.remove_child(vehicle_choice)
	skin.place(vehicle_choice, Rect2(655, 310, 134, 25), 12)
	vehicle_choice.hide()
	vehicle_choice.item_selected.connect(func(_index): await _command({"action": "vehicle", "vehicle": vehicle_choice.get_selected_id()}))
	map_choice = _map_options(skin)
	skin.remove_child(map_choice)
	skin.place(map_choice, Rect2(593, 405, 167, 20), 12)
	map_choice.item_selected.connect(func(_index): await _command({"action": "settings", "map": map_choice.get_selected_id()}))
	map_previous = skin.button("gl_larrow", Rect2(570, 405, 20, 20), func(): _cycle_room_map(-1), "上一张地图")
	map_previous.name = "PreviousRoomMap"
	map_next = skin.button("gl_rarrow", Rect2(766, 405, 20, 20), func(): _cycle_room_map(1), "下一张地图")
	map_next.name = "NextRoomMap"
	room_preview = Control.new()
	skin.place(room_preview, Rect2(568, 430, 222, 96))
	_original_chat()
	_update_room()

func _create_room_settings() -> void:
	var room: Dictionary = snapshot.get("room", {})
	if int(room.get("owner", 0)) != int(profile.get("id", 0)):
		toast("仅房主可以修改房间设置")
		return
	var dialog := _dialog("房间设置", Vector2(430, 240))
	var body: VBoxContainer = dialog.get_meta("body")
	_label("地图", body, 15)
	var choice := _map_options(body)
	choice.select(choice.get_item_index(int(room.get("map", 0))))
	dialog.confirmed.connect(func(): await _command({"action": "settings", "map": choice.get_selected_id()}))
	dialog.popup_centered()

func _update_room() -> void:
	if is_instance_valid(page_transition) and not page_transition_applying: return
	if scene not in ["room", "shop"] or not is_instance_valid(room_grid):return
	var room: Dictionary = snapshot.get("room", {})
	var stamp := JSON.stringify([room.get("members", []), room.get("map", 0), room.get("owner", 0), skin.pixel_scale, room_grid.size])
	if stamp == last_room_stamp:
		return
	last_room_stamp = stamp
	room_title.text = "%s  #%d" % [str(room.get("name", "")), int(room.get("id", 0))]
	for child in room_grid.get_children():
		room_grid.remove_child(child)
		child.queue_free()
	var members := {}
	var waiting := bool(_me().get("returned", false))
	var remaining := 0
	for member in room.get("members", []):
		members[int(member.seat)] = member
		if int(member.ai) == 0 and not bool(member.get("returned", false)):
			remaining += 1
	if waiting:
		room_title.text = "等待 %d 位玩家返回" % remaining
	room_title.tooltip_text = str(room.get("name", ""))
	# A returned player may prepare the next match while others view results.
	# The old match remains owned by the server until everyone has returned.
	skin.get_node("RoomInvite").disabled = waiting
	for key in ["RoomShop", "RoomItems", "AIPractice"]:
		skin.get_node(key).disabled = false
	skin.get_node("RoomSettings").disabled = int(room.owner) != int(profile.id)
	start_button.disabled = waiting or _room_has_unready_players(room)
	start_button.tooltip_text = "等待其他玩家返回" if waiting else "还有玩家未准备" if start_button.disabled else "开始"
	ready_button.disabled = false
	vehicle_choice.disabled = false
	for button: Button in vehicle_picker.buttons:
		button.disabled = false
	var scale: float = skin.pixel_scale
	var row_height: float = room_grid.size.y/4.0
	var group_width: float = 0
	var slot_width: float = (room_grid.size.x-group_width)/4.0
	for group in range(4):
		for position in range(4):
			var seat := group * 4 + position
			var panel := Control.new()
			panel.name="RoomSeat%02d"%seat
			panel.position=Vector2(group_width+position*slot_width,group*row_height)
			panel.size=Vector2(slot_width-4,row_height-4)
			room_grid.add_child(panel)
			if members.has(seat):
				var card := preload("res://native_room_seat.gd").new()
				card.member = members[seat]
				card.owner_id = int(room.owner)
				card.size=panel.size
				panel.add_child(card)
			else:
				var empty := Button.new()
				empty.disabled = false
				empty.tooltip_text = "加入 %s 组 · 位置 %d" % [char(65 + group), position + 1]
				empty.add_theme_font_size_override("font_size", maxi(10, int(11*scale)))
				for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
					empty.add_theme_stylebox_override(state, StyleBoxEmpty.new())
				empty.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				empty.add_theme_color_override("font_color", Color.WHITE)
				empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				empty.pressed.connect(func(): await _command({"action": "seat", "seat": seat}))
				panel.add_child(empty)
	vehicle_choice.select(vehicle_choice.get_item_index(int(_me().get("vehicle", 1))))
	vehicle_picker.set_selected(int(_me().get("vehicle", 0)))
	map_choice.select(map_choice.get_item_index(int(room.get("map", 0))))
	map_choice.disabled = int(room.owner) != int(profile.id)
	map_previous.disabled = map_choice.disabled
	map_next.disabled = map_choice.disabled
	start_button.visible = int(room.owner) == int(profile.id)
	ready_button.visible = not start_button.visible
	ready_button.tooltip_text = "已准备 · 点击取消" if bool(_me().get("ready", true)) else "准备"
	room_status.text = "%d / %d 人" % [room.get("members", []).size(), int(room.capacity)]
	_preview(room_preview, int(room.get("map", 0)))

func _room_has_unready_players(room:Dictionary) -> bool:
	for member:Dictionary in room.get("members",[]):
		if int(member.get("ai",0))==0 and int(member.id)!=int(room.owner) and not bool(member.get("ready",false)):return true
	return false

func _cycle_room_map(direction: int) -> void:
	if map_choice.disabled or command_busy:return
	map_choice.select(posmod(map_choice.selected + direction, map_choice.item_count))
	map_choice.item_selected.emit(map_choice.selected)

func _dialog(title: String, dimensions: Vector2, close_on_confirm := true) -> ConfirmationDialog:
	# Embedded dialogs share one native parent. Release its exclusive child
	# before opening another dialog from a menu button.
	for child in get_children():
		if child is Window and child.visible:
			child.hide()
			child.queue_free()
	var dialog := preload("res://native_dialog.gd").new()
	dialog.caption = title
	dialog.title = title
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.size = Vector2i((dimensions * ui_scale).min(size * 0.94))
	dialog.min_size = Vector2i(320, 220)
	add_child(dialog)
	var body := VBoxContainer.new()
	_fill(body)
	body.offset_left = 20 * ui_scale
	body.offset_right = -20 * ui_scale
	body.offset_top = 52 * ui_scale
	body.offset_bottom = -62 * ui_scale
	dialog.add_child(body)
	dialog.set_meta("body", body)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.dialog_hide_on_ok = close_on_confirm
	if close_on_confirm:
		dialog.confirmed.connect(func(): dialog.queue_free())
	return dialog

func _map_options(parent: Node) -> OptionButton:
	var choice := OptionButton.new()
	choice.add_item("随机地图", 0)
	for map: Dictionary in catalog.get("maps", []):
		choice.add_item(str(map.name), int(map.id))
	parent.add_child(choice)
	return choice

func _vehicle_options(parent: Node, random_choice := true) -> OptionButton:
	var choice := OptionButton.new()
	if random_choice:
		choice.add_item("随机战车", 0)
	for vehicle: Dictionary in catalog.get("vehicles", []):
		choice.add_item(str(vehicle.name), int(vehicle.id))
	parent.add_child(choice)
	return choice

func _map_name(id: int) -> String:
	if id == 0:
		return "随机地图"
	for map: Dictionary in catalog.get("maps", []):
		if int(map.id) == id:
			return str(map.name)
	return "原版战场 %02d" % id

func _vehicle_name(id: int) -> String:
	if id == 0:
		return "随机战车"
	for vehicle: Dictionary in catalog.get("vehicles", []):
		if int(vehicle.id) == id:
			return str(vehicle.name)
	return "战车"

func _preview(parent: Control, id: int) -> void:
	for child in parent.get_children():
		child.hide()
		child.queue_free()
	var native_preview := "res://assets/icons/PrevMap/%02d.png" % id
	if not ResourceLoader.exists(native_preview):
		native_preview = "res://assets/effects/PrevMap271/%02d.png" % id
	if ResourceLoader.exists(native_preview):
		var picture := TextureRect.new()
		picture.texture=load(native_preview)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		parent.add_child(picture)
		_fill(picture)
		return
	var backdrop := "background.png" if ResourceLoader.exists("res://assets/maps/%d/background.png" % id) else "background.jpg"
	for file in [backdrop, "terrain.png"]:
		var picture := TextureRect.new()
		picture.texture = load("res://assets/maps/%d/%s" % [id, file])
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fill(picture)
		parent.add_child(picture)

func _me() -> Dictionary:
	var room: Variant = snapshot.get("room")
	if room is Dictionary:
		for member: Dictionary in room.get("members", []):
			if int(member.id) == int(profile.get("id", 0)) and int(member.ai) == 0:
				return member
	return {}

func _invite_dialog() -> void:
	var dialog:=_dialog("邀请玩家",Vector2(430,290))
	var body:VBoxContainer=dialog.get_meta("body")
	_label("选择大厅中的玩家",body,17)
	var choice:=OptionButton.new()
	choice.name="InvitePlayer"
	body.add_child(choice)
	for player:Dictionary in snapshot.get("players",[]):
		if int(player.id)!=int(profile.id) and int(player.get("room",0))==0:
			choice.add_item(str(player.name),int(player.id))
	if choice.item_count==0:
		_label("当前没有可邀请的大厅玩家",body,15)
		dialog.get_ok_button().disabled=true
	dialog.confirmed.connect(func():
		await _command({"action":"invite","player":choice.get_selected_id()})
	)
	dialog.popup_centered()

func _present_invitation() -> void:
	if scene!="lobby" or _modal_open():return
	var invitation:Variant=snapshot.get("invitation")
	if not invitation is Dictionary:return
	if float(invitation.get("expires",0))<=float(snapshot.get("server_time",0)):return
	var stamp:=JSON.stringify(invitation)
	if stamp==invitation_stamp:return
	invitation_stamp=stamp
	var dialog:=_dialog("房间邀请",Vector2(460,270))
	var body:VBoxContainer=dialog.get_meta("body")
	_label(str(invitation.from)+" 邀请你加入",body,18)
	_label(str(invitation.room_name),body,18)
	dialog.confirmed.connect(func():await _command({"action":"accept_invite","room":int(invitation.room)}))
	dialog.canceled.connect(func():await _command({"action":"decline_invite"}))
	dialog.popup_centered()

func _bot_dialog() -> void:
	var room: Dictionary = snapshot.get("room", {})
	var editable := int(room.get("owner", 0)) == int(profile.get("id", 0))
	var dialog := _dialog("AI 陪练 · 总人数最多 %d 人" % int(room.capacity), Vector2(1120, 650), false)
	dialog.name = "AIOptions"
	dialog.set_meta("room_id", int(room.id))
	var body: VBoxContainer = dialog.get_meta("body")
	var status := _label("", body, 14, MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var groups := VBoxContainer.new()
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(groups)
	var slots := {}
	for member: Dictionary in room.get("members", []):
		slots[int(member.seat)] = member
	var difficulties: Array[OptionButton] = []
	var selections: Array[OptionButton] = []
	var seat_labels: Array[Label] = []
	for group in range(4):
		var row := HBoxContainer.new()
		groups.add_child(row)
		_label(char(65 + group) + " 组", row, 22, TEAMS[group]).custom_minimum_size.x = 72 * ui_scale
		for position in range(4):
			var index := group * 4 + position
			var box := _panel(row)
			(box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var member: Dictionary = slots.get(index, {})
			var human := not member.is_empty() and int(member.ai) == 0
			seat_labels.append(_label(str(member.get("name", "位置 %d" % (position + 1))), box, 12, TEAMS[group]))
			var level := OptionButton.new()
			level.name = "AIDifficulty%02d" % index
			for text in ["无", "简单 AI", "中等 AI", "困难 AI"]:
				level.add_item(text)
			level.select(int(member.get("ai", 0)))
			level.disabled = human or not editable
			box.add_child(level)
			var chosen := _vehicle_options(box)
			chosen.name = "AIVehicle%02d" % index
			chosen.select(chosen.get_item_index(int(member.get("vehicle", 0))))
			chosen.disabled = human or not editable or level.selected == 0
			difficulties.append(level)
			selections.append(chosen)
	var refresh := func():
		var current: Variant = snapshot.get("room")
		if scene not in ["room","shop"] or not current is Dictionary or int(current.id) != int(dialog.get_meta("room_id")):
			dialog.hide()
			dialog.queue_free()
			return
		var owner := int(current.owner) == int(profile.id)
		var occupied := {}
		for player: Dictionary in current.members:
			occupied[int(player.seat)] = player
		var total := 0
		for index in range(16):
			var member: Dictionary = occupied.get(index, {})
			var human := not member.is_empty() and int(member.ai) == 0
			seat_labels[index].text = str(member.get("name", "位置 %d" % (index % 4 + 1)))
			difficulties[index].disabled = human or not owner
			selections[index].disabled = human or not owner or difficulties[index].selected == 0
			if human or not owner:
				difficulties[index].select(int(member.get("ai", 0)))
				selections[index].select(selections[index].get_item_index(int(member.get("vehicle", 0))))
			if human or difficulties[index].selected > 0:
				total += 1
		var limit := int(current.capacity)
		status.text = "已安排 %d / %d 人" % [total, limit]
		if total > limit:
			status.text += "　请减少 %d 名 AI" % (total - limit)
		elif not owner:
			status.text += "　仅房主可以修改"
		dialog.get_ok_button().disabled = not owner or total > limit or dialog.has_meta("saving")
	dialog.set_meta("refresh", refresh)
	for level in difficulties:
		level.item_selected.connect(func(_index): refresh.call())
	refresh.call()
	dialog.confirmed.connect(func():
		refresh.call()
		if dialog.is_queued_for_deletion() or dialog.get_ok_button().disabled:
			return
		if command_busy:
			status.text = "正在处理上一步操作，请稍后确定"
			return
		var choices := []
		for index in range(16):
			choices.append({"seat": index, "level": difficulties[index].selected, "vehicle": selections[index].get_selected_id()})
		dialog.set_meta("saving", true)
		dialog.get_ok_button().disabled = true
		var saved := await _command({"action": "bots", "bots": choices})
		if not is_instance_valid(dialog) or dialog.is_queued_for_deletion():
			return
		if saved:
			dialog.queue_free()
		else:
			dialog.remove_meta("saving")
			refresh.call()
	)
	dialog.popup_centered()

func _show_game_items() -> void:
	if scene not in ["lobby","room","shop"] or _modal_open():return
	if not await _pause_room_readiness():return
	var dialog:=preload("res://native_game_items.gd").new()
	dialog.theme=theme
	dialog.catalog=catalog
	dialog.profile=profile
	dialog.size=Vector2i((Vector2(900,560)*ui_scale).min(size*.9))
	dialog.buy_requested.connect(func(item:int,slot:int):
		if slot<0:
			toast("携带槽已满，请先出售一个道具")
			return
		await _command({"action":"buy","item":item,"slot":slot})
	)
	dialog.sell_requested.connect(func(slot:int):
		if slot>=0:await _command({"action":"sell","slot":slot})
	)
	add_child(dialog)
	dialog.popup_centered()

func _show_shop() -> void:
	if scene == "shop":
		_return_from_shop()
		return
	if not await _pause_room_readiness():return
	if snapshot.get("room") is Dictionary:
		_show_room()
		shop_room_id = int(snapshot.room.id)
		for node in [room_grid, vehicle_picker, skin.get_node("RoomLanes")]:node.hide()
	else:
		_show_lobby()
		shop_room_id = 0
		room_list.get_parent().hide()
		player_list.get_parent().hide()
	scene = "shop"
	# Keep the original lobby/room header, chat and map/profile visible.
	# This also keeps ready/start and map synchronization live in the shop.
	for node in skin.get_children():
		if node is Button and node.tooltip_text == "道具商店":node.tooltip_text = "返回"
	var shop := preload("res://native_shop.gd").new()
	shop.name = "NativeCombatShop"
	shop.catalog = catalog
	shop.profile = profile
	shop.buy_requested.connect(func(item: int, slot: int):
		if slot < 0:
			toast("携带槽已满，请先出售一个道具")
			return
		await _command({"action": "buy", "item": item, "slot": slot})
	)
	shop.sell_requested.connect(func(slot: int):
		if slot >= 0:await _command({"action": "sell", "slot": slot})
	)
	skin.place(shop, Rect2(0, 62, 800, 307))
	native_shop = shop
	_update_inventory()

func _pause_room_readiness() -> bool:
	var room:Variant=snapshot.get("room")
	if not room is Dictionary:return true
	if scene not in ["room","shop"]:return false
	if int(room.owner)==int(profile.id) or not bool(_me().get("ready",false)):return true
	var requested_room:=int(room.id)
	if not await _command({"action":"ready","ready":false}):return false
	room=snapshot.get("room")
	return room is Dictionary and int(room.id)==requested_room and scene in ["room","shop"]

func _original_shop_title() -> String:
	return "道具商店"

func _return_from_shop() -> void:
	if snapshot.get("room") is Dictionary:
		_show_room()
	else:
		_show_lobby()

func _item_name(id: int) -> String:
	for item: Dictionary in catalog.get("items", []):
		if int(item.id) == id:
			return str(item.name)
	return "空槽"

func _update_inventory() -> void:
	if scene == "shop" and is_instance_valid(native_shop):
		native_shop.set_profile(profile)
		return
	if scene=="shop" and is_instance_valid(shop_gold):
		shop_gold.text="金币：%d" % int(profile.get("gold",0))
	if not is_instance_valid(inventory_row):
		return
	var stamp := JSON.stringify(profile.get("inventory", []))
	if stamp == last_inventory_stamp:
		return
	last_inventory_stamp = stamp
	for child in inventory_row.get_children():
		child.queue_free()
	var inventory: Array = profile.get("inventory", [0, 0, 0, 0])
	for i in range(4):
		var slot := i
		var id := int(inventory[i])
		var button := _button("%d · %s" % [i + 1, _item_name(id)], inventory_row, func():
			if scene == "shop":
				var dialog := _dialog("出售道具", Vector2(410, 200))
				_label("确定半价出售「%s」？" % _item_name(id), dialog.get_meta("body"), 16)
				dialog.confirmed.connect(func(): await _command({"action": "sell", "slot": slot}))
				dialog.popup_centered()
			elif scene == "battle":
				await _battle_command({"action": "item", "slot": slot})
		)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = id == 0
		if scene == "battle":
			button.text = ""
			button.tooltip_text = "F%d · %s" % [i + 5, _item_name(id)]
			button.custom_minimum_size = Vector2(31,31)*ui_scale
			for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
				button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
			button.icon = load("res://assets/icons/ItemIcon/%02d.png"%id) if id>0 else load("res://assets/icons/F%dBtn/00.png"%(i+5))
			button.expand_icon=true
			button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment=VERTICAL_ALIGNMENT_CENTER

func _vehicle_guide() -> void:
	var dialog := _dialog("战车图鉴 · 30 辆原版战车", Vector2(1050, 700))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(dialog.get_meta("body") as VBoxContainer).add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for vehicle: Dictionary in catalog.get("vehicles", []):
		var box := _panel(grid)
		(box.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(str(vehicle.name), box, 21, GOLD)
		var picture := TextureRect.new()
		picture.texture = load("res://assets/tanks/%d/preview.png" % int(vehicle.id))
		picture.custom_minimum_size = Vector2(220, 85) * ui_scale
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(picture)
		_label("%s · 耐久 %d" % [str(vehicle.role), int(vehicle.hp)], box, 14, MUTED)
		for weapon: Dictionary in vehicle.weapons:
			_label("%s   %d SP" % [str(weapon.name), int(weapon.cost)], box, 13)
	dialog.popup_centered()

func _show_battle() -> void:
	selected_weapon = 0
	charging = false
	charge = 0.0
	charge_ticks = 0.0
	_original_page()
	_reveal_scene()
	scene = "battle"
	for unit: Dictionary in _battle_data().get("units",[]):
		if int(unit.player)==int(profile.id):
			aim=float(unit.get("elevation", 45)) if bool(_battle_data().get("native_aim", false)) else float(unit.get("aim",45))
			aim_face=int(unit.face)
	skin.page = "battle"
	sound.set_scene("battle",int(_battle_data().get("map",1)))
	view = WorldView.new()
	view.name = "Battlefield"
	view.player_id = int(profile.id)
	view.catalog=catalog
	view.clock = net
	view.mouse_aim.connect(func(elevation:float,face:int):
		if _my_turn() and not battle_action_busy:
			aim=elevation
			aim_face=face
	)
	view.shake_enabled = bool(config.get("shake", true))
	view.quality = int(config.get("quality", 1))
	view.zoom_locked = bool(config.get("zoom_lock", false))
	view.effect.connect(func(kind,detail): sound.play_effect(kind,detail))
	content.add_child(view)
	_fill(view)
	walker=preload("res://native_walk.gd").new(self)
	view.local_walk=walker
	battle_hud = preload("res://battle_hud.gd").new()
	battle_hud.player_id = int(profile.id)
	battle_hud.clock = net
	battle_hud.catalog = catalog
	content.add_child(battle_hud)
	_fill(battle_hud)
	battle_status = Label.new()
	battle_detail = Label.new()
	charge_bar = ProgressBar.new()
	aim_slider = HSlider.new()
	for hidden in [battle_status,battle_detail,charge_bar,aim_slider]:
		content.add_child(hidden)
		hidden.visible = false
	weapon_buttons.clear()
	hud_buttons.clear()
	for index in range(3):
		var choice := index
		var b := _hud_button("weapon",index,func(): _select_weapon(choice))
		weapon_buttons.append(b)
		hud_buttons["weapon%d"%index] = b
	fire_button = _hud_button("fire",0,func(): pass)
	fire_button.name = "Fire"
	fire_button.text = "开火"
	fire_button.button_down.connect(_start_charging)
	fire_button.button_up.connect(_fire)
	hud_buttons.fire = fire_button
	hud_buttons.skip = _hud_button("skip",0,_skip_turn)
	hud_buttons.skip.tooltip_text="跳过本回合 · F9"
	hud_buttons.menu = _hud_button("menu",0,_battle_menu)
	hud_buttons.overview = _hud_button("overview",0,func(): view.show_whole_map())
	hud_buttons.overview.tooltip_text = "全图 · 右键拖动地图，滚轮缩放"
	hud_buttons.follow = _hud_button("follow",0,func(): view.reset_camera())
	hud_buttons.follow.text = "跟随"
	inventory_row = HBoxContainer.new()
	content.add_child(inventory_row)
	inventory_row.add_theme_constant_override("separation",0)
	_build_battle_chat()
	_update_inventory()
	_update_battle()

func _build_battle_chat() -> void:
	battle_chat = Control.new()
	battle_chat.name = "BattleChat"
	battle_chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(battle_chat)
	chat_label = RichTextLabel.new()
	chat_label.name = "History"
	chat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_label.scroll_active = false
	chat_label.scroll_following = true
	chat_label.size = Vector2(300, 62)
	chat_label.add_theme_font_size_override("normal_font_size", 13)
	chat_label.add_theme_color_override("default_color", Color.WHITE)
	chat_label.add_theme_color_override("font_outline_color", Color.BLACK)
	chat_label.add_theme_constant_override("outline_size", 3)
	battle_chat.add_child(chat_label)
	chat_input = LineEdit.new()
	chat_input.name = "Message"
	chat_input.placeholder_text = "房间聊天"
	chat_input.tooltip_text = "回车聊天，再按回车发送，Esc 取消"
	chat_input.context_menu_enabled = false
	chat_input.keep_editing_on_text_submit = true
	chat_input.max_length = 200
	chat_input.position = Vector2(0, 64)
	chat_input.size = Vector2(220, 24)
	chat_input.add_theme_font_size_override("font_size", 13)
	chat_input.add_theme_color_override("font_color", Color.WHITE)
	chat_input.add_theme_color_override("font_placeholder_color", Color("d3dedf"))
	chat_input.add_theme_color_override("caret_color", Color.WHITE)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.06, 0.07, 0.70)
	background.content_margin_left = 4
	chat_input.add_theme_stylebox_override("normal", background)
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.set_border_width_all(1)
	border.border_color = Color("b7d5d8")
	chat_input.add_theme_stylebox_override("focus", border)
	battle_chat.add_child(chat_input)
	chat_input.focus_entered.connect(func(): charging = false)
	chat_input.text_submitted.connect(func(_message): _send_chat())

func _reveal_scene() -> void:
	if not is_instance_valid(reveal_layer):
		var layer:=CanvasLayer.new()
		layer.layer=10
		add_child(layer)
		reveal_layer=ColorRect.new()
		reveal_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
		reveal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(reveal_layer)
	if reveal_tween:reveal_tween.kill()
	reveal_layer.color=Color(0,0,0,.8)
	reveal_tween=create_tween()
	reveal_tween.tween_property(reveal_layer,"color:a",0.0,.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _hud_button(kind: String, index: int, action: Callable) -> Button:
	var button := Button.new()
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.add_theme_color_override("font_color",Color.WHITE if kind in ["fire","overview","follow"] else Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color",Color("ffcd76") if kind in ["fire","overview","follow"] else Color.TRANSPARENT)
	button.add_theme_color_override("font_disabled_color",Color("777777") if kind=="fire" else Color.TRANSPARENT)
	if kind in ["skip","menu"]:
		for pair in [["normal",0],["hover",1],["pressed",2],["disabled",2]]:
			var box := StyleBoxTexture.new()
			box.texture = load("res://assets/icons/%s/%02d.png" % ["SkipBtn" if kind=="skip" else "MenuBtn",pair[1]])
			button.add_theme_stylebox_override(pair[0],box)
	content.add_child(button)
	return button

func _reflow_hud() -> void:
	if not is_instance_valid(battle_hud): return
	_layout_toast()
	var s: float = battle_hud.scale_factor
	battle_chat.position = Vector2(8*s, size.y-208*s)
	battle_chat.scale = Vector2.ONE*s
	for key: String in hud_buttons:
		var button: Button = hud_buttons[key]
		var r: Rect2 = battle_hud.rect_for("weapon",int(key.substr(6))) if key.begins_with("weapon") else battle_hud.rect_for(key)
		button.position = r.position
		button.size = r.size
		button.add_theme_font_size_override("font_size",int(12*s))
	inventory_row.position = Vector2(size.x-232*s,26*s)
	inventory_row.size = Vector2(136,31)*s
	for child in inventory_row.get_children():
		child.custom_minimum_size = Vector2(31,31)*s
		child.add_theme_constant_override("icon_max_width",int(31*s))
	battle_hud.battle = view.battle
	battle_hud.angle = aim
	battle_hud.charge = charge
	battle_hud.selected_weapon = selected_weapon
	battle_hud.camera_rect = Rect2(view.camera - view.size / view.zoom / 2, view.size / view.zoom)
	battle_hud.minimap_ground = view.terrain_texture

func _battle_menu() -> void:
	if _modal_open():return
	charging = false
	var menu := preload("res://native_menu.gd").new()
	menu.name = "NativeMenu"
	menu.options = {"music": sound.music_volume > 0, "effects": sound.effects_volume > 0, "fullscreen": full_screen, "zoom_lock": bool(config.get("zoom_lock", false))}
	content.add_child(menu)
	menu.changed.connect(func(option: String, enabled: bool):
		match option:
			"music":
				sound.music_volume = float(config.get("music", 0.45)) if enabled else 0.0
				sound.apply_volume()
			"effects":
				sound.effects_volume = float(config.get("effects", 0.75)) if enabled else 0.0
				sound.apply_volume()
			"fullscreen":
				if full_screen != enabled:_toggle_fullscreen()
			"zoom_lock":
				config.zoom_lock = enabled
				if is_instance_valid(view):view.zoom_locked = enabled
				_save_config()
	)
	menu.leave_requested.connect(_leave_battle)

func _battle_data() -> Dictionary:
	var room: Variant = snapshot.get("room")
	if room is Dictionary and room.get("battle") is Dictionary:
		return room.battle
	return {}

func _active() -> Dictionary:
	var battle := _battle_data()
	for unit: Dictionary in battle.get("units", []):
		if int(unit.seat) == int(battle.get("active", -1)):
			return unit
	return {}

func _my_turn() -> bool:
	var battle := _battle_data()
	var active := _active()
	if active.is_empty() or int(active.get("hp", 0)) <= 0 or int(active.get("player", 0)) != int(profile.get("id", -1)):
		return false
	return battle.get("result") == null and float(battle.get("deadline", 0)) > net.server_now()

func _own_battle_unit() -> Dictionary:
	for unit: Dictionary in _battle_data().get("units", []):
		if int(unit.player) == int(profile.id):
			return unit
	return {}

func _weapon_cost(unit: Dictionary, index: int) -> int:
	if int(unit.get("shot_mode", 0)) != 0:
		return 0
	return int(catalog.vehicles[int(unit.vehicle)-1].weapons[index].cost)

func _select_weapon(index: int) -> void:
	var unit := _input_battle_unit()
	if unit.is_empty():return
	if int(unit.sp) < _weapon_cost(unit, index):
		toast("SP 不足", 2)
		return
	selected_weapon = index
	sound.play_event(5)

func _update_battle() -> void:
	var battle := _battle_data()
	if battle.is_empty() or not is_instance_valid(view):
		return
	view.set_battle(battle)
	if walker:walker.accept(battle)
	var next_stamp:="%s:%s"%[battle.get("id",""),battle.get("generation",0)]
	if next_stamp!=battle_input_stamp:
		battle_input_stamp=next_stamp
		battle_action_serial+=1
		battle_action_busy=false
		charging=false
		charge=0.0
		charge_ticks=0.0
	_update_inventory()
	if battle.get("result") is Dictionary and not is_instance_valid(result_layer):
		_show_result(battle)

func _battle_command(command: Dictionary) -> void:
	if not _my_turn() or command_busy or battle_action_busy:
		return
	var battle_id := str(_battle_data().id)
	var generation := int(_battle_data().generation)
	battle_action_serial+=1
	var requested_serial:=battle_action_serial
	battle_action_busy=true
	if walker and not await walker.flush():
		if requested_serial==battle_action_serial:
			battle_action_busy=false
			toast("移动位置正在重新同步，请稍后再试",3)
		return
	if requested_serial!=battle_action_serial:return
	if not _my_turn() or str(_battle_data().id) != battle_id or int(_battle_data().generation) != generation:
		battle_action_busy=false
		return
	if str(command.get("action",""))=="fire":
		var own:=_own_battle_unit()
		if int(own.get("sp",0))<_weapon_cost(own,int(command.weapon)):
			battle_action_busy=false
			_failed_fire(own,int(command.weapon))
			return
	command.generation = generation
	await _command(command)
	if requested_serial==battle_action_serial:battle_action_busy=false

func _input_battle_unit() -> Dictionary:
	# Movement prediction already spends fuel before its server acknowledgement.
	if walker and walker.active and not walker.unit.is_empty():return walker.unit
	return _own_battle_unit()

func _failed_fire(own:Dictionary,_index:int) -> void:
	if own.is_empty() or scene!="battle":return
	charging=false
	charge=0.0
	charge_ticks=0.0
	if is_instance_valid(view) and not own.is_empty():view.fire_failed(own,aim,aim_face)
	toast("SP 不足", 2)

func _start_charging() -> void:
	if not _my_turn():return
	if command_busy or battle_action_busy:
		toast("正在同步行动…",2)
		return
	var own := _input_battle_unit()
	if own.is_empty():return
	if int(own.sp)<_weapon_cost(own,selected_weapon):
		_failed_fire(own,selected_weapon)
		return
	charging = true
	charge_generation = int(_battle_data().generation)
	charge = 0.0
	charge_ticks=0

func _skip_turn() -> void:
	charging=false
	charge_ticks=0
	await _battle_command({"action":"pass"})

func _fire() -> void:
	if not charging:
		return
	charging = false
	if not _my_turn() or charge_generation != int(_battle_data().generation):
		return
	battle_hud.previous_charge = charge
	await _battle_command({"action": "fire", "aim_mode": "native" if bool(_battle_data().get("native_aim", false)) else "world", "aim_face":aim_face, "angle": aim, "power": clampf(charge, 0.0, 1), "weapon": selected_weapon})

func _show_result(battle: Dictionary) -> void:
	if is_instance_valid(battle_chat):
		battle_chat.hide()
	for node in get_tree().get_nodes_in_group("native_modal"):
		node.hide()
		node.queue_free()
	charging = false
	var team := -1
	for unit: Dictionary in battle.get("units",[]):
		if int(unit.player)==int(profile.id):team=int(unit.team)
	var winner := int(battle.result.team)
	sound.play_event(9 if winner<0 else 7 if team==winner else 8)
	var result := preload("res://native_result.gd").new()
	result.battle = battle
	result.player_id = int(profile.id)
	result.return_requested.connect(func(): await _command({"action": "return"}))
	result_layer = result
	content.add_child(result_layer)

func _leave_battle() -> void:
	var dialog := _dialog("离开对局", Vector2(450, 210))
	_label("离开后当前战车将退出本局，其他玩家继续对战。", dialog.get_meta("body"), 15)
	dialog.confirmed.connect(func(): await _command({"action": "leave"}))
	dialog.popup_centered()

func _accept_state(state: Dictionary) -> void:
	if not snapshot.is_empty():
		if str(snapshot.get("epoch", "")) == str(state.get("epoch", "")):
			if int(state.get("version", 0)) < int(snapshot.get("version", 0)):
				return
		elif int(state.get("_request_sequence", 0)) < int(snapshot.get("_request_sequence", 0)):
			return
	snapshot = state
	profile = state.get("profile", {})
	if not qa and not channel_accepted:
		_show_channel_gate()
		channel_gate.set_channel_state(state)
		return
	_confirm_battle_command()
	account_label.text = "%s   ·   %d 金币   ·   %d 胜" % [str(profile.get("name", "")), int(profile.get("gold", 0)), int(profile.get("wins", 0))]
	var room: Variant = state.get("room")
	var wanted := "lobby"
	if room is Dictionary:
		wanted = "battle" if room.get("battle") is Dictionary else "room"
	if is_instance_valid(page_transition):
		if wanted == "battle":
			_cancel_page_transition()
		elif not page_transition_applying:
			return
	elif not page_transition_applying and not is_instance_valid(channel_gate) and scene in ["lobby", "room"] and wanted in ["lobby", "room"] and wanted != scene:
		_begin_page_transition()
		return
	if scene == "shop" and wanted != "battle":
		var current_room_id := int(room.id) if room is Dictionary else 0
		if current_room_id != shop_room_id:
			if room is Dictionary:_show_room()
			else:_show_lobby()
		else:
			if room is Dictionary:_update_room()
			_update_inventory()
	elif wanted != scene:
		if wanted == "lobby":
			_show_lobby()
		elif wanted == "room":
			_show_room()
		else:
			_show_battle()
	elif scene == "lobby":
		_update_lobby()
	elif scene == "room":
		_update_room()
	elif scene == "battle":
		_update_battle()
	_update_profile_labels()
	if scene=="lobby":
		for setting in [["RejectPrivate","reject_private"],["RejectInvites","reject_invites"]]:
			var toggle:=skin.get_node_or_null(setting[0]) as Button
			if toggle:toggle.set_pressed_no_signal(bool(profile.get(setting[1],false)));toggle.queue_redraw()
	var game_items:=get_node_or_null("NativeGameItems")
	var bot_options := get_node_or_null("AIOptions")
	if is_instance_valid(bot_options) and not bot_options.is_queued_for_deletion():
		bot_options.get_meta("refresh").call()
	if is_instance_valid(game_items):game_items.set_profile(profile)
	if is_instance_valid(chat_label):
		var messages: Array = (room.get("chat", []) if room is Dictionary else state.get("chat", [])).duplicate()
		messages.append_array(state.get("whispers",[]))
		messages.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
		if scene == "battle" and messages.size() > 4:
			messages = messages.slice(-4)
		var stamp := JSON.stringify(messages)
		if stamp != last_chat_stamp:
			last_chat_stamp = stamp
			chat_label.text = "\n".join(messages.map(func(message): return "%s  ›  %s" % [str(message.name), str(message.text)]))

func _confirm_battle_command() -> void:
	if command_context.is_empty():return
	var battle:=_battle_data()
	var confirmed:=str(battle.get("id",""))!=str(command_context.battle) or int(battle.get("generation",-1))!=int(command_context.generation) or battle.get("result") is Dictionary
	var shot:Variant=battle.get("shot")
	if not confirmed and str(command_context.action)=="fire" and shot is Dictionary:
		confirmed=int(shot.get("id",-1))>int(command_context.shot) and int(shot.get("actor",-1))==int(command_context.seat) and float(battle.get("deadline",0))<=0
	var item_consumed:=false
	if str(command_context.action)=="item":
		var inventory:Array=profile.get("inventory",[])
		var slot:=int(command_context.slot)
		item_consumed=slot>=0 and slot<inventory.size() and int(command_context.item)>0 and int(inventory[slot])==0
		confirmed=confirmed or item_consumed
	if confirmed:
		# The authoritative state is the acknowledgement. A lost original
		# action reply must not lock input or clear a newer command. Items are
		# confirmed by their consumed inventory slot, never replayed on timeout.
		command_serial+=1
		command_context.clear()
		command_busy=false
		battle_action_serial+=1
		battle_action_busy=false
		if item_consumed:sound.play_event(13)

func _command(command: Dictionary) -> bool:
	if command_busy or auth_busy:
		return false
	command_busy = true
	command_serial+=1
	var requested_serial:=command_serial
	command_context={}
	var battle:=_battle_data()
	if str(command.get("action","")) in ["fire","pass","item"] and not battle.is_empty():
		var shot:Variant=battle.get("shot")
		command_context={"action":str(command.action),"battle":str(battle.id),"generation":int(battle.generation),"seat":int(battle.active),"shot":int(shot.get("id",-1)) if shot is Dictionary else -1}
		if str(command.action)=="item":
			var slot:=int(command.get("slot",-1))
			var inventory:Array=profile.get("inventory",[])
			command_context.slot=slot
			command_context.item=int(inventory[slot]) if slot>=0 and slot<inventory.size() else 0
	var requested_token: String = net.token
	var response: Dictionary = await net.request("/api/command", command)
	if requested_serial!=command_serial:return true
	command_busy = false
	command_context.clear()
	if auth_busy or net.token != requested_token or net.token.is_empty():
		return false
	if response.has("profile"):
		_accept_state(response)
		if str(command.get("action",""))=="invite":toast("邀请已发送",3)
		if str(command.get("action","")) in ["buy","sell","item"]:
			sound.play_event(13 if str(command.action)=="item" else 17)
		return true
	elif response.has("error"):
		if str(command.get("action",""))=="fire" and str(response.error)=="SP 不足":
			_failed_fire(_input_battle_unit(),int(command.weapon))
		else:toast(str(response.error))
	return false

func _process(delta: float) -> void:
	if not is_instance_valid(channel_gate): _present_invitation()
	if quitting:return
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0:
			toast_label.visible = false
	if auth_busy or not net or net.token.is_empty():
		return
	poll_elapsed += delta
	if poll_elapsed >= 0.3 and not poll_busy:
		poll_elapsed = 0
		_poll()
	if scene != "battle":
		return
	_reflow_hud()
	var battle:Dictionary = view.battle
	var active := _active()
	if battle.is_empty() or active.is_empty():
		return
	var is_turn := _my_turn()
	var turn_key := str(battle.get("id",""))+":"+str(battle.get("generation",0))
	if is_turn and turn_key!=sound_turn_stamp:
		sound_turn_stamp=turn_key
		sound.play_event(1)
	var remaining := maxi(0, int(ceil(float(battle.get("deadline", 0)) - net.server_now())))
	battle_status.text = "第 %d 轮   ·   风 %s %d   ·   %s %s" % [int(battle.round), "→" if int(battle.wind) >= 0 else "←", absi(int(battle.wind)), str(active.name), "行动 %d秒" % remaining if float(battle.deadline) > 0 else "正在射击"]
	var own := {}
	for unit in battle.get("units", []):
		if int(unit.player) == int(profile.id):
			own = unit
	if own.is_empty():
		return
	battle_detail.text = "%s   耐久 %d/%d   SP %d/200   移动 %.0f   角度 %.0f°   力度 %.0f%%" % [_vehicle_name(int(own.vehicle)), int(own.hp), int(own.max_hp), int(own.sp), float(own.move), aim, charge * 100]
	if int(own.hp) <= 0:
		battle_detail.text += "   ·   已进入观战，AI 和其他玩家继续对战"
	var vehicle: Dictionary = catalog.vehicles[int(own.vehicle) - 1]
	var native_aim := bool(battle.get("native_aim", false))
	var aim_min := float(vehicle.get("aim_min", 5)) if native_aim else 5.0
	var aim_max := float(vehicle.get("aim_max", 175)) if native_aim else 175.0
	aim = clampf(aim, aim_min, aim_max)
	for index in range(3):
		var weapon: Dictionary = vehicle.weapons[index]
		weapon_buttons[index].text = "%d%s" % [index + 1, " ✓" if index == selected_weapon else ""]
		var cost := _weapon_cost(own, index)
		weapon_buttons[index].tooltip_text = "%s · %d SP" % [str(weapon.name), cost]
		weapon_buttons[index].disabled = int(own.sp) < cost
	# Keep an unaffordable shot clickable so mouse and keyboard get the same
	# native failed-fire smoke and sound instead of an apparently dead button.
	fire_button.disabled = not is_turn or command_busy or battle_action_busy
	hud_buttons.skip.disabled=not is_turn or command_busy or battle_action_busy
	charge_bar.value = charge * 100
	view.angle = aim
	view.power = charge
	if charging:
		if not is_turn or charge_generation != int(battle.generation):
			charging = false
		else:
			charge_ticks+=delta*60
			while charge_ticks>=1:
				charge_ticks-=1
				charge=minf(1,charge+2.0/300)
			if charge>=1:_fire()
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit or _modal_open()
	if is_turn and not typing:
		if Input.is_physical_key_pressed(KEY_UP):
			aim = minf(aim_max, aim + delta * 30)
		if Input.is_physical_key_pressed(KEY_DOWN):
			aim = maxf(aim_min, aim - delta * 30)
		aim_slider.set_value_no_signal(aim)
	var walk_direction:=0
	if is_turn and not typing and not charging and not command_busy and not battle_action_busy:
		walk_direction=int(Input.is_physical_key_pressed(KEY_RIGHT))-int(Input.is_physical_key_pressed(KEY_LEFT))
	if walker:walker.process(delta,walk_direction)
	if walker and walker.direction!=0 and not walker.unit.is_empty():aim_face=int(walker.unit.face)
	view.preview_face=aim_face

func _poll() -> void:
	poll_busy = true
	var requested_token: String = net.token
	var response: Dictionary = await net.request("/api/state", null, true)
	poll_busy = false
	if auth_busy or net.token != requested_token or net.token.is_empty():
		return
	if response.has("profile"):
		network_failures = 0
		_accept_state(response)
	elif int(response.get("status", 0)) == 401:
		_logout()
		toast("登录已过期，请重新登录")
	elif response.has("error"):
		network_failures += 1
		if network_failures % 10 == 1:
			toast("网络暂时中断，正在尝试恢复连接", 4)

func _input(event: InputEvent) -> void:
	if quitting:return
	if not event is InputEventKey:
		return
	if event.physical_keycode == KEY_F11 and event.pressed and not event.echo:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(channel_gate) or is_instance_valid(page_transition): return
	if _modal_open():return
	var focus := get_viewport().gui_get_focus_owner()
	if scene == "battle" and event.pressed and not event.echo and is_instance_valid(chat_input):
		if focus == chat_input and event.keycode == KEY_ESCAPE:
			if chat_input.has_ime_text():return
			chat_input.clear()
			chat_input.release_focus()
			get_viewport().set_input_as_handled()
			return
		if not (focus is LineEdit or focus is TextEdit) and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			chat_input.grab_focus()
			get_viewport().set_input_as_handled()
			return
	if focus is LineEdit or focus is TextEdit:
		return
	if event.physical_keycode == KEY_ESCAPE and event.pressed and not event.echo:
		if scene == "battle":_battle_menu()
		else:_settings()
		accept_event()
	if scene == "battle":
		if event.physical_keycode==KEY_F9 and event.pressed and not event.echo:
			_skip_turn()
			accept_event()
			return
		if event.physical_keycode == KEY_SPACE and not event.echo:
			if event.pressed:
				_start_charging()
			else:
				_fire()
			accept_event()
		if event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
			_select_weapon(event.physical_keycode - KEY_1)
		if event.pressed and not event.echo and event.physical_keycode >= KEY_F1 and event.physical_keycode <= KEY_F3:
			_select_weapon(event.physical_keycode - KEY_F1)
		if event.pressed and not event.echo and event.physical_keycode >= KEY_F5 and event.physical_keycode <= KEY_F8:
			_battle_command({"action":"item","slot":event.physical_keycode-KEY_F5})

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		charging = false

func _modal_open() -> bool:
	for node in get_tree().get_nodes_in_group("native_modal"):
		if node.is_visible_in_tree():return true
	for child in get_children():
		if child is Window and child.visible:return true
	return false

func _toggle_fullscreen() -> void:
	if not full_screen:
		old_size = DisplayServer.window_get_size()
		old_position = DisplayServer.window_get_position()
		old_window_mode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(old_window_mode)
		if old_window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(old_size)
			DisplayServer.window_set_position(old_position)
	full_screen = not full_screen

func _settings() -> void:
	var dialog := _dialog("游戏设置", Vector2(570, 490))
	var body: VBoxContainer = dialog.get_meta("body")
	_label("音乐", body, 15, MUTED)
	var music := HSlider.new()
	music.min_value = 0
	music.max_value = 1
	music.step = 0.01
	music.value = sound.music_volume
	body.add_child(music)
	music.value_changed.connect(func(value): sound.music_volume = value; sound.apply_volume())
	_label("音效", body, 15, MUTED)
	var effects := HSlider.new()
	effects.min_value = 0
	effects.max_value = 1
	effects.step = 0.01
	effects.value = sound.effects_volume
	body.add_child(effects)
	effects.value_changed.connect(func(value): sound.effects_volume = value; sound.apply_volume())
	var shake := CheckBox.new()
	shake.text = "爆炸震屏"
	shake.button_pressed = bool(config.get("shake", true))
	body.add_child(shake)
	var quality := OptionButton.new()
	for name in ["特效：轻量", "特效：标准", "特效：增强"]:
		quality.add_item(name)
	quality.select(int(config.get("quality", 1)))
	body.add_child(quality)
	var fps := OptionButton.new()
	fps.add_item("帧率上限：60", 60)
	fps.add_item("帧率上限：120", 120)
	fps.add_item("帧率上限：不限", 0)
	fps.select(fps.get_item_index(int(config.get("fps", 120))))
	body.add_child(fps)
	_label("高清版服务器（重新登录后生效）", body, 13, MUTED)
	var endpoint := LineEdit.new()
	endpoint.text = net.endpoint
	body.add_child(endpoint)
	_label("窗口可拖动调整或直接最大化；F11 切换全屏。", body, 13, MUTED)
	dialog.confirmed.connect(func():
		config.music = music.value
		config.effects = effects.value
		config.shake = shake.button_pressed
		config.quality = quality.selected
		config.fps = fps.get_selected_id()
		Engine.max_fps = int(config.fps)
		var address := endpoint.text.strip_edges().trim_suffix("/")
		if address.begins_with("https://") or address.begins_with("http://127.0.0.1:") or address.begins_with("http://localhost:") or address.begins_with("http://192.168.") or address.begins_with("http://10."):
			config.endpoint = address
			if scene == "login":
				net.endpoint = address
		else:
			toast("公网服务器请使用 HTTPS，局域网可使用内网地址")
		if is_instance_valid(view):
			view.shake_enabled = bool(config.shake)
			view.quality = int(config.quality)
		_save_config()
	)
	dialog.popup_centered()

func _save_config() -> void:
	if qa:
		return
	var file := FileAccess.open(data_root.path_join("settings.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config, "\t"))

func _vault(mode: String, value: String) -> String:
	if qa:
		return ""
	var helper := OS.get_executable_path().get_base_dir().path_join("Vault.exe")
	if not FileAccess.file_exists(helper):
		helper = ProjectSettings.globalize_path("res://../../.tools/Vault.exe")
	if not FileAccess.file_exists(helper):
		return ""
	var process := OS.execute_with_pipe(helper, PackedStringArray([mode]), true)
	if process.is_empty():
		return ""
	var pipe: FileAccess = process.stdio
	pipe.store_line(value)
	pipe.flush()
	return pipe.get_line().strip_edges()

func _logout() -> void:
	if auth_busy or quitting:return
	_cancel_page_transition()
	_cancel_channel_gate()
	auth_generation+=1
	auth_busy=true
	command_busy=true
	if not net.token.is_empty():
		await net.request("/api/logout", {})
	if quitting:return
	net.token = ""
	net.etag = ""
	snapshot.clear()
	profile.clear()
	_vault("clear", "")
	if launched_session:
		_return_to_launcher()
		return
	register_mode=false
	_show_login()
	account_label.text = "欢迎归队"
	auth_busy=false
	command_busy=false

func _ensure_server() -> void:
	var response: Dictionary = await net.request("/health")
	if response.get("edition") == "hd":
		return
	if not net.endpoint.begins_with("http://127.0.0.1:18180"):
		return
	var directory := OS.get_executable_path().get_base_dir()
	var executable := directory.path_join("server/hdserver.exe")
	var assets := directory.path_join("server/assets")
	if not FileAccess.file_exists(executable):
		executable = ProjectSettings.globalize_path("res://../../.tools/hdserver-current.exe")
		assets = ProjectSettings.globalize_path("res://assets")
	if FileAccess.file_exists(executable):
		OS.create_process(executable, PackedStringArray(["--listen", "127.0.0.1:18180", "--data", data_root.path_join("Server"), "--assets", assets]), false)
		for attempt in range(15):
			await get_tree().create_timer(0.2).timeout
			response = await net.request("/health")
			if response.get("edition") == "hd":
				return

func _quit() -> void:
	if quitting:return
	quitting=true
	_cancel_page_transition()
	if is_instance_valid(sound):
		sound.shutdown()
	if net:net.shutdown()
	print("HD: shutdown requested") if qa else null
	_save_config()
	if net and not net.token.is_empty():
		var http := HTTPRequest.new()
		http.timeout=1.0
		# Cancellation must not join a worker blocked in network I/O.
		http.use_threads=false
		add_child(http)
		net.configure_http(http)
		var error := http.request(net.endpoint + "/api/command", PackedStringArray(["Authorization: Bearer " + net.token, "Content-Type: application/json"]), HTTPClient.METHOD_POST, '{"action":"leave"}')
		if error==OK:await http.request_completed
		http.queue_free()
	if net:
		net.root = null
	if is_instance_valid(sound):
		await sound.wait_for_shutdown()
	get_tree().quit()
	print("HD: SceneTree quit submitted") if qa else null

func _qa_run() -> void:
	if str(qa_options.get("scene", "")) == "login":
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		if qa_options.has("screenshot"):
			var image := get_viewport().get_texture().get_image()
			image.save_png(str(qa_options.screenshot))
		print(JSON.stringify({"qa": true, "scene": scene, "native_layout": true}))
		await _quit()
		return
	var name := str(qa_options.get("user", "qa_" + Crypto.new().generate_random_bytes(5).hex_encode()))
	var response: Dictionary = await net.request("/api/register", {"name": name, "password": "qa-only-895432"})
	if not response.has("token"):
		response = await net.request("/api/login", {"name": name, "password": "qa-only-895432"})
	if not response.has("token"):
		push_error("QA login failed")
		get_tree().quit(2)
		return
	net.token = str(response.token)
	var state: Dictionary = await net.request("/api/state")
	_accept_state(state)
	if qa_options.has("session-script"):
		var ready_file := FileAccess.open(str(qa_options["session-script"])+".ready",FileAccess.WRITE)
		ready_file.store_string(JSON.stringify({"profile":int(profile.id),"scene":scene}))
		ready_file.close()
		var remaining := float(qa_options.get("session-seconds", 420.0))
		var seen_result := false
		while remaining>0 and not FileAccess.file_exists(str(qa_options["session-script"])+".finish"):
			await get_tree().create_timer(0.2).timeout
			remaining-=0.2
			var battle := _battle_data()
			if battle.get("result") is Dictionary and not seen_result:
				seen_result=true
				await get_tree().create_timer(1).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(str(qa_options["session-script"])+".result.png")
				var back := find_child("ReturnToRoom",true,false) as Button
				if not back:
					push_error("QA settlement return button missing")
					get_tree().quit(3)
					return
				back.pressed.emit()
			elif battle.is_empty():
				seen_result=false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(qa_options["session-script"])+".final.png")
		print(JSON.stringify({"qa_real_session":true,"scene":scene,"music_tracks":sound.tracks.size(),"effects":sound.effects.size(),"maps":catalog.get("maps",[]).size(),"vehicles":catalog.get("vehicles",[]).size()}))
		await _quit()
		return
	var target := str(qa_options.get("scene", "lobby"))
	if target in ["room", "battle"]:
		await _command({"action": "create", "name": "高清版验收房间", "map": int(qa_options.get("map", 1)), "capacity": 8})
		var bots := []
		for index in range(16):
			bots.append({"seat": index, "level": 2 if index in [4, 8, 12] else 0, "vehicle": index + 1 if index in [4, 8, 12] else 0})
		await _command({"action": "bots", "bots": bots})
		if target == "battle":
			await _command({"action": "start"})
	elif target == "shop":
		_show_shop()
	await get_tree().create_timer(float(qa_options.get("wait", 2))).timeout
	if qa_options.has("check-layout"):
		if not await _qa_layout_checks():
			get_tree().quit(2)
			return
	if qa_options.has("shot") and scene == "battle" and _my_turn():
		aim=65
		await _battle_command({"action": "fire", "angle": 65.0, "power": 0.7, "weapon": 0})
		await get_tree().create_timer(1.0).timeout
	if qa_options.has("screenshot"):
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(str(qa_options.screenshot))
		print(JSON.stringify({"qa": true, "scene": scene, "size": [image.get_width(), image.get_height()], "screenshot_error": error}))
		if is_instance_valid(view):
			print(JSON.stringify({"camera": str(view.camera), "zoom": view.zoom, "view_size": str(view.size), "units": _battle_data().get("units", [])}))
	if qa_options.has("duration"):
		await get_tree().create_timer(float(qa_options.duration)).timeout
	get_tree().root.close_requested.emit()

func _qa_layout_checks() -> bool:
	var reports := []
	var initial := DisplayServer.window_get_size()
	for dimensions in [Vector2i(960,600), Vector2i(960,900), Vector2i(1366,768), Vector2i(1920,1080), Vector2i(2560,1440), initial]:
		DisplayServer.window_set_size(dimensions)
		await get_tree().create_timer(0.2).timeout
		skin.reflow()
		if scene=="room":
			_update_room()
			await get_tree().process_frame
			await get_tree().process_frame
			var area := room_grid.get_global_rect().grow(1)
			for index in range(16):
				var slot := room_grid.get_node("RoomSeat%02d"%index) as Control
				if not area.encloses(slot.get_global_rect()) or slot.get_global_rect().intersects(chat_label.get_global_rect()):
					push_error("QA room seat overflow at %s seat %d"%[dimensions,index])
					return false
				for child in slot.get_children():
					if child is TextureRect and not slot.get_global_rect().grow(1).encloses(child.get_global_rect()):
						push_error("QA room card overflow at %s seat %d"%[dimensions,index])
						return false
			var shortcuts := find_child("VehicleShortcuts",true,false) as Control
			for child in shortcuts.get_children():
				if not shortcuts.get_global_rect().grow(1).encloses(child.get_global_rect()):
					push_error("QA vehicle shortcut overflow at %s"%dimensions)
					return false
		var physical := get_viewport_rect().size
		if not skin.size.is_equal_approx(physical):
			push_error("QA native viewport layout mismatch")
			return false
		for entry: Dictionary in skin.placements:
			var rect: Rect2 = entry.node.get_global_rect()
			if not Rect2(Vector2.ZERO,physical).grow(2).encloses(rect):
				push_error("QA page control overflow at %s: %s"%[dimensions,entry.node.name])
				return false
		if scene == "battle" and absf(view.size.x-physical.x) > 2:
			push_error("QA battlefield is still restricted to a fixed aspect ratio")
			return false
		reports.append({"window": str(DisplayServer.window_get_size()), "viewport": str(physical), "extra_space": str(skin.extra)})
	if scene == "room":
		var practice := find_child("AIPractice", true, false) as Button
		if not is_instance_valid(practice):
			push_error("QA integrated AI button missing")
			return false
		var point := practice.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.position = point
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			Input.parse_input_event(click)
			await get_tree().process_frame
		await get_tree().create_timer(0.1).timeout
		var level := find_child("AIDifficulty00", true, false) as OptionButton
		var vehicle := find_child("AIVehicle00", true, false) as OptionButton
		if not level or not vehicle or not level.disabled or not vehicle.disabled:
			push_error("QA native AI dialog failed to open or human seat was editable")
			return false
		for child in get_children():
			if child is ConfirmationDialog:
				child.canceled.emit()
		await get_tree().process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	await get_tree().create_timer(0.3).timeout
	var maximized := DisplayServer.window_get_size()
	_toggle_fullscreen()
	await get_tree().create_timer(0.25).timeout
	_toggle_fullscreen()
	await get_tree().create_timer(0.25).timeout
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MAXIMIZED:
		push_error("QA F11 failed to restore maximized state")
		return false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(initial)
	await get_tree().create_timer(0.2).timeout
	print(JSON.stringify({"qa_layout": true, "sizes": reports, "maximized": str(maximized), "native_AI_dialog": scene == "room", "restores_maximize": true}))
	return true
