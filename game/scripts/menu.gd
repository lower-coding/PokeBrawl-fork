class_name Menu
extends Node
## Menus, in the style of Pokkén Tournament but built from Cobblemon's GUI pieces
## (battle buttons, party slots, summary panel):
##   title       the stadium with the camera orbiting; A to enter
##   main        Battle, Online, Training, Quit
##   online      Host game, Join, Back
##   waiting     host waiting: its IPs and whether the router opened the port
##   join        type the IP (keyboard, or digit by digit with the gamepad)
##   connecting  trying to join someone else's game
##   selection   Pokémon grid, card of the highlighted one and the picks on the
##               field. Against the AI: you, rival and difficulty. Online: each
##               picks their own; you see what the other picks and when they are ready
##   vs          both face to face before the battle
## The HUD does the drawing by calling draw(); logic and input live here.
## Visible text is English and goes through tr() when drawn (game/i18n).

const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFFICULTY_NAME := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
const STAGES := ["stadium", "glade"]
const STAGE_NAME := {"stadium": "Stadium", "glade": "Forest Glade"}
const COLUMNS := 2
const MAIN_MENU := [["combat", "Battle", "Against the AI. Pick your Pokémon, the rival and the difficulty."],
	["online", "Online", "1 vs 1 with a friend over the internet."],
	["training", "Training", "Still or active rival, no rush. R resets, T stops or frees the rival."],
	["quit", "Quit", "Close the game."]]
const ONLINE := [["create", "Host game", "Your friend joins with your IP. Port 7777 (UDP)."],
	["join", "Join", "Type the IP of whoever hosted the game."],
	["back", "Back", ""]]
const IP_CHARS := "0123456789."

var main: Node
var is_open := false
var screen := "title"
var cursor := 0
var choice := {"p1": "pikachu", "p2": "snorlax", "diff": "normal", "mode": "combat"}
var online := false
var sel_phase := "p1"             # p1, p2, diff (against the AI); online only p1
var me_ready := false
var rival_choice_id := ""
var rival_ready := false
var message := ""                # notices (connection errors, disconnects), already translated
var ip := ""
var _caret := 0
var portraits := {}               # species -> Texture2D (grid icons)
var _models := {}
var _t := 0.0
var _vs_t := -1.0
var _vs := []                    # [mine, theirs] on the VS screen
var _card_vp: SubViewport
var _card_model: PokeModel
var _card_species := ""
var _generating := false


func _ready() -> void:
	var saved := _load_ip()
	ip = saved if saved != "" else "192.168.1."
	_caret = ip.length()


## Only those with all their moves done (the rest are half finished).
func pokemon_list() -> Array:
	var list: Array = []
	for sp in Roster.POKEMON:
		var data: Dictionary = Roster.POKEMON[sp]
		var ready := true
		for move in data.moves:
			if not Moves.DATA.has(move) or not ResourceLoader.exists(Moves.DATA[move].script):
				ready = false
		if ready:
			list.append(sp)
	return list


# ---------------------------------------------------------------- open and close

func open_menu(en := "") -> void:
	is_open = true
	_t = 0.0
	_vs_t = -1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.camera.target = null
	if en == "":
		en = "main" if screen != "title" else "title"
	_go(en)
	if portraits.is_empty() and not _generating:
		_generate_portraits()


func close() -> void:
	is_open = false
	for k in _models:
		_models[k].queue_free()
	_models.clear()
	_remove_card()


func _go(p: String) -> void:
	screen = p
	cursor = 0
	if p == "selection":
		me_ready = false
		sel_phase = "p1"
		var list := pokemon_list()
		cursor = maxi(list.find(choice.p1), 0)
		_place("p1")
		if not online or rival_choice_id != "":
			if online:
				choice.p2 = rival_choice_id
			_place("p2")
		elif _models.has("p2"):
			_models.p2.queue_free()
			_models.erase("p2")
		_frame()
		main.portraits(choice.p1, choice.p2)
		if online:
			_send_choice()
	else:
		for k in _models:
			_models[k].queue_free()
		_models.clear()
		_remove_card()


## Online: once connected, both go on to pick.
func online_connected() -> void:
	online = true
	rival_choice_id = ""
	rival_ready = false
	message = ""
	if not is_open:
		open_menu("selection")
	else:
		_go("selection")


func disconnected(reason: String) -> void:
	online = false
	message = reason
	open_menu("online")


