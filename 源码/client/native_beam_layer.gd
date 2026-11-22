extends Node2D
## CEffect04 (004aed00): Effect05 column from sky to each wave's impact.
const TICKS := 50.0
var world:Control
var frames:Array=[]

func _ready() -> void:
	var blend:=CanvasItemMaterial.new()
	blend.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
	material=blend
	frames=JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/Effect05/frames.json"))
	for frame:Dictionary in frames:world.texture("res://assets/effects/Effect05/"+str(frame.file))

func _process(_delta:float) -> void:
	queue_redraw()

func active_beams(shot:Dictionary,now:float) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for impact:Dictionary in shot.get("impacts",[]):
		if int(impact.get("projectile",0))!=5:continue
		var age:=now-float(shot.started)-float(impact.at)
		if age<0 or age>=TICKS/60:continue
		var alpha:=1-age*60/TICKS
		var scale_x:=.8*alpha
		var flicker:=float((int(age*60)*7+int(impact.x)*3)%10)*.06
		result.append({"origin":Vector2(float(impact.x),float(impact.y)),"width":64*scale_x,"alpha":alpha,"flash_scale":Vector2(scale_x*.4+1.1+flicker,scale_x*.4+.8)})
	return result

func _draw() -> void:
	if not world or not world.clock or world.battle.is_empty():return
	var shot:Variant=world.battle.get("shot")
	if not shot is Dictionary:return
	var column:Texture2D=world.texture("res://assets/effects/Effect05/"+str(frames[1].file))
	var flash:Texture2D=world.texture("res://assets/effects/Effect05/"+str(frames[0].file))
	for beam:Dictionary in active_beams(shot,world.clock.server_now()):
		var origin:Vector2=beam.origin
		var top:Vector2=world.screen(Vector2(origin.x,0))
		var bottom:Vector2=world.screen(origin)
		var width:float=float(beam.width)*world.zoom
		var tint:=Color(1,1,1,float(beam.alpha))
		draw_texture_rect(column,Rect2(Vector2(top.x-width/2,top.y),Vector2(width,maxf(0,bottom.y-top.y))),false,tint)
		draw_set_transform(bottom,0,beam.flash_scale*world.zoom)
		draw_texture(flash,-Vector2(float(frames[0].size[0]),float(frames[0].size[1]))/2,Color(1,1,1,minf(1,float(beam.alpha)+.3)))
		draw_set_transform(Vector2.ZERO)
