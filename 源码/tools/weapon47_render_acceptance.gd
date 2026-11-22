extends SceneTree
class FrozenClock extends RefCounted:
	func server_now() -> float:return 100.0

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	_run.call_deferred()

func _run() -> void:
	root.size=Vector2i(960,540)
	var view: Control=load("res://world_view.gd").new()
	view.clock=FrozenClock.new()
	root.add_child(view)
	view.size=Vector2(960,540)
	view.set_process(false)
	view.zoom=4.0
	view.screen_origin=Vector2.ZERO
	var trails: Array=[]
	for row in range(2):
		for column in range(2):
			var at: Vector2=Vector2(240+column*480,150+row*240)/view.zoom
			var sign:=1 if column==0 else -1
			trails.append({"projectile":1 if row==0 else 47,"kind":"normal","start":0.0,"duration":1.0,"points":[[at.x-20*sign,at.y],[at.x+20*sign,at.y]]})
	view.battle={"units":[],"deadline":0.0,"shot":{"id":1,"started":99.5,"duration":1.0,"trails":trails,"impacts":[]}}
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("NATIVE47_RENDERED")
	quit()
