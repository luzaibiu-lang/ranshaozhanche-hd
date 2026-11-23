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
