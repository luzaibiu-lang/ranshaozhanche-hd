extends RefCounted
## Immediate local input; authoritative acknowledgements replay only unconfirmed
## steps. HTTP round-trip time never determines the tank's walking speed.
var app:Control
var unit:Dictionary={}
var base:Dictionary={}
var pending:Array[Dictionary]=[]
var sequence:=0
var in_flight:=false
var flight_sequence:=0
var request_serial:=0
var retry_after:=0
var recovering:=false
var flush_error:=""
var stamp:=""
var ticks:=0.0
var send_elapsed:=0.0
var direction:=0
var active:=false
var failed:=false
var moved_this_frame:=false
var since_step:=1.0

func _init(owner:Control) -> void:app=owner

func accept(battle:Dictionary) -> void:
	var current:Dictionary={}
	for participant:Dictionary in battle.get("units",[]):
		if int(participant.player)==int(app.profile.get("id",0)):current=participant
	var next_stamp:="%s:%s"%[battle.get("id",""),battle.get("generation",0)]
	if next_stamp!=stamp:
		_retire_request()
		stamp=next_stamp
		pending.clear()
		ticks=0
		failed=false
		retry_after=0
		sequence=int(current.get("move_sequence",0))
	active=not current.is_empty() and int(current.get("hp",0))>0 and int(current.get("seat",-1))==int(battle.get("active",-2)) and float(battle.get("deadline",0))>0 and not battle.get("result") is Dictionary
	if not active:
		direction=0
		pending.clear()
	base=current.duplicate(true)
	if failed and not in_flight:failed=false
	var acknowledged:=int(current.get("move_sequence",0))
	# State polling may acknowledge a move before its original HTTP reply.
	# Retire that reply now, including any late error, and release queued fire.
	if in_flight and acknowledged>=flight_sequence:_retire_request()
	pending=pending.filter(func(entry):return int(entry.sequence)==0 or int(entry.sequence)>acknowledged)
	_replay()

func _replay() -> void:
	unit=base.duplicate(true)
	if unit.is_empty():return
	for entry:Dictionary in pending:_move(int(entry.distance))

func _solid(x:int,y:int) -> bool:
	var image:Image=app.view.terrain_image
	return x>=0 and y>=0 and x<image.get_width() and y<image.get_height() and image.get_pixel(x,y).a>0

func _slope() -> float:
	var width:=41 if (int(unit.vehicle)-1)%10==8 else 15
	var half:=width/2
	var heights:Array[int]=[]
	var bottom:=int(float(unit.y))-1
	var height:int=app.view.terrain_image.get_height()
	for i in range(width):
		var x:=int(float(unit.x))-half+i
		var h:=height
		for y in range(bottom-1,bottom+width-width/4+1):
			if _solid(x,y):h=y;break
		var y:=bottom-2
		while y>=0 and _solid(x,y):h=y;y-=1
		heights.append(h)
	var left:=half
	var right:=half
	for i in range(half,-1,-1):
		if heights[i]<=heights[left]:left=i
	for i in range(half,width):
		if heights[i]<=heights[right]:right=i
	if heights[left]>=height or heights[right]>=height or left==right:return float(unit.get("slope",0))
	return float(int(-rad_to_deg(atan2(float(heights[right]-heights[left]),float(right-left)))))

func _move(distance:int) -> int:
	if unit.is_empty() or int(unit.hp)<=0 or int(unit.get("stun",0))>0:return 0
	var facing:=signi(distance)
	if facing==0:return 0
	unit.face=facing
	var cost:float=app.catalog.vehicles[int(unit.vehicle)-1].move_cost
	if bool(unit.get("economy",false)):cost*=.5
	var steps:=mini(absi(distance),mini(int(float(unit.move)),int(float(unit.sp)/cost)))
	var moved:=0
	for i in range(steps):
		var x:=float(unit.x)+facing
		var y:int=app.view.terrain.walking_ground(x,int(float(unit.y))-22)
		if absf(float(y)-float(unit.y))>24 or y>int(app.view.battle.height)-20:break
		var pose:Dictionary=app.view.terrain.walking_pose(int(unit.vehicle),float(unit.x),float(unit.y),facing,bool(unit.get("falling",false)))
		if not bool(pose.allowed) or (not bool(pose.valid) and float(pose.y)<=float(unit.y)):break
		unit.x=x
		unit.y=float(pose.y)
		unit.slope=float(int(pose.slope))
		moved+=1
	unit.move=float(unit.move)-moved
	var spent:=float(unit.get("move_spent",0))+moved*cost
	unit.sp=maxi(0,int(unit.sp)-int(spent))
	unit.move_spent=spent-int(spent)
	var elevation:float=unit.get("elevation",45)
	unit.aim=fposmod(float(unit.slope)+(180-elevation if facing<0 else elevation),360)
	return moved

