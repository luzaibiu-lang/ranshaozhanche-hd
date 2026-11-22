extends Button
## The original backdrop already supplies the circular switch and label.
func _ready() -> void:
	toggle_mode=true
	for state in ["normal","hover","pressed","focus"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
	toggled.connect(func(_value):queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func _draw() -> void:
	if button_pressed:draw_circle(size/2,minf(size.x,size.y)*.23,Color("ffd35c"))
	if is_hovered():draw_arc(size/2,minf(size.x,size.y)*.4,0,TAU,24,Color.WHITE,1,true)
