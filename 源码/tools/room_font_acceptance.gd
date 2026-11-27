extends SceneTree

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()

func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(900, 720)
	var dialog = load("res://native_room_form.gd").new()
	dialog.room_name = "验证玩家的战场"
	dialog.pixel_scale = 1.5
	dialog.size = Vector2i(468, 467)
	root.add_child(dialog)
	dialog.popup_centered()
	await process_frame
	var expected: Font = dialog.canvas.theme.default_font
	var fields: Array = dialog.canvas.find_children("*", "LineEdit", false, false)
	fields.append_array([dialog.public_field, dialog.capacity_field, dialog.public_field.get_popup(), dialog.capacity_field.get_popup()])
	for field in fields:
		var font: Font = field.get_theme_font("font")
		if font != expected:
			push_error("Wrong font for %s" % field.name)
			quit(2)
			return
		for letter in "验证玩家的战场是否全部":
			if not font.has_char(letter.unicode_at(0)):
				push_error("Missing glyph in %s: %s" % [field.name, letter])
				quit(2)
				return
	var folder := OS.get_cmdline_user_args()[0]
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("room-form.png"))
	dialog.public_field.show_popup()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("room-menu.png"))
	print("ROOM_FONT_OK ", fields.size(), " controls checked")
	quit()
