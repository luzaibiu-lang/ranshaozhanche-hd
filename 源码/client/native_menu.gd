extends Control
## Native MenuBox artwork; input stays inside the game's own viewport.
signal changed(option: String, enabled: bool)
signal leave_requested
var options := {"music": true, "effects": true, "fullscreen": false, "zoom_lock": false}
var panel: Control
var toggles := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("native_modal")
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = Control.new()
	add_child(panel)
	var backing := TextureRect.new()
	backing.texture = load("res://assets/icons/MenuBox/00.png")
	backing.position = Vector2(4, 4)
	backing.size = Vector2(172, 179)
	backing.modulate.a = 0.5
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backing)
	var picture := TextureRect.new()
	picture.texture = load("res://assets/icons/MenuBox/01.png")
	picture.size = Vector2(180, 187)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(picture)
	var index := 0
	for key in ["music", "effects", "fullscreen", "zoom_lock"]:
		var y: float = [52, 67, 110, 125][index]
		var toggle := TextureRect.new()
		toggle.position = Vector2(106, y)
		toggle.size = Vector2(56, 12)
		toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(toggle)
		toggles[key] = toggle
		for enabled in [true, false]:
			var button := Button.new()
			button.name = key + ("_on" if enabled else "_off")
			button.position = Vector2(106 + (0 if enabled else 30), y - 2)
			button.size = Vector2(27, 17)
			_style_button(button)
			button.pressed.connect(func():
				options[key] = enabled
				_refresh()
				changed.emit(key, enabled)
			)
			panel.add_child(button)
		index += 1
	var leave := Button.new()
	leave.name = "LeaveMatch"
	leave.position = Vector2(9, 157)
	leave.size = Vector2(76, 20)
	_style_button(leave)
	leave.pressed.connect(func():
		hide()
		queue_free()
		leave_requested.emit()
	)
	panel.add_child(leave)
	resized.connect(_reflow)
	_refresh()
	_reflow()

func _style_button(button: Button) -> void:
	for key in ["normal", "pressed", "focus"]:
		button.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.45, 1, 0.16)
	button.add_theme_stylebox_override("hover", hover)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _refresh() -> void:
	for key in toggles:
		toggles[key].texture = load("res://assets/icons/MenuBox/%02d.png" % (2 if bool(options[key]) else 3))

func _reflow() -> void:
	var s := maxf(1, minf(size.x / 800, size.y / 600))
	panel.scale = Vector2.ONE * s
	panel.position = size - Vector2(188, 220) * s

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide()
		queue_free()
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		hide()
		queue_free()
		get_viewport().set_input_as_handled()
