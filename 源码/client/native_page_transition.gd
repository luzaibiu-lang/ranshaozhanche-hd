extends "res://native_channel_gate.gd"
## Shared original metal door between lobby and room; no channel controls.

signal covered

func _ready() -> void:
	opaque_backdrop = false
	super._ready()
	name = "NativePageTransition"
	add_to_group("native_modal")
	for item in placements:
		item.node.hide()

func _door_closed() -> void:
	_change_phase("covered")
	covered.emit()

func begin_open() -> void:
	if phase != "covered": return
	_change_phase("opening")
	_cue(10)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey: accept_event()

func _draw() -> void:
	super._draw()
	if not is_instance_valid(left): return
	# Page changes use plain native metal where the chooser has its buttons.
	_patch(Rect2(0, 585, SPLIT, 15), Rect2(0, 535 + extra.y, SPLIT + left_extra, 65), true)
