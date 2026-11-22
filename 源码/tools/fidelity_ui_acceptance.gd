extends SceneTree
## Exercise actual form/buttons/input inside one isolated native game process.
var app: Node
var options := {}
var checks := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	OS.set_environment("LOCALAPPDATA", str(options.profile))
	OS.set_environment("BCHD_VAULT_ROOT", str(options.profile).path_join("vault"))
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		print("FIDELITY_UI_STATE " + JSON.stringify({"scene": app.scene, "toast": app.toast_label.text, "profile": app.profile, "busy": app.command_busy}))
		root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
		push_error("FIDELITY_UI: " + message)
		quit(2)
		return false
	checks.append(message)
	return true

func click(control: Control, double_click := false) -> void:
	if not check(is_instance_valid(control), "click target exists"):return
	var position := control.get_global_rect().get_center()
	var window := control.get_viewport() as Window
	if window != root:position += Vector2(window.position)
	for index in range(2 if double_click else 1):
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.double_click = index == 1 and pressed
			root.push_input(event)
			await process_frame
	await create_timer(0.12).timeout

func wait_for(condition: Callable, message: String) -> bool:
	for attempt in range(100):
		if condition.call():return check(true, message)
		await create_timer(0.1).timeout
	return check(false, message)

func button(hint: String) -> Button:
	for child in app.skin.get_children():
		if child is Button and child.tooltip_text == hint:return child
	return null

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name + ".png"))