func process(delta:float,wanted:int) -> void:
	moved_this_frame=false
	since_step+=delta
	send_elapsed+=delta
	direction=wanted if active and not failed else 0
	if direction==0:ticks=0
	else:
		# 00530740 initializes 1 pixel/tick; 005352f0/005354a0 slow
		# uphill steps by 1 + uphill_degrees / 65 * 2.5 at 60 Hz.
		var next:Dictionary=app.view.terrain.walking_pose(int(unit.vehicle),float(unit.x),float(unit.y),direction,bool(unit.get("falling",false)))
		var slope:=float(int(next.slope))
		if slope>180:slope-=360
		var uphill:=maxf(0,slope*direction)
		ticks+=minf(delta,.1)*60/(1+uphill/65*2.5)
		var unconfirmed:=0
		for entry:Dictionary in pending:unconfirmed+=absi(int(entry.distance))
		while ticks>=1 and unconfirmed<120:
			ticks-=1
			var old_face:=int(unit.face)
			var moved:=_move(direction)
			moved_this_frame=moved_this_frame or moved>0
			if moved>0:since_step=0
			if moved>0 or old_face!=direction:
				unconfirmed+=1
				if not pending.is_empty() and int(pending.back().sequence)==0 and signi(int(pending.back().distance))==direction and absi(int(pending.back().distance))<45:pending.back().distance+=direction
				else:pending.append({"sequence":0,"distance":direction})
			else:break
		if ticks>1:ticks=1
	moved_this_frame=direction!=0 and since_step<.05
	if failed and not recovering and Time.get_ticks_msec()>=retry_after:_recover()
	if not in_flight and not pending.is_empty() and (send_elapsed>=.08 or direction==0):_send()

func _retire_request() -> void:
	request_serial+=1
	in_flight=false
	flight_sequence=0

func _recover() -> void:
	if recovering or not active:return
	recovering=true
	var requested_stamp:=stamp
	# Force a full state: a conditional 304 cannot repair a failed local walk.
	var response:Dictionary=await app.net.request("/api/state")
	recovering=false
	if requested_stamp!=stamp or app.quitting or app.scene!="battle" or app.walker!=self:return
	if response.has("profile"):
		app._accept_state(response)
		if requested_stamp==stamp:retry_after=0
	else:retry_after=Time.get_ticks_msec()+1000

func _send() -> void:
	if in_flight or failed or pending.is_empty() or not active or Time.get_ticks_msec()<retry_after:return
	var entry:Dictionary=pending[0]
	if int(entry.sequence)==0:
		sequence+=1
		entry.sequence=sequence
	entry.attempts=int(entry.get("attempts",0))+1
	in_flight=true
	flight_sequence=int(entry.sequence)
	request_serial+=1
	var requested_serial:=request_serial
	send_elapsed=0
	var requested_stamp:=stamp
	var response:Dictionary=await app.net.request("/api/command",{"action":"move","distance":entry.distance,"move_sequence":entry.sequence,"generation":int(app._battle_data().get("generation",0))})
	if requested_serial!=request_serial or requested_stamp!=stamp or app.quitting or app.scene!="battle" or app.walker!=self:return
	in_flight=false
	flight_sequence=0
	if response.has("profile"):
		app._accept_state(response)
	elif response.has("error"):
		# Retry only movement, with the SAME sequence. Never replay fire/items.
		if int(response.get("status",0))==0 and int(entry.attempts)<2:
			retry_after=Time.get_ticks_msec()+150
			return
		failed=true
		direction=0
		pending.clear()
		unit=base.duplicate(true)
		app.toast(str(response.error))
		_recover()
	if not failed and not pending.is_empty():_send()

func flush() -> bool:
	direction=0
	flush_error=""
	if failed:
		flush_error="network"
		_recover()
		return false
	var started:=Time.get_ticks_msec()
	var requested_stamp:=stamp
	while active and (in_flight or not pending.is_empty()):
		if not in_flight:_send()
		if failed or requested_stamp!=stamp or Time.get_ticks_msec()-started>4000:
			flush_error="network" if failed else "turn" if requested_stamp!=stamp else "timeout"
			print("HD: movement confirmation ",flush_error," elapsed=",Time.get_ticks_msec()-started," flight=",in_flight," pending=",pending.size())
			return false
		await app.get_tree().process_frame
	return requested_stamp==stamp and not failed

func cancel() -> void:
	_retire_request()
	active=false
	direction=0
	pending.clear()
	ticks=0
	stamp="cancelled"