# ---------------------------------------------------------------- input

func _pressed(a: String) -> bool:
	# When the menu opens, the press that opened it (B after an online battle) does
	# not count here: otherwise it would leave the selection right after entering.
	return _t > 0.15 and Input.is_action_just_pressed(a)


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	_turn_camera()
	if _vs_t >= 0.0:
		_vs_t += delta
		if _vs_t > 2.2:
			_vs_t = -1.0
			var vs := _vs.duplicate()
			close()
			main.start_battle(vs[0], vs[1], choice.diff)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	match screen:
		"title":
			if _pressed("menu_accept") or _pressed("jump"):
				_sound()
				_go("main")
		"main":
			_move_list(MAIN_MENU.size())
			if _pressed("menu_accept") or _pressed("jump"):
				_sound()
				match MAIN_MENU[cursor][0]:
					"combat", "training":
						online = false
						choice.mode = MAIN_MENU[cursor][0]
						main.mode = choice.mode
						_go("selection")
					"online":
						message = ""
						_go("online")
					"quit":
						get_tree().quit()
			elif _pressed("menu_back"):
				_go("title")
		"online":
			_move_list(ONLINE.size())
			if _pressed("menu_accept") or _pressed("jump"):
				_sound()
				match ONLINE[cursor][0]:
					"create":
						var err: String = main.start_net(true, "")
						message = err
						if err == "":
							_go("waiting")
					"join":
						_go("join")
						_caret = ip.length()
					"back":
						_go("main")
			elif _pressed("menu_back"):
				_go("main")
		"waiting", "connecting":
			if _pressed("menu_back"):
				main.close_net()
				_go("online")
		"join":
			_edit_ip_pad()
		"selection":
			_selection()


func _move_list(n: int) -> void:
	if _pressed("move_up"):
		cursor = (cursor + n - 1) % n
		_sound(1.6)
	elif _pressed("move_down"):
		cursor = (cursor + 1) % n
		_sound(1.6)


func _sound(tone := 1.3) -> void:
	main.audio.play_sound("dodge", main.camera.global_position, -16.0, tone)


# ---------------------------------------------------------------- IP

## With the keyboard the IP is typed (and Ctrl+V pastes it); with the gamepad, up and
## down change the digit, left and right move the cursor.
func _edit_ip_pad() -> void:
	var keyboard := Controls.last_device == "keyboard"
	if _pressed("menu_back") and not keyboard:
		_go("online")
		return
	if (_pressed("menu_accept") or _pressed("jump")) and not keyboard:
		_connect_peer()
		return
	if keyboard:
		if Input.is_key_pressed(KEY_ESCAPE):
			_go("online")
		return
	var step := 0
	if _pressed("move_up"):
		step = 1
	elif _pressed("move_down"):
		step = -1
	if step != 0:
		if _caret >= ip.length():
			ip += "0"
		var i := IP_CHARS.find(ip[_caret])
		ip[_caret] = IP_CHARS[(i + step + IP_CHARS.length()) % IP_CHARS.length()]
	if _pressed("move_left"):
		_caret = maxi(0, _caret - 1)
	elif _pressed("move_right"):
		_caret = mini(ip.length(), _caret + 1)


func _unhandled_input(ev: InputEvent) -> void:
	if not is_open or screen != "join" or not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	if k.keycode == KEY_BACKSPACE:
		if _caret > 0:
			ip = ip.substr(0, _caret - 1) + ip.substr(_caret)
			_caret -= 1
	elif k.keycode == KEY_DELETE:
		ip = ip.substr(0, _caret) + ip.substr(_caret + 1)
	elif k.keycode == KEY_LEFT:
		_caret = maxi(0, _caret - 1)
	elif k.keycode == KEY_RIGHT:
		_caret = mini(ip.length(), _caret + 1)
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_connect_peer()
	elif k.keycode == KEY_V and k.ctrl_pressed:
		var clean := ""
		for ch in DisplayServer.clipboard_get().strip_edges():
			if IP_CHARS.contains(ch):
				clean += ch
		ip = clean.substr(0, 15)
		_caret = ip.length()
	elif k.unicode > 0 and IP_CHARS.contains(char(k.unicode)) and ip.length() < 15:
		ip = ip.substr(0, _caret) + char(k.unicode) + ip.substr(_caret)
		_caret += 1
	else:
		return
	get_viewport().set_input_as_handled()


