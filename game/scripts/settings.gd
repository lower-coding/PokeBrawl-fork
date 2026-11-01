class_name Settings
extends Node
## The player's options, saved in user://settings.cfg and applied when loaded and on every
## change: the battle controls (each action on keyboard and on gamepad), music and effects
## volume, the sound of landing a hit, window mode, vertical sync and frame cap, camera shake, rumble, crosshair and its shape,
## the mouse's sweep changing target, a 2 vs 2's outlines and arrows, and language.
## The Options screen (Menu, drawn by MenuDraw) works through items(), menu_input() and
## menu_event(). Tests start from the defaults and never save, so a player's settings
## never change what a test sees.

const PATH := "user://settings.cfg"
const ROWS := 12                     # rows shown at once on the screen (it scrolls)
const BINDABLE := ["move_up", "move_down", "move_left", "move_right", "jump", "dodge", "lock_on", "cycle_target", "mov1", "mov2", "mov3", "mov4", "descend", "switch1", "switch2", "first_person", "pause"]
const FPS_CAPS := [0, 60, 120, 144, 240]
const LANGUAGES := ["", "en", "es"]
const CROSSHAIR_SHAPES := ["cross", "circle"]

var main: Node
var rumble := true
var shake := 1.0
var crosshair := true
var crosshair_shape := "cross"
var mouse_flick := false
var team_outline := true
var team_arrows := true
var music := 0.5
var sfx := 0.5
var hit_ping := false
var fullscreen := true
var vsync := true
var fps_cap := 0
var language := ""
var trainer := TrainerData.DEFAULT     # the profile: which trainer you are
var player_name := ""                  # and your name (empty: the trainer's)
var bindings := {}                   # action -> {"kb": data, "pad": data} (Controls.to_data)
var cursor := 1
var top := 0
var waiting := ""                    # the action waiting for a key or button
var _guard := 0.0
var _saving := true


func load_saved() -> void:
	if main._args.has("test") or main._args.has("aivsai"):
		_saving = false
		Audio.set_bus_volume("SFX", sfx)
		Audio.set_bus_volume("Music", music)
		return
	load_from(PATH)


