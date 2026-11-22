extends SceneTree
## Exercise the production renderer, silently on an inactive desktop.
class FrozenClock extends RefCounted:
	func server_now() -> float:return 100.0

var output := ""
var view: Control
var checks := []

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	output=OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func _run() -> void:
	root.size=Vector2i(1600,1100)
	view=load("res://world_view.gd").new()
	view.clock=FrozenClock.new()
	view.player_id=1
	root.add_child(view)
	view.set_process(false)
	view.size=Vector2(1600,1100)
	view.zoom=3
	view.screen_origin=Vector2.ZERO
	var units: Array=[]
	var battle := {"id":"aim-projectile-render-fixture","active":-1,"deadline":0.0,"units":units,"holes":[],"shot":null,"width":1920,"height":1200}
	view.battle=battle
	var directions := [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN]
	var ids := [1,2,3,18,19,101]
	var trails: Array=[]
	for row in range(ids.size()):
		for column in range(directions.size()):
			var at: Vector2 = Vector2(200+column*400,140+row*170)/view.zoom
			var delta: Vector2=directions[column]*20
			trails.append({"projectile":ids[row],"kind":"shell","start":0.0,"duration":1.0,"points":[[at.x-delta.x,at.y-delta.y],[at.x+delta.x,at.y+delta.y]]})
	battle.shot={"id":1,"started":99.5,"duration":1.0,"trails":trails,"impacts":[],"motion":[]}
	var layers := []
	for child in view.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("native_projectile_layer.gd"):layers.append(child)
	if not check(layers.size()==2,"production additive and opaque projectile layers are present"):return
	var cached: int=view.texture_cache.size()
	if not check(cached>200,"projectile and impact frames are warm before the first shot"):return
	await capture("projectiles-composite")
	for layer in layers:layer.visible=not layer.additive
	await capture("projectiles-core")
	for layer in layers:layer.visible=layer.additive
	await capture("projectiles-halo")
	if not check(view.texture_cache.size()==cached,"first projectile playback does not load any additional textures"):return
	for layer in layers:layer.visible=true
	var spinning := [5,16,17,20,21,28,29,59,60,82]
	for page in range(2):
		trails.clear()
		for row in range(mini(6,spinning.size()-page*6)):
			for column in range(directions.size()):
				var at: Vector2=Vector2(200+column*400,140+row*170)/view.zoom
				var delta: Vector2=directions[column]*20
				trails.append({"projectile":spinning[page*6+row],"kind":"shell","start":0.0,"duration":1.0,"points":[[at.x-delta.x,at.y-delta.y],[at.x+delta.x,at.y+delta.y]]})
		await capture("projectiles-spin-%d"%page)
	for layer in layers:layer.visible=false
	battle.shot=null
	battle.active=0
	battle.deadline=135.0
	view.zoom=3.5
	view.screen_origin=Vector2(800,620)
	var unit := {"vehicle":1,"seat":0,"player":1,"face":1,"hp":300,"max_hp":300,"team":0,"name":"","x":0.0,"y":0.0,"slope":0.0}
	units.append(unit)
	view.catalog={"vehicles":[]}
	for id in range(30):view.catalog.vehicles.append({"aim_min":0.0,"aim_max":90.0})
	view.angle=35
	view.render_positions["0"]=Vector2.ZERO
	var snapshots := []
	var source_offsets := [Vector2(-1,-22),Vector2(-2,-20),Vector2(5,-18),Vector2(4,-23),Vector2(2,-23),Vector2(-6,-19),Vector2(0,-25),Vector2(0,-20),Vector2(16,-24),Vector2(0,-20)]
	for id in range(1,31):
		unit.vehicle=id
		for face in [1,-1]:
			unit.face=face
			for slope in [-20.0,0.0,20.0]:
				unit.slope=slope
				view.render_slopes["0"]=slope
				view._update_vehicles(0.0)
				var vehicle: Node2D=view.vehicles[0]
				var actual: Vector2=view.aim_center(unit)
				var source: Vector2=source_offsets[(id-1)%10]
				var polar := float(int(rad_to_deg(atan2(-source.y,source.x))))
				if face<0:polar=180-polar
				var radians: float = (polar+slope)*0.017453288659453392
				var distance := float(int(source.length()))
				var expected := Vector2(floorf((cos(radians)*distance+.0005)*1000)/1000,-floorf((sin(radians)*distance+.0005)*1000)/1000)
				if not check(actual.distance_to(expected)<.001,"native barrel mount vehicle=%d face=%d slope=%d"%[id,face,int(slope)]):return
				var gun: Sprite2D=vehicle.layers[1 if (id-1)%10!=6 else 2]
				if not check(gun.position.distance_to(actual)<.001,"reticle and rendered barrel share mount vehicle=%d face=%d slope=%d"%[id,face,int(slope)]):return
				if id<=10 and slope==0:
					view.reticle.queue_redraw()
					await capture("aim-%02d-%s"%[id,"right"if face>0 else "left"])
					snapshots.append({"vehicle":id,"face":face,"center":[actual.x,actual.y]})
	print("AIM_PROJECTILE_ACCEPTANCE "+JSON.stringify({"checks":checks,"projectile_ids":ids,"directions":["right","up","left","down"],"reticle_snapshots":snapshots,"warm_textures":cached,"silent":true,"private_desktop":true}))
	quit()
