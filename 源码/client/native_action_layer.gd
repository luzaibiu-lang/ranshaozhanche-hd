extends Node2D
## Original OVER DRIVE (00508900/00508c90) and TargetMark (00532210).
## Every event uses the published shared shot clock, including late snapshots.
var world:Control
var sound_stamp:=""
var consumed:Dictionary={}
var letter_frames:Array=[]
var marker_frame:Dictionary={}
const LETTERS:=[0,1,2,3,4,3,5,1,2]

func _ready() -> void:
	letter_frames=JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/OverDrive/frames.json"))
	var markers:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/TargetMark/frames.json"))
	marker_frame=markers[0]
	for frame:Dictionary in letter_frames:world.texture("res://assets/effects/OverDrive/"+str(frame.file))
	world.texture("res://assets/effects/TargetMark/"+str(marker_frame.file))

func _process(_delta:float) -> void:
	if not world or not world.clock or world.battle.is_empty():return
	var shot:Variant=world.battle.get("shot")
	if not shot is Dictionary:return
	var stamp:=str(world.battle.get("id",""))+":"+str(shot.id)
	if stamp!=sound_stamp:
		sound_stamp=stamp
		consumed.clear()
	var now:float=world.clock.server_now()
	if bool(shot.get("overdrive",false)):
		var prepared:=float(shot.get("prepared",float(shot.started)-190.0/60))
		for tick in range(0,170,10):
			_cue("overdrive:%d"%tick,57 if tick<100 else 58,now-prepared-float(tick)/60)
		_cue("overdrive:171",59,now-prepared-171.0/60)
	for index in range(shot.get("cues",[]).size()):
		var cue:Dictionary=shot.cues[index]
		if str(cue.kind)=="lock":_cue("lock:%d"%index,54,now-float(shot.started)-float(cue.at),.6)
		if str(cue.kind)=="shield_hit":_cue("shield:%.6f"%float(cue.at),63,now-float(shot.started)-float(cue.at))
	queue_redraw()

func _cue(key:String,id:int,age:float,window:=.25) -> void:
	if age<-.000001 or consumed.has(key):return
	consumed[key]=true
	# Do not replay a queue of stale effects after reconnect or a long frame.
	if age<=window:world.effect.emit("native",id)

func overdrive_letters(shot:Dictionary,now:float) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not bool(shot.get("overdrive",false)):return result
	var age:=now-float(shot.get("prepared",float(shot.started)-190.0/60))
	var tick:=int(floor(age*60+.0001))
	if age<0 or tick>=190:return result
	var actor:Dictionary={}
	for unit:Dictionary in world.battle.get("units",[]):
		if int(unit.seat)==int(shot.actor):actor=unit;break
	if actor.is_empty():return result
	var origin:=Vector2(float(actor.x),float(actor.y))
	var upper_width:=0.0
	var lower_width:=0.0
	for index in range(9):
		var frame:Dictionary=letter_frames[LETTERS[index]]
		var x:=upper_width-150 if index<4 else lower_width-50
		var fast_ticks:=maxi(0,tick-169)
		var drift:=mini(tick+1,170)*.5+fast_ticks*15
		x+=drift if index<4 else -drift
		var at:=origin+Vector2(x,-150 if index<4 else -100)
		if index<4:
			upper_width+=float(frame.size[0])+(10 if index==0 else 0)
		else:
			lower_width+=float(frame.size[0])+(8 if index==6 else 0)
		if tick<index*10:continue
		# 00508bc0 updates each active letter after the phase transition.
		var letter_age:=tick-index*10+1
		var letter_scale:=1.0+12.0*maxf(0,1-letter_age/10.0)
		var alpha:=minf(.7,letter_age*.01)
		if fast_ticks>0:alpha=maxf(.01,.7-fast_ticks*.04)
		var emphasis:=tick>=100 and tick<170 and tick%2==0
		result.append({"frame":LETTERS[index],"position":at,"alpha":alpha,"scale":letter_scale,"emphasis":emphasis})
	return result

func active_marks(shot:Dictionary,now:float) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var latest:Dictionary={}
	for cue:Dictionary in shot.get("cues",[]):
		var age:=now-float(shot.started)-float(cue.at)
		if str(cue.kind)!="lock" or age<-.000001 or age>=3:continue
		latest[int(cue.seat)]={"cue":cue,"age":age}
	for seat:int in latest:
		var cue:Dictionary=latest[seat].cue
		var at:=Vector2(float(cue.x),float(cue.y))
		for unit:Dictionary in world.battle.get("units",[]):
			if int(unit.seat)==seat:at=Vector2(float(unit.x),float(unit.y));break
		result.append({"seat":seat,"position":at,"alpha":clampf(3-float(latest[seat].age),0,1)})
	return result

func _draw() -> void:
	if not world or not world.clock or world.battle.is_empty():return
	var shot:Variant=world.battle.get("shot")
	if not shot is Dictionary:return
	var now:float=world.clock.server_now()
	for letter:Dictionary in overdrive_letters(shot,now):
		var frame:Dictionary=letter_frames[int(letter.frame)]
		var sprite:Texture2D=world.texture("res://assets/effects/OverDrive/"+str(frame.file))
		var tint:=Color(1,1,1,float(letter.alpha))
		# 00508620 flashes the actual letters red during the native second phase.
		if bool(letter.emphasis):tint=Color(1,0,0,float(letter.alpha))
		draw_set_transform(world.screen(letter.position),0,Vector2.ONE*world.zoom*float(letter.scale))
		draw_texture(sprite,-Vector2(float(frame.pivot[0]),float(frame.pivot[1])),tint)
	for mark:Dictionary in active_marks(shot,now):
		var sprite:Texture2D=world.texture("res://assets/effects/TargetMark/"+str(marker_frame.file))
		draw_set_transform(world.screen(mark.position),0,Vector2.ONE*world.zoom)
		draw_texture(sprite,-Vector2(float(marker_frame.pivot[0]),float(marker_frame.pivot[1])),Color(1,1,1,float(mark.alpha)))
	draw_set_transform(Vector2.ZERO)
