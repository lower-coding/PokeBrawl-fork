extends Node3D
## Main battle scene. Builds the stage, both fighters, the camera, the HUD, effects,
## sound and the AI, and runs the battle: start, KO, rematch, pause and training.
##
## Launch: godot --path game -- [--p1=pikachu] [--p2=snorlax] [--diff=normal]
##         [--stage=stadium|glade] [--training] [--aivsai] [--test=name] [--lang=en|es]
## Online:  --host [--p1=species]            hosts a game (port 7777)
##          --join=IP [--p1=species]         joins someone else's
##          --bot (the AI plays your own Pokémon), --lag=ms --jitter=ms --loss=%

var options := {"rumble": true, "shake": 1.0, "volume": 1.0}
var ground_y := 0.0
var mode := "combat"            # combat, training
var paused := false

var arena: Arena
var vfx: Vfx
var fx: Fx
var audio: Audio
var combat: Combat
var camera: BattleCamera
var hud: Hud
var menu: Menu
var ai: AI
var player_ai: AI               # only with --aivsai (tests)
var net: Net                     # online only
var fighters: Array = []
var player: Fighter
var _fonts := {}
var _end_t := -1.0
var _rematch_said := false
var _no_input := 0.0          # at the start, so the menu's A press does not make it jump
var _args := {}


func _ready() -> void:
	Controls.configure()
	# Less input lag: "mailbox" VSync does not wait on the frame queue and does not
	# tear. If the system does not support it, the normal mode stays.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var parts := a.substr(2).split("=")
			_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	# The language follows the system; --lang=en or --lang=es forces one.
	if _args.has("lang"):
		TranslationServer.set_locale(_args.lang)
	process_physics_priority = -20
	set_stage(_args.get("stage", "stadium"))
	combat = Combat.new()
	combat.main = self
	combat.process_physics_priority = 10
	add_child(combat)
	vfx = Vfx.new()
	vfx.main = self
	add_child(vfx)
	fx = Fx.new()
	fx.main = self
	add_child(fx)
	audio = Audio.new()
	audio.main = self
	add_child(audio)
	camera = BattleCamera.new()
	camera.main = self
	camera.fov = 62.0
	add_child(camera)
	camera.current = true
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	menu = Menu.new()
	menu.main = self
	add_child(menu)
	if _args.has("training"):
		mode = "training"
		menu.choice.mode = "training"
	# With --p1, --test or --aivsai it goes straight into battle; otherwise, to the menu.
	if _args.has("host") or _args.has("join"):
		var err := start_net(_args.has("host"), _args.get("join", ""), _args.get("p1", "pikachu"))
		if err != "":
			push_error(err)
	elif _args.has("p1") or _args.has("aivsai") or (_args.has("test") and not _args.test.begins_with("menu")):
		start_battle(_args.get("p1", "pikachu"), _args.get("p2", "snorlax"), _args.get("diff", "normal"))
	else:
		menu.open_menu()
	if _args.has("test"):
		var p: Node = preload("res://scripts/tests.gd").new()
		p.main = self
		p.test_name = _args.test
		add_child(p)
	elif not menu.is_open and net == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func font(bold := true) -> Font:
	var k := "n" if bold else "r"
	if not _fonts.has(k):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.font_weight = 700 if bold else 500
		_fonts[k] = f
	return _fonts[k]


## Builds the stage: "stadium" (the gym one) or "glade" (outdoors). It can be changed
## in the menu; it is rebuilt from scratch.
func set_stage(stage_id: String) -> void:
	if arena and arena.stage == stage_id:
		return
	if arena:
		arena.queue_free()
		remove_child(arena)
	arena = GladeArena.new() if stage_id == "glade" else Arena.new()
	arena.stage = stage_id
	arena.main = self
	add_child(arena)
	move_child(arena, 0)
	arena.build()
	if hud and fighters.size() == 2:
		portraits(fighters[0].species, fighters[1].species)


func start_battle(p1: String, p2: String, diff: String) -> void:
	vfx.clear()
	for l in fighters:
		l.queue_free()
	fighters.clear()
	combat.clear()
	if ai:
		ai.queue_free()
	if player_ai:
		player_ai.queue_free()
	var side := 1.0 if net and not net.host else -1.0
	var a := _create(p1, 0, Vector3(7 * side, 0, 0), -PI * 0.5 * side)
	var b := _create(p2, 1, Vector3(-7 * side, 0, 0), PI * 0.5 * side)
	a.rival = b
	b.rival = a
	player = a
	a.is_player = true
	ai = null
	if net:
		_setup_net(a, b)
	else:
		_setup_ai(a, b, diff)
	combat.targets = fighters.duplicate()
	camera.target = a
	camera.yaw = -PI * 0.5 * -side
	_end_t = -1.0
	_rematch_said = false
	_no_input = 0.25
	Engine.time_scale = 1.0
	portraits(p1, p2)
	_introduce()
	audio.cry(p1, a.global_position)


