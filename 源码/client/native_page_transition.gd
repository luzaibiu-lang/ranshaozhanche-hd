extends Control

signal covered
signal opened
signal cue_requested(id: int)

const DOOR_ART := preload("res://assets/legacy/GameBack.png")
const CLOSE_TIME := 0.75
const LATCH_TIME := 0.28
const OPEN_TIME := 0.8
const SOURCE_X := [0.0, 150.0, 650.0, 800.0]
const SOURCE_Y := [72.0, 120.0, 220.0, 320.0, 369.0]

var phase := "closing"
var phase_history: Array[String] = ["closing"]
var cue_events: Array[int] = []
var elapsed := 0.0
var closed := 0.0
var top_leaf: Control
var bottom_leaf: Control
var logo_rect := Rect2()

func _ready() -> void:
	name = "NativePageTransition"
	add_to_group("native_modal")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	top_leaf = _make_leaf("TopLeaf", true)
	bottom_leaf = _make_leaf("BottomLeaf", false)
	resized.connect(_layout)
	_layout()
	_cue.call_deferred(11)

func _make_leaf(leaf_name: String, upper: bool) -> Control:
	var leaf := Control.new()
	leaf.name = leaf_name
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(leaf)
	leaf.draw.connect(_draw_leaf.bind(leaf, upper))
	return leaf

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0: return
	var factor := minf(size.x / 800.0, size.y / 600.0)
	var logo_size := Vector2(500, 200) * factor
	logo_rect = Rect2((size - logo_size) * 0.5, logo_size)
	top_leaf.size = Vector2(size.x, size.y * 0.5)
	bottom_leaf.size = top_leaf.size
	_position_leaves()
	top_leaf.queue_redraw()
	bottom_leaf.queue_redraw()

func _position_leaves() -> void:
	top_leaf.position.y = -(1.0 - closed) * top_leaf.size.y
	bottom_leaf.position.y = size.y - closed * bottom_leaf.size.y

func _draw_leaf(leaf: Control, upper: bool) -> void:
	# Preserve the original logo's proportions. Stretch only the surrounding metal.
	var xs := [0.0, logo_rect.position.x, logo_rect.end.x, size.x]
	var ys := [0.0, logo_rect.position.y, size.y * 0.5, logo_rect.end.y, size.y]
	var first_row := 0 if upper else 2
	var origin_y: float = ys[first_row]
	for row in range(first_row, first_row + 2):
		for column in range(3):
			var source := Rect2(SOURCE_X[column], SOURCE_Y[row],
				SOURCE_X[column + 1] - SOURCE_X[column], SOURCE_Y[row + 1] - SOURCE_Y[row])
			var dest := Rect2(xs[column], ys[row] - origin_y,
				xs[column + 1] - xs[column], ys[row + 1] - ys[row])
			leaf.draw_texture_rect_region(DOOR_ART, dest, source)

func _process(delta: float) -> void:
	elapsed += delta
	match phase:
		"closing":
			closed = smoothstep(0.0, CLOSE_TIME, elapsed)
			_position_leaves()
			if elapsed >= CLOSE_TIME:
				_change_phase("latch")
				_cue(12)
		"latch":
			if elapsed >= LATCH_TIME:
				_change_phase("covered")
				covered.emit()
		"opening":
			closed = 1.0 - smoothstep(0.0, OPEN_TIME, elapsed)
			_position_leaves()
			if elapsed >= OPEN_TIME:
				_change_phase("finished")
				opened.emit()

func begin_open() -> void:
	if phase == "covered":
		_change_phase("opening")
		_cue(10)

func _change_phase(value: String) -> void:
	phase = value
	elapsed = 0.0
	phase_history.append(value)

func _cue(id: int) -> void:
	cue_events.append(id)
	cue_requested.emit(id)

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey:
		if event.keycode == KEY_F11: return
		get_viewport().set_input_as_handled()
