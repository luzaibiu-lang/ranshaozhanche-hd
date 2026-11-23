extends Control
## Native combat item shop: three categories, four cells per category, backpack.
signal buy_requested(item: int, slot: int)
signal sell_requested(slot: int)
const CATEGORIES := [[1, 2, 3, 14], [5, 6, 7, 8, 11], [4, 9, 10, 12, 13, 15, 16, 17]]
var catalog: Dictionary = {}
var profile: Dictionary = {}
var selected_item := 1
var selected_slot := -1
var pages := [0, 0, 0]
var item_buttons := {}
var backpack: Array[Button] = []
var backpack_icons: Array[TextureRect] = []
var information: Label
var balance: Label
var price_label: Label
var sell_price: Label
var layout: Control
var buy_button: Button
var sell_button: Button
var left_art: Texture2D = preload("res://assets/icons/Shop/08.png")
var right_art: Texture2D = preload("res://assets/icons/Shop/09.png")
var selection_art: Texture2D = preload("res://assets/icons/Shop/03.png")
var selection: TextureRect
var logical_width := 800.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout = Control.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	layout.draw.connect(_draw_art)
	# This native frame has a black center. Its original additive blend
	# keeps the category color visible instead of painting a black card.
	selection = TextureRect.new()
	selection.texture = selection_art
	selection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var highlight := CanvasItemMaterial.new()
	highlight.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	selection.material = highlight
	layout.add_child(selection)
	for category in range(3):
		for id in CATEGORIES[category]:
			var button := Button.new()
			button.name = "ShopItem%02d" % id
			button.icon = load("res://assets/icons/ItemIcon/%02d.png" % id)
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_constant_override("icon_max_width", 29)
			button.add_theme_font_size_override("font_size", 10)
			button.text = str(_item(id).get("name", "")) + "\n%d G" % int(_item(id).get("price", 0))
			button.tooltip_text = str(_item(id).get("description", ""))
			_flat(button)
			button.pressed.connect(_select_item.bind(id))
			button.gui_input.connect(_on_item_input.bind(id))
			layout.add_child(button)
			item_buttons[id] = button
		for direction in [-1, 1]:
			var arrow := Button.new()
			arrow.name = "ShopPage%d%s" % [category, "Left" if direction < 0 else "Right"]
			arrow.position = Vector2(32 if direction < 0 else 484, 47 + category * 75)
			arrow.size = Vector2(30, 44)
			_flat(arrow)
			arrow.pressed.connect(func():
				pages[category] = posmod(int(pages[category]) + direction, maxi(1, CATEGORIES[category].size() - 3))
				_refresh()
			)
			layout.add_child(arrow)
	information = Label.new()
	information.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information.add_theme_font_size_override("font_size", 11)
	information.add_theme_color_override("font_color", Color.WHITE)
	information.size = Vector2(121, 157)
	layout.add_child(information)
	for index in range(4):
		var button := Button.new()
		button.name = "InventorySlot%d" % index
		button.size = Vector2(38, 38)
		# Shop/09 frames contain a 31px icon inset five pixels from this
		# hit target. Button icon alignment/padding cannot express that inset.
		var icon := TextureRect.new()
		icon.name = "InventoryIcon"
		icon.position = Vector2(5, 5)
		icon.size = Vector2(31, 31)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		backpack_icons.append(icon)
		_flat(button)
		button.pressed.connect(func(): selected_slot = index; _refresh())
		layout.add_child(button)
		backpack.append(button)
	buy_button = _art_button("ShopBuyBtn", Vector2(271, 267), _buy_selected)
	buy_button.name = "BuyItem"
	sell_button = _art_button("ShopSellBtn", Vector2(588, 266), func(): sell_requested.emit(selected_slot))
	sell_button.name = "SellItem"
	balance = _number_label()
	price_label = _number_label()
	sell_price = _number_label()
	resized.connect(_reflow)
	_reflow()
	_refresh()

func _select_item(id: int) -> void:
	selected_item = id
	_refresh()

func _on_item_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		item_buttons[id].accept_event()
		_select_item(id)
		_buy_selected()

func _buy_selected() -> void:
	var inventory: Array = profile.get("inventory", [0, 0, 0, 0])
	var slot := selected_slot
	if slot < 0 or int(inventory[slot]) != 0:
		slot = -1
		for index in range(inventory.size()):
			if int(inventory[index]) == 0:
				slot = index
				break
	buy_requested.emit(selected_item, slot)

