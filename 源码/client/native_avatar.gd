extends Control
## Original default avatar, assembled from source SPR layers without native DLLs.
const ORDER := [16,5,4,6,7,9,12,14]
var layers := {}
var elapsed := 0.0
var frame_stamp := -1

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	for id in ORDER:
		var metadata:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/%d/frames.json"%id))
		var images:Array=[]
		for frame:Dictionary in metadata:images.append(load("res://assets/avatar/%d/%s"%[id,str(frame.file)]))
		layers[id]={"frames":metadata,"images":images}

func _process(delta: float) -> void:
	elapsed+=delta
	var stamp:=int(elapsed*10)
	if stamp!=frame_stamp:
		frame_stamp=stamp
		queue_redraw()

func _draw() -> void:
	var factor:=minf(size.x/75,size.y/120)
	var origin:=(size-Vector2(75,120)*factor)/2+Vector2(37,57)*factor
	for id in ORDER:
		if not layers.has(id):continue
		var layer:Dictionary=layers[id]
		var index:int=frame_stamp%layer.images.size() if id==14 else 1 if id==6 and frame_stamp%40==39 else 0
		index=maxi(0,index)
		var frame:Dictionary=layer.frames[index]
		var image:Texture2D=layer.images[index]
		draw_texture_rect(image,Rect2(origin-Vector2(float(frame.pivot[0]),float(frame.pivot[1]))*factor,image.get_size()*factor),false)
