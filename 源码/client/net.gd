extends RefCounted

var root: Node
var endpoint := "http://127.0.0.1:18180"
var token := ""
var etag := ""
var server_offset := 0.0
var request_sequence := 0
var closing := false
var pending := {}
var clock_ready:=false
var clock_anchor:=0.0
var clock_tick:=0.0
var last_clock_value:=0.0
var best_round_trip:=1000.0

func _init(host: Node) -> void:
	root = host

func request(path: String, payload: Variant = null, conditional := false) -> Dictionary:
	if closing:return {"error":"连接已关闭","status":0}
	request_sequence += 1
	var sequence := request_sequence
	var began:=Time.get_ticks_usec()/1000000.0
	var http := HTTPRequest.new()
	# Movement has a turn-bound, idempotent sequence and can be retried.
	# A lost acknowledgement must not hold all battle controls for ten seconds.
	http.timeout = 1.5 if payload is Dictionary and str(payload.get("action", "")) == "move" else 3.0 if path == "/api/state" else 10.0
	# HTTPRequest already polls nonblocking sockets on the main loop. Its
	# threaded mode uses blocking HTTPClient I/O; cancelling a timed-out request
	# then waits for that worker and can freeze input/rendering until its peer
	# finally replies. Keep all API requests nonblocking, including cancellation.
	http.use_threads = false
	configure_http(http)
	root.add_child(http)
	pending[http]=true
	var headers := PackedStringArray(["Accept: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	if conditional and not etag.is_empty():
		headers.append("If-None-Match: " + etag)
	var body := ""
	var method := HTTPClient.METHOD_GET
	if payload != null:
		if path == "/api/command" and payload is Dictionary:
			payload = payload.duplicate()
			payload.loading_barrier = true
		method = HTTPClient.METHOD_POST
		body = JSON.stringify(payload)
		headers.append("Content-Type: application/json; charset=utf-8")
	var error := http.request(endpoint.trim_suffix("/") + path, headers, method, body)
	if error != OK:
		pending.erase(http)
		http.queue_free()
		return {"error": "无法建立连接", "status": 0}
	var response: Array = await http.request_completed
	pending.erase(http)
	http.queue_free()
	var status := int(response[1])
	if status == 304:
		return {"unchanged": true, "status": status}
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "连接暂时中断，正在等待恢复", "status": 0}
	var decoder := JSON.new()
	if decoder.parse((response[3] as PackedByteArray).get_string_from_utf8()) != OK or not decoder.data is Dictionary:
		return {"error": "服务器返回了无法识别的数据", "status": status}
	var data: Dictionary = decoder.data
	data["_request_sequence"] = sequence
	data["status"] = status
	if status == 200 and conditional:
		for header: String in response[2]:
			if header.to_lower().begins_with("etag:"):
				etag = header.substr(5).strip_edges()
	if data.has("server_time"):
		_sync_clock(float(data.server_time),began,Time.get_ticks_usec()/1000000.0)
	return data

func configure_http(http: HTTPRequest) -> void:
	if OS.has_feature("web"):return
	if endpoint.begins_with("https://") and FileAccess.file_exists("res://hd-public.crt"):
		var certificate := X509Certificate.new()
		if certificate.load("res://hd-public.crt") == OK:
			http.set_tls_options(TLSOptions.client(certificate))

func shutdown() -> void:
	closing=true
	for http: HTTPRequest in pending.keys():
		http.cancel_request()
		http.request_completed.emit(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())

func server_now() -> float:
	if not clock_ready:return Time.get_unix_time_from_system()
	var value:=clock_anchor+Time.get_ticks_usec()/1000000.0-clock_tick
	last_clock_value=maxf(last_clock_value,value)
	return last_clock_value

func _sync_clock(stamp:float,sent:float,received:float) -> void:
	var round_trip:=received-sent
	best_round_trip=minf(best_round_trip,round_trip)
	var estimate:=stamp+round_trip/2
	if not clock_ready:
		clock_ready=true
		clock_anchor=estimate
		clock_tick=received
		last_clock_value=estimate
	elif round_trip<=best_round_trip+.1:
		var current:=clock_anchor+received-clock_tick
		# A late HTTP response cannot rewind or jump the animation clock.
		clock_anchor=current+clampf(estimate-current,-.004,.004)
		clock_tick=received
	server_offset=clock_anchor-Time.get_unix_time_from_system()
