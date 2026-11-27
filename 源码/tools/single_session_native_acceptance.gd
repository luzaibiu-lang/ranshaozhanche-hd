extends SceneTree
var options := {}
var app: Node
func _initialize() -> void:
 AudioServer.set_bus_mute(0, true)
 for value in OS.get_cmdline_user_args():
  if "=" in value:
   var parts := value.trim_prefix("--").split("=", true, 1)
   options[parts[0]] = parts[1]
 OS.set_environment("LOCALAPPDATA", str(options.profile))
 OS.set_environment("BCHD_VAULT_ROOT", str(options.profile).path_join("vault"))
 _run.call_deferred()
func wait_for(condition: Callable, seconds := 25.0) -> bool:
 var deadline := Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await create_timer(.1).timeout
 print("SINGLE_SESSION scene=",app.scene," catalog=",app.catalog_ready," token=",not app.net.token.is_empty()," auth_busy=",app.auth_busy," notice=",app.login_page.notice.text if is_instance_valid(app.login_page) else "none")
 if is_instance_valid(app):root.get_texture().get_image().save_png(str(options.output).path_join("native-failure.png"))
 push_error("single session condition timed out")
 quit(2)
 return false
func click(control: Control) -> void:
 var point := control.get_global_rect().get_center()
 for down in [true, false]:
  var event := InputEventMouseButton.new()
  event.position = point
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = down
  root.push_input(event)
  await process_frame
func _run() -> void:
 var packs := OS.get_executable_path().get_base_dir().path_join("packs")
 for file in DirAccess.get_files_at(packs):
  if file.ends_with(".pck"):ProjectSettings.load_resource_pack(packs.path_join(file), false)
 var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(options.fixture)))
 app = load("res://main.gd").new()
 root.add_child(app)
 app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 if not await wait_for(func():return app.catalog_ready and app.scene=="login"):return
 app.username.text = str(fixture.name)
 app.password.text = str(fixture.password)
 await click(app.login_page.submit)
 if not await wait_for(func():return app.scene=="channel" and is_instance_valid(app.channel_gate) and app.channel_gate.phase=="select"):return
 await click(app.channel_gate.row)
 await click(app.channel_gate.enter_button)
 if not await wait_for(func():return app.scene=="lobby" and not is_instance_valid(app.channel_gate)):return
 if not await app._command({"action":"create","name":"native-exclusive-qa","map":4}):
  push_error("native room creation failed");quit(3);return
 if not await wait_for(func():return app.scene=="room"):return
 var ready := FileAccess.open(str(options.ready), FileAccess.WRITE)
 ready.store_string(JSON.stringify({"ready":true,"room":int(app.snapshot.room.id)}))
 ready.close()
 if not await wait_for(func():return app.scene=="login" and app.net.token.is_empty() and not app.auth_busy, 90):return
 if not str(app.login_page.notice.text).contains("其他地方登录"):
  push_error("native login replacement reason missing");quit(4);return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(str(options.output).path_join("native-replaced.png"))
 var report := FileAccess.open(str(options.output).path_join("native-result.json"), FileAccess.WRITE)
 report.store_string(JSON.stringify({"passed":true,"actual_windows_release":true,"private_desktop":true,"audio":"Dummy","forced_login_scene":true,"cleared_session":true,"replacement_notice":true}))
 report.close()
 await app._quit()
