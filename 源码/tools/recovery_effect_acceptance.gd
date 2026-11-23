extends SceneTree
## Exercise production recovery rendering with authoritative timestamps.
class FrozenClock extends RefCounted:
	var now := 100.0
	func server_now() -> float: return now

var clock := FrozenClock.new()
var view: Control
var checks: Array[String] = []
var options := {}
var sounds: Array = []

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(2)
		return false
	checks.append(message)
	return true

func fixture(id: String) -> Dictionary:
	var own := {"seat":0,"player":1,"name":"Recovery QA","team":0,"vehicle":1,"hp":300,"max_hp":300,"sp":150,"move":100.0,"face":1,"aim":35.0,"elevation":35.0,"slope":0.0,"falling":false,"shield":0,"stun":0,"stealth":0,"blind":0,"poison":0,"burn":0,"damage":0,"x":700.0,"y":806.0}
	var ally: Dictionary = own.duplicate(true)
	ally.seat=1; ally.player=2; ally.x=820.0
	var enemy: Dictionary = own.duplicate(true)
	enemy.seat=4; enemy.player=3; enemy.team=1; enemy.x=1050.0
	return {"id":id,"map":9,"width":1536,"height":1024,"native_aim":true,"active":0,"round":1,"generation":1,"wind":0,"deadline":135.0,"units":[own,ally,enemy],"holes":[],"shot":null,"result":null}

func cue(id: int, seat: int, enabled: bool = true) -> Dictionary:
	return {"id":id,"at":100.0,"seat":seat,"x":700.0+120.0*seat,"y":806.0,"amount":40,"fuel":false,"item_effect":enabled}

func present(data: Dictionary, at: float) -> void:
	clock.now=at
	view.set_battle(data)
	view.overview=0; view.manual_until=10000
	view.camera=Vector2(780,690); view.target_camera=view.camera
	view.zoom=1.5; view.zoom_target=1.5
	view._process(0)
	view.recovery_layer._process(0)

func capture(name: String) -> void:
	view.queue_redraw(); view.overlay.queue_redraw()
	view.recovery_layer.queue_redraw(); view.recovery_layer.normal_layer.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(options.output).path_join(name+".png"))

func samples(name: String) -> Array:
	return view.recovery_layer.visible_samples().filter(func(sample: Dictionary) -> bool: return str(sample.effect)==name)

