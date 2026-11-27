extends Control
## Original-game art in an interactive tile field; authentication lives in main.
signal submit_requested
signal registration_toggled
signal remember_toggled(enabled: bool)
signal cue_requested(id: int)

const BACKGROUND = preload("res://assets/maps/17/background.jpg")
var registering := false
var initial_username := ""
var remembered := false
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var remember: CheckBox
var submit: Button
var mode_button: Button
var form: Control
var notice: Label
var brand: Label
var subtitle: Label
var hint: Label
var tile_layer: Node2D
var tiles: Array[Dictionary] = []
var placements: Array[Dictionary] = []
var pointer := Vector2(-10000, -10000)
var pointer_active := false
var elapsed := 0.0
var notice_time := 0.0
var unit := 1.0
var tile_size := 120.0
var leaving := false
var exit_tween: Tween
var layout_size := Vector2.ZERO

func _ready() -> void:
	name = "NativeLoginPage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var dark := ColorRect.new()
	dark.color = Color("080d13")
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dark)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile_layer = Node2D.new()
	add_child(tile_layer)
	brand = _label("燃烧战车", 30, Color("fff5d8"))
	brand.z_index = 40
	add_child(brand)
	subtitle = _label("高清重制版", 13, Color("d8dce5"))
	subtitle.z_index = 40
	add_child(subtitle)
	form = Control.new()
	form.name = "LoginForm"
	form.z_index = 50
	form.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(form)
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.045, 0.06, 0.54)
	panel.set_corner_radius_all(4)
	plate.add_theme_stylebox_override("panel", panel)
	_place(plate, Rect2(0, 0, 480, 302 if registering else 263))
	_place(_label("账号", 21), Rect2(28, 29, 100, 43), 21)
	_place(_label("密码", 21), Rect2(28, 101, 100, 43), 21)
	username = _entry("Username", false)
	username.text = initial_username
	username.max_length = 16
	_place(username, Rect2(150, 16, 190, 54), 21)
	password = _entry("Password", true)
	_place(password, Rect2(150, 88, 190, 54), 21)
	confirmation = _entry("Confirmation", true)
	confirmation.visible = registering
	if registering:
		_place(_label("确认密码", 20), Rect2(28, 173, 116, 43), 20)
		_place(confirmation, Rect2(150, 160, 190, 54), 21)
	else:
		form.add_child(confirmation)
	submit = _button("注册" if registering else "登录", "Login")
	_place(submit, Rect2(360, 16, 92, 198 if registering else 126), 24)
	submit.pressed.connect(func():cue_requested.emit(65);submit_requested.emit())
	mode_button = _button("已有账号？返回登录" if registering else "没有账号？注册", "ToggleRegistration")
	_place(mode_button, Rect2(150, 230 if registering else 158, 302, 42), 19)
	mode_button.pressed.connect(func():cue_requested.emit(65);registration_toggled.emit())
	remember = CheckBox.new()
	remember.name = "RememberLogin"
	remember.text = "记住登录（仅本机）"
	remember.button_pressed = remembered
	remember.visible = not registering
	remember.add_theme_color_override("font_color", Color("fff3cc"))
	remember.add_theme_color_override("font_hover_color", Color.WHITE)
	for key in ["font_pressed_color", "font_hover_pressed_color"]:remember.add_theme_color_override(key, Color("fff3cc"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:remember.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for checked in [false, true]:
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="1" y="1" width="18" height="18" rx="2" fill="#302616" stroke="#ffe8ae" stroke-width="1.5"/>'
		if checked:svg += '<path d="M5 10 L8.5 14 L15 6" fill="none" stroke="#ffe46c" stroke-width="2.5"/>'
		svg += '</svg>'
		var icon := Image.new()
		if icon.load_svg_from_string(svg) == OK:
			var texture := ImageTexture.create_from_image(icon)
			remember.add_theme_icon_override("checked" if checked else "unchecked", texture)
			remember.add_theme_icon_override("checked_disabled" if checked else "unchecked_disabled", texture)
	_place(remember, Rect2(150, 214, 302, 30), 14)
	remember.toggled.connect(func(value: bool):remember_toggled.emit(value))
	notice = _label("", 14, Color("fff0bc"))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(notice, Rect2(4, 308 if registering else 269, 472, 65), 14)
	username.text_submitted.connect(func(_text: String):password.grab_focus())
	password.text_submitted.connect(func(_text: String):
		if registering:confirmation.grab_focus()
		else:submit_requested.emit()
	)
	confirmation.text_submitted.connect(func(_text: String):submit_requested.emit())
	hint = _label("F11 全屏  ·  Enter 确认", 12, Color("dce0e8"))
	hint.z_index = 40
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)
	resized.connect(_layout)
	if get_window().has_signal("mouse_exited"):
		get_window().connect("mouse_exited", func():pointer_active = false)
	_layout()
	username.grab_focus()

func _label(text: String, points: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.8))
	label.add_theme_constant_override("outline_size", 1)
	return label

