extends Node
## Content-addressed packs: verify before mounting, coalesce requests, never
## let an incomplete download become a usable map or a persistent cache entry.
signal status_changed(message: String, failed: bool)

const CACHE := "user://web-packs"
const LIMIT := 160*1024*1024
var manifest := {}
var mounted := {}
var pending := {}
var active := 0
var enabled := false

func _ready() -> void:
	enabled = OS.has_feature("web") and FileAccess.file_exists("res://web-stream.json")
	if not enabled:return
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://web-stream.json"))
	DirAccess.make_dir_recursive_absolute(CACHE)
	_prune()
	_publish_state()

func has_group(key: String) -> bool:
	return manifest.get("groups",{}).has(key)

func is_loaded(key: String) -> bool:
	return not enabled or mounted.has(key)

func ensure_groups(keys: Array) -> bool:
	for key: String in keys:
		if not await ensure_group(key):return false
	return true

func ensure_group(key: String) -> bool:
	if not enabled or mounted.has(key):return true
	if not has_group(key):
		status_changed.emit("资源清单缺少 "+key,true)
		return false
	if pending.has(key):
		while pending.has(key):await get_tree().process_frame
		return mounted.has(key)
	pending[key]=true
	_publish_state()
	while active>=2:await get_tree().process_frame
	active+=1
	var spec: Dictionary=manifest.groups[key]
	var digest := str(spec.sha256)
	var destination := CACHE.path_join(digest+".pck")
	var ok := _valid(destination,spec)
	if not ok:
		for attempt in range(3):
			status_changed.emit("正在加载游戏资源…",false)
			var request := HTTPRequest.new()
			# Browser fetch already decodes Content-Encoding; avoid a second
			# gzip pass inside Godot while retaining nginx's static compression.
			request.accept_gzip=false
			request.timeout=90
			request.body_size_limit=int(spec.size)+1024
			add_child(request)
			var origin: String = JavaScriptBridge.get_interface("window").location.origin
			var started := request.request(origin+str(spec.url))
			if started==OK:
				var result: Array=await request.request_completed
				if int(result[0])==HTTPRequest.RESULT_SUCCESS and int(result[1])==200:
					var data: PackedByteArray=result[3]
					var hash := HashingContext.new()
					hash.start(HashingContext.HASH_SHA256)
					hash.update(data)
					if data.size()==int(spec.size) and hash.finish().hex_encode()==digest:
						_prune(data.size())
						var temporary := destination+".pending"
						var file := FileAccess.open(temporary,FileAccess.WRITE)
						if file:
							file.store_buffer(data)
							file.close()
							ok=DirAccess.rename_absolute(temporary,destination)==OK
			request.queue_free()
			if ok:break
			if attempt<2:await get_tree().create_timer(0.6*(attempt+1)).timeout
	if ok:ok=ProjectSettings.load_resource_pack(destination,false)
	if ok:mounted[key]=true
	else:status_changed.emit("资源加载失败，请检查网络后重试",true)
	active-=1
	pending.erase(key)
	_publish_state()
	return ok

func _publish_state() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("globalThis.BurningChariotResourceState="+JSON.stringify({"loaded":mounted.keys(),"pending":pending.keys()}),true)

func _valid(path: String,spec: Dictionary) -> bool:
	if not FileAccess.file_exists(path):return false
	var file := FileAccess.open(path,FileAccess.READ)
	if not file:return false
	var same_size := file.get_length()==int(spec.size)
	file.close()
	return same_size and FileAccess.get_sha256(path)==str(spec.sha256)

func _prune(incoming := 0) -> void:
	var keep := {}
	for spec: Dictionary in manifest.get("groups",{}).values():keep[str(spec.sha256)+".pck"]=true
	var total := 0
	var old: Array=[]
	var protected := {}
	for key: String in mounted:protected[str(manifest.groups[key].sha256)+".pck"]=true
	for name: String in DirAccess.get_files_at(CACHE):
		if name.ends_with(".pending"):
			DirAccess.remove_absolute(CACHE.path_join(name))
		elif name.ends_with(".pck"):
			var file := FileAccess.open(CACHE.path_join(name),FileAccess.READ)
			if not file:continue
			var size := file.get_length()
			file.close()
			total+=size
			if not protected.has(name):old.append({"name":name,"size":size,"time":FileAccess.get_modified_time(CACHE.path_join(name)),"current":keep.has(name)})
	old.sort_custom(func(a,b):return a.time<b.time if a.current==b.current else not a.current)
	for entry: Dictionary in old:
		if total+incoming<=LIMIT:break
		if DirAccess.remove_absolute(CACHE.path_join(str(entry.name)))==OK:total-=int(entry.size)
