extends Control

const Platform = preload("res://game_platform.gd")

signal weapon_selected(index: int)
signal item_selected(slot: int)
signal fire_started
signal fire_released
signal fire_canceled

const KEYS := ["left", "up", "down", "right", "weapon0", "weapon1", "weapon2", "item0", "item1", "item2", "item3", "fire"]
const CAPTIONS := ["◀", "▲", "▼", "▶", "F1", "F2", "F3", "1", "2", "3", "4", "发射"]
var keys := {}
var claimed := {}
var buttons_enabled := false
var inventory := []
var selected := 0
var blocked: Callable
var chat_anchor := Vector2.ZERO
var browser_cancel: JavaScriptObject
var browser_canvas: JavaScriptObject

static func touch_device() -> bool:
	return Platform.mobile_ui()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in KEYS.size():
		var key: String = KEYS[i]
		var box := Panel.new()
		box.name = key
		# Block the emulated mouse click on the same touch, including its release.
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(box)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("22323ddc")
		style.border_color = Color("a4bcce")
		style.set_border_width_all(2)
		box.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = CAPTIONS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		keys[key] = {"box":box, "style":style, "label":label, "icon":icon}
	resized.connect(_layout)
	if OS.has_feature("web"):
		# Godot 4.5.1 Web maps touchcancel to touchend. Cancel charge before the engine sees a release.
		browser_canvas = JavaScriptBridge.get_interface("document").getElementById("canvas")
		if browser_canvas:
			browser_cancel = JavaScriptBridge.create_callback(_on_browser_cancel)
			browser_canvas.addEventListener("touchcancel", browser_cancel, true)
	_layout()

func _on_browser_cancel(_arguments: Array) -> void:
	reset_touches()

func _exit_tree() -> void:
	if browser_canvas and browser_cancel:
		browser_canvas.removeEventListener("touchcancel", browser_cancel, true)
	browser_canvas = null
	browser_cancel = null

func _layout() -> void:
	reset_touches()
	var u := minf(size.x, size.y) / 390.0
	var hud := clampf(minf(size.x / 800, size.y / 600), 0.8, 3.0)
	var side := 44.0 * u
	var step := side + 3.0 * u
	var pad := 9.0 * u
	var base := size.y - 90.0 * hud - side - 3.0 * u
	var item_x := size.x - pad - 3 * step - side
	var left := Vector2(pad, base)
	for i in 4:
		var offset: Vector2 = [Vector2(0, 0), Vector2(1, -1), Vector2(1, 0), Vector2(2, 0)][i]
		_place(KEYS[i], Rect2(left + offset * step, Vector2.ONE * side), u)
		_place("item%d" % i, Rect2(Vector2(item_x + step*i, base-step), Vector2.ONE * side), u)
	for i in 3:
		_place("weapon%d" % i, Rect2(left + Vector2(step*i, -2*step), Vector2.ONE * side), u)
	var diameter := 1.45 * side
	# Right-align the firing circle with the inventory row, leaving the native menu accessible.
	_place("fire", Rect2(Vector2(size.x - pad - diameter, base+side+2*u-diameter*.76), Vector2.ONE * diameter), u)
	chat_anchor = Vector2(pad + 3 * step, base - 43 * hud)
	if chat_anchor.x + 223 * hud > item_x:
		chat_anchor = Vector2(pad, base - 2 * step - 90 * hud)

func _place(key: String, rect: Rect2, u: float) -> void:
	var entry: Dictionary = keys[key]
	var box: Panel = entry.box
	box.position = rect.position.round()
	box.size = rect.size.round()
	var style: StyleBoxFlat = entry.style
	style.set_corner_radius_all(roundi(box.size.x / 2) if key == "fire" else maxi(2, roundi(5*u)))
	var label: Label = entry.label
	label.add_theme_font_size_override("font_size", maxi(10, roundi((18 if key == "fire" else 15)*u)))
	var icon: TextureRect = entry.icon
	icon.position = Vector2(2,2)
	icon.size = box.size-Vector2(4,4)

func set_inventory(values: Array) -> void:
	if inventory == values:return
	inventory = values.duplicate()
	for i in 4:
		var entry: Dictionary = keys["item%d" % i]
		var id := int(inventory[i]) if i < inventory.size() else 0
		entry.icon.texture = load("res://assets/icons/ItemIcon/%02d.png" % id) if id > 0 else null
		entry.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if id > 0 else HORIZONTAL_ALIGNMENT_CENTER
		entry.label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if id > 0 else VERTICAL_ALIGNMENT_CENTER
		entry.label.z_index=1
		entry.label.add_theme_color_override("font_outline_color",Color.BLACK)
		entry.label.add_theme_constant_override("outline_size",3)
	_paint()

func set_actions(enabled: bool, weapon: int) -> void:
	if enabled == buttons_enabled and weapon == selected:return
	buttons_enabled = enabled
	selected = weapon
	if not enabled:reset_touches()
	_paint()

func _enabled(key: String) -> bool:
	if not buttons_enabled:return false
	if key.begins_with("item"):
		var slot := key.right(1).to_int()
		return slot < inventory.size() and int(inventory[slot]) > 0
	return true

func _paint() -> void:
	for key: String in keys:
		var entry: Dictionary = keys[key]
		var style: StyleBoxFlat = entry.style
		var down := key in claimed.values()
		style.border_color = Color("ffce70") if down or key == "weapon%d" % selected else Color("99afc1")
		style.bg_color = Color("704820ed") if down else Color("73452fdd") if key == "fire" else Color("203441dc")
		entry.box.modulate.a = 1.0 if _enabled(key) else .61

func direction(positive: String, negative: String) -> int:
	var held := claimed.values()
	return int(positive in held) - int(negative in held)

func reset_touches() -> void:
	if claimed.is_empty():return
	var had_fire := "fire" in claimed.values()
	claimed.clear()
	if had_fire:fire_canceled.emit()
	_paint()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():return
	if event is InputEventScreenDrag:
		if claimed.has(event.index):
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventScreenTouch:return
	if not event.pressed or event.canceled:
		if not claimed.has(event.index):return
		var key: String = claimed[event.index]
		claimed.erase(event.index)
		get_viewport().set_input_as_handled()
		_paint()
		if key == "fire":
			if event.canceled or (blocked.is_valid() and blocked.call()):fire_canceled.emit()
			else:fire_released.emit()
		return
	if blocked.is_valid() and blocked.call():return
	var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	for key: String in keys:
		var box: Panel = keys[key].box
		if not box.get_rect().has_point(at):continue
		get_viewport().set_input_as_handled()
		if not _enabled(key) or key in claimed.values():
			claimed[event.index] = ""
			return
		claimed[event.index] = key
		_paint()
		if key == "fire":fire_started.emit()
		elif key.begins_with("weapon"):weapon_selected.emit(key.right(1).to_int())
		elif key.begins_with("item"):item_selected.emit(key.right(1).to_int())
		return