func _gold_style(bright := false, pressed := false) -> StyleBoxTexture:
	var image := Image.create(24, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		var t := float(y) / 63
		var color := Color("fff399") .lerp(Color("e2a000"), t)
		if t < 0.38:color = Color("fffbe0").lerp(Color("ffe768"), t / 0.38)
		if bright:color = Color("fff02b").lerp(Color("ffda32"), t)
		if pressed:color = Color("d89d0a").lerp(Color("f5bf25"), t)
		for x in range(24):
			var border := x < 2 or x >= 22 or y < 2 or y >= 62
			image.set_pixel(x, y, Color("fff8c9") if border else color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.texture_margin_left = 3
	style.texture_margin_right = 3
	style.texture_margin_top = 3
	style.texture_margin_bottom = 3
	style.content_margin_left = 9
	style.content_margin_right = 9
	return style

func _entry(id: String, secret: bool) -> LineEdit:
	var field := LineEdit.new()
	field.name = id
	field.secret = secret
	field.add_theme_stylebox_override("normal", _gold_style())
	field.add_theme_stylebox_override("focus", _gold_style(true))
	for key in ["font_color", "caret_color"]:field.add_theme_color_override(key, Color("342a10"))
	field.add_theme_color_override("selection_color", Color("94660d"))
	field.add_theme_color_override("font_selected_color", Color.WHITE)
	return field

func _button(text: String, id: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _gold_style())
	button.add_theme_stylebox_override("hover", _gold_style(true))
	button.add_theme_stylebox_override("pressed", _gold_style(false, true))
	button.add_theme_stylebox_override("disabled", _gold_style(false, true))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	focus.border_color = Color.WHITE
	button.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:button.add_theme_color_override(key, Color("785511"))
	button.add_theme_color_override("font_disabled_color", Color("a48a49"))
	return button

func _place(node: Control, rect: Rect2, points := 0) -> void:
	form.add_child(node)
	placements.append({"node":node, "rect":rect, "font":points})

func _layout() -> void:
	if not is_instance_valid(form) or size.x < 1 or size.y < 1:return
	unit = minf(clampf(minf(size.x / 1280, size.y / 720), 0.65, 1.6), (size.x - 24) / 480)
	var height := 376.0 if registering else 337.0
	unit = minf(unit, (size.y - 80) / height)
	form.position = Vector2((size.x - 480 * unit) / 2, maxf(72 * unit, size.y * 0.215 - (24 * unit if registering else 0)))
	form.size = Vector2(480, height) * unit
	for item in placements:
		item.node.position = item.rect.position * unit
		item.node.size = item.rect.size * unit
		if int(item.font) > 0:item.node.add_theme_font_size_override("font_size", maxi(11, roundi(int(item.font) * unit)))
	brand.position = Vector2(44, 26) * unit
	brand.size = Vector2(300, 50) * unit
	brand.add_theme_font_size_override("font_size", roundi(30 * unit))
	subtitle.position = Vector2(46, 72) * unit
	subtitle.size = Vector2(230, 24) * unit
	subtitle.add_theme_font_size_override("font_size", maxi(11, roundi(13 * unit)))
	hint.position = Vector2(maxf(16, size.x - 320 * unit), size.y - 40 * unit)
	hint.size = Vector2(290, 24) * unit
	if layout_size != size:
		layout_size = size
		_build_tiles()

func _build_tiles() -> void:
	for child in tile_layer.get_children():child.queue_free()
	tiles.clear()
	tile_size = clampf(size.y / 6, 96, 220)
	var texture_size := BACKGROUND.get_size()
	var cover := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var offset := (size - texture_size * cover) / 2
	var gap := clampf(tile_size / 60, 1.5, 3)
	var columns := ceili(size.x / tile_size) + 1
	var rows := ceili(size.y / tile_size)
	var start := (size.x - columns * tile_size) / 2
	for row in range(rows):
		for column in range(columns):
			var center := Vector2(start + (column + 0.5) * tile_size, (row + 0.5) * tile_size)
			var half := (tile_size - gap) / 2
			var cut := 3.0 * tile_size / 120
			var base := PackedVector2Array([Vector2(-half+cut,-half),Vector2(half-cut,-half),Vector2(half,-half+cut),Vector2(half,half-cut),Vector2(half-cut,half),Vector2(-half+cut,half),Vector2(-half,half-cut),Vector2(-half,-half+cut)])
			var shadow := Polygon2D.new()
			shadow.color = Color(0, 0, 0, 0)
			tile_layer.add_child(shadow)
			var tile := Polygon2D.new()
			tile.texture = BACKGROUND
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tile.polygon = base
			var uv := PackedVector2Array()
			for point in base:uv.append((center + point - offset) / cover)
			tile.uv = uv
			tile.position = center
			tile_layer.add_child(tile)
			tiles.append({"node":tile,"shadow":shadow,"center":center,"base":base,"amount":0.0,"tilt":Vector2.ZERO,"seed":float(row*17+column*11)})

func _input(event: InputEvent) -> void:
	if leaving:return
	if event is InputEventMouseMotion:
		pointer = event.position
		pointer_active = Rect2(Vector2.ZERO, size).has_point(pointer)
	elif event is InputEventScreenTouch:
		pointer = event.position
		pointer_active = event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.position
		pointer_active = true

func _process(delta: float) -> void:
	elapsed += delta
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0:notice.text = ""
	var response := 1.0 - exp(-delta * 9)
	for tile in tiles:
		var relative: Vector2 = (pointer - tile.center) / tile_size
		var target := pow(maxf(0, 1 - relative.length() / 1.65), 2) if pointer_active and not leaving else 0.0
		tile.amount = lerpf(float(tile.amount), target, response)
		var wanted := Vector2(clampf(relative.y, -1, 1), -clampf(relative.x, -1, 1)) * 0.18 * target
		tile.tilt = (tile.tilt as Vector2).lerp(wanted, response)
		var points := PackedVector2Array()
		for point: Vector2 in tile.base:
			var vertex := Vector3(point.x, point.y, 0).rotated(Vector3.RIGHT, tile.tilt.x).rotated(Vector3.UP, tile.tilt.y)
			points.append(Vector2(vertex.x, vertex.y) * (1 + tile.amount * 0.035) / (1 - vertex.z / (tile_size * 3)))
		var idle := sin(elapsed * 0.65 + tile.seed) * 0.6
		tile.node.polygon = points
		tile.node.position = tile.center + Vector2(0, idle - tile.amount * 8 * unit)
		tile.node.z_index = roundi(tile.amount * 20)
		var light: float = 0.88 + tile.amount * 0.12 + 0.018 * sin(tile.seed)
		tile.node.modulate = Color(light, light, light, 1)
		tile.shadow.polygon = points
		tile.shadow.position = tile.node.position + Vector2(4, 9) * tile.amount * unit
		tile.shadow.color = Color(0, 0, 0, tile.amount * 0.6)
		tile.shadow.z_index = tile.node.z_index - 1

func set_busy(busy: bool) -> void:
	for field in [username, password, confirmation]:field.editable = not busy
	remember.disabled = busy
	submit.disabled = busy
	mode_button.disabled = busy
	submit.text = "验证中" if busy else "注册" if registering else "登录"

func show_notice(message: String, seconds := 4.0) -> void:
	notice.text = message
	notice_time = seconds

func begin_exit() -> void:
	if leaving:return
	leaving = true
	pointer_active = false
	set_busy(true)
	exit_tween = create_tween().set_parallel(true)
	exit_tween.tween_property(form, "modulate:a", 0.0, 0.35)
	exit_tween.tween_property(form, "position:y", form.position.y - 18 * unit, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
