extends Control
## Original Shop.spr player panel. Extend only its lane spans for wide screens.
var artwork: Texture2D = preload("res://assets/icons/Shop/01.png")
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var s := size.y / 307.0
	var left := 48.0 * s
	var right := 30.0 * s
	draw_texture_rect_region(artwork, Rect2(0, 0, left, size.y), Rect2(0, 0, 48, 307))
	draw_texture_rect_region(artwork, Rect2(left, 0, maxf(0, size.x - left - right), size.y), Rect2(48, 0, 490, 307))
	draw_texture_rect_region(artwork, Rect2(size.x - right, 0, right, size.y), Rect2(538, 0, 30, 307))
