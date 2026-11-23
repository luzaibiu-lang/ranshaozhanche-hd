extends Control
## Shop frame 4 and native nine-cell, paged vehicle selector.
signal vehicle_selected(id: int)
const OriginalSkin = preload("res://original_skin.gd")
var catalog: Dictionary = {}
var selected := 0
var page_index := 0
var layout: Control
var shortcuts: Control
var buttons: Array[Button] = []
var caption: Label
var stats: Label
var preview: TextureRect
var ability: TextureRect
var selection: TextureRect
var left: Button
var right: Button
var logical_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout = Control.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var background := TextureRect.new()
	background.texture = preload("res://assets/icons/Shop/04.png")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(background)
	# AbilityInfo contains the native ring and grey backing; its 93px
	# patch matches Shop/04 at (34,17), including every grey edge pixel.
	ability = _picture(Vector2(34, 17), Vector2(93, 93))
	preview = _picture(Vector2(152, 23), Vector2(83, 35))
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	caption = _label(Vector2(147, 0), Vector2(90, 20), 11)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats = _label(Vector2(152, 62), Vector2(85, 62), 10)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shortcuts = Control.new()
	shortcuts.name = "VehicleShortcuts"
	# Native screenshot pixel matches place a 37px frame at x=50,117,184.
	shortcuts.position = Vector2(38, 141)
	shortcuts.size = Vector2(199, 132)
	layout.add_child(shortcuts)
	for index in range(9):
		var button := Button.new()
		button.name = "VehicleCell%d" % index
		button.position = Vector2((index % 3) * 67, (index / 3) * 46)
		button.size = Vector2(61, 40)
		# TotUnit269 frames are 37x34 with a shared center pivot. The native
		# selector centers that whole frame; Button's default left alignment
		# and expanding it to 43px shifted and enlarged every vehicle.
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 37)
		for state in ["normal", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.1, 0.7, 1, 0.2)
		button.add_theme_stylebox_override("hover", hover)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func(): vehicle_selected.emit(page_index * 9 + index))
		shortcuts.add_child(button)
		buttons.append(button)
	selection = _picture(Vector2.ZERO, Vector2(61, 44))
	selection.texture = preload("res://assets/icons/Shop/05.png")
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	selection.material = additive
	left = _arrow("gl_larrow", Vector2(22, 274), -1)
	right = _arrow("gl_rarrow", Vector2(224, 274), 1)
	resized.connect(_reflow)
	_reflow()
	_refresh()

func _picture(at: Vector2, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.position = at
	image.size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(image)
	return image

func _label(at: Vector2, dimensions: Vector2, points: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", Color("171717"))
	label.clip_text = true
	layout.add_child(label)
	return label

func _arrow(asset: String, at: Vector2, direction: int) -> Button:
	var button := Button.new()
	button.name = "VehiclePrevious" if direction < 0 else "VehicleNext"
	button.position = at
	button.size = Vector2(20, 20)
	button.tooltip_text = "上一页战车" if direction < 0 else "下一页战车"
	for pair in [["normal", 0], ["hover", 1], ["pressed", 2], ["disabled", 3]]:
		button.add_theme_stylebox_override(pair[0], OriginalSkin.sprite_style(asset, int(pair[1])))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func():
		page_index = posmod(page_index + direction, 4)
		_refresh()
	)
	layout.add_child(button)
	return button

func set_selected(id: int) -> void:
	if id != selected:
		selected = id
		page_index = clampi(id / 9, 0, 3)
	if is_instance_valid(layout):_refresh()

func _refresh() -> void:
	for index in range(9):
		var id := page_index * 9 + index
		var button := buttons[index]
		button.visible = id <= 30
		if id > 30:continue
		button.icon = load("res://assets/effects/TotUnit269/%02d.png" % id)
		button.tooltip_text = "随机战车" if id == 0 else str(catalog.vehicles[id - 1].name)
	var frame := 0 if selected == 0 else (selected - 1) % 10
	ability.texture = load("res://assets/icons/AbilityInfo/%02d.png" % frame)
	preview.texture = load("res://assets/effects/TotUnit269/%02d.png" % selected)
	caption.text = "随机" if selected == 0 else str(catalog.vehicles[selected - 1].name)
	stats.text = ""
	if selected > 0:
		var vehicle: Dictionary = catalog.vehicles[selected - 1]
		stats.tooltip_text = "防御系数 %.2f\n移动燃料 %.3f / 像素\n武器燃料 %d / %d / %d" % [float(vehicle.armor), float(vehicle.move_cost), int(vehicle.weapons[0].cost), int(vehicle.weapons[1].cost), int(vehicle.weapons[2].cost)]
	var cell := selected - page_index * 9
	selection.visible = cell >= 0 and cell < 9
	if selection.visible:selection.position = shortcuts.position + Vector2((cell % 3) * 67, (cell / 3) * 46) - Vector2(1, 2)

func _reflow() -> void:
	logical_scale = minf(size.x / 249, size.y / 296)
	layout.scale = Vector2.ONE * logical_scale
	layout.position = (size - Vector2(249, 296) * logical_scale) / 2
