extends SceneTree
var frames := 0
func _initialize() -> void:
 AudioServer.set_bus_mute(0, true)
 process_frame.connect(func(): frames += 1)
 _run.call_deferred()
func _run() -> void:
 var host := Node.new()
 root.add_child(host)
 var net = load("res://net.gd").new(host)
 var origin := OS.get_cmdline_user_args()[0]
 net.endpoint = origin
 net.token = "a".repeat(64)
 net.socket_retry = Time.get_ticks_msec()+100000
 net.consecutive_failures = 5
 var response: Dictionary = await net.request("/api/state", null, true)
 if int(response.get("status",0)) != 304 or net.consecutive_failures != 0:
  push_error("304 did not repair health");quit(2);return
 var healthy: int = net.last_success
 net.rtt_ms = 0
 net.endpoint = origin + "/slow"
 var before: int = frames
 response = await net.request("/api/state")
 if int(response.get("status",200)) != 0 or not bool(response.get("recoverable",false)) or net.consecutive_failures != 1 or frames-before < 30:
  push_error("timeout blocked frames or lost health classification");quit(3);return
 net.endpoint = origin
 response = await net.request("/api/state", null, true)
 if int(response.get("status",0)) != 304 or net.consecutive_failures != 0 or net.last_success <= healthy:
  push_error("successful 304 did not reset timeout history");quit(4);return
 net.endpoint = "http://127.0.0.1:18180"
 var first: TLSOptions = net._tls()
 if first == null or first != net._tls():
  push_error("certificate cache was not reused");quit(5);return
 net.shutdown()
 print("TRANSPORT029 " + JSON.stringify({"passed":true,"checks":4,"frames_during_timeout":frames-before,"http_304_clears_failure_history":true,"certificate_reused":true}))
 quit()
