extends RefCounted
## Native crater masks, applied in C++ to small texture tiles at impact time.
## No full-map byte copies, worker completion or deferred destruction frame.
const TILE := 256
var image:Image
var overview:ImageTexture
var tiles:Array[Dictionary]=[]
var masks:Array[Dictionary]=[]
var circle_masks:Dictionary={}
var dirty:Dictionary={}
var last_upload_bytes:=0

func _init(definitions:Array) -> void:
	for definition:Dictionary in definitions:
		var mask:=Image.create(int(definition.width),int(definition.height),false,Image.FORMAT_RGBA8)
		for y in range(int(definition.height)):
			var span:Array=definition.rows[y]
			if int(span[0])>=0:mask.fill_rect(Rect2i(int(span[0]),y,int(span[1])-int(span[0])+1,1),Color.WHITE)
		masks.append({"mask":mask,"clear":Image.create(mask.get_width(),mask.get_height(),false,Image.FORMAT_RGBA8)})

func reset(source:Image) -> void:
	image=source.duplicate()
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	tiles.clear()
	dirty.clear()
	for y in range(0,image.get_height(),TILE):
		for x in range(0,image.get_width(),TILE):
			var area:=Rect2i(x,y,mini(TILE,image.get_width()-x),mini(TILE,image.get_height()-y))
			var section:=image.get_region(area)
			tiles.append({"area":area,"image":section,"texture":ImageTexture.create_from_image(section)})
	var small:=_overview_image()
	if overview and overview.get_size()==Vector2(small.get_size()):overview.update(small)
	else:overview=ImageTexture.create_from_image(small)
	last_upload_bytes=0

func _overview_image() -> Image:
	var small:=image.duplicate()
	var factor:=minf(1,240.0/image.get_width())
	small.resize(maxi(1,int(image.get_width()*factor)),maxi(1,int(image.get_height()*factor)),Image.INTERPOLATE_NEAREST)
	return small

func walking_ground(x: float, from_y: int) -> int:
	var column := int(x)
	var height := image.get_height()
	if column < 8 or column >= image.get_width()-8:
		return height+200
	for y in range(maxi(0, from_y), height-2):
		if image.get_pixel(column, y).a == 0 or image.get_pixel(column, y+2).a == 0:
			continue
		var support := 0
		for dx in range(-5, 6):
			if image.get_pixel(column+dx, y).a > 0:
				support += 1
		if support >= 5:
			return y
	return height+200

func walking_support(vehicle: int, x: float, y: float) -> Dictionary:
	var width := 41 if (vehicle-1)%10==8 else 15
	var height := image.get_height()
	var left := int(x)-width/2
	var bottom := int(y)-1
	var heights:Array[int]=[]
	var contact := false
	for i in range(width):
		var column := left+i
		var at := height
		if column>=0 and column<image.get_width():
			contact=contact or _walking_solid(column,int(y))
			for row in range(bottom-1,bottom+width-width/4+1):
				if _walking_solid(column,row):at=row;break
			var row:=bottom-2
			while row>=0 and _walking_solid(column,row):at=row;row-=1
		heights.append(at)
	var pose:Dictionary={"x":x,"y":y,"slope":0.0,"valid":false}
	if not contact:return pose
	var middle := width/2
	var li:=middle;var ri:=middle;var near_l:=middle;var near_r:=middle
	var best:=height;var near:=height
	for i in range(middle,-1,-1):
		if heights[i]<near and heights[i]-int(y)<width/3+1:near_l=i;near=heights[i]
		if heights[i]<=best:li=i;best=heights[i]
	best=height;near=height
	for i in range(middle,width):
		if heights[i]<near and heights[i]-int(y)<width/3+1:near_r=i;near=heights[i]
		if heights[i]<=best:ri=i;best=heights[i]
	var start:=li;var end:=ri
	if heights[li]<height and heights[ri]<height:
		pose.valid=true;pose.y=maxi(heights[li],heights[ri])
	elif heights[li]<height and middle-near_l<=width/4+1 and heights[near_l]<height:
		end=near_l;pose.valid=true;pose.y=(heights[li]+heights[near_l])/2
	elif heights[ri]<height and near_r-middle<=width/4+1 and heights[near_r]<height:
		start=near_r;pose.valid=true;pose.y=(heights[ri]+heights[near_r])/2
	if pose.valid:
		pose.slope=_walking_angle(end-start,heights[start]-heights[end])
		if y<float(pose.y):pose.valid=false
	return pose