func _connect_peer() -> void:
	if ip.count(".") != 3:
		message = tr("The IP has four numbers separated by dots.")
		return
	_save_ip(ip)
	var err: String = main.start_net(false, ip)
	message = err
	if err == "":
		_go("connecting")


func _load_ip() -> String:
	var f := FileAccess.open("user://last_ip.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


func _save_ip(text: String) -> void:
	var f := FileAccess.open("user://last_ip.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)


# ---------------------------------------------------------------- selection

func _selection() -> void:
	var list := pokemon_list()
	var n := list.size()
	if sel_phase == "diff":
		var i := DIFFICULTIES.find(choice.diff)
		if _pressed("move_left"):
			choice.diff = DIFFICULTIES[(i + 2) % 3]
			_sound(1.6)
		elif _pressed("move_right"):
			choice.diff = DIFFICULTIES[(i + 1) % 3]
			_sound(1.6)
		# Up and down, the stage: it is built right away and seen in the background.
		elif _pressed("move_up") or _pressed("move_down"):
			var e := STAGES.find(main.arena.stage)
			main.set_stage(STAGES[(e + 1) % STAGES.size()])
			_sound(1.6)
		if _pressed("menu_accept") or _pressed("jump"):
			_sound()
			_start_vs(choice.p1, choice.p2)
		elif _pressed("menu_back"):
			sel_phase = "p2"
			cursor = maxi(list.find(choice.p2), 0)
		return
	if online and me_ready:
		if _pressed("menu_back"):
			me_ready = false
			_send_choice()
		return
	var before := cursor
	if _pressed("move_right"):
		cursor = mini(cursor + 1, n - 1)
	elif _pressed("move_left"):
		cursor = maxi(cursor - 1, 0)
	elif _pressed("move_down"):
		cursor = mini(cursor + COLUMNS, n - 1)
	elif _pressed("move_up"):
		cursor = maxi(cursor - COLUMNS, 0)
	if cursor != before:
		_sound(1.6)
		var side: String = sel_phase
		choice[side] = list[cursor]
		_place(side)
		_frame()
		main.portraits(choice.p1, choice.p2)
		main.audio.cry(choice[side], _models[side].global_position)
		if online:
			_send_choice()
	if _pressed("menu_accept") or _pressed("jump"):
		_sound()
		if online:
			me_ready = true
			_send_choice()
			main.check_start()
		elif sel_phase == "p1":
			sel_phase = "p2"
			cursor = maxi(list.find(choice.p2), 0)
			if not _models.has("p2"):
				_place("p2")
				_frame()
		elif choice.mode == "training":
			_start_vs(choice.p1, choice.p2)
		else:
			sel_phase = "diff"
	elif _pressed("menu_back"):
		if online:
			main.close_net()
			online = false
			_go("online")
		elif sel_phase == "p2":
			sel_phase = "p1"
			cursor = maxi(list.find(choice.p1), 0)
		else:
			_go("main")


func _send_choice() -> void:
	if main.net:
		main.net.send_event({"t": "choice", "species": choice.p1, "ready": me_ready})


## The online rival changes Pokémon or gets ready.
func rival_choice(sp: String, ready: bool) -> void:
	if not Roster.POKEMON.has(sp):
		return
	var change := sp != rival_choice_id
	rival_choice_id = sp
	rival_ready = ready
	if is_open and screen == "selection" and change:
		choice.p2 = sp
		_place("p2")
		_frame()
		main.portraits(choice.p1, sp)


func _start_vs(mine: String, theirs: String) -> void:
	_vs = [mine, theirs]
	_vs_t = 0.0
	screen = "vs"
	main.portraits(mine, theirs)
	main.audio.cry(mine, main.camera.global_position, 1.0)


## From main, online: both are ready.
func show_vs(mine: String, theirs: String) -> void:
	if not is_open:
		open_menu("selection")
	_start_vs(mine, theirs)


# ---------------------------------------------------------------- background scene

func _turn_camera() -> void:
	if screen in ["selection", "vs"]:
		return
	var cam: Camera3D = main.camera
	var a := _t * 0.08
	cam.global_position = Vector3(sin(a) * 15.0, 6.5 + sin(_t * 0.2) * 0.8, cos(a) * 15.0)
	cam.look_at(Vector3(0, 1.0, 0))


func _place(side: String) -> void:
	if _models.has(side):
		_models[side].queue_free()
	var sp: String = choice[side]
	var m := PokeModel.new()
	m.setup(sp)
	var box: AABB = m._res.mesh.get_aabb()
	m.scale = Vector3.ONE * Roster.POKEMON[sp].height / maxf(box.size.y, 0.05)
	m.rotation.y = deg_to_rad(-120.0 if side == "p1" else 120.0)
	main.add_child(m)
	var x := -1.0 if side == "p1" else 1.0
	m.global_position = Vector3(x * (1.4 + Roster.POKEMON[sp].radius), 0, 0)
	m.play("battle_idle" if m.has_anim("battle_idle") else "ground_idle", 0.0)
	_models[side] = m


func _frame() -> void:
	var height: float = Roster.POKEMON[choice.p1].height
	if _models.has("p2"):
		height = maxf(height, Roster.POKEMON[choice.p2].height)
	var cam: Camera3D = main.camera
	# Both stay up top, between the grid and the card: the camera looks from below
	# them.
	var looks := Vector3(0.9, -height * 0.55, 0)
	cam.global_position = Vector3(0.9, height * 0.75 + 0.9, 3.8 + height * 1.9)
	cam.look_at(looks)
	cam.reset_physics_interpolation()


# ---------------------------------------------------------------- portraits

## Grid icons: each Pokémon rendered once to a texture.
func _generate_portraits() -> void:
	_generating = true
	for sp in pokemon_list():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.size = Vector2i(96, 96)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var data := _setup_portrait(vp, sp, 0.5)
		# Wait for the animation to place the skeleton: before that, the locators are in
		# the rest pose and the framing ends up on the belly.
		for i in 18:
			await get_tree().process_frame
		_frame_portrait(data)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless":
			var img := vp.get_texture().get_image()
			portraits[sp] = ImageTexture.create_from_image(img)
			if main._args.get("test", "") == "menu":
				img.save_png("res://../captures/retrato_%s.png" % sp)
		vp.queue_free()
	_generating = false


func _setup_portrait(vp: SubViewport, sp: String, turn: float) -> Dictionary:
	var m := PokeModel.new()
	m.setup(sp)
	var box: AABB = m._res.mesh.get_aabb()
	m.scale = Vector3.ONE * Roster.POKEMON[sp].height / maxf(box.size.y, 0.05)
	m.rotation.y = PI + turn
	vp.add_child(m)
	m.play("battle_idle" if m.has_anim("battle_idle") else "ground_idle", 0.0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	# With physics interpolation the camera would only move on the next physics step,
	# and the picture would be taken from inside the model.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.25
	vp.add_child(sun)
	var amb := WorldEnvironment.new()
	amb.environment = Environment.new()
	amb.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	amb.environment.ambient_light_color = Color(0.85, 0.87, 0.95)
	amb.environment.ambient_light_energy = 0.75
	amb.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(amb)
	return {"model": m, "cam": cam, "height": Roster.POKEMON[sp].height}


func _frame_portrait(r: Dictionary, body := false) -> void:
	var m: PokeModel = r.model
	if body:
		# Card: the whole body.
		var center := Vector3(0, r.height * 0.5, 0)
		var dist: float = r.height * 0.62 / tan(deg_to_rad(15.0))
		r.cam.position = center + Vector3(0, r.height * 0.1, dist)
		r.cam.look_at(center)
		return
	var points: Array = []
	for bone in ["locator_face", "locator_head", "head"]:
		if m.skel.find_bone(bone) >= 0:
			points.append(m.bone_world(bone))
	var face := Vector3(0, r.height * 0.75, 0)
	if points.size() >= 2:
		face = (points[0] + points[1]) * 0.5
	elif points.size() == 1:
		face = points[0]
	var box_height: float = clampf(r.height * 0.6, 0.6, 1.4)
	var dist := box_height * 0.5 / tan(deg_to_rad(15.0))
	var looks := face - Vector3(0, box_height * 0.08, 0)
	r.cam.position = looks + Vector3(0, box_height * 0.1, dist)
	r.cam.look_at(looks)


## Selection card: the highlighted Pokémon in full, animated, in its slot.
func _card(sp: String, px: Vector2i) -> Texture2D:
	if _card_vp == null:
		_card_vp = SubViewport.new()
		_card_vp.own_world_3d = true
		_card_vp.transparent_bg = true
		_card_vp.msaa_3d = Viewport.MSAA_4X
		_card_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_card_vp)
	if _card_vp.size != px:
		_card_vp.size = px
	if sp != _card_species:
		_card_species = sp
		for c in _card_vp.get_children():
			c.queue_free()
		var data := _setup_portrait(_card_vp, sp, 0.45)
		_card_model = data.model
		_frame_portrait(data, true)
	if _card_model:
		_card_model.rotation.y = PI + 0.45 + sin(_t * 0.6) * 0.25
	return _card_vp.get_texture()


func _remove_card() -> void:
	if _card_vp:
		_card_vp.queue_free()
	_card_vp = null
	_card_model = null
	_card_species = ""


# ---------------------------------------------------------------- drawing

func draw_ui(h: Hud) -> void:
	var s: int = h._s
	var gw: float = h._c.size.x / s
	var gh: float = h._c.size.y / s
	var pl: int = h._p_log()
	var ink := Hud.INK
	var gold := Color("ffc94a")
	match screen:
		"title":
			var y := gh * 0.28
			h._text(Vector2(gw * 0.5, y) * s, "PokeBrawl", s * 3, ink, 0)
			h._text(Vector2(gw * 0.5, y + 36) * s, tr("Real-time Pokémon battles"), s, Color(ink, 0.85), 0)
			var a := 0.55 + 0.45 * sin(_t * TAU * 0.8)
			h._text(Vector2(gw * 0.5, gh - 46) * s, tr("%s to start") % Controls.glyph("jump"), s, Color(gold, a), 0)
		"main", "online":
			var list: Array = MAIN_MENU if screen == "main" else ONLINE
			var title := "PokeBrawl" if screen == "main" else tr("Online")
			h._text(Vector2(24, 26) * s, title, s * 2, ink)
			for i in list.size():
				var g := Vector2(24, 70 + i * 32)
				var sel := i == cursor
				h._piece("battle_menu_fight", g, Vector2(90, 26), Rect2(0, 26 if sel else 0, 90, 26))
				h._text((g + Vector2(7, 8)) * s, tr(list[i][1]), pl, ink)
			_box(h, Vector2(130, 70), tr(list[cursor][2]) if list[cursor][2] != "" else "", message)
			if screen == "main":
				_credits(h, gh)
		"waiting":
			h._text(Vector2(24, 26) * s, tr("Waiting for rival"), s * 2, ink)
			var lines: Array = [tr("Give your friend one of these IPs:")]
			var net: Net = main.net
			if net and net.public_ip != "":
				lines.append("  " + tr("Over the internet: %s") % net.public_ip)
			for loc in Net.local_ips():
				lines.append("  " + tr("Local network or VPN: %s") % loc)
			lines.append("")
			if net and net.upnp_testing:
				lines.append(tr("Opening port 7777 on the router") + ".".repeat(int(_t * 2.0) % 4))
			elif net and net.upnp_ok:
				lines.append(tr("Port 7777 open on the router."))
			else:
				lines.append("!" + tr("The router did not open the port: open it (UDP 7777) or use Radmin VPN or ZeroTier."))
			lines.append(tr("%s back") % Controls.glyph("menu_back"))
			_box_lines(h, Vector2(24, 64), lines)
		"connecting":
			h._text(Vector2(24, 26) * s, tr("Connecting"), s * 2, ink)
			_box_lines(h, Vector2(24, 64), [tr("Joining %s:7777") % ip + ".".repeat(int(_t * 2.0) % 4),
				"", tr("%s cancel") % Controls.glyph("menu_back")])
		"join":
			h._text(Vector2(24, 26) * s, tr("Join"), s * 2, ink)
			var g := Vector2(24, 70)
			h._piece("battle_log", g, Vector2(169, 55))
			h._text((g + Vector2(8, 7)) * s, tr("Game IP:"), pl, Color(ink, 0.8))
			var x := g.x + 8
			for i in ip.length() + 1:
				var ch: String = ip[i] if i < ip.length() else ""
				var w := h._text_width(ch if ch != "" else "0", s) / s
				if i == _caret:
					h._rect(Vector2(x - 0.5, g.y + 30), Vector2(w + 1, 1.5), Color(gold, 0.6 + 0.4 * sin(_t * TAU)))
				h._text(Vector2(x, g.y + 19) * s, ch, s, ink)
				x += w + 1
			var help := tr("Type or paste with Ctrl+V. Enter connects.") if Controls.last_device == "keyboard" \
				else tr("Up and down change the digit. %s connects.") % Controls.glyph("jump")
			h._text((g + Vector2(8, 40)) * s, help, pl, Color(ink, 0.6))
			if message != "":
				_box(h, Vector2(200, 70), "", message)
		"selection":
			_draw_selection(h, s, gw, gh, pl)
		"vs":
			_draw_vs(h, s, gw, gh, pl)


## Credits at the bottom of the main menu, small. Cobblemon's assets are
## CC BY-NC 3.0: the team, the license and the non-profit nature are named.
const CREDITS := ["Created by xjoje6",
	"Models, animations, particles, sounds and battle UI: the Cobblemon team (CC BY-NC 3.0, adapted)",
	"Non-profit fan project. Pokémon belongs to Nintendo, Game Freak and The Pokémon Company."]


func _credits(h: Hud, gh: float) -> void:
	var s: int = h._s
	var pl: int = h._p_log()
	var step := 11.0 * pl / s
	var y := gh - 6.0 - 12.0 * pl / s - (CREDITS.size() - 1) * step
	for i in CREDITS.size():
		h._text(Vector2(24, y) * s, tr(CREDITS[i]), pl, Color(Hud.INK, 0.8 if i == 0 else 0.55))
		y += step


func _box(h: Hud, g: Vector2, text: String, telegraph: String) -> void:
	var lines: Array = [text] if text != "" else []
	if telegraph != "":
		if text != "":
			lines.append("")
		lines.append("!" + telegraph)
	_box_lines(h, g, lines, Vector2(169, 55))


func _box_lines(h: Hud, g: Vector2, lines: Array, dims := Vector2(169, 101)) -> void:
	var s: int = h._s
	var pl: int = h._p_log()
	h._piece("battle_log_expanded" if dims.y > 60 else "battle_log", g, dims)
	var y := g.y + 7
	for ln in lines:
		var text: String = ln
		var col := Hud.INK
		if text.begins_with("!"):
			text = text.substr(1)
			col = Color("ff8a6a")
		for part in h._wrap(text, 154.0 * s, pl):
			if y > g.y + dims.y - 10:
				return
			h._text(Vector2(g.x + 7, y) * s, part, pl, col)
			y += 12.0 * pl / s


func _draw_selection(h: Hud, s: int, gw: float, gh: float, pl: int) -> void:
	var ink := Hud.INK
	var list := pokemon_list()
	var title := tr("Pick your Pokémon")
	if sel_phase == "p2":
		title = tr("Pick the rival")
	elif sel_phase == "diff":
		title = tr("Difficulty")
	h._text(Vector2(14, 12) * s, title, s * 2, ink)
	# Grid: Cobblemon party slots with each one's portrait.
	for i in list.size():
		var sp: String = list[i]
		var g := Vector2(14 + (i % COLUMNS) * 50, 42 + (i / COLUMNS) * 30)
		var marked := i == cursor and sel_phase != "diff" and not (online and me_ready)
		h._piece("summary_party_slot", g, Vector2(46, 27), Rect2(0, 27 if marked else 0, 46, 27))
		if portraits.has(sp):
			h._c.draw_texture_rect(portraits[sp], Rect2((g + Vector2(1, -2)) * s, Vector2(25, 25) * s), false)
		var types: Array = Roster.POKEMON[sp].types
		for k in types.size():
			h._type_icon(types[k], g + Vector2(27 + k * 8, 3), 8)
		var mark := ""
		var mark_col := Color("ffc94a")
		if sp == choice.p1 and (sel_phase != "p1" or me_ready):
			mark = tr("You")
		if not online and sp == choice.p2 and sel_phase == "diff":
			mark = tr("AI") if mark == "" else tr("You") + " " + tr("AI")
			mark_col = Color("ff8a6a")
		if online and sp == rival_choice_id:
			mark = tr("Rival") if mark == "" else tr("Both")
			mark_col = Color("ff8a6a")
		if mark != "":
			h._text((g + Vector2(27, 13)) * s, mark, pl, mark_col)
	# Card of the highlighted one: Cobblemon's summary panel.
	var sp_card: String = list[cursor] if sel_phase != "diff" else choice.p2
	var data: Dictionary = Roster.POKEMON[sp_card]
	var b := Vector2(gw - 331 - 10, gh - 161 - 12)
	h._piece("summary_base", b, Vector2(331, 161))
	h._c.draw_texture_rect(_card(sp_card, Vector2i(67, 70) * s), Rect2((b + Vector2(5, 30)) * s, Vector2(67, 70) * s), false)
	h._text((b + Vector2(7, 4)) * s, tr(data.display_name), pl, ink)
	for k in data.types.size():
		h._type_icon(data.types[k], b + Vector2(7 + k * 13, 104), 12)
	var x1 := b.x + 82
	var y1 := b.y + 16
	for ln in h._wrap(tr(data.style), 124.0 * s, pl):
		h._text(Vector2(x1, y1) * s, ln, pl, ink)
		y1 += 9
	y1 += 4
	h._text(Vector2(x1, y1) * s, tr(data.passive.display_name), pl, Color("ffc94a"))
	y1 += 9
	for ln in h._wrap(tr(data.passive.text), 124.0 * s, pl):
		if y1 > b.y + 150:
			break
		h._text(Vector2(x1, y1) * s, ln, pl, Color(ink, 0.8))
		y1 += 9
	var x2 := b.x + 218
	var y2 := b.y + 16
	for move in data.moves:
		var d: Dictionary = Moves.DATA[move]
		h._type_icon(d.type, Vector2(x2, y2), 9)
		h._text(Vector2(x2 + 12, y2 + 0.5) * s, tr(d.display_name), pl, ink)
		y2 += 11
		for ln in h._wrap(tr(d.desc), 104.0 * s, pl).slice(0, 2):
			h._text(Vector2(x2 + 2, y2) * s, ln, pl, Color(ink, 0.6))
			y2 += 8
		y2 += 4
	# Footer: what to do now.
	var foot := ""
	if sel_phase == "diff":
		foot = tr("< %s >   up/down: %s   %s battle   %s back") % [tr(DIFFICULTY_NAME[choice.diff]), tr(STAGE_NAME[main.arena.stage]),
			Controls.glyph("jump"), Controls.glyph("menu_back")]
	elif online:
		var rival_state := tr("choosing...")
		if rival_choice_id != "":
			rival_state = "%s, %s" % [tr(Roster.POKEMON[rival_choice_id].display_name), tr("ready") if rival_ready else tr("choosing")]
		h._text(Vector2(14, gh - 40) * s, tr("Rival: %s") % rival_state, pl, Color("ff8a6a"))
		if main.net:
			h._text(Vector2(14, gh - 30) * s, "Ping %d ms" % main.net.ping_ms(), pl, Color(ink, 0.7))
		foot = (tr("Ready, waiting for the rival   %s change") % Controls.glyph("menu_back")) if me_ready \
			else (tr("%s ready   %s leave") % [Controls.glyph("jump"), Controls.glyph("menu_back")])
	else:
		foot = tr("%s pick   %s back") % [Controls.glyph("jump"), Controls.glyph("menu_back")]
	h._text(Vector2(14, gh - 18) * s, foot, pl, Color("ffc94a"))


func _draw_vs(h: Hud, s: int, gw: float, gh: float, pl: int) -> void:
	var ink := Hud.INK
	var k := clampf(_vs_t / 0.35, 0.0, 1.0)
	h._c.draw_rect(Rect2(Vector2.ZERO, h._c.size), Color(0.03, 0.04, 0.07, 0.6 * k))
	for i in 2:
		var sp: String = _vs[i]
		var side := -1.0 if i == 0 else 1.0
		var enters := (1.0 - k) * 140.0 * side
		var c := Vector2(gw * 0.5 + side * 120 + enters, gh * 0.42)
		h._piece("portrait_background", c - Vector2(66, 66), Vector2(132, 132))
		if portraits.has(sp):
			h._c.draw_texture_rect(portraits[sp], Rect2((c - Vector2(62, 62)) * s, Vector2(124, 124) * s), false)
		h._text(Vector2(c.x, c.y + 72) * s, tr(Roster.POKEMON[sp].display_name), s * 2, ink, 0)
		var who: String = tr("You") if i == 0 else (tr("Rival") if online else tr("AI, %s") % tr(DIFFICULTY_NAME[choice.diff]).to_lower())
		h._text(Vector2(c.x, c.y + 94) * s, who, pl, Color("ffc94a") if i == 0 else Color("ff8a6a"), 0)
	h._text(Vector2(gw * 0.5, gh * 0.42 - 12) * s, "VS", s * 3, Color(ink, k), 0)
