extends SceneTree
class SlowNetwork extends "res://net.gd":
	var lag:=.25
	func request(path:String,payload:Variant=null,conditional:=false) -> Dictionary:
		var response:Dictionary=await super.request(path,payload,conditional)
		await root.get_tree().create_timer(lag).timeout
		return response

var app:Control
var options:Dictionary={}
var checks:Array=[]
var samples:Array=[]

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1)
			options[pair[0]]=pair[1]
	OS.set_environment("LOCALAPPDATA",str(options.output).path_join("profile"))
	OS.set_environment("BCHD_VAULT_ROOT",str(options.output).path_join("vault"))
	_run.call_deferred()

func check(ok:bool,message:String) -> bool:
	if not ok:
		push_error(message)
		if app:root.get_texture().get_image().save_png(str(options.output).path_join("failure.png"))
		quit(2)
		return false
	checks.append(message)
	return true

func wait_for(condition:Callable,message:String) -> bool:
	for i in range(160):
		if condition.call():return check(true,message)
		await create_timer(.05).timeout
	return check(false,message)

func key(code:int,pressed:bool) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	await process_frame

func capture(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func _run() -> void:
	var bootstrap:Node=load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await create_timer(.4).timeout
	app=bootstrap.get_child(0)
	if not await wait_for(func():return not app.catalog.is_empty(),"catalog loaded"):return
	app.register_mode=true
	app._show_login()
	app.username.text=str(options.name)
	app.password.text="qa-only-895432"
	app.confirmation.text=app.password.text
	app._login()
	if not await wait_for(func():return app.scene=="lobby","normal registration enters lobby"):return
	var guest:RefCounted=load("res://net.gd").new(app)
	guest.endpoint=app.net.endpoint
	var response:Dictionary=await guest.request("/api/register",{"name":str(options.name)+"b","password":"qa-only-895432"})
	guest.token=str(response.token)
	await app._command({"action":"create","name":"控制与延迟验收","map":9,"capacity":8})
	await guest.request("/api/command",{"action":"join","room":int(app.snapshot.room.id)})
	await app._command({"action":"vehicle","vehicle":1})
	await app._command({"action":"start"})
	if not await wait_for(func():return app.scene=="battle","actual battle started"):return
	for i in range(4):
		var item:Button=app.inventory_row.get_child(i)
		if not check(item.icon!=null and item.icon.resource_path.ends_with("F%dBtn/00.png"%(i+5)),"empty native inventory retains F%d icon"%(i+5)):return
	var slow:=SlowNetwork.new(app)
	slow.endpoint=app.net.endpoint
	slow.token=app.net.token
	app.net=slow
	app.view.clock=slow
	app.battle_hud.clock=slow
	await app._poll()
	await create_timer(.2).timeout
	var focus:=root.gui_get_focus_owner()
	if focus:focus.release_focus()
	var walker:RefCounted=app.walker
	var initial:Vector2=app.view.render_positions[str(int(walker.unit.seat))]
	# Choose a supported direction before holding the actual key. No game
	# state or map is replaced to make the walk pass.
	var original:Dictionary=walker.unit.duplicate(true)
	var scores:Dictionary={}
	for direction in [-1,1]:
		walker.unit=original.duplicate(true)
		scores[direction]=walker._move(direction*100)
	walker.unit=original.duplicate(true)
	var direction:int=1 if int(scores[1])>=int(scores[-1]) else -1
	if not check(int(scores[direction])>=20,"real spawn has a supported walk segment"):return
	walker.unit=original.duplicate(true)
	walker.unit.x=float(walker.unit.x)+.25
	var fraction_x:float=walker.unit.x
	walker._move(direction)
	if not check(is_equal_approx(float(walker.unit.x)-fraction_x,direction),"walking preserves fractional position after native carrying/teleporting"):return
	walker.unit=original.duplicate(true)
	await key(KEY_RIGHT if direction>0 else KEY_LEFT,true)
	await create_timer(.075).timeout
	var first:Vector2=app.view.render_positions[str(int(walker.unit.seat))]
	if not check((first.x-initial.x)*direction>=1,"walk responds before delayed network acknowledgement"):return
	var began:=Time.get_ticks_usec()
	var previous:=first
	while Time.get_ticks_usec()-began<900000:
		await process_frame
		var at:Vector2=app.view.render_positions[str(int(walker.unit.seat))]
		samples.append({"x":at.x,"y":at.y,"pending":walker.pending.size(),"elapsed":float(Time.get_ticks_usec()-began)/1000000})
		if not check((at.x-previous.x)*direction>=-.01,"no rollback on movement acknowledgement"):return
		previous=at
	await key(KEY_RIGHT if direction>0 else KEY_LEFT,false)
	var released:Vector2=app.view.render_positions[str(int(walker.unit.seat))]
	if not check((released.x-initial.x)*direction>=15,"walking progresses under 250 ms response delay"):return
	if not check(await walker.flush(),"pending moves flush before another action"):return
	await create_timer(.4).timeout
	var stopped:Vector2=app.view.render_positions[str(int(walker.unit.seat))]
	if not check(absf(stopped.x-released.x)<.01,"releasing movement stops immediately and remains reconciled"):return
	var own:Dictionary={}
	for participant:Dictionary in app._battle_data().units:
		if int(participant.player)==int(app.profile.id):own=participant
	if not check(Vector2(float(own.x),float(own.y)).distance_to(stopped)<.01,"predicted final position equals actual server position"):return
	if not check(int(own.sp)==int(walker.unit.sp) and absf(float(own.move)-float(walker.unit.move))<.01,"predicted fuel and movement equal authority after acknowledgement"):return
	await capture("walk-stopped")
	# Mouse ring drag must change the native elevation without firing.
	var shown:Dictionary=app.view.battle.units[0]
	var center:Vector2=app.view.screen(app.view.aim_center(shown))
	app.view._update_mouse_aim(center+Vector2(35,-35)*app.view.zoom,shown)
	var slope:=fposmod(float(shown.get("slope",0))+180,360)-180
	var data:Dictionary=app.catalog.vehicles[int(shown.vehicle)-1]
	var expected:=clampf(45-slope,float(data.aim_min),float(data.aim_max))
	if not check(absf(app.aim-expected)<2,"native mouse aiming changes elevation: got %s expected %s slope %s"%[app.aim,expected,slope]):return
	var before:int=int(app._battle_data().generation)
	# Reproduce a stale snapshot locally, then restore the live snapshot.
	# The server-side deadline test separately checks the same boundary.
	var live:Dictionary=app._battle_data()
	var saved_deadline:float=live.deadline
	live.deadline=app.net.server_now()-.1
	app._start_charging()
	if not check(not app._my_turn() and not app.charging,"expired snapshot blocks a new charge before the next poll"):return
	live.deadline=saved_deadline
	var native_sp:int=own.sp
	var native_mode:int=own.shot_mode
	var predicted_sp:int=walker.unit.sp
	var predicted_mode:int=walker.unit.shot_mode
	own.sp=0
	walker.unit.sp=0
	app.selected_weapon=0
	await key(KEY_F3,true)
	await key(KEY_F3,false)
	if not check(app.selected_weapon==0,"F3 follows the same insufficient SP rule as the mouse"):return
	own.shot_mode=3
	walker.unit.shot_mode=3
	await key(KEY_F3,true)
	await key(KEY_F3,false)
	if not check(app.selected_weapon==2 and app._weapon_cost(own,2)==0,"item projectile can be selected from the F3 tab at zero SP"):return
	own.sp=native_sp
	own.shot_mode=native_mode
	walker.unit.sp=predicted_sp
	walker.unit.shot_mode=predicted_mode
	app._select_weapon(0)
	await key(KEY_SPACE,true)
	await create_timer(.15).timeout
	if not check(app.charging,"charge is active before testing F9 cancellation"):return
	await key(KEY_F9,true)
	await key(KEY_F9,false)
	await key(KEY_SPACE,false)
	if not await wait_for(func():return int(app._battle_data().generation)>before,"F9 actually skips to next participant"):return
	if not check(not app.charging,"F9 cancels pending charge"):return
	var battle:Dictionary=app._battle_data()
	await guest.request("/api/command",{"action":"pass","generation":int(battle.generation)})
	await app._poll()
	if not await wait_for(func():return app._my_turn(),"next complete turn returns to the player"):return
	await key(KEY_SPACE,true)
	await create_timer(.6).timeout
	if not check(app.charging and app.charge>.20 and app.charge<.30,"space uses native 120 raw power per second"):return
	await capture("power-quarter")
	await key(KEY_SPACE,false)
	if not await wait_for(func():return app._battle_data().get("shot") is Dictionary,"space release really fires"):return
	var shot:Dictionary=app._battle_data().shot
	var points:Array=shot.trails[0].points
	if not check(float(shot.started)>app.net.server_now() and absf(float(shot.started)-float(shot.prepared)-.5)<.001,"delayed firing client receives the ordinary shot before shared muzzle time"):return
	var remote:Dictionary=await guest.request("/api/state")
	var remote_shot:Dictionary=remote.room.battle.shot
	if not check(float(remote_shot.started)==float(shot.started) and remote_shot.trails[0].points[0]==points[0],"second player has exactly the same muzzle point and clock"):return
	if not check(points.size()>2,"fired shot has actual native trajectory"):return
	if not await wait_for(func():return float(app._battle_data().deadline)>0,"released shot resolves and next participant can act"):return
	battle=app._battle_data()
	await guest.request("/api/command",{"action":"pass","generation":int(battle.generation)})
	await app._poll()
	if not await wait_for(func():return app._my_turn(),"second test turn returns after shot resolution"):return
	var old_shot:=int(app._battle_data().shot.id)
	await key(KEY_SPACE,true)
	await create_timer(1.25).timeout
	if not check(app.charging and app.charge>.45 and app.charge<.55,"native half power is reached in about 1.25 seconds"):return
	await capture("power-half")
	if not await wait_for(func():return app._battle_data().get("shot") is Dictionary and int(app._battle_data().shot.id)>old_shot,"full power automatically fires while space remains held"):return
	if not check(not app.charging and is_equal_approx(app.charge,1),"full power fire clears charging exactly once"):return
	var maximum:Dictionary=app._battle_data().shot
	var motion:Array=maximum.trails[0].points
	var speed:=Vector2(float(motion[1][0])-float(motion[0][0]),float(motion[1][1])-float(motion[0][1])).length()
	if not check(speed>19 and speed<21,"maximum native shot has original 20-pixel-per-tick launch speed"):return
	await key(KEY_SPACE,false)
	await create_timer(.2).timeout
	if not check(int(app._battle_data().shot.id)==int(maximum.id),"releasing space after automatic fire does not fire twice"):return
	if not await wait_for(func():return float(app._battle_data().deadline)>0,"maximum shot resolves normally"):return
	battle=app._battle_data()
	await guest.request("/api/command",{"action":"pass","generation":int(battle.generation)})
	await app._poll()
	if not await wait_for(func():return app._my_turn(),"button skip test returns to player turn"):return
	await key(KEY_SPACE,true)
	await create_timer(.1).timeout
	var skip:Button=app.hud_buttons.skip
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=skip.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event)
		await process_frame
	await key(KEY_SPACE,false)
	if not await wait_for(func():return not app._my_turn(),"actual skip button cancels charge and changes participant"):return
	if not check(not app.charging,"button skip leaves no pending space charge"):return
	await app._command({"action":"leave"})
	if not check(not walker.active and walker.pending.is_empty() and app.walker==null,"leaving clears local walk and queued input"):return
	await guest.request("/api/command",{"action":"leave"})
	var report:Dictionary={"passed":true,"checks":checks,"walk_samples":samples,"response_delay":slow.lag,"private_desktop":true,"silent":true}
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("CONTROL_ACCEPTANCE "+JSON.stringify({"checks":checks.size(),"passed":true}))
	await app._quit()
