extends Node2D
## Original fire sprites with continuous flow and short, clocked ember trails.
const IDS := [24,26,90,91,92]
var world:Control
var flow:ShaderMaterial

func _ready() -> void:
	flow=ShaderMaterial.new()
	flow.shader=preload("res://native_flame.gdshader")
	material=flow

func _process(_delta:float) -> void:
	if world and world.clock:
		var shot:Variant=world.battle.get("shot")
		if shot is Dictionary:flow.set_shader_parameter("phase",world.clock.server_now()-float(shot.started))
	queue_redraw()

func flame_samples(trail:Dictionary,time:float) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var age:=time-float(trail.get("start",0))
	var duration:=float(trail.duration)
	if age<0 or age>duration+.22:return result
	var blue:=int(trail.projectile) in [91,92]
	var color:=Color(.12,.4,1) if blue else Color(1,.28,.035)
	# Follow past published positions, so the tail bends with the actual shot.
	# No persistent particles accumulate across turns or reconnection.
	for index in range(1,9):
		var behind:=float(index)*.022
		var at:=age-behind
		if at<0 or at>duration:continue
		var fade:float=(1-float(index)/9)*clampf((duration+.22-age)/.22,0,1)
		var point:Vector2=world.point_on_trail(trail,at)
		var tangent:Vector2=world.point_on_trail(trail,minf(duration,at+.016))-world.point_on_trail(trail,maxf(0,at-.016))
		var side:=tangent.normalized().orthogonal()
		point+=side*sin(at*45+index*2.3)*index*.45
		result.append({"position":point,"radius":maxf(.7,4-index*.38),"alpha":fade*.32,"color":color})
	return result

func _draw() -> void:
	if not world or not world.clock or world.battle.is_empty():return
	var shot:Variant=world.battle.get("shot")
	if not shot is Dictionary:return
	var time:float=world.clock.server_now()-float(shot.started)
	for trail:Dictionary in shot.get("trails",[]):
		var id:=int(trail.get("projectile",0))
		if id not in IDS:continue
		for ember:Dictionary in flame_samples(trail,time):
			var radius:float=float(ember.radius)*world.zoom
			var tint:Color=ember.color
			tint.a=float(ember.alpha)
			draw_set_transform(Vector2.ZERO)
			draw_texture_rect(world.glow,Rect2(world.screen(ember.position)-Vector2.ONE*radius,Vector2.ONE*radius*2),false,tint)
		var age:=time-float(trail.get("start",0))
		if age<0 or age>float(trail.duration):continue
		var frames:Array=world.projectile_frames.get(id,[])
		if frames.is_empty():continue
		var rule:Dictionary=world.projectile_rules[str(id)]
		var layer:Dictionary=rule.layers[0]
		var index:=int(layer.first)+(int(age*60)/maxi(1,int(layer.ticks)))%int(layer.count)
		var frame:Dictionary=frames[index]
		var sprite:Texture2D=world.texture("res://assets/projectiles/%s/%s"%[str(rule.sprite),str(frame.file)])
		var at:Vector2=world.point_on_trail(trail,age)
		var direction:Vector2=world.point_on_trail(trail,minf(float(trail.duration),age+1.0/60))-world.point_on_trail(trail,maxf(0,age-1.0/60))
		draw_set_transform(world.screen(at),direction.angle(),Vector2.ONE*world.zoom)
		draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])))
	draw_set_transform(Vector2.ZERO)
