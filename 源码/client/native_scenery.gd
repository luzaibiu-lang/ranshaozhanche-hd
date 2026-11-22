extends Node2D
## Original CTerrain::update (004df740) weather, using the bk_*.spr frames.
## Cosmetic only: this class never changes terrain, wind or combat state.
const KINDS := {1:"bridge",2:"snow",3:"rain",4:"jungle",5:"meteor",6:"cave",7:"bubble",8:"volcano",9:"city",10:"factory",11:"underworld",12:"futurespace",13:"desertplanet",14:"volcano",15:"city",16:"city"}
const PERIOD := {1:10,2:2,3:1,4:25,5:30,6:2,7:8,8:5,9:5,10:2,11:8,12:7,13:5,14:5,15:5,16:5}
var world: Control
var map_id := -1
var records: Array[Dictionary] = []
var frames: Array = []
var images: Array[Texture2D] = []
var tick := 0
var remainder := 0.0
var rng := RandomNumberGenerator.new()
var additive: Node2D
var normal: Node2D
var factory_x := 0.0

func _ready() -> void:
	normal = Node2D.new()
	normal.draw.connect(func(): _paint(false))
	add_child(normal)
	additive = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.material = material
	additive.draw.connect(func(): _paint(true))
	add_child(additive)

func reset(id: int, battle_id: String) -> void:
	map_id = id
	records.clear()
	frames.clear()
	images.clear()
	tick = 0
	remainder = 0
	rng.seed = hash(battle_id)
	if not KINDS.has(id):return
	var directory := "res://assets/scenery/bk_%s" % KINDS[id]
	frames = JSON.parse_string(FileAccess.get_file_as_string(directory + "/frames.json"))
	for frame: Dictionary in frames:images.append(load(directory.path_join(str(frame.file))))
	# Fill the background as if the original scene had been running for 8 s.
	for i in range(480):_step()

func _process(delta: float) -> void:
	if not world or world.battle.is_empty() or frames.is_empty():return
	remainder += minf(delta, 0.25)
	while remainder >= 1.0/60:
		remainder -= 1.0/60
		_step()
	normal.queue_redraw()
	additive.queue_redraw()

func _spawn(edge := false) -> void:
	var kind: String = KINDS[map_id]
	var width := float(world.battle.width)
	var height := float(world.battle.height)
	var margin := 200.0 if kind in ["rain","snow","volcano","city"] else 600.0
	var at := Vector2(rng.randi_range(int(-margin),int(width+margin-1)), -margin/2)
	if kind in ["bridge","underworld","futurespace","desertplanet","meteor","jungle"]:at.y = -300
	if kind in ["rain","snow","volcano","city"]:at.y = -200
	if kind == "cave":at = Vector2(rng.randi_range(-100,int(width+99)),rng.randi_range(-100,int(height+99)))
	if kind in ["bubble","factory"]:at.y = height+200
	if kind == "factory":at.x = factory_x + rng.randi_range(-80,79)
	if edge:
		at.x = -200 if int(world.battle.wind)>=0 else width+200
		at.y = rng.randi_range(0,int(height-1))
	var record := {"at":at,"x":at.x,"age":0,"angle":float(rng.randi_range(0,359)),"phase":float(rng.randi_range(0,359)),"phase_speed":8.0,"scale":0.6,"stretch":1.0,"opacity":0.6,"frame":0,"add":true,"spin":true,"margin":margin}
	match kind:
		"underworld":record.scale=1.6
		"futurespace","desertplanet":record.scale=0.3
		"rain":record.scale=1;record.stretch=rng.randi_range(0,9)+2;record.spin=false;record.angle=0;record.opacity=0.1
		"city","volcano":record.scale=1;record.stretch=1+rng.randi_range(0,9)*0.5;record.spin=false;record.angle=0;record.opacity=1
		"bubble":record.scale=rng.randi_range(0,29)/100.0+0.3;record.add=false;record.phase_speed=rng.randi_range(2,11);record.spin=false
		"snow":record.scale=0.7;record.opacity=0.4;record.spin=false
		"jungle":record.frame=rng.randi_range(0,1);record.scale=rng.randi_range(0,39)/100.0+0.4;record.add=false;record.spin=false
		"meteor":record.frame=rng.randi_range(0,2);record.scale=1;record.add=false
		"factory":record.scale=rng.randi_range(0,199)/100.0+2;record.opacity=0.15;record.add=true;record.spin=false
	records.append(record)

func _step() -> void:
	if not KINDS.has(map_id) or not world:return
	var kind: String = KINDS[map_id]
	var wind := float(world.battle.get("wind",0))
	if kind == "factory" and tick%30==0:factory_x = rng.randi_range(-200,int(world.battle.width)+199)
	if tick%int(PERIOD[map_id])==0 and (kind != "factory" or tick%30<20):_spawn()
	if kind == "snow" and absf(wind)>5 and tick%3==0:_spawn(true)
	for record in records:
		record.age += 1
		var at: Vector2 = record.at
		var dx := wind/10
		var dy := 4.0
		match kind:
			"rain":dx=wind/5;dy=18
			"city","volcano":dx=wind/5;dy=13
			"meteor","jungle":dx=wind/15;dy=3;record.angle+=4
			"factory":dx=wind/5;dy=-20;record.angle+=4
			"bubble":dy=-4
			"snow":dy=3
			"cave":dy=1
		record.x += dx
		at.x = int(record.x)
		at.y += dy
		if kind in ["snow","bubble"]:
			record.phase += float(record.phase_speed)
			at.x += int(sin(deg_to_rad(float(record.phase)))*6)
			if kind == "snow":record.angle+=4
		if record.spin:record.angle+=5
		if kind in ["rain","city","volcano"]:record.angle=90-rad_to_deg(Vector2(dx,dy).angle())
		if kind in ["bridge","underworld","futurespace","desertplanet"]:record.opacity=0.3+0.7*absf(float(int(record.age)%40)-20)/20
		if kind == "cave":record.opacity=0.3+0.7*absf(float(int(record.age)%20)-10)/10
		record.at = at
	var dimensions := Vector2(float(world.battle.width),float(world.battle.height))
	records = records.filter(func(r): return (r.at as Vector2).x>=-600 and (r.at as Vector2).x<=dimensions.x+600 and (r.at as Vector2).y>=-600 and (r.at as Vector2).y<=dimensions.y+600)
	tick += 1

func _paint(add: bool) -> void:
	if not world or images.is_empty():return
	var layer: Node2D = additive if add else normal
	for record in records:
		if bool(record.add)!=add:continue
		var index := int(record.frame)
		var image := images[index]
		var point: Vector2 = world.screen(record.at)
		var factor := float(record.scale)*float(world.zoom)
		var extent := image.get_size()*factor
		if point.x<-extent.x or point.y<-extent.y or point.x>world.size.x+extent.x or point.y>world.size.y+extent.y:continue
		var angle := -deg_to_rad(float(record.angle))
		layer.draw_set_transform(point,angle,Vector2(factor,factor*float(record.stretch)))
		var frame: Dictionary = frames[index]
		layer.draw_texture(image,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])),Color(1,1,1,clampf(float(record.opacity),0,1)))
	layer.draw_set_transform(Vector2.ZERO)