func _setup_ai(a: Fighter, b: Fighter, diff: String) -> void:
	ai = AI.new()
	ai.main = self
	ai.me = b
	ai.rival = a
	ai.difficulty = diff
	ai.process_physics_priority = -10
	add_child(ai)
	if _args.has("aivsai"):
		player_ai = AI.new()
		player_ai.main = self
		player_ai.me = a
		player_ai.rival = b
		player_ai.difficulty = diff
		player_ai.process_physics_priority = -10
		add_child(player_ai)
		a.is_player = false


func _introduce() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	hud.clear_log()
	hud.log_entry(tr("Go, %s!") % tr(a.data.display_name))
	hud.log_entry(tr("%s jumps onto the field!") % tr(b.data.display_name))
	if mode == "training":
		hud.log_entry(tr("Training. R resets, T stops or frees the rival, F3 shows the hitboxes."))


func _create(sp: String, eq: int, pos: Vector3, yaw: float) -> Fighter:
	var l := Fighter.new()
	add_child(l)
	l.setup(self, sp, eq)
	l.global_position = pos
	l.face_yaw = yaw
	l.start_pos = pos
	l.start_yaw = yaw
	l.reset_physics_interpolation()
	l.defeated.connect(_on_defeat)
	fighters.append(l)
	return l


func rematch() -> void:
	var a: Fighter = fighters[0]
	var b: Fighter = fighters[1]
	combat.clear()
	vfx.clear()
	a.reset(a.start_pos, a.start_yaw)
	b.reset(b.start_pos, b.start_yaw)
	camera.yaw = a.start_yaw + PI
	_end_t = -1.0
	_rematch_said = false
	Engine.time_scale = 1.0
	_introduce()


func _on_defeat(who: Fighter) -> void:
	if _end_t >= 0.0:
		return
	_end_t = 0.0
	# Brief slow motion: the last hit is visible, without taking control away. Not
	# online: time has to run the same on both machines.
	if net == null:
		Engine.time_scale = 0.35
	var winner: Fighter = who.rival
	hud.log_entry(tr("%s fainted!") % tr(who.data.display_name))
	hud.log_entry(tr("%s wins.") % tr(winner.data.display_name))
	audio.play_sound("ko", who.global_position, -2.0)


# ---------------------------------------------------------------- online

## Hosts a game or joins someone else's. Returns an error or "".
## With "species" (a shortcut for arguments and tests) it is picked and marked ready on
## connecting; without it, once connected both go to the menu's selection.
func start_net(as_host: bool, ip: String, species := "") -> String:
	close_net()
	net = Net.new()
	net.main = self
	net.lag_sim = float(_args.get("lag", "0")) / 1000.0
	net.jitter_sim = float(_args.get("jitter", "0")) / 1000.0
	net.loss_sim = float(_args.get("loss", "0"))
	add_child(net)
	menu.rival_choice_id = ""
	menu.rival_ready = false
	net.connected.connect(func():
		if species != "":
			menu.online = true
			menu.choice.p1 = species
			menu.me_ready = true
			net.send_event({"t": "choice", "species": species, "ready": true})
			check_start()
		else:
			menu.online_connected())
	net.event.connect(_net_event)
	net.disconnected.connect(_disconnection)
	var err := net.create() if as_host else net.join(ip)
	return err


func close_net() -> void:
	if net:
		net.close()
		net.queue_free()
		net = null


## The host starts the battle when both are ready.
func check_start() -> void:
	if net == null or not net.host or not menu.me_ready or not menu.rival_ready or menu.rival_choice_id == "":
		return
	var mine: String = menu.choice.p1
	var theirs: String = menu.rival_choice_id
	menu.me_ready = false
	menu.rival_ready = false
	net.send_event({"t": "start", "host": mine, "guest": theirs})
	_start_online(mine, theirs)


func _setup_net(a: Fighter, b: Fighter) -> void:
	b.is_remote = true
	b.is_player = false
	net.local = a
	net.remote = b
	net.frame = 0
	net.in_battle = true
	if _args.has("bot"):
		ai = AI.new()
		ai.main = self
		ai.me = a
		ai.rival = b
		ai.difficulty = _args.get("diff", "normal")
		ai.process_physics_priority = -10
		add_child(ai)
		a.is_player = false


func _net_event(d: Dictionary) -> void:
	match d.t:
		"choice":
			menu.rival_choice(d.species, d.ready)
			check_start()
		"start":
			menu.me_ready = false
			menu.rival_ready = false
			_start_online(d.guest, d.host)
		"to_selection":
			_to_selection(false)
		"hit":
			# Confirmation from the rival: my hit landed. Number and type, like offline.
			if fighters.size() > 1 and d.damage > 0.5:
				vfx.number(d.point, d.damage, d.affinity)
				if d.affinity > 1.05:
					hud.log_entry(tr("It's super effective!"))
				elif d.affinity < 0.95:
					hud.log_entry(tr("It's not very effective..."))
		"effect":
			if net.local:
				net.local.effect(d.type, d.v)
		"rematch":
			rematch()
		"asks_rematch":
			if net.host and _end_t > 1.0:
				net.send_event({"t": "rematch"})
				rematch()


