extends RefCounted

signal state_received(state: Dictionary)
signal session_invalidated(state: Dictionary)
var rejected_session := ""
var root: Node
var endpoint := "http://127.0.0.1:18180"
var token := ""
var etag := ""
var server_offset := 0.0
var request_sequence := 0
var closing := false
var pending := {}
var clock_ready := false
var clock_anchor := 0.0
var clock_tick := 0.0
var last_clock_value := 0.0
var best_round_trip := 1000.0
var socket: WebSocketPeer
var socket_token := ""
var socket_ready := false
var socket_began := 0
var socket_retry := 0
var socket_ping := 0
var socket_last_packet := 0
var stream_replies := {}
var stream_waiting := {}
var last_success := 0
var consecutive_failures := 0
var rtt_ms := 250.0
var last_failure := ""
var tls_options: TLSOptions
var tls_endpoint := ""
var receipt_prefix := Crypto.new().generate_random_bytes(12).hex_encode()
var cached_battle := ""
var cached_shot := -1
var shot_cache: Dictionary = {}
var enabled := false
var resume_busy := false
var lifetime_successes := 0
var stream_packets := 0
var stream_bytes := 0

func _init(host: Node) -> void:
 root = host
 root.get_tree().process_frame.connect(_pump)

func request(path: String, payload: Variant = null, conditional := false) -> Dictionary:
 if closing:return {"error":"连接已关闭", "status":0}
 request_sequence += 1
 var sequence := request_sequence
 if payload is Dictionary and path == "/api/command":
  payload = payload.duplicate()
  payload.loading_barrier = true
  if not payload.has("request_id"):payload.request_id = "%s-%d" % [receipt_prefix, sequence]
 if not token.is_empty() and path in ["/api/state", "/api/command"]:
  enabled = true
  var start := Time.get_ticks_msec()
  while not socket_ready and Time.get_ticks_msec()-start < 1200 and not closing:
   if socket_retry > Time.get_ticks_msec():break
   await root.get_tree().process_frame
  if socket_ready:
   var result := await _stream_request(path, payload, conditional, sequence)
   if not bool(result.get("_fallback", false)):return result
 return await _http_request(path, payload, conditional, sequence)

func _timeout(path: String, payload: Variant) -> float:
 if payload is Dictionary and str(payload.get("action", "")) == "move":return clampf(2.5+rtt_ms/1000*3, 2.5, 6)
 if path == "/api/state":return clampf(4+rtt_ms/1000*4, 4, 10)
 return clampf(10+rtt_ms/1000*3, 10, 15)

func _stream_request(path: String, payload: Variant, conditional: bool, sequence: int) -> Dictionary:
 var id := str(sequence)
 var began := Time.get_ticks_usec()/1000000.0
 var session := token
 var frame := {"id":id, "path":path, "payload":payload, "conditional":conditional, "etag":etag}
 stream_waiting[id] = true
 if socket.send_text(JSON.stringify(frame)) != OK:
  stream_waiting.erase(id)
  return {"_fallback":true}
 var until := Time.get_ticks_msec()+int(_timeout(path, payload)*1000)
 while not closing and token == session and socket_ready and Time.get_ticks_msec() < until:
  if stream_replies.has(id):break
  await root.get_tree().process_frame
 stream_waiting.erase(id)
 if stream_replies.has(id):
  var reply: Dictionary = stream_replies[id]
  stream_replies.erase(id)
  return _decode_stream(reply, sequence, began)
 # The SAME request_id goes through REST. A server receipt resolves an
 # ambiguous lost reply without executing fire/items/chat a second time.
 if token != session or closing:return {"error":"连接已关闭", "status":0}
 _drop_stream()
 return {"_fallback":true}

func _decode_stream(reply: Dictionary, sequence: int, began: float) -> Dictionary:
 var status := int(reply.get("status", 0))
 var data: Dictionary = reply.get("data", {})
 data.status = status
 data._request_sequence = sequence
 if status == 401:_session_error(data)
 if reply.has("etag") and not str(reply.etag).is_empty():etag = str(reply.etag)
 if status == 304:data.unchanged = true
 if status > 0:
  _success()
  if began > 0:rtt_ms = lerpf(rtt_ms, maxf(.001, Time.get_ticks_usec()/1000000.0-began)*1000, .15)
 if data.has("server_time"):
  var now := Time.get_ticks_usec()/1000000.0
  _sync_clock(float(data.server_time), began if began > 0 else now, now)
 if not _restore_shot(data):return {"error":"正在恢复战斗同步", "status":0, "recoverable":true}
 return data

