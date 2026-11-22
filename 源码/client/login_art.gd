extends Control
## Exact vector illustration from the existing launcher (Launcher.cs OnPaint).

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var factor := size / Vector2(345, 510)
	draw_rect(Rect2(Vector2.ZERO, size), Color("18212b"))
	draw_line(Vector2(25,338)*factor, Vector2(320,338)*factor, Color("2c3945"), factor.x)
	var hull := PackedVector2Array()
	for point in [Vector2(78,244),Vector2(101,221),Vector2(240,221),Vector2(270,245),Vector2(250,271),Vector2(94,271)]:
		hull.append(point * factor)
	draw_colored_polygon(hull, Color("f6ae3f"))
	var turret := PackedVector2Array()
	for point in [Vector2(124,213),Vector2(143,178),Vector2(202,178),Vector2(221,213)]:
		turret.append(point * factor)
	draw_colored_polygon(turret, Color("f6ae3f"))
	draw_line(Vector2(196,185)*factor, Vector2(260,146)*factor, Color("f6ae3f"), 13*factor.x, true)
	for i in range(5):
		draw_arc(Vector2(109+i*31,249)*factor, 10*factor.x, 0, TAU, 30, Color("18212b"), 10*factor.x, true)
