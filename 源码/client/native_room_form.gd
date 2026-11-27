extends ConfirmationDialog
## Original croomback layout. Controls render at the physical window size.
var room_name := ""
var capacity := 8
var public_field: OptionButton
var password_field: LineEdit
var pixel_scale := 1.0
var name_field: LineEdit
var capacity_field: OptionButton
var canvas: Control

func _ready() -> void:
	borderless=true
	unresizable=true
	exclusive=true
	add_theme_constant_override("buttons_min_width",int(77*pixel_scale))
	add_theme_constant_override("buttons_min_height",int(33*pixel_scale))
	title="创建房间"
	var image:Image=load("res://assets/legacy/croomback.png").get_image()
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c:=image.get_pixel(x,y)
			if c.r>.95 and c.b>.95 and c.g<.05:image.set_pixel(x,y,Color.TRANSPARENT)
	# The original button artwork is supplied by live native button controls.
	for y in range(263,301):
		for x in range(40,270):image.set_pixel(x,y,image.get_pixel(25,y))
	var frame:=StyleBoxTexture.new()
	frame.texture=ImageTexture.create_from_image(image)
	frame.content_margin_left=20*pixel_scale
	frame.content_margin_right=20*pixel_scale
	frame.content_margin_top=40*pixel_scale
	frame.content_margin_bottom=12*pixel_scale
	add_theme_stylebox_override("panel",frame)
	add_theme_stylebox_override("embedded_border",StyleBoxEmpty.new())
	add_theme_stylebox_override("embedded_unfocused_border",StyleBoxEmpty.new())
	var layer:=Node2D.new()
	add_child(layer)
	canvas=Control.new()
	# The Node2D layout layer breaks Control theme inheritance.
	canvas.theme = Theme.new()
	canvas.theme.default_font = preload("res://game_platform.gd").ui_font()
	layer.add_child(canvas)
	canvas.size=Vector2(size)
	name_field=_entry(room_name,Rect2(88,82,199,24))
	name_field.name="RoomName"
	name_field.max_length=24
	public_field=OptionButton.new()
	public_field.name="RoomPublic"
	canvas.add_child(public_field)
	_place(public_field,Rect2(88,115,73,22))
	public_field.add_item("是",0)
	public_field.add_item("否",1)
	password_field=_entry("",Rect2(228,115,58,22))
	password_field.name="RoomPassword"
	password_field.max_length=16
	password_field.editable=false
	password_field.secret=true
	public_field.item_selected.connect(func(index):
		password_field.editable=index==1
		if index==0:password_field.text=""
		else:password_field.grab_focus()
	)
	_entry("全部",Rect2(88,147,73,22)).editable=false
	_entry("全部",Rect2(88,180,73,22)).editable=false
	capacity_field=OptionButton.new()
	capacity_field.name="RoomCapacity"
	canvas.add_child(capacity_field)
	_place(capacity_field,Rect2(228,147,58,22))
	for value in range(2,9):capacity_field.add_item(str(value),value)
	capacity_field.select(capacity_field.get_item_index(capacity))
	var blue:=preload("res://original_skin.gd").box(Color("006cc7"),Color("0054a9"))
	for state in ["normal","hover","pressed","focus"]:capacity_field.add_theme_stylebox_override(state,blue)
	for state in ["normal","hover","pressed","focus"]:public_field.add_theme_stylebox_override(state,blue)
	public_field.add_theme_color_override("font_color",Color.WHITE)
	capacity_field.add_theme_color_override("font_color",Color.WHITE)
	for button:Button in [get_ok_button(),get_cancel_button()]:
		var path:="pop_ok" if button==get_ok_button() else "pop_cancel"
		button.text=" "
		button.custom_minimum_size=Vector2(77,33)*pixel_scale
		for pair in [["normal",0],["hover",1],["pressed",2]]:
			button.add_theme_stylebox_override(pair[0],preload("res://original_skin.gd").sprite_style(path,int(pair[1]),3))
		button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	get_ok_button().get_parent().add_theme_constant_override("separation",int(20*pixel_scale))
	confirmed.connect(func():room_name=name_field.text;capacity=capacity_field.get_selected_id())
	name_field.text_submitted.connect(func(_value):get_ok_button().pressed.emit())
	name_field.grab_focus()

func _place(node:Control,rect:Rect2) -> void:
	node.position=rect.position*pixel_scale
	node.size=rect.size*pixel_scale
	node.add_theme_font_size_override("font_size",maxi(12,int(12*pixel_scale)))
	if node is OptionButton:
		node.get_popup().theme = canvas.theme

func _entry(text:String,rect:Rect2) -> LineEdit:
	var node:=LineEdit.new()
	canvas.add_child(node)
	node.text=text
	_place(node,rect)
	node.add_theme_color_override("font_color",Color.WHITE)
	node.add_theme_color_override("font_uneditable_color",Color.WHITE)
	for key in ["normal","read_only"]:node.add_theme_stylebox_override(key,StyleBoxEmpty.new())
	node.add_theme_stylebox_override("focus",preload("res://original_skin.gd").box(Color("006cc7"),Color("87bff2")))
	return node