func _restore_shot(data: Dictionary) -> bool:
 var room: Variant = data.get("room")
 if not room is Dictionary:return true
 var battle: Variant = room.get("battle")
 if not battle is Dictionary:return true
 var id := str(battle.get("id", ""))
 if battle.get("shot_ref") is Dictionary:
  var reference: Dictionary = battle.shot_ref
  if str(reference.get("battle_id", "")) != cached_battle or int(reference.get("shot_id", -1)) != cached_shot or shot_cache.is_empty():
   _drop_stream()
   return false
  battle.shot = shot_cache
 elif battle.get("shot") is Dictionary:
  cached_battle = id
  cached_shot = int(battle.shot.id)
  shot_cache = battle.shot
  if socket_ready:socket.send_text(JSON.stringify({"type":"cache", "battle_id":id, "shot_id":cached_shot}))
 elif cached_battle != id:
  cached_battle = id
  cached_shot = -1
  shot_cache = {}
 return true

func _pump() -> void:
 if closing:return
 var now := Time.get_ticks_msec()
 if socket and socket_token != token:
  _drop_stream()
  socket_retry = 0
  enabled = false
 if token.is_empty() or not enabled:return
 if not socket:
  if now < socket_retry:return
  socket = WebSocketPeer.new()
  socket.inbound_buffer_size = 8*1024*1024
  socket.max_queued_packets = 128
  socket_token = token
  socket_began = now
  socket_last_packet = now
  var url := endpoint.replace("https://", "wss://").replace("http://", "ws://").trim_suffix("/")+"/api/stream"
  var error := socket.connect_to_url(url, null if OS.has_feature("web") else _tls())
  if error != OK:_drop_stream();return
 socket.poll()
 var status := socket.get_ready_state()
 if status == WebSocketPeer.STATE_CLOSED or now-socket_last_packet > 16000 or not socket_ready and now-socket_began > 8000:
  _drop_stream()
  return
 if status != WebSocketPeer.STATE_OPEN:return
 if not socket.has_meta("authenticated"):
  socket.set_meta("authenticated", true)
  socket.send_text(JSON.stringify({"id":"auth", "type":"auth", "token":token}))
 while socket and socket.get_available_packet_count() > 0:
  var packet := socket.get_packet()
  stream_packets += 1
  stream_bytes += packet.size()
  socket_last_packet = now
  var decoded: Variant = JSON.parse_string(packet.get_string_from_utf8())
  if not decoded is Dictionary:continue
  var id := str(decoded.get("id", ""))
  if id == "auth":
   if int(decoded.get("status",0)) == 200:
    socket_ready = true
    socket_ping = now
    _success()
   else:
    var rejection: Dictionary = decoded.get("data", {})
    rejection.status = int(decoded.get("status",401))
    _session_error(rejection)
    _drop_stream()
   continue
  if not socket_ready:continue
  if id == "heartbeat":
   _success()
   continue
  if not id.is_empty() and stream_waiting.has(id):stream_replies[id] = decoded
  elif id.is_empty():
   var data := _decode_stream(decoded, request_sequence, 0)
   if data.has("profile") or int(data.get("status",0)) == 401:state_received.emit(data)
 if socket_ready and now-socket_ping >= 5000:
  socket_ping = now
  socket.send_text(JSON.stringify({"id":"heartbeat", "type":"ping"}))

func _drop_stream() -> void:
 if socket:socket.close()
 socket = null
 socket_ready = false
 socket_retry = Time.get_ticks_msec()+3000
 # A new socket requires a full shot before agreeing to cache references.
 cached_battle = ""
 cached_shot = -1
 shot_cache = {}

func resume() -> void:
 etag = ""
 if token.is_empty() or not enabled or resume_busy:return
 if Time.get_ticks_msec()-socket_last_packet > 8000:
  _drop_stream()
  socket_retry = 0
 _resume_state()

