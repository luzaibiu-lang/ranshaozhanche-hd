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

func click(control: Control) -> void:
	if not check(is_instance_valid(control), "click target exists"):return
	var position := control.get_global_rect().get_center()
	var window := control.get_viewport() as Window
	if window != root:position += Vector2(window.position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
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

func type_search(value:String) -> void:
	await click(app.skin.get_node("LobbyPlayerSearch"))
	for character in value:
		var key:=InputEventKey.new()
		key.keycode=character.to_upper().unicode_at(0)
		key.unicode=character.unicode_at(0)
		key.pressed=true
		root.push_input(key)
		await process_frame

func clear_search() -> void:
	await click(app.skin.get_node("LobbyPlayerSearch"))
	var select:=InputEventKey.new()
	select.keycode=KEY_A
	select.ctrl_pressed=true
	select.pressed=true
	root.push_input(select)
	await process_frame
	var key:=InputEventKey.new()
	key.keycode=KEY_BACKSPACE
	key.pressed=true
	root.push_input(key)
	await process_frame

func lobby_visual_checks() -> bool:
	for dimensions in [Vector2i(960,600),Vector2i(1440,900)]:
		DisplayServer.window_set_size(dimensions)
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		for table_name in ["OriginalRoomTable","OriginalPlayerTable"]:
			var table:Control=app.skin.get_node(table_name)
			var area:=table.get_global_rect()
			var body:=image.get_pixelv(Vector2i(area.position+Vector2(area.size.x*.5,area.size.y-10)))
			if not check(body.r>.93 and body.g>.93 and body.b>.97,"original pale ListView body at "+str(dimensions)+" "+table_name):return false
			var header:=image.get_pixelv(Vector2i(area.position+Vector2(8,4)))
			if not check(absf(header.r-210.0/255)<.035 and absf(header.b-1)<.035,"original lavender header at "+str(dimensions)+" "+table_name):return false
		var player_row:Control
		for row in app.player_list.get_children():
			if row.visible:player_row=row;break
		if not check(player_row!=null and player_row.columns[0].get_theme_color("font_color")==Color.BLACK,"online player names use readable native black text"):return false
		if not check(is_equal_approx(player_row.pixel_scale,app.skin.pixel_scale) and player_row.size.y<=18*app.skin.pixel_scale,"lobby rows reflow text and height after resizing to "+str(dimensions)):return false
		var rooms:Control=app.skin.get_node("OriginalRoomTable")
		if not check(rooms.headings==["No","道具","模式","地图","标题","房主","人员","密室","状态", ""],"room header names match original running client"):return false
		await screenshot("lobby-native-%dx%d"%[dimensions.x,dimensions.y])
	return true

func _run() -> void:
	var bootstrap:Node=load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(0.5).timeout
	app=bootstrap.get_child(0)
	if not await wait_for(func():return not app.catalog.is_empty(),"catalog loaded"):return
	await click(app.skin.find_child("ToggleRegistration",true,false))
	app.username.text=str(options.name)
	app.password.text="qa-only-895432"
	app.confirmation.text="qa-only-895432"
	await click(app.skin.find_child("Login",true,false))
	if not await wait_for(func():return is_instance_valid(app.channel_gate) and app.channel_gate.phase=="select","registered player reached channel selection"):return
	await click(app.channel_gate.row)
	await click(app.channel_gate.enter_button)
	if not await wait_for(func():return app.scene=="lobby" and not is_instance_valid(app.channel_gate),"registered player entered lobby"):return
	if options.has("return-test"):
		await check_return_flow()
		return
	var owner:=preload("res://net.gd").new(app)
	owner.endpoint=app.net.endpoint
	owner.token=app.net.token
	var guest:=preload("res://net.gd").new(app)
	guest.endpoint=app.net.endpoint
	var response:Dictionary=await guest.request("/api/register",{"name":str(options.name)+"b","password":"qa-only-895432"})
	if not check(response.has("token"),"secondary test account registered"):return
	guest.token=str(response.token)
	var guest_id:=int(response.profile.id)
	await guest.request("/api/state")
	await app._poll()
	if not await lobby_visual_checks():return
	await type_search(str(options.name)+"b")
	await click(app.skin.get_node("SearchLobbyPlayer"))
	if not check(app.selected_lobby_player_id==guest_id,"existing magnifier selects the matching online player"):return
	var visible_rows:=[]
	for row in app.player_list.get_children():
		if row.visible:visible_rows.append(row)
	if not check(visible_rows.size()==1 and int(visible_rows[0].get_meta("player_id"))==guest_id,"actual typed search filters the existing online presence list"):return
	await screenshot("lobby-search-result")
	await click(visible_rows[0])
	if not check(app.chat_input.text=="/w "+str(options.name)+"b ","searched player still opens correctly addressed private message"):return
	await clear_search()
	if not check(app.lobby_player_query.is_empty(),"actual Backspace clearing restores all online players"):return
	await type_search("no-match-xyz")
	var enter:=InputEventKey.new()
	enter.keycode=KEY_ENTER
	enter.physical_keycode=KEY_ENTER
	enter.pressed=true
	root.push_input(enter)
	await process_frame
	if not check(app.selected_lobby_player_id==0 and app.toast_label.text.contains("没有找到在线玩家"),"Enter on missing player shows clear result without a request"):return
	await clear_search()
	response=await guest.request("/api/command",{"action":"create","name":"qa-room-"+str(options.name),"capacity":8,"map":1})
	if not check(response.get("room") is Dictionary,"secondary human creates discoverable public room"):return
	var public_room_id:=int(response.room.id)
	await app._poll()
	await process_frame
	var room_row:Button
	for child in app.room_list.get_children():
		if child.tooltip_text=="qa-room-"+str(options.name):room_row=child
	if not check(room_row!=null,"actual lobby table contains public room"):return
	if not check(room_row.columns[0].get_theme_color("font_color")==Color.BLACK,"unselected room uses original black row text"):return
	var native_table:Control=app.skin.get_node("OriginalRoomTable")
	var widths:Array=native_table.spans(native_table.column_widths,room_row.size.x,app.skin.pixel_scale,4)
	var expected_x:=0.0
	for index in range(widths.size()):
		if not check(absf(room_row.columns[index].position.x-expected_x-2*app.skin.pixel_scale)<1.5,"room row text aligns with original header column "+str(index)):return
		expected_x+=float(widths[index])
	await click(room_row)
	await process_frame
	for child in app.room_list.get_children():
		if child.visible and child.tooltip_text=="qa-room-"+str(options.name):room_row=child
	if not check(room_row.button_pressed and room_row.columns[0].get_theme_color("font_color")==Color.WHITE,"actual room selection preserves native navy and white selection text"):return
	await screenshot("lobby-selected-room")
	await click(button("房间信息"))
	var info:ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:info=child
	if not check(info!=null and info.caption=="房间信息","selected lobby room opens original-style information window"):return
	await screenshot("lobby-room-info")
	await click(info.get_cancel_button())
	for child in app.room_list.get_children():
		if child.tooltip_text=="qa-room-"+str(options.name):room_row=child
	var double_click:=InputEventMouseButton.new()
	double_click.position=room_row.get_global_rect().get_center()
	double_click.button_index=MOUSE_BUTTON_LEFT
	double_click.pressed=true
	double_click.double_click=true
	root.push_input(double_click)
	await process_frame
	double_click.pressed=false
	root.push_input(double_click)
	if not await wait_for(func():return app.scene=="room" and int(app.snapshot.room.id)==public_room_id,"actual lobby row double-click joins correct room"):return
	await click(button("返回大厅"))
	if not await wait_for(func():return app.scene=="lobby","native exit returns public-room guest to lobby"):return
	await guest.request("/api/command",{"action":"leave"})
	await app._poll()
	await click(app.skin.get_node("RejectPrivate"))
	if not await wait_for(func():return bool(app.profile.get("reject_private",false)),"original reject-private switch persists through live API"):return
	response=await guest.request("/api/command",{"action":"chat","text":"/w "+str(options.name)+" blocked-private"})
	if not check(response.has("error"),"refused whisper is rejected by server"):return
	await click(app.skin.get_node("RejectPrivate"))
	if not await wait_for(func():return not bool(app.profile.get("reject_private",false)),"private messages can be enabled again"):return
	response=await guest.request("/api/command",{"action":"chat","text":"/w "+str(options.name)+" native-private-message"})
	if not check(not response.has("error"),"enabled private message routes to recipient"):return
	await app._poll()
	if not check(app.chat_label.text.contains("native-private-message") and not JSON.stringify(app.snapshot.chat).contains("native-private-message"),"private message appears only in recipient private chat"):return
	await click(app.skin.get_node("RejectInvites"))
	if not await wait_for(func():return bool(app.profile.get("reject_invites",false)),"original reject-invites switch persists"):return
	await click(app.skin.get_node("RejectInvites"))
	if not await wait_for(func():return not bool(app.profile.get("reject_invites",false)),"invitations can be enabled again"):return
	await click(button("创建房间"))
	var form:ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:form=child
	form.public_field.select(1)
	form.public_field.item_selected.emit(1)
	if not check(form.password_field.editable,"private-room option enables password input"):return
	form.password_field.text="qa-room-123"
	await screenshot("create-private-room")
	await click(form.get_ok_button())
	if not await wait_for(func():return app.scene=="room" and bool(app.snapshot.room.locked),"actual private-room form creates a locked room"):return
	var room_id:=int(app.snapshot.room.id)
	response=await guest.request("/api/command",{"action":"join","room":room_id,"password":"wrong"})
	if not check(response.has("error"),"wrong password rejected by live service"):return
	response=await guest.request("/api/command",{"action":"join","room":room_id,"password":"qa-room-123"})
	if not check(response.get("room") is Dictionary,"correct password joins private room"):return
	await guest.request("/api/command",{"action":"leave"})
	await app._poll()
	await click(button("邀请玩家"))
	var invite:ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:invite=child
	var choice:=invite.find_child("InvitePlayer",true,false) as OptionButton
	if not check(choice!=null and choice.get_item_index(guest_id)>=0,"original invite button opens actual lobby player selector"):return
	choice.select(choice.get_item_index(guest_id))
	await screenshot("invite-player")
	await click(invite.get_ok_button())
	if not await wait_for(func():return not app.command_busy,"invite submitted"):return
	response=await guest.request("/api/state")
	if not check(response.get("invitation") is Dictionary,"recipient receives pending invitation"):return
	app.net.token=guest.token
	app.net.etag=""
	app.snapshot.clear()
	app._accept_state(response)
	await create_timer(0.5).timeout
	var incoming:ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:incoming=child
	if not check(incoming!=null and incoming.caption=="房间邀请","recipient sees actual native invitation window"):return
	await screenshot("incoming-invitation")
	await click(incoming.get_cancel_button())
	if not await wait_for(func():return not app.command_busy,"decline request completed"):return
	response=await guest.request("/api/state")
	if not check(not response.has("invitation") and response.get("room")==null,"cancel declines without joining"):return
	response=await owner.request("/api/command",{"action":"invite","player":guest_id})
	if not check(not response.has("error"),"room owner can invite again after decline"):return
	await app._poll()
	await create_timer(0.5).timeout
	incoming=null
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:incoming=child
	if not check(incoming!=null,"second invitation window opens once"):return
	await click(incoming.get_ok_button())
	if not await wait_for(func():return app.scene=="room" and int(app._me().id)==guest_id,"actual acceptance joins the invited private room"):return
	if not check(int(app.snapshot.room.id)==room_id and bool(app.snapshot.room.locked),"private room identity and lock synchronize for guest"):return
	if not check(app.map_choice.disabled and app.skin.get_node("PreviousRoomMap").disabled and app.skin.get_node("NextRoomMap").disabled,"guest cannot change the room map through dropdown or native arrows"):return
	await screenshot("guest-joined-private-room")
	await app._command({"action":"leave"})
	await owner.request("/api/logout",{})
	print("FIDELITY_UI_ACCEPTANCE "+JSON.stringify({"checks":checks,"normal_ui":true,"private_input_only":true}))
	await app._quit()

func fixture_player(suffix:String):
	var remote:=preload("res://net.gd").new(app)
	remote.endpoint=app.net.endpoint
	var registered:=await remote.request("/api/register", {"name":str(options.name)+suffix, "password":"qa-only-895432"})
	if not check(registered.has("token"),"registered fixture player "+suffix):return null
	remote.token=registered.token
	return remote

func fixture_command(remote, cmd:Dictionary) -> Dictionary:
	var state:Dictionary=await remote.request("/api/command",cmd)
	check(not state.has("error"),"fixture command "+str(cmd.action)+" "+str(state.get("error","")))
	return state

func check_return_flow() -> void:
	var owner=await fixture_player("h")
	var opponent=await fixture_player("o")
	var created:=await fixture_command(owner, {"action":"create","map":1,"capacity":8})
	var room_id:=int(created.room.id)
	await fixture_command(opponent, {"action":"join","room":room_id})
	await app._command({"action":"join","room":room_id})
	if not await wait_for(func():return app.scene=="room" and not is_instance_valid(app.page_transition),"guest entered room"):return
	var bots:=[]
	for index in range(16):
		bots.append({"seat":index,"level":1 if index==2 else 0,"vehicle":1})
	await fixture_command(owner, {"action":"bots","bots":bots})
	await fixture_command(owner, {"action":"start"})
	var first_match:=""
	for match_index in range(2):
		if not await wait_for(func():return app.scene=="battle" and app._battle_data().get("result")==null,"match visible "+str(match_index+1)):return
		var match_id:=str(app._battle_data().id)
		if match_index==0:first_match=match_id
		elif not check(match_id!=first_match,"second match has a distinct ID"):return
		await fixture_command(opponent, {"action":"leave"})
		if not await wait_for(func():return app.find_child("ReturnToRoom",true,false)!=null,"settlement appears after last opponent forfeits"):return
		await screenshot("settlement-"+str(match_index+1))
		await click(app.find_child("ReturnToRoom",true,false))
		if not await wait_for(func():return app.scene=="room" and not is_instance_valid(app.page_transition) and not app.command_busy,"guest returned before host"):return
		if not check(app._me().returned and app._me().ready and app.ready_button.visible and not app.ready_button.disabled,"early return enables ready button"):return
		await click(app.ready_button)
		if not await wait_for(func():return not app._me().ready,"real ready button cancels auto-ready"):return
		if match_index==1:
			await fixture_command(owner, {"action":"leave"})
			if not await wait_for(func():return app.start_button.visible and not app._me().returned,"unreturned host leaves, guest inherits room"):return
			if not check(app.snapshot.room.battle==null and not app._me().ready,"host departure clears result and preserves readiness"):return
			break
		await click(app.ready_button)
		if not await wait_for(func():return app._me().ready,"real ready button readies again"):return
		await click(app.skin.get_node("RoomShop"))
		if not await wait_for(func():return app.scene=="shop" and not app._me().ready,"opening real shop cancels readiness"):return
		if not check(app.skin.find_child("NativeCombatShop",true,false)!=null,"shop contents mounted"):return
		var returned_shop:Control=app.skin.find_child("NativeCombatShop",true,false)
		await click(returned_shop.item_buttons[1])
		await click(returned_shop.buy_button)
		if not await wait_for(func():return int(app.profile.inventory[0])==1,"purchase while another human remains in settlement"):return
		await click(returned_shop.backpack[0])
		await click(returned_shop.sell_button)
		if not await wait_for(func():return int(app.profile.inventory[0])==0,"sale while another human remains in settlement"):return
		await screenshot("early-return-shop")
		await click(app.skin.get_node("RoomShop"))
		if not await wait_for(func():return app.scene=="room","close shop returns to room"):return
		await click(app.vehicle_picker.buttons[3])
		if not await wait_for(func():return int(app._me().vehicle)==3,"early return can select vehicle"):return
		var lobby:Dictionary=await opponent.request("/api/state")
		var visible_rooms:Array=lobby.rooms.filter(func(row):return int(row.id)==room_id)
		if not check(visible_rooms.size()==1 and visible_rooms[0].phase=="settlement" and int(visible_rooms[0].waiting_returns)==1,"lobby reports one player in settlement"):return
		await screenshot("early-return-room")
		await fixture_command(owner, {"action":"return"})
		if not await wait_for(func():return not app._me().returned,"last player returns"):return
		if not check(not app._me().ready,"last player cannot reset cancel-ready"):return
		await fixture_command(opponent, {"action":"join","room":room_id})
		var denied:Dictionary=await owner.request("/api/command",{"action":"start"})
		if not check(denied.has("error") and str(denied.error).contains("准备"),"host blocked while guest is unready"):return
		await click(app.ready_button)
		if not await wait_for(func():return app._me().ready,"ready for second match"):return
		await fixture_command(owner, {"action":"start"})
	await screenshot("room-after-last-host-leaves")
	await owner.request("/api/logout",{})
	await opponent.request("/api/logout",{})
	print("FIDELITY_UI_ACCEPTANCE "+JSON.stringify({"checks":checks,"private_input_only":true}))
	await app._quit()
