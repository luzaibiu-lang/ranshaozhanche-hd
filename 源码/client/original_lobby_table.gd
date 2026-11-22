extends Control
## Native ListView surface measured from the original running lobby.
var headings: Array = []
var column_widths: Array = []
var grow_column := 0
var logical_height := 277.0
var grid_lines := false
const BODY := Color(245.0/255,245.0/255,1)
const HEADER := Color(210.0/255,210.0/255,1)
const GRID := Color(240.0/255,240.0/255,240.0/255)

static func spans(widths: Array, available: float, scale_factor: float, grow: int) -> Array:
	var result := []
	var total := 0.0
	for width in widths:
		result.append(float(width)*scale_factor)
		total += float(width)*scale_factor
	if not result.is_empty():result[clampi(grow,0,result.size()-1)] += available-total
	return result

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := size.y/logical_height
	var edge := maxf(1,s)
	var header_height := 18*s
	draw_rect(Rect2(Vector2.ZERO,size),BODY)
	draw_line(Vector2.ZERO,Vector2(size.x,0),Color("808080"),edge)
	draw_line(Vector2.ZERO,Vector2(0,size.y),Color("808080"),edge)
	draw_line(Vector2(0,size.y-edge),Vector2(size.x,size.y-edge),Color.WHITE,edge)
	draw_line(Vector2(size.x-edge,0),Vector2(size.x-edge,size.y),Color.WHITE,edge)
	var widths := spans(column_widths,size.x-2*edge,s,grow_column)
	var x := edge
	for index in range(widths.size()):
		var width: float = widths[index]
		draw_rect(Rect2(x,edge,width,header_height),HEADER)
		draw_line(Vector2(x,edge),Vector2(x+width,edge),Color.WHITE,edge)
		draw_line(Vector2(x,edge),Vector2(x,edge+header_height),Color.WHITE,edge)
		draw_line(Vector2(x+width-edge,edge),Vector2(x+width-edge,edge+header_height),Color("808080"),edge)
		draw_line(Vector2(x,edge+header_height-edge),Vector2(x+width,edge+header_height-edge),Color("808080"),edge)
		if index < headings.size():
			draw_string(get_theme_default_font(),Vector2(x+4*s,edge+14*s),str(headings[index]),HORIZONTAL_ALIGNMENT_LEFT,width-7*s,maxi(10,roundi(12*s)),Color.BLACK)
		x += width
		if grid_lines and index < widths.size()-1:draw_line(Vector2(x,header_height+edge),Vector2(x,size.y-edge),GRID,edge)
	if grid_lines:
		var y := header_height+edge+17*s
		while y < size.y-edge:
			draw_line(Vector2(edge,y),Vector2(size.x-edge,y),GRID,edge)
			y += 17*s
