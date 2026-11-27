extends RefCounted

const WEB_SESSION := "burningchariot.hd.session"
static var web_font: Font
static var full_font_ready := false
static var full_font_loading := false

static func mobile_ui() -> bool:
	if OS.has_feature("web"):
		if not bool(JavaScriptBridge.eval("typeof globalThis.BurningChariotDevice === 'object'", true)):
			JavaScriptBridge.eval(FileAccess.get_file_as_string("res://device_profile.js"), true)
		return bool(JavaScriptBridge.eval("globalThis.BurningChariotDevice.mobile === true", true))
	return OS.get_name() in ["Android", "iOS"]

static func endpoint(config: Dictionary) -> String:
	if OS.has_feature("web"):
		var origin: String = JavaScriptBridge.get_interface("window").location.origin
		return origin + "/hd-api"
	return str(config.get("endpoint", "http://127.0.0.1:18180"))

static func browser_session(mode: String, token := "") -> String:
	# Browsers with storage disabled can still sign in for this page lifetime.
	var key := JSON.stringify(WEB_SESSION)
	var script := ""
	match mode:
		"read":
			script = "return sessionStorage.getItem(%s) || localStorage.getItem(%s) || ''" % [key, key]
		"write", "tab", "clear":
			script = "sessionStorage.removeItem(%s); localStorage.removeItem(%s);" % [key, key]
			if mode != "clear":
				var storage := "localStorage" if mode == "write" else "sessionStorage"
				script += "%s.setItem(%s,%s);" % [storage, key, JSON.stringify(token)]
		_:
			return ""
	var result: Variant = JavaScriptBridge.eval("(function(){try{%s}catch(e){} return ''})()" % script, true)
	return str(result) if result is String else ""

static func ui_font() -> Font:
	if OS.has_feature("web"):
		if web_font==null:web_font=load("res://assets/fonts/NotoSansSC-UI.otf")
		return web_font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	return font

static func ensure_text(text: String) -> void:
	if not OS.has_feature("web") or full_font_ready or full_font_loading:return
	var font := ui_font()
	var missing := false
	for character in text:
		if not font.has_char(character.unicode_at(0)):missing=true;break
	if not missing:return
	full_font_loading=true
	var resources: Node = Engine.get_main_loop().root.get_node_or_null("WebResources")
	if resources and await resources.ensure_group("font_full"):
		font.fallbacks=[load("res://assets/fonts/NotoSansSC-Regular.otf")]
		full_font_ready=true
	full_font_loading=false