func _flat(button: Button) -> void:
	for state in ["normal", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.13)
	button.add_theme_stylebox_override("hover", hover)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color.WHITE)

func _art_button(name: String, at: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.position = at
	button.size = Vector2(59, 30)
	button.pressed.connect(action)
	for pair in [["normal", 0], ["hover", 1], ["pressed", 2], ["disabled", 0]]:
		var style := StyleBoxTexture.new()
		style.texture = load("res://assets/icons/%s/%02d.png" % [name, int(pair[1])])
		button.add_theme_stylebox_override(pair[0], style)
	layout.add_child(button)
	return button

func _number_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size = Vector2(111, 22)
	layout.add_child(label)
	return label

func _item(id: int) -> Dictionary:
	for item: Dictionary in catalog.get("items", []):
		if int(item.id) == id:return item
	return {}

func set_profile(value: Dictionary) -> void:
	profile = value
	if is_instance_valid(layout):_refresh()

func _refresh() -> void:
	var extra := logical_width - 800
	selection.visible = false
	for category in range(3):
		for index in range(CATEGORIES[category].size()):
			var id: int = CATEGORIES[category][index]
			var button: Button = item_buttons[id]
			var column := index - int(pages[category])
			button.visible = column >= 0 and column < 4
			button.position = Vector2(70 + column * (103 + extra / 4), 47 + category * 75)
			button.size = Vector2(100 + extra / 4, 44)
		var right := layout.get_node("ShopPage%dRight" % category) as Button
		right.position.x = 484 + extra
		var index: int = CATEGORIES[category].find(selected_item)
		var column := index - int(pages[category])
		if index >= 0 and column >= 0 and column < 4:
			selection.position = Vector2(70 + column * (103 + extra / 4), 47 + category * 75)
			selection.size = Vector2(100 + extra / 4, 46)
			selection.visible = true
	information.position = Vector2(578 + extra, 48)
	var item := _item(selected_item)
	information.text = "%s\n\n%s" % [str(item.get("name", "")), str(item.get("description", ""))]
	var inventory: Array = profile.get("inventory", [0, 0, 0, 0])
	for index in range(4):
		var id := int(inventory[index])
		backpack[index].position = Vector2(589 + extra + index * 51, 206)
		backpack_icons[index].texture = load("res://assets/icons/ItemIcon/%02d.png" % id) if id > 0 else null
		backpack[index].tooltip_text = str(_item(id).get("name", "空槽"))
		backpack[index].modulate = Color("ffe68c") if selected_slot == index else Color.WHITE
	buy_button.position.x = 271 + extra
	sell_button.position = Vector2(581 + extra, 263)
	sell_button.disabled = selected_slot < 0 or int(inventory[selected_slot]) == 0
	balance.position = Vector2(341 + extra, 272)
	balance.text = str(int(item.get("price", 0)))
	price_label.position = Vector2(358 + extra, 249)
	price_label.text = ""
	sell_price.position = Vector2(658 + extra, 273)
	sell_price.text = str(int(profile.get("gold", 0)))
	layout.queue_redraw()

func _reflow() -> void:
	var s := size.y / 307.0
	if s <= 0:return
	layout.scale = Vector2.ONE * s
	logical_width = maxf(800, size.x / s)
	_refresh()

func _draw_art() -> void:
	var extra := logical_width - 800
	# Preserve the original arrow buttons and end caps while widening cells.
	layout.draw_texture_rect_region(left_art, Rect2(0, 0, 70, 267), Rect2(0, 0, 70, 267))
	layout.draw_texture_rect_region(left_art, Rect2(70, 0, 408 + extra, 267), Rect2(70, 0, 408, 267))
	layout.draw_texture_rect_region(left_art, Rect2(478 + extra, 0, 90, 267), Rect2(478, 0, 90, 267))
	layout.draw_texture_rect_region(left_art, Rect2(0, 267, 271 + extra, 40), Rect2(0, 267, 271, 40))
	layout.draw_texture_rect_region(left_art, Rect2(271 + extra, 267, 297, 40), Rect2(271, 267, 297, 40))
	layout.draw_texture(right_art, Vector2(551 + extra, 11))
