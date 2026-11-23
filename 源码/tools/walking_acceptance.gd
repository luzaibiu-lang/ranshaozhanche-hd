extends SceneTree
class MovementHost extends Control:
	var view:Control
	var catalog:Dictionary
var options:Dictionary={}
var checks:=0
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair:=arg.trim_prefix("--").split("=",true,1);options[pair[0]]=pair[1]
	_run.call_deferred()
func verify(ok:bool,message:String) -> bool:
	if not ok:push_error(message);quit(2);return false
	checks+=1;return true
func _run() -> void:
	var packs:=OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file),false)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
	var images:Dictionary={}
	for name:String in fixture.profiles:
		var image:=Image.create(int(fixture.width),int(fixture.height),false,Image.FORMAT_RGBA8)
		for x in range(int(fixture.width)):
			var y:=int(fixture.profiles[name][x])
			if y<int(fixture.height):image.fill_rect(Rect2i(x,y,1,int(fixture.height)-y),Color(.3,.5,.2,1))
		images[name]=image
	var terrain:RefCounted=load("res://native_terrain.gd").new([])
	for sample:Dictionary in fixture.cases:
		terrain.image=images[str(sample.profile)]
		var vehicle:=9 if int(sample.footprint)==41 else 1
		var pose:Dictionary=terrain.walking_pose(vehicle,float(sample.x),float(sample.y),int(sample.direction))
		var expected:Dictionary=sample.expected
		if not verify(bool(pose.allowed)==bool(expected.allowed) and bool(pose.valid)==bool(expected.valid) and int(pose.x)==int(expected.x) and int(pose.y)==int(expected.y) and absf(float(pose.slope)-float(expected.slope))<.002,"original walking oracle %s %s: got%s expected%s"%[sample.profile,str([sample.x,sample.y,sample.direction,vehicle]),str(pose),str(expected)]):return
	# Render native tanks on a shallow and a steep step using the actual walker.
	var app:=MovementHost.new();root.add_child(app)
	app.catalog={"vehicles":[]}
	for i in range(30):app.catalog.vehicles.append({"move_cost":.1})
	app.view=load("res://world_view.gd").new();root.add_child(app.view);app.view.set_process(false);app.view.size=Vector2(1280,720)
	app.view.battle={"height":256}
	var walker:RefCounted=load("res://native_walk.gd").new(app)
	for direction in [-1,1]:
		for width in [15,41]:
			for step_height in [1,4,5,8,16,22,40]:
				var profile:PackedInt32Array=PackedInt32Array(fixture.profiles["step%d-%d"%[step_height,direction]])
				var start_x:=110 if direction>0 else 145
				app.view.terrain.image=images["step%d-%d"%[step_height,direction]];app.view.terrain_image=app.view.terrain.image
				walker.unit={"vehicle":9 if width==41 else 1,"hp":300,"sp":150,"move":150.0,"face":direction,"x":float(start_x),"y":float(profile[start_x]),"slope":0.0,"elevation":35,"falling":false}
				var before:Dictionary=walker.unit.duplicate(true)
				var moved:int=walker._move(direction*45)
				if not verify(moved>0 or width==41,"walking can approach obstacle without global lock"):return
				var stopped:Dictionary=walker.unit.duplicate(true);var again:int=walker._move(direction*45)
				if step_height>=16:
					if not verify(again==0 and int(walker.unit.sp)==int(stopped.sp) and is_equal_approx(float(walker.unit.move),float(stopped.move)),"blocked wall consumes no fuel/SP after stopping"):return
				if not verify(int(walker.unit.face)==direction,"blocked/allowed move retains requested facing"):return
	FileAccess.open(str(options.output).path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"checks":checks,"original_cases":fixture.cases.size(),"private_desktop":true,"audio_driver":"Dummy"}))
	print("WALKING_ACCEPTANCE "+str(checks));app.view.queue_free();app.queue_free();await process_frame;quit()