func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(0.5).timeout
	app = bootstrap.get_child(0)
	if not await wait_for(func(): return not app.catalog.is_empty(), "normal startup loaded catalog"):return
	if options.get("nonbattle", "false")=="true":DisplayServer.window_set_size(Vector2i(1440,900))
	await click(app.skin.find_child("ToggleRegistration", true, false))
	app.username.text = str(options.name)
	app.password.text = "qa-only-895432"
	app.confirmation.text = "qa-only-895432"
	await click(app.skin.find_child("Login", true, false))
	if not await wait_for(func(): return app.scene == "lobby", "actual registration form reached lobby"):return
	var avatar:Control=app.skin.get_node("NativeAvatar")
	var avatar_frame:int=avatar.frame_stamp
	await create_timer(0.25).timeout
	if not check(avatar.layers.size()==8 and avatar.frame_stamp!=avatar_frame,"original profile avatar layers render and animate without native DLLs"):return
	await click(button("游戏物品"))
	var game_items:Window=app.get_node("NativeGameItems")
	if not check(game_items.visible and game_items.tabs.get_tab_count()==3,"original Game Item opens its own three-tab native window"):return
	game_items.tabs.current_tab=2
	await create_timer(.2).timeout
	var item_shop:Control=game_items.shop
	var dialog_gold := int(app.profile.gold)
	var dialog_cues: int = app.sound.played_cues.count("coin.wav")
	await click(item_shop.item_buttons[1], true)
	if not await wait_for(func():return int(app.profile.inventory[0])==1,"double-click buys through Game Item window"):return
	var attack_price := int(item_shop._item(1).price)
	if not check(int(app.profile.gold) == dialog_gold - attack_price, "Game Item double-click spends the price once"):return
	if not check(app.sound.played_cues.count("coin.wav") == dialog_cues + 1, "Game Item double-click plays original coin sound once"):return
	game_items.tabs.current_tab=1
	await process_frame
	if not check(game_items.inventory.get_child_count()==4 and game_items.inventory.get_child(0).get_child(2).text.contains("攻击装置"),"My Items displays the actual equipped native item"):return
	game_items.tabs.current_tab=2
	await process_frame
	await click(item_shop.backpack[0])
	await click(item_shop.sell_button)
	if not await wait_for(func():return int(app.profile.inventory[0])==0,"Game Item sale clears the same authoritative slot"):return
	await screenshot("game-items-native")
	game_items.close_requested.emit()
	await process_frame
	if not check(not app._modal_open(),"Game Item close releases native modal input"):return
	await click(button("道具商店"))
	if not await wait_for(func(): return app.scene == "shop", "native combat shop opened"):return
	var shop: Control = app.native_shop
	if options.get("nonbattle", "false")=="true":
		var seen := {}
		for page in range(5):
			for id: int in shop.item_buttons:
				var item: Button = shop.item_buttons[id]
				if item.visible:
					await click(item)
					if not check(shop.information.text.contains(item.text.get_slice("\n",0)), "native item description matches selected item "+str(id)):return
					seen[id]=true
			for category in range(3):await click(shop.layout.get_node("ShopPage%dRight"%category))
		if not check(seen.size()==17,"all seventeen native items are reachable through actual paging"):return
		await click(shop.item_buttons[2])
		var neutral := InputEventMouseMotion.new()
		neutral.position = Vector2(20,540)
		root.push_input(neutral)
		await RenderingServer.frame_post_draw
		var sample := Vector2i(shop.item_buttons[1].get_global_rect().end-Vector2(18,18))
		var unselected := root.get_texture().get_image().get_pixelv(sample)
		await click(shop.item_buttons[1])
		root.push_input(neutral)
		await RenderingServer.frame_post_draw
		var highlighted := root.get_texture().get_image().get_pixelv(sample)
		if not check(unselected.r>.3 and highlighted.r>=unselected.r*.8,"shop selection preserves native category color instead of blacking out its center"):return
	for i in range(4):await click(shop.layout.get_node("ShopPage2Right"))
	if not check(shop.item_buttons[17].visible, "special-item paging reaches item 17"):return
	await click(shop.item_buttons[17])
	var starting_gold := int(app.profile.gold)
	if not check(int(app.profile.inventory[0]) == 0, "single click only selects the product"):return
	var purchase_cues: int = app.sound.played_cues.count("coin.wav")
	await click(shop.buy_button)
	if not await wait_for(func(): return int(app.profile.inventory[0]) == 17, "real shop purchase populated backpack"):return
	if not check(app.sound.played_cues.count("coin.wav") == purchase_cues + 1, "buy button plays original coin sound once"):return
	if not check(app.skin.get_node("ProfileGold").text.contains(str(int(app.profile.gold))), "visible account balance updates immediately after purchase"):return
	await click(shop.backpack[0])
	var sale_cues: int = app.sound.played_cues.count("coin.wav")
	await click(shop.sell_button)
	if not await wait_for(func(): return int(app.profile.inventory[0]) == 0, "real shop sale cleared backpack"):return
	if not check(app.sound.played_cues.count("coin.wav") == sale_cues + 1, "sell button plays original coin sound once"):return
	if not check(int(app.profile.gold) == starting_gold - 900, "purchase and half-price sale changed balance exactly"):return
	for i in range(4):
		var previous_gold := int(app.profile.gold)
		await click(shop.item_buttons[1], true)
		if not await wait_for(func(): return int(app.profile.inventory[i]) == 1, "purchase fills actual slot " + str(i)):return
		if not check(int(app.profile.gold) == previous_gold - attack_price, "each double-click deducts exactly one purchase"):return
	var full_gold := int(app.profile.gold)
	await click(shop.item_buttons[1], true)
	if not check(int(app.profile.gold) == full_gold and app.toast_label.text.contains("已满"), "full backpack rejects purchase without charging"):return
	await screenshot("shop-actual-interaction")
	if not await app._command({"action": "sell", "slot": 0}):
		check(false, "prepare an empty slot for the insufficient gold scenario")
		return
	var double_shot_price := int(shop._item(14).price)
	while int(app.profile.gold) >= double_shot_price:
		if not await app._command({"action": "buy", "slot": 0, "item": 14}) or not await app._command({"action": "sell", "slot": 0}):
			check(false, "prepare insufficient gold through real shop transactions")
			return
	var low_gold := int(app.profile.gold)
	await click(shop.item_buttons[14], true)
	if not await wait_for(func(): return not app.command_busy and app.toast_label.text.contains("金币不足"), "double-click with insufficient gold reports the server error"):return
	if not check(int(app.profile.gold) == low_gold and int(app.profile.inventory[0]) == 0, "insufficient gold leaves balance and backpack unchanged"):return
	await click(button("返回"))
	await click(button("创建房间"))
	var create: ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:create = child
	await screenshot("create-room-native")
	if not check(create.get_ok_button().size.x>=76*create.pixel_scale and create.get_ok_button().size.y>=32*create.pixel_scale,"original create-room buttons retain their full artwork dimensions"):return
	await click(create.get_ok_button())
	if not await wait_for(func(): return app.scene == "room", "room created through actual dialog"):return
	var picker: Control = app.vehicle_picker
	if options.get("nonbattle", "false")=="true":
		for id in range(31):
			while int(picker.page_index)!=id/9:
				await click(picker.right)
			await click(picker.buttons[id%9])
			if not await wait_for(func():return int(app._me().vehicle)==id,"all native vehicles selectable: "+str(id)):return
		await screenshot("vehicle-all-thirty")
		for id in range(20):
			if not await wait_for(func():return not app.command_busy,"previous map request completed"):return
			app.map_choice.select(app.map_choice.get_item_index(id))
			app.map_choice.item_selected.emit(app.map_choice.get_item_index(id))
			if not await wait_for(func():return int(app.snapshot.room.map)==id,"room map synchronizes: "+str(id)):return
			await process_frame
			var visible_preview:TextureRect
			for child in app.room_preview.get_children():
				if child is TextureRect and child.visible:visible_preview=child
			if not check(visible_preview!=null and visible_preview.texture.resource_path.ends_with("/%02d.png"%id),"correct original map thumbnail: "+str(id)):return
		await screenshot("map-19-original-thumbnail")
		await click(app.skin.get_node("NextRoomMap"))
		if not await wait_for(func():return int(app.snapshot.room.map)==0,"native next-map arrow wraps final map to random"):return
		await click(app.skin.get_node("PreviousRoomMap"))
		if not await wait_for(func():return int(app.snapshot.room.map)==19,"native previous-map arrow restores final original map"):return
		await click(picker.left)
		await click(picker.buttons[0])
		await wait_for(func():return int(app._me().vehicle)==18,"vehicle page restored for reference test")
		while int(picker.page_index)!=0:await click(picker.right)
	for page in range(3):await click(picker.right)
	await click(picker.buttons[3])
	if not await wait_for(func(): return int(app._me().vehicle) == 30, "paged native selector reaches vehicle 30"):return
	if not check(picker.caption.text == "绿金刚", "native vehicle name and selection synchronize"):return
	await screenshot("vehicle-30-selection")
	for page in range(3):await click(picker.left)
	await click(picker.buttons[0])
	if not await wait_for(func(): return int(app._me().vehicle) == 0, "native random-vehicle cell selects random"):return
	await click(picker.buttons[1])
	if not await wait_for(func(): return int(app._me().vehicle) == 1, "native selection restores first vehicle"):return
	app.map_choice.select(app.map_choice.get_item_index(17))
	app.map_choice.item_selected.emit(app.map_choice.get_item_index(17))
	if not await wait_for(func(): return int(app.snapshot.room.map) == 17, "PNG map preview synchronized through room settings"):return
	app.map_choice.select(app.map_choice.get_item_index(1))
	app.map_choice.item_selected.emit(app.map_choice.get_item_index(1))
	if not await wait_for(func(): return int(app.snapshot.room.map) == 1, "room map selection returned to reference bridge"):return
	await click(button("道具商店"))
	if not await wait_for(func(): return app.scene == "shop", "shop opens inside actual room"):return
	if not check(app.start_button.is_visible_in_tree() and app.map_choice.is_visible_in_tree(), "room shop retains start control and map selection"):return
	await screenshot("shop-inside-room")
	await click(button("返回"))
	if not await wait_for(func(): return app.scene == "room" and app.vehicle_picker.is_visible_in_tree(), "room shop returns to native vehicle selector"):return
	var practice_button:Button=app.skin.find_child("AIPractice",true,false)
	if not check(practice_button.get_theme_stylebox("normal") is StyleBoxTexture,"AI Practice uses the same native metal artwork as game buttons"):return
	await click(practice_button)
	var robots: ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:robots = child
	await screenshot("ai-native-dialog")
	if not check(robots.get_ok_button().size.x>=77 and robots.get_ok_button().size.y>=33,"native AI confirm/cancel buttons render at full size"):return
	var difficulty := app.find_child("AIDifficulty04", true, false) as OptionButton
	difficulty.select(2)
	difficulty.item_selected.emit(2)
	await click(robots.get_ok_button())
	if not await wait_for(func(): return app.snapshot.room.members.size() == 2, "native AI configuration assigned separate seat"):return
	await screenshot("room-actual-interaction")
	if options.get("nonbattle", "false")=="true":
		app.chat_input.text="房间输入同步测试 native-room-chat"
		app.chat_input.grab_focus()
		var enter:=InputEventKey.new()
		enter.keycode=KEY_ENTER
		enter.physical_keycode=KEY_ENTER
		enter.pressed=true
		root.push_input(enter)
		if not await wait_for(func():return app.chat_label.text.contains("native-room-chat"),"actual Enter sends room chat and clears entry"):return
		if not check(app.chat_input.text.is_empty(),"chat input cleared after successful submission"):return
		await screenshot("room-chat")
		await click(button("返回大厅"))
		if not await wait_for(func():return app.scene=="lobby","native room exit returns to lobby"):return
		await screenshot("lobby-returned")
		print("FIDELITY_UI_ACCEPTANCE "+JSON.stringify({"checks":checks,"normal_ui":true,"private_input_only":true,"nonbattle":true}))
		await app._quit()
		return
	await click(app.start_button)
	if not await wait_for(func(): return app.scene == "battle", "actual start button entered battle"):return
	if not check(bool(app._battle_data().get("native_aim", false)), "native aim protocol negotiated"):return
	if not check(app.view.scenery.records.size()>0, "original bridge scenery is animated in real battle"):return
	app.sound.play_effect("fire", 2)
	app.sound.play_effect("explosion", 2)
	app.sound.play_effect("move", 2)
	if not check(app.sound.played_cues.has("shot07.wav") and app.sound.played_cues.has("exp02.wav") and app.sound.played_cues.has("move02.wav"), "native weapon and vehicle cues actually play through muted WASAPI"):return
	var weather_before: Vector2 = app.view.scenery.records[0].at
	await create_timer(0.12).timeout
	if not check(not (app.view.scenery.records[0].at as Vector2).is_equal_approx(weather_before), "native scenery moves across rendered frames"):return
	var own: Dictionary = app.battle_hud.own_unit()
	var elevation := app.aim as float
	var up:=InputEventKey.new()
	up.physical_keycode=KEY_UP
	up.pressed=true
	Input.parse_input_event(up)
	await create_timer(.25).timeout
	up.pressed=false
	Input.parse_input_event(up)
	await process_frame
	if not check(app.aim>elevation+2 and absf(app.view.angle-app.aim)<1,"actual Up key changes the tank reticle and readable angle together"):return
	await screenshot("battle-reticle-aim")
	elevation=app.aim
	var left := InputEventKey.new()
	left.physical_keycode = KEY_LEFT
	left.pressed = true
	Input.parse_input_event(left)
	await create_timer(0.6).timeout
	left.pressed = false
	Input.parse_input_event(left)
	if not await wait_for(func(): return int(app.battle_hud.own_unit().face) == -1, "actual left input changes facing"):return
	if not check(is_equal_approx(app.aim, elevation), "movement preserved native elevation"):return
	if not await wait_for(func(): return not app.command_busy and app._my_turn(), "human input remains available before firing"):return
	var fire_key := InputEventKey.new()
	fire_key.keycode = KEY_SPACE
	fire_key.physical_keycode = KEY_SPACE
	fire_key.pressed = true
	root.push_input(fire_key)
	await create_timer(0.8).timeout
	if not check(app.charging and app.charge>0.3, "actual space key accumulates visible shot power"):return
	fire_key.pressed = false
	root.push_input(fire_key)
	if not await wait_for(func(): return app._battle_data().get("shot") is Dictionary and int(app._battle_data().shot.actor)==int(own.seat), "actual space release submits authoritative human shot"):return
	if not check(not app.charging and app._battle_data().shot.trails.size()>0, "shot animates without stuck charging state"):return
	await screenshot("battle-human-shot")
	await click(app.hud_buttons.menu)
	var menu: Control = app.content.get_node("NativeMenu")
	await click(menu.panel.get_node("effects_off"))
	if not check(app.sound.effects_volume == 0, "native menu effects-off control works"):return
	await click(menu.panel.get_node("zoom_lock_on"))
	if not check(app.view.zoom_locked, "native menu zoom lock works"):return
	await screenshot("menu-actual-interaction")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await process_frame
	if not check(not app._modal_open(), "escape closed only the native menu"):return
	await screenshot("battle-actual-interaction")
	print("FIDELITY_UI_ACCEPTANCE " + JSON.stringify({"checks": checks, "normal_ui": true, "private_input_only": true}))
	await app._quit()
