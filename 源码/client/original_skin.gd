extends Control
## Native controls laid out against original artwork; the viewport renders at
## the physical window size. There is no 800x600 framebuffer or mouse hook.

const BASE := Vector2(800, 600)
signal click_sound
var design_size := Vector2(800, 600)
var page := "lobby"
var placements: Array[Dictionary] = []
var pixel_scale := 1.0
var origin := Vector2.ZERO
var extra := Vector2.ZERO
var backdrop: Texture2D
var backdrop_name := ""
static var metal_styles:Dictionary={}
static var blue_styles:Dictionary={}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(reflow)
	call_deferred("reflow")

func reflow() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	pixel_scale = minf(size.x / design_size.x, size.y / design_size.y)
	extra = size / pixel_scale - design_size
	origin = Vector2.ZERO
	if page == "login":
		origin = (size - design_size * pixel_scale) / 2
	for entry in placements:
		var node: Control = entry.node
		if not is_instance_valid(node):
			continue
		var rect: Rect2 = responsive_rect(entry.rect)
		node.position = origin + rect.position * pixel_scale
		node.size = rect.size * pixel_scale
		if int(entry.font) > 0:
			node.add_theme_font_size_override("font_size", maxi(9, int(float(entry.font) * pixel_scale)))
	queue_redraw()

func responsive_rect(value: Rect2) -> Rect2:
	var rect := value
	if page == "login":
		return rect
	if page == "shop":
		rect.position += extra / 2
		return rect
	if page == "battle":
		if rect.position == Vector2.ZERO and rect.size.x == 800:
			rect.size += extra
		elif rect.position.y >= 463:
			rect.position.y += extra.y
			if rect.size.x == 800:
				rect.size.x += extra.x
			elif rect.position.x >= 650:
				rect.position.x += extra.x
		elif rect.position.x >= 630:
			rect.position.x += extra.x
		elif rect.position.x >= 200 and rect.position.y < 60:
			rect.position.x += extra.x / 2
		return rect
	# Original right-hand player/map column keeps its width and moves to the
	# right edge. The room list and chat grow into the additional space.
	if page == "room" and rect.position == Vector2(0, 62) and rect.size.x == 568:
		rect.size.x += extra.x
		return rect
	if rect.position.x == 0 and rect.size.x == 800 and rect.position.y >= 60 and rect.position.y < 370:
		rect.size.x += extra.x
		return rect
	if rect.position.x >= 550:
		rect.position.x += extra.x
		if rect.position.y>=370:
			rect.position.y+=extra.y
			return rect
	elif rect.end.x >= 500 and rect.position.y >= 75:
		rect.size.x += extra.x
	if rect.position.y >= 370:
		if rect.position.y >= 570:
			rect.position.y += extra.y
		elif rect.size.y >= 100:
			rect.size.y += extra.y
		else:
			rect.position.y += extra.y
	return rect

func _piece(destination: Rect2, source: Rect2) -> void:
	draw_texture_rect_region(backdrop, Rect2(destination.position * pixel_scale, destination.size * pixel_scale), source)

func _draw() -> void:
	if not backdrop or page == "login":
		return
	var width := 800.0 + extra.x
	# The original buttons, logos, frame ends and right column keep their
	# aspect. Only the original metal/blue/grey panel spans are extended.
	_piece(Rect2(0,0,555,75), Rect2(0,0,555,75))
	_piece(Rect2(555,0,extra.x + 41,75), Rect2(555,0,41,75))
	_piece(Rect2(596+extra.x,0,204,75), Rect2(596,0,204,75))
	if backdrop_name == "GameBack":
		_piece(Rect2(0,75,width,295), Rect2(5,75,20,295))
		_piece(Rect2((width-460)/2,128,460,185), Rect2(160,128,460,185))
	else:
		_piece(Rect2(0,75,10,295), Rect2(0,75,10,295))
		_piece(Rect2(10,75,520+extra.x,295), Rect2(10,75,520,295))
		_piece(Rect2(530+extra.x,75,25,295), Rect2(530,75,25,295))
		_piece(Rect2(555+extra.x,75,245,295), Rect2(555,75,245,295))
	for row in [[370.0,33.0,0.0],[403.0,165.0,extra.y],[568.0,32.0,0.0]]:
		var y: float = row[0]
		var height: float = row[1]
		var grow: float = row[2]
		var shift := extra.y if y >= 568 else 0.0
		_piece(Rect2(0,y+shift,150,height+grow), Rect2(0,y,150,height))
		_piece(Rect2(150,y+shift,350+extra.x,height+grow), Rect2(150,y,350,height))
		_piece(Rect2(500+extra.x,y+shift,55,height+grow), Rect2(500,y,55,height))
	_piece(Rect2(width-245,370+extra.y,245,230), Rect2(555,370,245,230))
	if extra.y > 0:
		_piece(Rect2(width-245,370,245,extra.y), Rect2(555,350,245,20))

func place(node: Control, rect: Rect2, font_size := 0) -> Control:
	add_child(node)
	placements.append({"node": node, "rect": rect, "font": font_size})
	reflow()
	return node

