extends Button
## Actual native ListView columns, shared with the restored pale headers.
const Table = preload("res://original_lobby_table.gd")
var column_weights: Array = []
var columns: Array[Label] = []
var pixel_scale := 1.0
var grow_column := 0
var leading_icon: TextureRect

func configure(values: Array, weights: Array, scale_factor: float, grow := 0) -> void:
	column_weights=weights
	pixel_scale=scale_factor
	grow_column=grow
	custom_minimum_size.y=17*pixel_scale
	text=""
	add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	var hover:=StyleBoxFlat.new()
	hover.bg_color=Color("e8e8f6")
	add_theme_stylebox_override("hover",hover)
	var selected:=StyleBoxFlat.new()
	selected.bg_color=Color("000080")
	for state in ["pressed","hover_pressed"]:add_theme_stylebox_override(state,selected)
	add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	for value in values:
		var label:=Label.new()
		label.text=str(value)
		label.clip_text=true
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",maxi(10,int(12*pixel_scale)))
		label.add_theme_color_override("font_color",Color.BLACK)
		add_child(label)
		columns.append(label)
	resized.connect(_layout)
	_layout.call_deferred()
	toggled.connect(func(_value):_text_color(button_pressed))
	button_down.connect(func():_text_color(true))
	button_up.connect(func():_text_color(button_pressed))
	_text_color(button_pressed)

func _ready() -> void:
	_text_color(button_pressed)

func set_leading_icon(texture: Texture2D) -> void:
	leading_icon=TextureRect.new()
	leading_icon.texture=texture
	leading_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	leading_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	leading_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(leading_icon)
	_layout.call_deferred()

func _text_color(selected: bool) -> void:
	for column in columns:column.add_theme_color_override("font_color",Color.WHITE if selected else Color.BLACK)

func _layout() -> void:
	var widths:=Table.spans(column_weights,size.x,pixel_scale,grow_column)
	var x:=0.0
	for i in range(columns.size()):
		var width:float=widths[i]
		var inset:=19*pixel_scale if i==0 and is_instance_valid(leading_icon) else 2*pixel_scale
		columns[i].position=Vector2(x+inset,0)
		columns[i].size=Vector2(maxf(0,width-inset-2*pixel_scale),size.y)
		x+=width
	if is_instance_valid(leading_icon):
		leading_icon.position=Vector2(pixel_scale,0)
		leading_icon.size=Vector2(17,17)*pixel_scale