func load_from(file: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(file) != OK:
		# No saved options yet: the defaults, volumes included, still go into effect.
		Audio.set_bus_volume("SFX", sfx)
		Audio.set_bus_volume("Music", music)
		return
	rumble = cf.get_value("game", "rumble", rumble)
	shake = cf.get_value("game", "shake", shake)
	crosshair = cf.get_value("game", "crosshair", crosshair)
	var shape = cf.get_value("game", "crosshair_shape", crosshair_shape)
	crosshair_shape = shape if shape in CROSSHAIR_SHAPES else CROSSHAIR_SHAPES[0]
	mouse_flick = cf.get_value("game", "mouse_flick", mouse_flick)
	team_outline = cf.get_value("game", "team_outline", team_outline)
	team_arrows = cf.get_value("game", "team_arrows", team_arrows)
	language = cf.get_value("game", "language", language)
	trainer = TrainerData.valid(cf.get_value("profile", "trainer", trainer))
	player_name = str(cf.get_value("profile", "name", player_name)).substr(0, Menu.NAME_MAX)
	music = cf.get_value("sound", "music", music)
	sfx = cf.get_value("sound", "sfx", sfx)
	hit_ping = cf.get_value("sound", "hit_ping", hit_ping)
	fullscreen = cf.get_value("screen", "fullscreen", fullscreen)
	vsync = cf.get_value("screen", "vsync", vsync)
	fps_cap = cf.get_value("screen", "fps_cap", fps_cap)
	bindings = cf.get_value("controls", "bindings", {})
	apply(true)


func save() -> void:
	if _saving:
		save_to(PATH)


func save_to(file: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "rumble", rumble)
	cf.set_value("game", "shake", shake)
	cf.set_value("game", "crosshair", crosshair)
	cf.set_value("game", "crosshair_shape", crosshair_shape)
	cf.set_value("game", "mouse_flick", mouse_flick)
	cf.set_value("game", "team_outline", team_outline)
	cf.set_value("game", "team_arrows", team_arrows)
	cf.set_value("game", "language", language)
	cf.set_value("profile", "trainer", trainer)
	cf.set_value("profile", "name", player_name)
	cf.set_value("sound", "music", music)
	cf.set_value("sound", "sfx", sfx)
	cf.set_value("sound", "hit_ping", hit_ping)
	cf.set_value("screen", "fullscreen", fullscreen)
	cf.set_value("screen", "vsync", vsync)
	cf.set_value("screen", "fps_cap", fps_cap)
	cf.set_value("controls", "bindings", bindings)
	cf.save(file)


## Puts everything into effect. "screen" also sets the window (only when loading or when
## the player changes it: the command line's window stays otherwise).
func apply(screen := false) -> void:
	Audio.set_bus_volume("SFX", sfx)
	Audio.set_bus_volume("Music", music)
	if screen and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		# "Mailbox" when on: it does not wait on the frame queue (less input lag) and does not tear.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	if language != "":
		TranslationServer.set_locale(language)
	Controls.configure()
	for action in bindings:
		for kind in ["kb", "pad"]:
			var ev := Controls.from_data(bindings[action].get(kind, []))
			if ev:
				Controls.rebind(action, ev)


# ---------------------------------------------------------------- the Options screen

## Rows of the screen: {id, kind (header, bind, slider, toggle, choice, action), label,
## value (already translated), help}.
func items() -> Array:
	var out: Array = []
	out.append({"id": "h_controls", "kind": "header", "label": tr("Controls")})
	var users := _key_users()
	for a in BINDABLE:
		var kb := ""
		var pad := ""
		var kb_clash := false
		var pad_clash := false
		var clashes: Array = []
		for ev in InputMap.action_get_events(a):
			var key_name := Controls.event_name(ev, "playstation" if Controls.last_device == "playstation" else "xbox")
			var others: Array = users[str(Controls.to_data(ev))].filter(func(o): return o != a)
			if not others.is_empty():
				clashes.append(tr("%s also does: %s") % [key_name, ", ".join(others.map(_action_name))])
				if Controls.is_pad(ev):
					pad_clash = true
				else:
					kb_clash = true
			if Controls.is_pad(ev):
				pad = key_name
			elif kb == "" or not Controls.is_arrow(a, ev):
				kb = key_name
		var row := {"id": a, "kind": "bind", "label": _action_name(a), "kb": kb, "pad": pad, "kb_clash": kb_clash, "pad_clash": pad_clash, "clashes": clashes}
		if Controls.MOVE_ARROWS.has(a):
			row.value = kb
			row.help = tr("Press to change it, then press the new key. Esc cancels. The arrow keys, the stick and the D-pad always move too.")
		else:
			row.value = "%s  /  %s" % [kb, pad]
			row.help = tr("Press to change it, then press the new key or button: a key changes the keyboard's, a button the gamepad's. Esc cancels.")
		out.append(row)
	out.append({"id": "reset_controls", "kind": "action", "label": tr("Default controls"), "value": "",
		"help": tr("Puts every action back on its usual key and button.")})
	out.append({"id": "h_sound", "kind": "header", "label": tr("Sound")})
	out.append({"id": "music", "kind": "slider", "label": tr("Music"), "value": "%d%%" % roundi(music * 100.0),
		"help": tr("Volume of the music in the menus and battles.")})
	out.append({"id": "sfx", "kind": "slider", "label": tr("Effects"), "value": "%d%%" % roundi(sfx * 100.0),
		"help": tr("Volume of moves, hits, cries and the crowd.")})
	out.append({"id": "hit_ping", "kind": "toggle", "label": tr("Hit sound"),
		"value": tr("On") if hit_ping else tr("Off"), "help": tr("A short ping when you hit the foe, just one for a quick burst of hits.")})
	out.append({"id": "h_screen", "kind": "header", "label": tr("Screen")})
	out.append({"id": "fullscreen", "kind": "toggle", "label": tr("Full screen"),
		"value": tr("On") if fullscreen else tr("Off"), "help": tr("Full screen or a window.")})
	out.append({"id": "vsync", "kind": "toggle", "label": tr("Vertical sync"),
		"value": tr("On") if vsync else tr("Off"), "help": tr("Stops tearing; off can lower the delay a little.")})
	out.append({"id": "fps_cap", "kind": "choice", "label": tr("Frame limit"),
		"value": tr("None") if fps_cap == 0 else "%d" % fps_cap, "help": tr("Highest frames per second.")})
	out.append({"id": "h_game", "kind": "header", "label": tr("Game")})
	out.append({"id": "shake", "kind": "slider", "label": tr("Camera shake"), "value": "%d%%" % roundi(shake * 100.0),
		"help": tr("How much the camera shakes on hits.")})
	out.append({"id": "rumble", "kind": "toggle", "label": tr("Rumble"),
		"value": tr("On") if rumble else tr("Off"), "help": tr("The gamepad rumbles on hits.")})
	out.append({"id": "crosshair", "kind": "toggle", "label": tr("Crosshair"),
		"value": tr("On") if crosshair else tr("Off"), "help": tr("With nothing locked on, marks where your moves go.")})
	out.append({"id": "crosshair_shape", "kind": "choice", "label": tr("Crosshair shape"),
		"value": tr("Circle") if crosshair_shape == "circle" else tr("Cross"), "help": tr("A dot with four ticks round it, or a dot in a ring.")})
	out.append({"id": "mouse_flick", "kind": "toggle", "label": tr("Mouse sweep changes target"),
		"value": tr("On") if mouse_flick else tr("Off"), "help": tr("Locked on, a quick sweep of the mouse moves the lock to the next target. Off, only the Change target key does.")})
	out.append({"id": "team_outline", "kind": "toggle", "label": tr("Ally and foe outline"),
		"value": tr("On") if team_outline else tr("Off"), "help": tr("In a 2 vs 2, a blue outline on your ally and a red one on your foes.")})
	out.append({"id": "team_arrows", "kind": "toggle", "label": tr("Ally and foe arrows"),
		"value": tr("On") if team_arrows else tr("Off"), "help": tr("In a 2 vs 2 with nothing locked on, a blue arrow over your ally and a red one over your foes.")})
	out.append({"id": "language", "kind": "choice", "label": tr("Language"),
		"value": {"": tr("System"), "en": "English", "es": "Español"}[language], "help": tr("The game's language.")})
	return out


## Which of the actions each key or button is on (by its Controls.to_data): two on one clash.
func _key_users() -> Dictionary:
	var users := {}
	for a in BINDABLE:
		for ev in InputMap.action_get_events(a):
			users.get_or_add(str(Controls.to_data(ev)), []).append(a)
	return users


func _action_name(a: String) -> String:
	match a:
		"move_up": return tr("Move forward")
		"move_down": return tr("Move back")
		"move_left": return tr("Move left")
		"move_right": return tr("Move right")
		"jump": return tr("Jump")
		"dodge": return tr("Dodge")
		"lock_on": return tr("Lock on")
		"cycle_target": return tr("Change target")
		"mov1": return tr("Move 1")
		"mov2": return tr("Move 2")
		"mov3": return tr("Move 3")
		"mov4": return tr("Move 4")
		"descend": return tr("Descend (flying)")
		"switch1": return tr("Switch 1")
		"switch2": return tr("Switch 2")
		"first_person": return tr("First person")
		"pause": return tr("Pause")
	return a


func menu_input(menu: Menu) -> void:
	_guard = maxf(0.0, _guard - get_process_delta_time())
	if waiting != "" or _guard > 0.0:
		return
	var list := items()
	var n := list.size()
	var before := cursor
	if menu._pressed("move_up"):
		cursor = _next(list, cursor, -1)
	elif menu._pressed("move_down"):
		cursor = _next(list, cursor, 1)
	if cursor != before:
		menu._sound("move")
		top = clampi(top, cursor - ROWS + 1, cursor)
		if cursor == 1:
			top = 0
	var it: Dictionary = list[cursor]
	var step := 0
	if menu._pressed("move_left"):
		step = -1
	elif menu._pressed("move_right"):
		step = 1
	if step != 0 and it.kind in ["slider", "choice", "toggle"]:
		_change(it.id, step)
		menu._sound("move")
	if menu._accept():
		match it.kind:
			"bind":
				waiting = it.id
				menu._sound("ok")
			"action":
				bindings.clear()
				apply()
				save()
				menu._sound("ok")
			"slider", "choice", "toggle":
				_change(it.id, 1)
				menu._sound("move")
	elif menu._pressed("menu_back"):
		menu._sound("back")
		save()
		if menu.options_return:
			# From the selection: back the way the Rules screen goes, so the picks and the room stay.
			menu.options_return = false
			menu.screen = "selection"
			menu.enter_t = 0.0
		else:
			menu._go("main")
	if n == 0:
		return


func _next(list: Array, i: int, step: int) -> int:
	var j := i
	for k in list.size():
		j = (j + step + list.size()) % list.size()
		if list[j].kind != "header":
			return j
	return i


func _change(id: String, step: int) -> void:
	match id:
		"music":
			music = clampf(snappedf(music + 0.1 * step, 0.1), 0.0, 1.0)
		"sfx":
			sfx = clampf(snappedf(sfx + 0.1 * step, 0.1), 0.0, 1.0)
		"hit_ping":
			hit_ping = not hit_ping
			# Turned on, a sample of what it sounds like.
			if hit_ping:
				main.audio.ping()
		"shake":
			shake = clampf(snappedf(shake + 0.25 * step, 0.25), 0.0, 1.0)
		"rumble":
			rumble = not rumble
		"crosshair":
			crosshair = not crosshair
		"crosshair_shape":
			crosshair_shape = CROSSHAIR_SHAPES[(CROSSHAIR_SHAPES.find(crosshair_shape) + step + CROSSHAIR_SHAPES.size()) % CROSSHAIR_SHAPES.size()]
		"mouse_flick":
			mouse_flick = not mouse_flick
		"team_outline":
			team_outline = not team_outline
		"team_arrows":
			team_arrows = not team_arrows
		"fullscreen":
			fullscreen = not fullscreen
			apply(true)
		"vsync":
			vsync = not vsync
			apply(true)
		"fps_cap":
			fps_cap = FPS_CAPS[(FPS_CAPS.find(fps_cap) + step + FPS_CAPS.size()) % FPS_CAPS.size()]
		"language":
			language = LANGUAGES[(LANGUAGES.find(language) + step + LANGUAGES.size()) % LANGUAGES.size()]
			TranslationServer.set_locale(language if language != "" else OS.get_locale_language())
	apply()
	save()


## While waiting for a binding: the next key, mouse button, gamepad button or trigger.
func menu_event(menu: Menu, ev: InputEvent) -> void:
	if waiting == "":
		return
	var take: InputEvent = null
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			waiting = ""
			_guard = 0.2
			menu.get_viewport().set_input_as_handled()
			return
		take = ev
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		take = ev
	elif ev is InputEventJoypadButton and ev.pressed:
		take = ev
	elif ev is InputEventJoypadMotion and ev.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and absf(ev.axis_value) > 0.6:
		take = ev
	if take == null:
		return
	# The directions stay on the stick and D-pad: a button only cancels, or a player with just a
	# gamepad would be stuck here.
	if Controls.is_pad(take) and Controls.MOVE_ARROWS.has(waiting):
		waiting = ""
		_guard = 0.3
		menu._sound("back")
		menu.get_viewport().set_input_as_handled()
		return
	Controls.rebind(waiting, take)
	var b: Dictionary = bindings.get(waiting, {})
	b["pad" if Controls.is_pad(take) else "kb"] = Controls.to_data(take)
	bindings[waiting] = b
	waiting = ""
	_guard = 0.3
	save()
	menu._sound("ok")
	menu.get_viewport().set_input_as_handled()


## The name shown for you: the one you typed, or your trainer's.
func shown_name() -> String:
	return player_name if player_name.strip_edges() != "" else tr(TrainerData.LIST[trainer].name)
