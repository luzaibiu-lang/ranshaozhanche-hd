extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(Engine.get_license_text()+"\n\nThird-party notices\n===================\n")
	for component: Dictionary in Engine.get_copyright_info():
		file.store_string(str(component.get("name",""))+"\n")
		for part: Dictionary in component.get("parts",[]):
			file.store_string(str(part.get("license",""))+"\n")
			for line in part.get("copyright",[]):file.store_string(str(line)+"\n")
	var licenses := Engine.get_license_info()
	for name: String in licenses:
		file.store_string("\n"+name+"\n"+str(licenses[name])+"\n")
	file.close()
	quit()
