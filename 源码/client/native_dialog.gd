extends ConfirmationDialog
## Native frame is the window panel itself: AcceptDialog owns content layout.
var caption := ""

func _ready() -> void:
	borderless=true
	unresizable=true
	exclusive=true
	add_theme_constant_override("buttons_min_width",77)
	add_theme_constant_override("buttons_min_height",33)
	var image: Image=load("res://assets/legacy/cchangeback.png").get_image()
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c:=image.get_pixel(x,y)
			if c.r>.95 and c.b>.95 and c.g<.05:image.set_pixel(x,y,Color.TRANSPARENT)
	image.fill_rect(Rect2i(65,22,210,19),Color("dc8945"))
	var frame:=StyleBoxTexture.new()
	frame.texture=ImageTexture.create_from_image(image)
	frame.texture_margin_left=20
	frame.texture_margin_right=20
	frame.texture_margin_top=48
	frame.texture_margin_bottom=35
	frame.content_margin_left=24
	frame.content_margin_right=24
	frame.content_margin_top=55
	frame.content_margin_bottom=55
	add_theme_stylebox_override("panel",frame)
	add_theme_stylebox_override("embedded_border",StyleBoxEmpty.new())
	add_theme_stylebox_override("embedded_unfocused_border",StyleBoxEmpty.new())
	var heading:=Node2D.new()
	add_child(heading)
	heading.draw.connect(func():
		var font:=get_theme_default_font()
		heading.draw_string_outline(font,Vector2(20,38),caption,HORIZONTAL_ALIGNMENT_CENTER,size.x-40,18,3,Color.WHITE)
		heading.draw_string(font,Vector2(20,38),caption,HORIZONTAL_ALIGNMENT_CENTER,size.x-40,18,Color("252525"))
	)
	size_changed.connect(func():heading.queue_redraw())
	for button:Button in [get_ok_button(),get_cancel_button()]:
		var path:="pop_ok" if button==get_ok_button() else "pop_cancel"
		button.text=" "
		button.custom_minimum_size=Vector2(77,33)
		for pair in [["normal",0],["hover",1],["pressed",2],["disabled",2]]:
			button.add_theme_stylebox_override(pair[0],preload("res://original_skin.gd").sprite_style(path,int(pair[1]),3))
		button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