func _resume_state() -> void:
 resume_busy = true
 var session := token
 var data := await request("/api/state")
 resume_busy = false
 if token == session and data.has("profile"):state_received.emit(data)

func stream_active() -> bool:
 return socket_ready and Time.get_ticks_msec()-socket_last_packet < 12000

func _success() -> void:
 last_success = Time.get_ticks_msec()
 consecutive_failures = 0
 lifetime_successes += 1

func _failure(kind: String) -> void:
 consecutive_failures += 1
 last_failure = kind

func health() -> Dictionary:
 var age := Time.get_ticks_msec()-last_success if last_success > 0 else 0
 return {"transport":"websocket" if stream_active() else "http", "silent_ms":age, "failures":consecutive_failures, "rtt_ms":roundi(rtt_ms), "last_failure":last_failure,"successes":lifetime_successes,"stream_packets":stream_packets,"stream_bytes":stream_bytes}

func _http_request(path: String, payload: Variant, conditional: bool, sequence: int) -> Dictionary:
 var began := Time.get_ticks_usec()/1000000.0
 var session := token
 var http := HTTPRequest.new()
 http.timeout = _timeout(path, payload)
 http.use_threads = false
 # Browsers decode gzip themselves; native HTTPRequest decodes it once.
 http.accept_gzip = not OS.has_feature("web")
 configure_http(http)
 root.add_child(http)
 pending[http] = true
 var headers := PackedStringArray(["Accept: application/json"])
 if not token.is_empty():headers.append("Authorization: Bearer "+token)
 if conditional and not etag.is_empty():headers.append("If-None-Match: "+etag)
 var body := ""
 var method := HTTPClient.METHOD_GET
 if payload != null:
  method = HTTPClient.METHOD_POST
  body = JSON.stringify(payload)
  headers.append("Content-Type: application/json; charset=utf-8")
 var error := http.request(endpoint.trim_suffix("/")+path, headers, method, body)
 if error != OK:
  pending.erase(http)
  http.queue_free()
  _failure("connect")
  return {"error":"连接暂时不稳定，正在恢复", "status":0,"network_error":"connect","recoverable":true}
 var response: Array = await http.request_completed
 pending.erase(http)
 http.queue_free()
 if session != token:return {"error":"会话已切换", "status":0}
 var status := int(response[1])
 if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
  _failure("transport_%d" % int(response[0]))
  return {"error":"连接暂时不稳定，正在恢复", "status":0,"network_error":last_failure,"recoverable":true}
 _success()
 rtt_ms = lerpf(rtt_ms, (Time.get_ticks_usec()/1000000.0-began)*1000, .15)
 if status == 304:return {"unchanged":true,"status":status}
 var decoder := JSON.new()
 if decoder.parse((response[3] as PackedByteArray).get_string_from_utf8()) != OK or not decoder.data is Dictionary:
  _failure("invalid_response")
  return {"error":"服务器返回了无法识别的数据", "status":status}
 var data: Dictionary = decoder.data
 data._request_sequence = sequence
 data.status = status
 if status == 401:_session_error(data)
 if status == 200 and conditional:
  for header: String in response[2]:
   if header.to_lower().begins_with("etag:"):etag = header.substr(5).strip_edges()
 if data.has("server_time"):_sync_clock(float(data.server_time), began, Time.get_ticks_usec()/1000000.0)
 return data

func _session_error(data: Dictionary) -> void:
 if int(data.get("status",0)) != 401 or token.is_empty() or rejected_session == token:return
 rejected_session = token
 session_invalidated.emit(data)

func clear_session() -> void:
 token = ""
 etag = ""
 enabled = false
 _drop_stream()
 stream_replies.clear()

func _tls() -> TLSOptions:
 if endpoint != tls_endpoint:
  tls_endpoint = endpoint
  tls_options = null
  if endpoint.begins_with("https://") and FileAccess.file_exists("res://hd-public.crt"):
   var certificate := X509Certificate.new()
   if certificate.load("res://hd-public.crt") == OK:tls_options = TLSOptions.client(certificate)
 return tls_options

func configure_http(http: HTTPRequest) -> void:
 if OS.has_feature("web"):return
 var options := _tls()
 if options:http.set_tls_options(options)

func shutdown() -> void:
 closing = true
 _drop_stream()
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