func _walking_solid(x:int,y:int) -> bool:
	return x>=0 and y>=0 and x<image.get_width() and y<image.get_height() and image.get_pixel(x,y).a>0

func _walking_angle(dx:int,dy:int) -> float:
	if dx==0:return 90.0 if dy>0 else 270.0 if dy<0 else 0.0
	if dy==0:return 0.0 if dx>0 else 180.0
	var ratio:float=PackedFloat32Array([floor((absf(float(dy)/dx)+.0005)*1000)/1000])[0]
	var angle:float=PackedFloat32Array([floor((atan(ratio)/.017453288659453392+.0005)*1000)/1000])[0]
	if dx<0:angle=180-angle if dy>0 else angle+180
	elif dy<0:angle=360-angle
	return PackedFloat32Array([angle])[0]

func walking_pose(vehicle:int,x:float,y:float,direction:int,falling:=false) -> Dictionary:
	var current:=walking_support(vehicle,x,y)
	var pose:=walking_support(vehicle,x+direction,y)
	pose.allowed=false
	if direction==0 or falling:return pose
	var half := 20 if (vehicle-1)%10==8 else 7
	if (direction<0 and int(pose.x)<=half) or (direction>0 and int(pose.x)+half>=image.get_width()):return pose
	var slope:=fposmod(float(pose.slope)+180,360)-180
	if slope*direction>65:return pose
	var previous:=float(current.slope)
	if (fposmod(previous+180,360)-180)*direction<0:previous=0
	var difference:=fposmod(float(pose.slope)-previous+180,360)-180
	if difference*direction>=40 or float(current.y)-float(pose.y)>=5:return pose
	pose.allowed=true
	return pose

func carve(hole:Dictionary) -> void:
	var mask_id:=int(hole.get("mask",0))
	var patch:Dictionary
	var at:Vector2i
	if mask_id>0 and mask_id<=masks.size():
		patch=masks[mask_id-1]
		var mask:Image=patch.mask
		at=Vector2i(int(hole.x)-int(mask.get_width()/2),int(hole.y)-int(mask.get_height()/2))
	else:
		var radius:=float(hole.r)
		if radius<=0:return
		# Fractional centers matter for non-native/circular compatibility cuts.
		var left:=int(float(hole.x)-radius)
		var top:=int(float(hole.y)-radius)
		var right:=int(float(hole.x)+radius)
		var bottom:=int(float(hole.y)+radius)
		var mask:=Image.create(right-left+1,bottom-top+1,false,Image.FORMAT_RGBA8)
		for y in range(top,bottom+1):
			var span:=sqrt(maxf(0,radius*radius-pow(float(y)-float(hole.y),2)))
			var start:=int(float(hole.x)-span)
			mask.fill_rect(Rect2i(start-left,y-top,int(float(hole.x)+span)-start+1,1),Color.WHITE)
		patch={"mask":mask,"clear":Image.create(mask.get_width(),mask.get_height(),false,Image.FORMAT_RGBA8)}
		at=Vector2i(left,top)
	var mask:Image=patch.mask
	var empty:Image=patch.clear
	var area:=Rect2i(at,mask.get_size())
	image.blit_rect_mask(empty,mask,Rect2i(Vector2i.ZERO,mask.get_size()),at)
	for index in range(tiles.size()):
		var tile:Dictionary=tiles[index]
		var overlap:=area.intersection(tile.area)
		if not overlap.has_area():continue
		(tile.image as Image).blit_rect_mask(empty,mask,Rect2i(overlap.position-at,overlap.size),overlap.position-(tile.area as Rect2i).position)
		dirty[index]=true

func flush() -> void:
	last_upload_bytes=0
	if dirty.is_empty():return
	for index:int in dirty:
		var tile:Dictionary=tiles[index]
		(tile.texture as ImageTexture).update(tile.image)
		last_upload_bytes+=(tile.image as Image).get_width()*(tile.image as Image).get_height()*4
	overview.update(_overview_image())
	dirty.clear()

func draw_in(canvas:Control,origin:Vector2,factor:float) -> void:
	var visible:=Rect2(Vector2.ZERO,canvas.size)
	for tile:Dictionary in tiles:
		var area:Rect2i=tile.area
		var destination:=Rect2(Vector2(area.position)*factor+origin,Vector2(area.size)*factor)
		if visible.intersects(destination):canvas.draw_texture_rect(tile.texture,destination,false)
