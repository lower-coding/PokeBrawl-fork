extends SceneTree
## Writes the Godot Engine's license and every third-party notice compiled into it
## (FreeType, ENet, Mbed TLS...) to the file given after "--", for the release package:
##   godot --headless --path game -s res://../tools/godot_notices.gd -- ../export/PokeBrawl/GODOT-LICENSES.txt


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "GODOT-LICENSES.txt"
	var text := "PokeBrawl is made with Godot Engine (https://godotengine.org), under this license:\n\n"
	text += Engine.get_license_text() + "\n"
	text += "Godot Engine includes these third-party components:\n\n"
	for c in Engine.get_copyright_info():
		text += "- %s\n" % c.name
		for p in c.parts:
			text += "  %s: %s\n" % [", ".join(p.copyright), p.license]
	text += "\nTheir licenses, in full:\n"
	var info := Engine.get_license_info()
	for name in info:
		text += "\n----- %s -----\n\n%s\n" % [name, info[name]]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(text)
	print("wrote ", out, " (", text.length(), " chars)")
	quit()