func _start_online(mine: String, theirs: String) -> void:
	# From the menu, with the VS screen; from arguments (tests), straight in.
	if menu.is_open:
		menu.show_vs(mine, theirs)
		return
	start_battle(mine, theirs, "normal")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not _args.has("test") else Input.MOUSE_MODE_VISIBLE


## Online, after a battle: both pick again without dropping the connection.
func _to_selection(warn: bool) -> void:
	if net == null:
		return
	if warn:
		net.send_event({"t": "to_selection"})
	net.in_battle = false
	net.local = null
	net.remote = null
	for l in fighters:
		l.queue_free()
	fighters.clear()
	player = null
	combat.clear()
	combat.targets = []
	vfx.clear()
	if ai:
		ai.queue_free()
		ai = null
	_end_t = -1.0
	hud.clear_log()
	menu.online = true
	menu.open_menu("selection")


func _disconnection(reason: String) -> void:
	hud.log_entry(reason)
	push_warning(reason)
	if net:
		net.queue_free()
		net = null
	if _args.get("test", "") == "net":
		return
	back_to_menu()
	menu.disconnected(reason)


## For the Cobblemon particle interpreter: ground height under a point.
func ground_at(_p: Vector3, _from: float) -> float:
	return ground_y


func shake_camera(k: float, pos: Vector3) -> void:
	var d := camera.global_position.distance_to(pos)
	camera.shake_camera(k * clampf(1.4 - d / 25.0, 0.3, 1.0))


# ---------------------------------------------------------------- player input

func _physics_process(delta: float) -> void:
	if _end_t >= 0.0:
		_end_t += delta / maxf(Engine.time_scale, 0.01)
		if _end_t > 0.9:
			Engine.time_scale = 1.0
		if _end_t > 1.6 and not _rematch_said:
			_rematch_said = true
			hud.log_entry((tr("%s rematch, %s pick another.") if net else tr("%s rematch, %s menu.")) % [Controls.glyph("jump"), Controls.glyph("menu_back")])
	if _no_input > 0.0:
		_no_input -= delta
		if player:
			player.ctrl.clear()
		return
	if player == null or not player.is_player or paused:
		return
	var c := player.ctrl
	c.move_input = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	c.yaw = camera.yaw
	for a in ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "descend"]:
		if Input.is_action_just_pressed(a):
			c.press(a)
		elif Input.is_action_pressed(a):
			c.held[a] = true
		else:
			c.release(a)


func _unhandled_input(ev: InputEvent) -> void:
	Controls.notice(ev)
	if ev.is_action_pressed("debug"):
		hud.debug = not hud.debug
	if fighters.size() < 2:
		return
	if ev.is_action_pressed("reset") and net == null and (mode == "training" or _end_t > 1.0):
		rematch()
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_T and mode == "training" and ai:
		ai.mode = "still" if ai.mode == "active" else "active"
		ai.me.ctrl.move_input = Vector2.ZERO
	if _end_t > 1.6 and ev.is_action_pressed("jump"):
		if net == null:
			rematch()
		elif net.host:
			net.send_event({"t": "rematch"})
			rematch()
		else:
			net.send_event({"t": "asks_rematch"})
	elif _end_t > 1.6 and ev.is_action_pressed("menu_back"):
		if net:
			_to_selection(true)
		else:
			back_to_menu()
	if ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused and not menu.is_open and not _args.has("test"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## HUD and jumbotron portraits for this matchup.
func portraits(p1: String, p2: String) -> void:
	hud.prepare_portraits([p1, p2])
	arena.screens(hud._portraits[0].vp.get_texture(), hud._portraits[1].vp.get_texture(),
		Roster.TYPE_COLOR[Roster.POKEMON[p1].types[0]], Roster.TYPE_COLOR[Roster.POKEMON[p2].types[0]])


## Leaves the battle and returns to the menu with the last picks.
func back_to_menu() -> void:
	if net:
		net.close()
		net.queue_free()
		net = null
	if paused:
		paused = false
		get_tree().paused = false
	vfx.clear()
	for l in fighters:
		l.queue_free()
	fighters.clear()
	player = null
	combat.clear()
	combat.targets = []
	if ai:
		ai.queue_free()
		ai = null
	if player_ai:
		player_ai.queue_free()
		player_ai = null
	_end_t = -1.0
	Engine.time_scale = 1.0
	hud.clear_log()
	menu.open_menu()


func toggle_pause() -> void:
	# Online the game does not pause: the rival keeps playing.
	if net and not paused:
		return
	paused = not paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
