extends RefCounted

const WEB_SESSION := "burningchariot.hd.session"

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
		return load("res://assets/fonts/NotoSansSC-Regular.otf")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	return font
