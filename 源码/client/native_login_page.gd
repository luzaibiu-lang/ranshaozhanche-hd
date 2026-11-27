extends Control
## Original-game art in an interactive tile field; authentication lives in main.
signal submit_requested
signal registration_toggled
signal remember_toggled(enabled: bool)
signal cue_requested(id: int)

const BACKGROUND = preload("res://assets/maps/17/background.jpg")

# Orthographic projection of the original 128-wide, 20-deep octagonal tile.
class SolidTile extends Polygon2D:
	var outline: PackedVector2Array
	var front_uv: PackedVector2Array
	var back_uv: PackedVector2Array
	var depth_unit: float
	var orientation := Basis.IDENTITY
	var moving := false

	func configure(points: PackedVector2Array, coords: PackedVector2Array, scale_unit: float) -> void:
		outline = points
		front_uv = coords
		depth_unit = scale_unit
		var center_u := (coords[0].x + coords[1].x) * 0.5
		for coord in coords:
			back_uv.append(Vector2(2 * center_u - coord.x, coord.y))
		polygon = points
		uv = coords

	func rotate_solid(axis: Vector3, angle: float) -> void:
		moving = not is_zero_approx(angle)
		orientation = Basis(axis, angle)
		var front := orientation.z.z >= 0
		var depth := 10.0 if front else -10.0
		var projected := PackedVector2Array()
		for point in outline:
			projected.append(project(point, depth))
		polygon = projected if absf(orientation.z.z) > 0.00001 else PackedVector2Array()
		uv = front_uv if front else back_uv
		var light := minf(1.0, 0.15 + absf(orientation.z.z))
		color = Color(light, light, light)
		z_index = int(moving)
		queue_redraw()

	func project(point: Vector2, depth: float) -> Vector2:
		var p := orientation * Vector3(point.x, point.y, depth * depth_unit)
		return Vector2(p.x, p.y)

	func _draw() -> void:
		if not moving:return
		# The three strips share both endpoints with the caps, so the slab stays
		# closed at oblique angles. Cull their back-facing normals.
		var tex_size := texture.get_size()
		for edge in range(outline.size()):
			var next := (edge + 1) % outline.size()
			var a := outline[edge]
			var b := outline[next]
			var normal := Vector3(b.y-a.y, a.x-b.x, 0).normalized()
			var incidence := (orientation * normal).z
			if incidence <= 0.0001:continue
			var light := minf(1.0, 0.15 + incidence)
			var shade := Color(light,light,light)
			var front_a := front_uv[edge] / tex_size
			var front_b := front_uv[next] / tex_size
			var back_a := back_uv[edge] / tex_size
			var back_b := back_uv[next] / tex_size
			var upper := PackedVector2Array([project(a,10),project(b,10),project(b,4),project(a,4)])
			var lower := PackedVector2Array([project(a,-4),project(b,-4),project(b,-10),project(a,-10)])
			draw_colored_polygon(upper, shade, PackedVector2Array([front_a,front_b,front_b,front_a]), texture)
			draw_colored_polygon(PackedVector2Array([upper[3],upper[2],lower[1],lower[0]]),Color("cccccc").srgb_to_linear() * shade)
			draw_colored_polygon(lower, shade, PackedVector2Array([back_a,back_b,back_b,back_a]), texture)

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
var pointer_samples: Array[Vector3] = []
var last_cell := -1
var columns := 0
var grid_left := 0.0
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
	dark.color = Color("0f0f0f")
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
		get_window().connect("mouse_exited", _reset_pointer)
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
	var gap := tile_size * 2 / 128
	columns = ceili(size.x / tile_size) + 1
	var rows := ceili(size.y / tile_size)
	var start := (size.x - columns * tile_size) / 2
	grid_left = start
	_reset_pointer()
	for row in range(rows):
		for column in range(columns):
			var center := Vector2(start + (column + 0.5) * tile_size, (row + 0.5) * tile_size)
			var half := (tile_size - gap) / 2
			var cut := 4.0 * tile_size / 128
			var base := PackedVector2Array([Vector2(-half+cut,-half),Vector2(half-cut,-half),Vector2(half,-half+cut),Vector2(half,half-cut),Vector2(half-cut,half),Vector2(-half+cut,half),Vector2(-half,half-cut),Vector2(-half,-half+cut)])
			var tile := SolidTile.new()
			tile.texture = BACKGROUND
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var uv := PackedVector2Array()
			for point in base:uv.append((center + point - offset) / cover)
			tile.configure(base, uv, tile_size / 128)
			tile.position = center
			tile_layer.add_child(tile)
			tiles.append({"node":tile,"center":center,"base":base,"started":-2.0,"duration":0.0,"amplitude":0.0,"axis":Vector3.UP,"angle":0.0})

func _reset_pointer() -> void:
	pointer_samples.clear()
	last_cell = -1

func _track_pointer(point: Vector2) -> void:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		_reset_pointer()
		return
	var cell := floori(point.y / tile_size) * columns + floori((point.x - grid_left) / tile_size)
	while not pointer_samples.is_empty() and (elapsed - pointer_samples[0].z >= 0.5 or pointer_samples.size() >= 10):
		pointer_samples.pop_front()
	pointer_samples.append(Vector3(point.x, point.y, elapsed))
	if cell == last_cell or cell < 0 or cell >= tiles.size():return
	last_cell = cell
	var sample := pointer_samples[0]
	var travel := (point - Vector2(sample.x, sample.y)) * (128.0 / tile_size)
	if travel.is_zero_approx():return
	var strength := clampf(travel.length() / 70.0, 0.6, 1.0)
	var tile := tiles[cell]
	tile.started = elapsed
	tile.duration = roundf(1200.0 * strength) / 1000.0
	tile.amplitude = 1.7 * (1.0 - cos(strength * PI / 2.0))
	tile.axis = Vector3(-travel.y, travel.x, 0).normalized()
	cue_requested.emit(2)

func _input(event: InputEvent) -> void:
	if leaving:return
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_track_pointer(event.position)
	elif event is InputEventScreenTouch:
		_reset_pointer()
		if event.pressed:_track_pointer(event.position)
	elif event is InputEventScreenDrag:
		_track_pointer(event.position)

func _process(delta: float) -> void:
	elapsed += delta
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0:notice.text = ""
	for tile in tiles:
		if tile.duration <= 0.0:continue
		var progress := clampf((elapsed - float(tile.started)) / float(tile.duration), 0, 1)
		if progress >= 1.0:
			tile.angle = 0.0
			tile.duration = 0.0
			tile.node.rotate_solid(Vector3.UP, 0)
			continue
		var phase := sin(progress * PI / 2.0)
		var angle := sin(3.0 * PI * phase) * float(tile.amplitude) * cos(phase * PI / 2.0)
		tile.angle = angle
		tile.node.rotate_solid(tile.axis, angle)

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
	_reset_pointer()
	set_busy(true)
	exit_tween = create_tween().set_parallel(true)
	exit_tween.tween_property(form, "modulate:a", 0.0, 0.35)
	exit_tween.tween_property(form, "position:y", form.position.y - 18 * unit, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
