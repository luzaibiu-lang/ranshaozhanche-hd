extends Control
## Native ResultBox: blue animated panel, four metal corners, Chinese outcome.
signal return_requested
var battle: Dictionary = {}
var player_id := 0
var elapsed := 0.0
var panel: Control
var art := {}
var return_button: Button
var panel_height := 360.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group("native_modal")
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in range(8):
		art[i] = load("res://assets/icons/ResultBox/%02d.png" % i)
	panel = Control.new()
	panel.draw.connect(_draw_panel)
	add_child(panel)
	var result: Dictionary = battle.result
	var reward: Dictionary = result.get("rewards", {})
	var y := 55.0
	for team in range(4):
		var members: Array = battle.get("units", []).filter(func(u): return int(u.team) == team)
		if members.is_empty():
			continue
		var group := Label.new()
		group.text = "%s 组" % char(65 + team)
		group.position = Vector2(50, y)
		group.add_theme_font_size_override("font_size", 12)
		group.add_theme_color_override("font_color", Color("80ff7b") if team == int(result.team) else Color("f4dc7a"))
		panel.add_child(group)
		y += 20
		for unit: Dictionary in members:
			var row := Label.new()
			row.position = Vector2(60, y)
			row.text = str(unit.name)
			row.size = Vector2(175, 20)
			row.add_theme_font_size_override("font_size", 12)
			row.add_theme_color_override("font_color", Color.WHITE)
			row.clip_text = true
			panel.add_child(row)
			var gold := Label.new()
			gold.position = Vector2(240, y)
			gold.add_theme_font_size_override("font_size", 12)
			gold.add_theme_color_override("font_color", Color.WHITE)
			gold.text = "+%d G" % int(reward.get(str(int(unit.player)), 0)) if int(unit.player) > 0 else "AI"
			panel.add_child(gold)
			y += 18
	return_button = Button.new()
	return_button.name = "ReturnToRoom"
	panel_height = maxf(360,y+62)
	return_button.position = Vector2(163, panel_height-42)
	return_button.size = Vector2(74, 28)
	return_button.tooltip_text = "返回房间"
	for pair in [["normal", 0], ["hover", 1], ["pressed", 2]]:
		var style := StyleBoxTexture.new()
		style.texture = load("res://assets/icons/ResultCloseBtn/%02d.png" % int(pair[1]))
		return_button.add_theme_stylebox_override(pair[0], style)
	return_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return_button.pressed.connect(func(): return_requested.emit())
	panel.add_child(return_button)
	resized.connect(_reflow)
	_reflow()

func _reflow() -> void:
	var s := minf(minf(size.x / 800, size.y / 600), (size.y-32)/panel_height)
	panel.scale = Vector2.ONE * s
	panel.position = (size - Vector2(400, panel_height) * s) / 2

func _process(delta: float) -> void:
	elapsed += delta
	panel.modulate.a = minf(1, elapsed / 0.35)
	panel.queue_redraw()

func _draw_panel() -> void:
	panel.draw_rect(Rect2(0, 0, 400, panel_height), Color(0, 50.0 / 255, 150.0 / 255, 0.7))
	panel.draw_texture_rect(art[0], Rect2(0, 0, 400, 7), false)
	panel.draw_texture_rect(art[0], Rect2(0, panel_height-7, 400, 7), false)
	panel.draw_set_transform(Vector2(7, 0), PI / 2)
	panel.draw_texture_rect(art[0], Rect2(0, 0, panel_height, 7), false)
	panel.draw_set_transform(Vector2(400, 0), PI / 2)
	panel.draw_texture_rect(art[0], Rect2(0, 0, panel_height, 7), false)
	panel.draw_set_transform(Vector2.ZERO)
	for part in [[1, Vector2(-2, -2)], [2, Vector2(370, -2)], [3, Vector2(-2, panel_height-30)], [4, Vector2(370, panel_height-30)]]:
		panel.draw_texture(art[part[0]], part[1])
	var own_team := -1
	for unit: Dictionary in battle.get("units", []):
		if int(unit.player) == player_id:
			own_team = int(unit.team)
	var winner := int(battle.result.team)
	var frame := 7 if winner < 0 else 5 if winner == own_team else 6
	panel.draw_texture(art[frame], Vector2(136, 10))
