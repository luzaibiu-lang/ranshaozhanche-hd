extends SceneTree
var app: Node
var opts := {}
func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=",true,1)
		if pair.size()==2:opts[pair[0]]=pair[1]
	OS.set_environment("LOCALAPPDATA",str(opts.output).path_join("profile"))
	_run.call_deferred()
func _run() -> void:
	var bootstrap: Node = load("res://bootstrap.tscn").instantiate()
	root.add_child(bootstrap)
	await process_frame
	app = bootstrap.get_child(0)
	for i in range(100):
		if app.catalog_loading:break
		await create_timer(.05).timeout
	if not app.catalog_loading:quit(2);return
	app.net.endpoint = str(opts.next)
	app._reset_catalog()
	if not await app._load_catalog():quit(3);return
	await create_timer(4).timeout
	if not app.catalog_ready or app.catalog_origin != str(opts.next) or app.catalog.vehicles[0].name != "烈火":quit(4);return
	FileAccess.open(str(opts.output).path_join("switch.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":true,"late_old_response_ignored":true,"new_catalog_preserved":true}))
	await app._quit()
