extends SceneTree

var controls: Control
var events: Array = []
var failures: Array = []
var checks := 0
var modal := false

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	run.call_deferred()

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:failures.append(detail)

func touch(index: int, at: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func key(name: String) -> Vector2:
	return controls.keys[name].box.get_global_rect().get_center()

func run() -> void:
	root.min_size = Vector2i.ZERO
	controls = load("res://mobile_battle_controls.gd").new()
	root.add_child(controls)
	controls.blocked = func(): return modal
	controls.weapon_selected.connect(func(slot): events.append(["weapon",slot]))
	controls.item_selected.connect(func(slot): events.append(["item",slot]))
	controls.fire_started.connect(func(): events.append("start"))
	controls.fire_released.connect(func(): events.append("release"))
	controls.fire_canceled.connect(func(): events.append("cancel"))
	controls.set_inventory([1, 2, 3, 4])
	controls.set_actions(true, 0)
	for dimensions in [Vector2i(844,390),Vector2i(320,568),Vector2i(932,430),Vector2i(2048,1536)]:
		controls.size = dimensions
		for name: String in controls.keys:
			var rect: Rect2 = controls.keys[name].box.get_rect()
			check(Rect2(Vector2.ZERO,dimensions).encloses(rect), "bounds "+name+str(dimensions))
			for other: String in controls.keys:
				if name < other:check(not rect.intersects(controls.keys[other].box.get_rect()), "overlap "+name+"/"+other)
	controls.size = Vector2(844,390)
	touch(1,key("right"),true)
	touch(2,key("up"),true)
	touch(3,key("fire"),true)
	check(controls.direction("right","left")==1 and controls.direction("up","down")==1 and events==["start"],"three simultaneous presses")
	touch(1,key("left"),false)
	check(controls.direction("right","left")==0 and controls.direction("up","down")==1 and events==["start"],"release outside belongs to original finger")
	touch(3,key("weapon1"),false)
	check(events==["start","release"],"single shot on original release")
	touch(2,key("up"),false)
	for kind in ["weapon","item"]:
		for index in (3 if kind=="weapon" else 4):
			var count := events.size()
			touch(0,key(kind+str(index)),true)
			touch(0,key(kind+str(index)),false)
			check(events.size()==count+1 and events.back()==[kind,index],"command "+kind+str(index))
	controls.set_inventory([0,2,0,4])
	var count := events.size()
	touch(0,key("item0"),true)
	touch(0,key("item0"),false)
	check(events.size()==count,"empty slot suppresses action")
	touch(0,key("fire"),true)
	touch(0,key("fire"),false,true)
	check(events.back()=="cancel","canceled finger suppresses shot")
	touch(0,key("fire"),true)
	touch(1,key("down"),true)
	controls.set_actions(false, 1)
	touch(0,key("fire"),false)
	check(events.back()=="cancel" and controls.direction("up","down")==0,"turn loss clears all presses")
	controls.set_actions(true, 1)
	modal=true
	count=events.size()
	touch(0,key("fire"),true)
	touch(0,key("fire"),false)
	check(events.size()==count,"modal suppresses shot")
	modal=false
	touch(0,key("fire"),true)
	controls.size=Vector2(390,844)
	touch(0,key("fire"),false)
	check(events.back()=="cancel","rotation clears charge")
	print(JSON.stringify({"checks":checks,"failures":failures,"events":events}))
	quit(0 if failures.is_empty() else 1)
