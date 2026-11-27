extends Control
## A real channel chooser carried by the two native TitleBack door leaves.

signal enter_requested
signal refresh_requested
signal settings_requested
signal fullscreen_requested
signal exit_requested
signal cue_requested(id: int)
signal opened
signal closed_latched

const OriginalSkin = preload("res://original_skin.gd")
const CLOSE_TIME := 0.75
const LATCH_TIME := 0.28
const OPEN_TIME := 0.8
const SPLIT := 308.0

var phase := "closing"
var elapsed := 0.0
var closed := 0.0
var selected := false
var online := false
var refreshing := false
var status := "正在连接高清版服务…"
var state: Dictionary = {}
var cue_events: Array[int] = []
var phase_history: Array[String] = ["closing"]
var left: Control
var right: Control
var row: Button
var enter_button: Button
var refresh_button: Button
var details: Label
var notice: Label
var player_count: Label
var placements: Array[Dictionary] = []
var art: Texture2D = preload("res://assets/legacy/TitleBack.png")
var font: Font
var factor := 1.0
var extra := Vector2.ZERO
var left_extra := 0.0
var opaque_backdrop := true

func _ready() -> void:
	name = "NativeChannelGate"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	font = get_theme_default_font()
	left = Control.new()
	right = Control.new()
	for leaf in [left, right]:
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(leaf)
	row = _button("●  经典频道", Rect2(16, 222, 265, 29), true, _select)
	row.name = "ChannelClassic"
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode = true
	row.clip_text = true
	for entry in [["normal", "0068bf"], ["hover", "087bd1"], ["pressed", "174b86"]]:
		row.add_theme_stylebox_override(entry[0], OriginalSkin.box(Color(entry[1]), Color("8ab9ed")))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		row.add_theme_color_override(key, Color.WHITE)
	for heading in [["状态", Rect2(15, 201, 59, 18), "fixed"], ["频道名", Rect2(75, 201, 136, 18), ""], ["人数", Rect2(212, 201, 70, 18), "count"]]:
		var label := _label(heading[0], heading[1], true, 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 0)
		placements.back().anchor = heading[2]
	player_count = _label("", Rect2(212, 222, 66, 29), true, 14)
	player_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placements.back().anchor = "count"
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.double_click and phase == "select" and online:
			_select()
			_request_enter()
	)
	enter_button = _button("进  入", Rect2(158, 537, 122, 43), true, _request_enter)
	enter_button.name = "EnterChannel"
	refresh_button = _button("刷  新", Rect2(29, 537, 120, 43), true, func(): refresh_requested.emit())
	refresh_button.name = "RefreshChannels"
	_button("选  项", Rect2(473, 537, 98, 43), false, func(): settings_requested.emit(), "right")
	_button("全屏模式", Rect2(579, 537, 98, 43), false, func(): fullscreen_requested.emit(), "right")
	_button("退  出", Rect2(686, 537, 101, 43), false, func(): exit_requested.emit(), "right")
	details = _label("频道公告", Rect2(345, 142, 410, 310), false, 19)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice = _label(status, Rect2(333, 540, 125, 39), false, 11)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resized.connect(_layout)
	_cue.call_deferred(11)
	_layout()
	_update_controls()

func _button(text: String, rect: Rect2, on_left: bool, action: Callable, anchor := "") -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font)
	for entry in [["normal", 0], ["hover", 1], ["pressed", 2], ["disabled", 2]]:
		button.add_theme_stylebox_override(entry[0], OriginalSkin.metal_style(int(entry[1])))
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_color_override("font_disabled_color", Color("35353b"))
	button.pressed.connect(func():
		if phase != "select": return
		_cue(65)
		action.call()
	)
	(left if on_left else right).add_child(button)
	placements.append({"node": button, "rect": rect, "left": on_left, "font": 14, "anchor": anchor})
	return button

func _label(text: String, rect: Rect2, on_left: bool, points: int) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if points == 11 else VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", Color("f1f1f5"))
	label.add_theme_color_override("font_outline_color", Color("303036"))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(left if on_left else right).add_child(label)
	placements.append({"node": label, "rect": rect, "left": on_left, "font": points, "anchor": ""})
	return label