func picture(path: String, rect: Rect2, centered := false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load("res://assets/" + path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if centered else TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(node, rect)
	return node

func background(name: String) -> void:
	backdrop_name = name
	backdrop = load("res://assets/legacy/" + name + ".png")
	queue_redraw()

func label(text: String, rect: Rect2, font_size := 12, color := Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.clip_text = true
	node.add_theme_color_override("font_color", color)
	place(node, rect, font_size)
	return node

func entry(rect: Rect2, secret := false) -> LineEdit:
	var node := LineEdit.new()
	node.secret = secret
	node.add_theme_stylebox_override("normal", box(Color("606060"), Color("424242")))
	node.add_theme_stylebox_override("focus", box(Color("606060"), Color("e5e5e5")))
	node.add_theme_color_override("font_color", Color.WHITE)
	place(node, rect, 12)
	return node

static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = border
	value.set_border_width_all(1)
	value.content_margin_left = 3
	value.content_margin_right = 3
	return value

static func sprite_style(path: String, state: int, states := 0) -> StyleBoxTexture:
	var texture: Texture2D = load("res://assets/legacy/" + path + ".png")
	if states == 0:
		states = 3 if texture.get_height() % 3 == 0 and texture.get_height() % 4 != 0 else 4
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(0, texture.get_height() / states * mini(state, states - 1), texture.get_width(), texture.get_height() / states)
	var value := StyleBoxTexture.new()
	value.texture = atlas
	return value

func button(path: String, rect: Rect2, action: Callable, hint := "") -> Button:
	var node := Button.new()
	node.tooltip_text = hint
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	node.pressed.connect(func(): click_sound.emit())
	for pair in [["normal", 0], ["hover", 1], ["pressed", 2], ["disabled", 3]]:
		node.add_theme_stylebox_override(pair[0], sprite_style(path, pair[1]))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	place(node, rect)
	return node

func text_button(text: String, rect: Rect2, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	node.pressed.connect(func(): click_sound.emit())
	for pair in [["normal",0],["hover",1],["pressed",2],["disabled",2]]:
		node.add_theme_stylebox_override(pair[0],metal_style(int(pair[1])))
	node.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	node.add_theme_color_override("font_color", Color.BLACK)
	node.add_theme_color_override("font_hover_color", Color.BLACK)
	node.add_theme_color_override("font_pressed_color", Color.BLACK)
	node.add_theme_color_override("font_outline_color",Color("f5f5fa"))
	node.add_theme_constant_override("outline_size",1)
	place(node, rect, 12)
	return node

func blue_button(text: String, rect: Rect2, action: Callable) -> Button:
	var node := text_button(text, rect, action)
	for pair in [["normal", 0], ["hover", 1], ["pressed", 2], ["disabled", 3]]:
		node.add_theme_stylebox_override(pair[0], blue_style(int(pair[1])))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(state, Color("082740"))
	node.add_theme_color_override("font_disabled_color", Color("3d4756"))
	for entry in placements:
		if entry.node == node:entry.font = 14
	reflow()
	return node

static func blue_style(state: int) -> StyleBoxTexture:
	if blue_styles.has(state):return blue_styles[state]
	var image: Image = load("res://assets/legacy/gl_start.png").get_image()
	if image.is_compressed():image.decompress()
	var height := image.get_height()/4
	var frame := image.get_region(Rect2i(0, mini(state, 3)*height, image.get_width(), height))
	# Retain the native Start button's metal rim and blue gradient; replace
	# its baked-in caption so AI Practice is a clear, source-matched action.
	for y in range(5, height-5):
		for x in range(14, frame.get_width()-14):frame.set_pixel(x, y, frame.get_pixel(11, y))
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(frame)
	style.texture_margin_left = 9
	style.texture_margin_right = 9
	style.texture_margin_top = 5
	style.texture_margin_bottom = 5
	style.content_margin_left = 10
	style.content_margin_right = 10
	blue_styles[state] = style
	return style

static func metal_style(state:int) -> StyleBoxTexture:
	if metal_styles.has(state):return metal_styles[state]
	var value:=sprite_style("pop_ok",mini(state,2),3)
	# Keep only the original metal perimeter; generated text uses a clean
	# middle strip, not the baked-in Chinese '确定' glyphs.
	var image:Image=load("res://assets/legacy/pop_ok.png").get_image()
	if image.is_compressed():image.decompress()
	var height:=image.get_height()/3
	var frame:=image.get_region(Rect2i(0,mini(state,2)*height,image.get_width(),height))
	for y in range(5,height-5):
		for x in range(12,frame.get_width()-12):frame.set_pixel(x,y,frame.get_pixel(8,y))
	value.texture=ImageTexture.create_from_image(frame)
	value.texture_margin_left=10
	value.texture_margin_right=10
	value.texture_margin_top=5
	value.texture_margin_bottom=5
	value.content_margin_left=10
	value.content_margin_right=10
	metal_styles[state]=value
	return value
