extends Control
## UserBox + TotUnit + PlayState, using the native card composition.
var member: Dictionary = {}
var owner_id := 0
var elapsed := 0.0
var images := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if int(member.get("id", 0)) == owner_id:
		elapsed += delta
		queue_redraw()

func image(group: String, frame: int) -> Texture2D:
	var path := "res://assets/icons/%s/%02d.png" % [group, frame]
	if not images.has(path):images[path] = load(path)
	return images[path]

func _draw() -> void:
	if member.is_empty():return
	var s := minf(size.x / 120, size.y / 60)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * s)
	var width := size.x / s
	var height := size.y / s
	var card := image("UserBox", int(member.seat) / 4)
	# Keep the original rounded ends and stretch only the solid middle.
	# A wide room slot must not retain a short 120-pixel card on its left.
	draw_texture_rect_region(card, Rect2(0, 0, 12, height), Rect2(0, 0, 12, 60))
	draw_texture_rect_region(card, Rect2(12, 0, width-54, height), Rect2(12, 0, 66, 60))
	draw_texture_rect_region(card, Rect2(width-42, 0, 42, height), Rect2(78, 0, 42, 60))
	var id := int(member.vehicle)
	var path := "res://assets/effects/TotUnit269/%02d.png" % id
	if not images.has(path):images[path] = load(path)
	draw_texture(images[path], Vector2(width-42, 18))
	var state := 1 if bool(member.ready) or int(member.ai) > 0 else 0
	draw_texture(image("PlayState", state), Vector2(9, 31))
	var name_color := Color("ffb28f") if int(member.seat) / 4 == 0 else Color("fff3aa")
	draw_string(get_theme_default_font(), Vector2(22, 14), str(member.name), HORIZONTAL_ALIGNMENT_LEFT, width-27, 10, name_color)
	if int(member.get("id", 0)) == owner_id:
		draw_texture(image("RMaster", int(elapsed * 12) % 8), Vector2(-4, -4))
	draw_set_transform(Vector2.ZERO)