func _layout() -> void:
	if not is_instance_valid(left) or size.x <= 0 or size.y <= 0: return
	factor = minf(size.x / 800.0, size.y / 600.0)
	extra = size / factor - Vector2(800, 600)
	left_extra = extra.x * 0.38
	for item in placements:
		var rect: Rect2 = item.rect
		if item.left:
			if item.anchor == "count":
				rect.position.x += left_extra
			elif item.anchor == "fixed":
				pass
			elif rect.position.y < 500:
				rect.size.x += left_extra
			elif rect.position.x >= 150:
				rect.position.x += left_extra * 0.5
				rect.size.x += left_extra * 0.5
			else:
				rect.size.x += left_extra * 0.5
		else:
			rect.position.x += extra.x if item.anchor == "right" else left_extra
			if item.node == details:
				rect.size.x += extra.x - left_extra
				rect.size.y += extra.y
			if item.node == notice: rect.size.x += extra.x - left_extra
		if rect.position.y >= 500: rect.position.y += extra.y
		item.node.position = rect.position * factor
		item.node.size = rect.size * factor
		item.node.add_theme_font_size_override("font_size", maxi(10, int(item.font * factor)))
	left.size = size
	right.size = size
	_position_leaves()
	queue_redraw()

func _position_leaves() -> void:
	var seam := (SPLIT + left_extra) * factor
	left.position.x = -(1.0 - closed) * (seam + 5.0 * factor)
	right.position.x = (1.0 - closed) * (size.x - seam + 5.0 * factor)

func set_channel_state(value: Dictionary) -> void:
	state = value
	var was_online := online
	online = value.get("profile") is Dictionary and not value.profile.is_empty()
	if online and not was_online: status = "请选择频道" if not selected else "频道已就绪"
	_update_controls()

func show_notice(message: String) -> void:
	status = message
	_update_controls()

func set_refreshing(value: bool) -> void:
	refreshing = value
	if value: status = "正在刷新频道…"
	elif status == "正在刷新频道…": status = "请选择频道" if not selected else "频道已就绪"
	_update_controls()

func _select() -> void:
	if phase != "select" or not online: return
	selected = true
	status = "点击进入或双击频道"
	_update_controls()

func _request_enter() -> void:
	if phase != "select" or not selected or not online: return
	_change_phase("validating")
	status = "正在进入频道…"
	_update_controls()
	enter_requested.emit()

func reject_enter(message: String) -> void:
	if phase != "validating": return
	status = message
	_change_phase("select")
	_update_controls()

func begin_open() -> void:
	if phase != "validating": return
	_change_phase("opening")
	_cue(10)

func _update_controls() -> void:
	if not is_instance_valid(row): return
	var choosing := phase == "select"
	row.disabled = not choosing or not online
	row.set_pressed_no_signal(selected)
	row.text = "●  经典频道" if online else "○  正在连接…"
	player_count.text = "%d 人" % state.get("players", []).size() if online else "—"
	enter_button.disabled = not choosing or not online or not selected
	refresh_button.disabled = not choosing or refreshing
	for item in placements:
		if item.node is Button and item.node not in [row, enter_button, refresh_button]:
			item.node.disabled = not choosing
	details.text = "经典频道\n\n在线玩家：%d 人\n现有房间：%d 个\n\n选择左侧频道，再点击「进入」。\n也可以双击频道直接进入。\n\n好友联机与 AI 陪练共用此频道。" % [state.get("players", []).size(), state.get("rooms", []).size()] if online else "频道公告\n\n正在连接高清版服务。\n连接就绪后可选择频道进入。\n\n连接失败时可点击「刷新」重试，\n或在「选项」中检查连接设置。"
	notice.text = status

func _change_phase(value: String) -> void:
	phase = value
	elapsed = 0
	phase_history.append(value)

func _cue(id: int) -> void:
	cue_events.append(id)
	cue_requested.emit(id)