func _run() -> void:
	var packs := OS.get_executable_path().get_base_dir().path_join("packs")
	if DirAccess.dir_exists_absolute(packs):
		for file in DirAccess.get_files_at(packs):
			if file.ends_with(".pck"): ProjectSettings.load_resource_pack(packs.path_join(file),false)
	root.size=Vector2i(1366,768)
	view=load("res://world_view.gd").new()
	view.player_id=1; view.clock=clock; view.shake_enabled=false
	root.add_child(view)
	view.set_process(false); view.size=Vector2(1366,768)
	view.effect.connect(func(kind: String, detail: int): sounds.append([kind,detail]))
	for child in view.get_children(): child.set_process(false)
	var data := fixture("supply-full-health")
	data.supplies=[cue(1,0)]
	present(data,100.001)
	if not check(samples("Effect30").size()==1 and samples("Effect54").size()==20,"full-health supply still creates the native ring and twenty sparks"): return
	var ring: Dictionary=samples("Effect30")[0]
	if not check(ring.frame==0 and is_equal_approx(ring.scale,1.6) and ring.position==Vector2(700,806),"ring starts at the authoritative tank position at native scale"): return
	var pivot: Array=view.recovery_layer.sequences.Effect30[0].pivot
	if not check(view.recovery_layer.sequences.Effect30.size()==10 and Vector2(pivot[0],pivot[1])==Vector2(49,73),"ring uses all ten original frames and their original pivots"): return
	var initial: Array=samples("Effect54").duplicate(true)
	await capture("supply-frame-0")
	present(data,100.101)
	if not check(view.recovery_layer.bursts.size()==1 and samples("Effect30")[0].frame==1,"repeat polling retains one burst and advances five-tick ring frames"): return
	var advanced: Array=samples("Effect54")
	var native_spark: Dictionary=view.recovery_layer.bursts[0].sparks[0]
	var native_travel := sin(deg_to_rad(6.06 * float(native_spark.speed))) * float(native_spark.distance)
	if not check(is_equal_approx(float(advanced[0].position.y),806.0+float(native_spark.offset.y)-native_travel),"supply sparks use the native sine-eased rise"): return
	for index in range(advanced.size()):
		if not check(advanced[index].position.y<initial[index].position.y and advanced[index].scale<initial[index].scale and advanced[index].alpha<initial[index].alpha,"spark %d rises, shrinks and fades" % index): return
	await capture("supply-frame-1")
	present(data,100.79)
	if not check(samples("Effect30")[0].frame==9,"ring reaches its final native frame"): return
	present(data,100.86)
	if not check(samples("Effect30").is_empty() and not samples("Effect54").is_empty(),"ring ends while surviving sparks continue"): return
	present(data,103.1)
	if not check(view.recovery_layer.visible_samples().is_empty() and view.recovery_layer.bursts.is_empty(),"expired supply leaves no retained particles"): return
	data=fixture("team-supply"); data.supplies=[cue(1,0),cue(2,1,false)]
	present(data,100.1)
	if not check(view.supply_numbers.size()==2 and view.recovery_layer.bursts.size()==1,"team supply shows each recipient's number and only the user's item burst"): return
	await capture("team-supply")
	data=fixture("fuel"); var fuel := cue(1,0); fuel.fuel=true; data.supplies=[fuel]
	present(data,100.1)
	if not check(view.recovery_layer.visible_samples().is_empty() and view.supply_numbers.size()==1,"fuel keeps its own feedback without a healing ring"): return
	data=fixture("hidden-enemy"); data.units[2].stealth=2; data.supplies=[cue(1,4)]
	present(data,100.1)
	if not check(view.recovery_layer.visible_samples().is_empty() and view.supply_numbers.is_empty(),"recovery cannot reveal an invisible enemy"): return
	data=fixture("late-supply"); data.supplies=[cue(1,0)]
	present(data,102.1)
	if not check(samples("Effect30").is_empty() and not samples("Effect54").is_empty(),"late snapshots resume surviving sparks without replaying the ring"): return
	data=fixture("stale-supply"); data.supplies=[cue(1,0)]
	present(data,110.0)
	if not check(view.recovery_layer.visible_samples().is_empty(),"stale snapshots do not restart healing effects"): return
	data=fixture("future-supply"); data.supplies=[cue(1,0)]
	present(data,99.9)
	if not check(view.recovery_layer.visible_samples().is_empty(),"future healing does not draw before its timestamp"): return
	present(data,100.1)
	if not check(samples("Effect30").size()==1,"future healing appears at the correct time"): return
	data=fixture("healing-projectile"); data.deadline=0.0
	data.shot={"id":1,"started":100.0,"duration":3.0,"hole_base":0,"cuts":[],"trails":[],"impacts":[{"at":0.5,"x":700,"y":806,"radius":50,"kind":"heal","projectile":60}]}
	sounds.clear(); present(data,100.6)
	if not check(samples("Effect03").size()==20 and view.explosions.is_empty() and view.particles.is_empty() and is_zero_approx(view.shake),"healing impact uses twenty native scatter particles without destructive debris or shake"): return
	if not check(sounds==[["native",56]],"healing impact emits the original recovery sound once"): return
	var scatter: Array=samples("Effect03").duplicate(true)
	for sample: Dictionary in scatter:
		if not check(sample.frame>=0 and sample.frame<=4 and sample.additive==(sample.frame!=4),"recovery scatter preserves native frame-specific blending"): return
	present(data,100.6)
	if not check(view.recovery_layer.impacts.size()==1 and sounds.size()==1 and samples("Effect03")==scatter,"repeat impact snapshot does not duplicate visual or sound"): return
	await capture("healing-impact")
	present(data,100.8)
	for index in range(scatter.size()):
		if not check(samples("Effect03")[index].frame==scatter[index].frame and samples("Effect03")[index].alpha<scatter[index].alpha,"scatter %d retains its selected sprite and fades over time" % index): return
	data.id="stale-impact"; sounds.clear(); present(data,103.2)
	if not check(samples("Effect03").is_empty() and sounds.is_empty(),"late healing impact emits neither fresh particles nor sound"): return
	data=fixture("rescue-item"); present(data,100.0); sounds.clear()
	view.explode(Vector2(700,806),50,"heal",105,0.0)
	if not check(samples("Effect03").size()==20 and sounds==[["native",56]],"dedicated rescue item receives recovery feedback rather than an orange explosion"): return
	for dimensions in [Vector2i(960,600),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=dimensions; view.size=Vector2(dimensions)
		data=fixture("layout-%s" % dimensions); data.supplies=[cue(1,0)]
		present(data,100.1)
		await capture("recovery-%dx%d" % [dimensions.x,dimensions.y])
		if not check(samples("Effect30").size()==1 and Rect2(Vector2.ZERO,Vector2(dimensions)).has_point(view.screen(Vector2(700,806))),"recovery remains anchored and visible at %s" % dimensions): return
	data=fixture("same-map-restart"); present(data,101.0)
	if not check(view.recovery_layer.bursts.is_empty() and view.recovery_layer.impacts.is_empty() and view.recovery_layer.visible_samples().is_empty(),"new match on the same map clears all recovery effects"): return
	print("RECOVERY_EFFECT_ACCEPTANCE "+JSON.stringify({"checks":checks,"private_desktop":true,"silent":true,"no_accounts_created":true}))
	quit()