func _process(delta: float) -> void:
	elapsed += delta
	match phase:
		"closing":
			closed = 1.0 - pow(1.0 - clampf(elapsed / CLOSE_TIME, 0, 1), 3)
			if elapsed >= CLOSE_TIME:
				closed = 1
				_change_phase("latch")
				_cue(12)
		"latch":
			if elapsed >= LATCH_TIME:
				_door_closed()
		"opening":
			closed = 1.0 - smoothstep(0.0, OPEN_TIME, elapsed)
			if elapsed >= OPEN_TIME:
				closed = 0
				_change_phase("finished")
				opened.emit()
	_position_leaves()
	queue_redraw()

func _door_closed() -> void:
	_change_phase("select")
	_update_controls()
	closed_latched.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_request_enter()
		accept_event()

func _patch(source: Rect2, destination: Rect2, on_left: bool) -> void:
	var offset := left.position if on_left else right.position
	draw_texture_rect_region(art, Rect2(destination.position * factor + offset, destination.size * factor), source)

func _draw() -> void:
	if not is_instance_valid(left): return
	if opaque_backdrop and phase not in ["opening", "finished"]:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	# Dedicated channel geometry: unlike the lobby it grows between y=220
	# and 500, keeping its borders continuous and the original logo intact.
	var ys := [0.0, 177.0, 220.0, 500.0, 535.0, 600.0]
	for index in range(ys.size() - 1):
		var y: float = ys[index]
		var h: float = ys[index + 1] - y
		var dy := y + (extra.y if y >= 500 else 0.0)
		var dh := h + (extra.y if y == 220 else 0.0)
		var cuts := [0.0, 282.0, 285.0, SPLIT] if y == 0 else [0.0, 140.0, 282.0, SPLIT] if y == 177 else [0.0, 15.0, 282.0, SPLIT]
		for col in range(3):
			var x: float = cuts[col]
			var w: float = cuts[col + 1] - x
			var dx := x + (left_extra if col == 2 else 0.0)
			_patch(Rect2(x, y, w, h), Rect2(dx, dy, w + (left_extra if col == 1 else 0.0), dh), true)
		var rx := [SPLIT, 480.0, 507.0, 800.0] if y == 0 else [SPLIT, 327.0, 780.0, 800.0]
		if y == 535:
			# The native bottom strip contains baked buttons. Reuse only its
			# plain metal rail, otherwise responsive controls get doubled.
			_patch(Rect2(SPLIT, 585, 492, 15), Rect2(SPLIT + left_extra, dy, 492 + extra.x - left_extra, dh), false)
			continue
		for col in range(3):
			var x: float = rx[col]
			var w: float = rx[col + 1] - x
			var dx := x + left_extra + (extra.x - left_extra if col == 2 else 0.0)
			_patch(Rect2(x, y, w, h), Rect2(dx, dy, w + (extra.x - left_extra if col == 1 else 0.0), dh), false)
	# Fresh text keeps the three native headings crisp instead of widening
	# baked glyphs. The online count stays under its own column at any aspect.
	for cell in [Rect2(14, 200, 60, 20), Rect2(74, 200, 138 + left_extra, 20), Rect2(212 + left_extra, 200, 70, 20)]:
		var destination := Rect2(cell.position * factor + left.position, cell.size * factor)
		draw_rect(destination, Color("a7a7af"))
		draw_rect(destination.grow(-factor), Color("d6d6de"), false, factor)
	# Short latch flash and sparks sit on the native seam, not over the list.
	if phase == "latch":
		var alpha := 1.0 - clampf(elapsed / LATCH_TIME, 0, 1)
		var x := (SPLIT + left_extra) * factor
		draw_line(Vector2(x, 105 * factor), Vector2(x, size.y - 75 * factor), Color(0.7, 0.87, 1, alpha * 0.65), 4 * factor)
		for index in range(8):
			var y := (150.0 + index * 42.0) * factor
			var travel := (1.0 - alpha) * 30 * factor
			for direction in [-1, 1]:
				var point := Vector2(x + direction * travel, y + travel * 0.25)
				draw_line(point, point + Vector2(direction * 6, 2) * factor, Color(1, 0.8, 0.43, alpha), factor * 1.5)
