class_name Menu
extends Node
## Menus: white and clean like Sword and Shield's, laid out like Smash Ultimate's. The
## stage is not behind them: it is only built when the battle starts. Screens:
##   title       the logo; A to enter
##   main        Battle, Online, Training, Moves, Options, Quit
##   online      Host game, Join, Back
##   waiting     host waiting: its IPs and whether the router opened the port
##   join        type the IP (keyboard, or digit by digit with the gamepad)
##   connecting  trying to join someone else's game
##   format      Battle, Training and hosting online: 1 vs 1 or 3 vs 3, before anyone picks
##   selection   Pokémon grid on top, each side's picks below with their moves, and the
##               battle's options (stage, difficulty, rules, edit moves, fight). Random picks a
##               Pokémon on the grid and rolls moves on the options. Online: each picks their
##               own and the host picks the stage and the rules. A team stays hidden from the
##               rival until both are ready
##   rules       a 3 vs 3's rules for this battle (BattleRules), from the selection
##   moves       each Pokémon's default four moves and ability, its stats sheet and each move's
##               details. Opened from the selection it lists only that battle's picks, and what
##               changes there lasts for that battle (prepping)
##   options     controls, sound, screen and language (Options)
##   vs          both face to face before the battle
## Logic and input live here; MenuDraw draws. Visible text is English and goes through tr()
## when drawn (game/i18n).

const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFFICULTY_NAME := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
const STAGES := ["night", "floating", "league"]
const STAGE_NAME := {"night": "Night Stadium", "floating": "Floating Stadium", "league": "League Stadium"}
const STAGE_TEXT := {"night": "A Galar stadium at night, packed and walled all round: nobody falls off.",
	"floating": "A platform over the void. Whoever is pushed off the edge is out.",
	"league": "The League's coliseum. The field closes in bit by bit: outside it you lose HP."}
const PORTRAIT_SIZE := Vector2i(340, 240)
const FORM_ZONE := 10            # a wall tab's zone number: cell * this + which form
const MAIN_MENU := [["combat", "Battle", "Against the AI. Pick your Pokémon, the rival and the difficulty."],
	["online", "Online", "1 vs 1 or 3 vs 3 with a friend over the internet."],
	["training", "Training", "Still or active rival, no rush. R resets, T stops or frees the rival."],
	["moves", "Moves", "Pick each Pokémon's four moves and its ability, and see what each one does."],
	["options", "Options", "Controls, sound, screen and language."],
	["quit", "Quit", "Close the game."],
	["profile", "Profile", "Your trainer and your name. Online, your rival sees them."]]
const ONLINE := [["create", "Host game", "Your friend joins with your IP. Port 7777 (UDP)."],
	["join", "Join", "Type the IP of whoever hosted the game."],
	["back", "Back", ""]]
const FORMATS := [["1v1", "1 vs 1", "One Pokémon each."],
	["3v3", "3 vs 3", "Three Pokémon a side, one on the field at a time. Switch between them."],
	["back", "Back", ""]]
const IP_CHARS := "0123456789."
## Headings among a move slot's options: rows that are not moves and the cursor skips.
const OWN_MOVES := "#own"
const COMMON_MOVES := "#common"
## The profile's name: up to NAME_MAX of these (with the pad, each letter goes round them).
const NAME_MAX := 12
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_."
const PROFILE_COLUMNS := 3
## The on-screen keyboard for the name (pad and mouse; the real keyboard types directly):
## four rows of ten keys and a row of four wide ones.
const NAME_KEYS := [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ñ"],
	["Z", "X", "C", "V", "B", "N", "M", "-", "_", "."], ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["shift", "space", "del", "done"]]
## The main and online menus are tiles of different sizes (MenuDraw): where each arrow goes
## from each one ([up, down, left, right], -1 stays).
const MAIN_NAV := [[-1, -1, -1, 1], [6, 3, 0, 2], [6, 4, 1, -1], [1, -1, 0, 4], [2, 5, 3, -1], [4, -1, 3, -1], [-1, 2, 1, -1]]
const ONLINE_NAV := [[-1, -1, -1, 1], [-1, 2, 0, -1], [1, -1, 0, -1]]
const CRY_DB := -30.0            # a Pokémon's cry on being chosen
const VS_CRY_DB := -22.0         # and on the VS screen

var main: Node
var is_open := false
var screen := "title"
var cursor := 0
## The next battle. "format": 1v1 or 3v3; "team", "team2": each side's picks in a 3 vs 3, the
## first one leads (it is "p1" or "p2" too); "rules": BattleRules; "loadouts": per side, species ->
## the moves rolled for this battle (what is chosen by hand is saved, in Loadout). Not saved: it
## lasts until the game closes.
var choice := {"p1": "pikachu", "p2": "snorlax", "diff": "normal", "mode": "combat", "stage": "night",
	"format": "1v1", "team": [], "team2": [], "rules": BattleRules.defaults(), "loadouts": [{}, {}]}
var team_preview := ""           # a 3 vs 3's pick: who the cursor is on, shown in the next slot
var form_pick := {}              # wall Pokémon -> the form showing (in memory only)
var rules_cursor := 1            # the Rules screen: highlighted row (0 is a heading)
var rules_top := 0               # first row shown (it scrolls)
var online := false
var sel_phase := "p1"             # p1, p2 (the rival against the AI), setup (options and start)
var setup_cursor := 0
var me_ready := false
var rival_choice_id := ""
var rival_loadout := {}          # the online rival's moves and ability (sent with its choice)
var rival_trainer := ""          # and its trainer
var rival_ready := false
var rival_count := 0             # online 3 vs 3: how many the rival has picked
var rival_team: Array = []       # its team, once it is ready (not before)
var rival_loadouts := {}         # species -> moves and ability, for that team
var _hosting := false            # the format screen is for a game about to be hosted
var message := ""                # notices (connection errors, disconnects), already translated
var ip := ""
var confirm := {}                # a yes/no question on top: {text, yes (Callable), on (0 no, 1 yes)}
var portraits := {}               # species -> Texture2D (grid icons)
var enter_t := 0.0               # time on this screen (entry animations)
var draw: MenuDraw
var _key := Vector2i.ZERO        # selected key of the on-screen keypad (column, row)
var _t := 0.0
var _vs_t := -1.0
var _vs := []                    # [mine, theirs] on the VS screen
var _renders := {}               # slot -> {vp, model, species, used}: live 3D renders on the menus
var _generating := false
var cries := 0                   # how many so far (the tests count them)
var _all_forms: Array = []       # what all_forms() found
# Moves screen: pokemon (list), slots (its 4 + ability), list (options for the slot)
var edit_phase := "pokemon"
var edit_sp := ""
var edit_side := -1              # whose pick is being edited; -1, a default rather than a pick
var edit_slot := 0               # 0-3: moves, 4: ability
var edit_cursor := 0             # highlighted option in the list
var edit_top := 0                # first option shown (the list scrolls)
var details := false             # the details panel of the highlighted move
var _edit_return := "main"       # where B leaves the Moves screen to
var rival_name := ""             # the online rival's name
var rival_version := ""          # the online rival's game version ("" until it says)
# Profile screen: -1 is the name, 0.. the trainers' grid.
var profile_cursor := 0
var name_edit := false           # typing the name
var name_key := Vector2i.ZERO    # the on-screen keyboard's key (column 0-9, row 0-4)
var name_lower := false          # its letters in lowercase
var _clicked := false            # a left click on what the pointer is over: accepts, this frame
var _back_click := false         # a right click: back, this frame


func _ready() -> void:
	var saved := _load_ip()
	ip = saved if saved != "" else "192.168.1."
	draw = MenuDraw.new()
	draw.m = self


## One entry per wall cell, as the form showing. Echoes share their base's cell.
func pokemon_list() -> Array:
	var list: Array = []
	for sp in all_forms():
		if not Roster.POKEMON[sp].has("echo_of"):
			list.append(form_pick.get(sp, sp))
	return list


## The wall's cell for "sp", showing that form.
func cell_of(sp: String) -> int:
	if Roster.POKEMON.has(sp):
		form_pick[Roster.base_of(sp)] = sp
	return maxi(pokemon_list().find(sp), 0)


## Whether a form of "sp" is on this team.
func on_team(sp: String, team: Array) -> bool:
	return team.any(func(o): return Roster.base_of(o) == Roster.base_of(sp))


## The forms of "sp" that can be picked: more than one puts tabs on its cell.
func forms_of(sp: String) -> Array:
	var all := all_forms()
	return Roster.forms(sp).filter(func(f): return f in all)


## The highlighted cell shows its next form. False if it has no other.
func _next_form() -> bool:
	var sp: String = pokemon_list()[cursor]
	var forms := forms_of(sp)
	if forms.size() < 2:
		return false
	form_pick[Roster.base_of(sp)] = forms[(forms.find(sp) + 1) % forms.size()]
	return true


## The form the highlighted cell now shows takes the place of the one on the team, if any, and is
## what this side has picked so far.
func _form_changed() -> void:
	var sp: String = pokemon_list()[cursor]
	if team_battle():
		var picks: Array = choice[_picks_key()]
		for i in picks.size():
			if Roster.base_of(picks[i]) == Roster.base_of(sp):
				picks[i] = sp
	_pick_on_wall(cursor)


## LB / L1 / Q on the wall.
func _flip_form() -> void:
	if _next_form():
		_form_changed()


## A click on a cell's tab: that form, without picking it.
func _click_form(cell: int, which: int) -> void:
	var forms := forms_of(pokemon_list()[cell])
	if which >= forms.size():
		return
	cursor = cell
	form_pick[Roster.base_of(forms[which])] = forms[which]
	_form_changed()


## Every Pokémon and form with all its moves done (the rest are half finished). Looked up once:
## each check goes to the disk, and the wall asks for this many times a frame.
func all_forms() -> Array:
	if not _all_forms.is_empty():
		return _all_forms
	for sp in Roster.POKEMON:
		var data: Dictionary = Roster.POKEMON[sp]
		var ready := true
		for move in data.moves:
			if not Moves.DATA.has(move) or not ResourceLoader.exists(Moves.DATA[move].script):
				ready = false
		if ready:
			_all_forms.append(sp)
	return _all_forms


# ---------------------------------------------------------------- open and close

func open_menu(en := "") -> void:
	is_open = true
	_t = 0.0
	_vs_t = -1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.camera.target = null
	if main.arena:
		main.arena.visible = false
		# Nothing to show behind the menus: the stage stops (crowd, clocks, the League's field).
		main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	if en == "":
		en = "main" if screen != "title" else "title"
	_go(en)
	if portraits.is_empty() and not _generating:
		_generate_portraits()


func close() -> void:
	is_open = false
	confirm = {}
	_free_renders()
	if main.arena:
		main.arena.visible = true
		main.arena.process_mode = Node.PROCESS_MODE_INHERIT


func _go(p: String) -> void:
	screen = p
	main.music.play(p if p in ["selection", "vs", "moves"] else "menu")
	cursor = 0
	enter_t = 0.0
	details = false
	confirm = {}
	if p == "selection":
		me_ready = false
		sel_phase = "p1"
		cursor = cell_of(choice.p1)
		if online:
			if rival_choice_id != "":
				choice.p2 = rival_choice_id
			rival_count = 0
			rival_team = []
			if team_battle():
				choice.team = []
				choice.team2 = []
				team_preview = pokemon_list()[cursor]
			send_choice()
		elif team_battle():
			# Back from a battle both teams are still picked: straight to its options.
			if choice.team.size() == Party.SIZE and choice.team2.size() == Party.SIZE:
				_to_setup()
			team_preview = pokemon_list()[cursor]
	elif p == "format":
		cursor = maxi(FORMATS.map(func(f): return f[0]).find(choice.format), 0)
	elif p == "profile":
		name_edit = false
		profile_cursor = TrainerData.ids().find(main.options.trainer)
	elif p == "moves":
		edit_phase = "pokemon"
		cursor = cell_of(choice.p1)
		edit_side = -1
		edit_sp = pokemon_list()[cursor]


## Online: once connected, both go on to pick.
func online_connected() -> void:
	online = true
	rival_choice_id = ""
	rival_version = ""
	rival_ready = false
	message = ""
	choice.loadouts = [{}, {}]
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
	if a == "menu_back" and _back_click:
		return true
	return _t > 0.15 and Input.is_action_just_pressed(a)


func _accept() -> bool:
	return _clicked or _pressed("menu_accept") or _pressed("jump")


func _process(delta: float) -> void:
	_menu_frame(delta)
	_clicked = false
	_back_click = false


func _menu_frame(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	enter_t += delta
	if draw:
		draw.step(delta)
	if _vs_t >= 0.0:
		_vs_t += delta
		if _vs_t > 2.2:
			_vs_t = -1.0
			var vs := _vs.duplicate()
			close()
			if not online:
				main.set_stage(choice.stage)
			main.start_battle(vs[0], vs[1], choice.diff, rival_loadout if online else {}, rival_trainer if online else "")
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not confirm.is_empty():
		_confirm_input()
		return
	match screen:
		"title":
			if _accept():
				_sound("ok")
				_go("main")
		"main":
			_move_nav(MAIN_NAV)
			if _accept():
				_sound("ok")
				match MAIN_MENU[cursor][0]:
					"combat", "training":
						online = false
						_hosting = false
						choice.mode = MAIN_MENU[cursor][0]
						main.mode = choice.mode
						_go("format")
					"online":
						message = ""
						_go("online")
					"moves":
						_edit_return = "main"
						_go("moves")
					"options":
						_go("options")
					"profile":
						_go("profile")
					"quit":
						get_tree().quit()
			elif _pressed("menu_back"):
				_sound("back")
				_go("title")
		"format":
			_move_nav(ONLINE_NAV)
			if _accept():
				_sound("ok")
				if FORMATS[cursor][0] == "back":
					_go("online" if _hosting else "main")
				else:
					choice.format = FORMATS[cursor][0]
					choice.team = []
					choice.team2 = []
					choice.loadouts = [{}, {}]
					if _hosting:
						var err: String = main.start_net(true, "")
						message = err
						_go("waiting" if err == "" else "online")
					else:
						_go("selection")
			elif _pressed("menu_back"):
				_sound("back")
				_go("online" if _hosting else "main")
		"online":
			_move_nav(ONLINE_NAV)
			if _accept():
				_sound("ok")
				match ONLINE[cursor][0]:
					"create":
						_hosting = true
						_go("format")
					"join":
						_go("join")
						_key = Vector2i.ZERO
					"back":
						_go("main")
			elif _pressed("menu_back"):
				_sound("back")
				_go("main")
		"waiting", "connecting":
			if _pressed("menu_back"):
				_sound("back")
				main.close_net()
				_go("online")
		"join":
			_edit_ip_pad()
		"selection":
			_selection()
		"moves":
			_edit_moves()
		"options":
			main.options.menu_input(self)
		"rules":
			_rules_input()
		"profile":
			_profile_input()


func _move_nav(nav: Array) -> void:
	var to := -1
	for i in 4:
		if _pressed(["move_up", "move_down", "move_left", "move_right"][i]):
			to = nav[cursor][i]
	if to >= 0 and to != cursor:
		cursor = to
		_sound("move")


## Menu sounds: soft and short (move, ok, back).
func _sound(kind := "move") -> void:
	main.audio.ui(kind)


## A yes/no question on top of the screen (leaving an online room...). B or "No" closes it.
func ask(text: String, yes: Callable) -> void:
	confirm = {"text": text, "yes": yes, "on": 0, "t": 0.0}


func _confirm_input() -> void:
	confirm.t += get_process_delta_time()
	if _pressed("move_left") or _pressed("move_right") or _pressed("move_up") or _pressed("move_down"):
		confirm.on = 1 - int(confirm.on)
		_sound("move")
	if _accept():
		var yes: Callable = confirm.yes
		var take: bool = confirm.on == 1
		confirm = {}
		if take:
			_sound("ok")
			yes.call()
		else:
			_sound("back")
	elif _pressed("menu_back"):
		_sound("back")
		confirm = {}


# ---------------------------------------------------------------- IP

## On-screen keypad for the IP. With the gamepad: move between keys, A presses, B deletes
## (and goes back when the IP is empty). With the keyboard: type it, Enter connects,
## Ctrl+V pastes, Esc goes back. Both work at any time.
const KEYPAD := [["1", "2", "3", "del"], ["4", "5", "6", "paste"], ["7", "8", "9", "clear"], [".", "0", "connect", "connect"]]


func _edit_ip_pad() -> void:
	var before := _key
	if _pressed("move_left"):
		_key.x = (_key.x + 3) % 4
	elif _pressed("move_right"):
		_key.x = (_key.x + 1) % 4
	elif _pressed("move_up"):
		_key.y = (_key.y + 3) % 4
	elif _pressed("move_down"):
		_key.y = (_key.y + 1) % 4
	# "Connect" spans two keys: landing on its right half moves to its left half.
	if _key.y == 3 and _key.x == 3:
		_key.x = 2
	if _key != before:
		_sound("move")
	if Controls.last_device != "keyboard":
		if _accept():
			_sound("ok")
			_press_key(KEYPAD[_key.y][_key.x])
		elif _pressed("menu_back"):
			if ip.is_empty():
				_sound("back")
				_go("online")
			else:
				ip = ip.substr(0, ip.length() - 1)


func key_label(k: String) -> String:
	match k:
		"del":
			return "<-"
		"paste":
			return tr("Paste")
		"clear":
			return tr("Clear")
		"connect":
			return tr("Connect")
	return k


func key_on() -> Vector2i:
	return _key


func _press_key(k: String) -> void:
	match k:
		"del":
			ip = ip.substr(0, ip.length() - 1)
		"clear":
			ip = ""
		"paste":
			_paste()
		"connect":
			_connect_peer()
		_:
			if ip.length() < 15:
				ip += k


func _paste() -> void:
	var clean := ""
	for ch in DisplayServer.clipboard_get().strip_edges():
		if IP_CHARS.contains(ch):
			clean += ch
	ip = clean.substr(0, 15)


func _unhandled_input(ev: InputEvent) -> void:
	# (The tests drive the menus with actions: the real pointer resting over their window
	# must not move the cursor.)
	if is_open and (ev is InputEventMouseMotion or ev is InputEventMouseButton) and confirm.is_empty() and _vs_t < 0.0 			and not (ev is InputEventMouseMotion and main._args.has("test")):
		_mouse(ev)
	if is_open and screen == "options":
		main.options.menu_event(self, ev)
		return
	if is_open and screen == "profile" and name_edit and ev is InputEventKey and ev.pressed:
		_type_name(ev)
		get_viewport().set_input_as_handled()
		return
	if not is_open or screen != "join" or not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	if k.keycode == KEY_BACKSPACE:
		ip = ip.substr(0, ip.length() - 1)
	elif k.keycode == KEY_ESCAPE:
		_go("online")
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_connect_peer()
	elif k.keycode == KEY_V and k.ctrl_pressed:
		_paste()
	elif k.unicode > 0 and IP_CHARS.contains(char(k.unicode)) and ip.length() < 15:
		ip += char(k.unicode)
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

## The options under the picks, in order. Online the guest cannot change the stage.
func setup_items() -> Array:
	var out: Array = ["stage"]
	if not online and choice.mode != "training":
		out.append("diff")
	return out + ["rules", "build", "ready" if online else "fight"]


func _selection() -> void:
	if sel_phase != "setup" and _pressed("mov1"):
		_flip_form()
	var list := pokemon_list()
	var n := list.size()
	var host: bool = online and main.net != null and main.net.host
	# Online, the host can also change the stage from the grid (RB / E).
	if host and sel_phase != "setup" and _pressed("mov2"):
		_cycle_stage(1)
	if sel_phase == "setup":
		_setup_input(list)
		return
	if _pressed("menu_info"):
		_random_pick()
		return
	var to := cursor
	if _pressed("move_right"):
		to = mini(cursor + 1, n - 1)
	elif _pressed("move_left"):
		to = maxi(cursor - 1, 0)
	elif _pressed("move_down"):
		to = _wall_step(cursor, 1)
	elif _pressed("move_up"):
		to = _wall_step(cursor, -1)
	if to != cursor:
		_pick_on_wall(to)
	if _accept():
		_take(list[cursor])
	elif _pressed("menu_back"):
		_sound("back")
		if team_battle() and not (online and choice.team.is_empty()):
			_team_back()
		elif online:
			ask(tr("Leave the room? You will be disconnected."), func():
				main.close_net()
				online = false
				_go("online"))
		elif sel_phase == "p2":
			sel_phase = "p1"
			cursor = cell_of(choice.p1)
		else:
			_go("main")


## The wall's row of cell "i".
func wall_row(i: int) -> int:
	return i / int(MenuDraw.wall_shape(pokemon_list().size()).cols)


## The cell "step" rows from cell "i", the one right above or below it on screen (a shorter last
## row is centered). There and back lands on the same cell. "i" itself if no row is there.
func _wall_step(i: int, step: int) -> int:
	var n := pokemon_list().size()
	var cols: int = MenuDraw.wall_shape(n).cols
	var row := i / cols + step
	if row < 0 or row * cols >= n:
		return i
	var from_off := (cols - mini(cols, n - i / cols * cols)) * 0.5
	var to_off := (cols - mini(cols, n - row * cols)) * 0.5
	var at := i % cols + from_off - to_off
	var col := ceili(at) if to_off > from_off else floori(at)
	return row * cols + clampi(col, 0, mini(cols, n - row * cols) - 1)


## "sp" is this side's pick: on to the next side, or to the battle's options.
func _take(sp: String) -> void:
	_sound("ok")
	if team_battle():
		_team_pick(sp)
		return
	_cry(sp)
	choice[sel_phase] = sp
	if sel_phase == "p1" and not online:
		sel_phase = "p2"
		cursor = cell_of(choice.p2)
	else:
		_to_setup()


## A Pokémon's cry, when it is chosen: never for just passing over it.
func _cry(sp: String) -> void:
	cries += 1
	main.audio.cry(sp, main.camera.global_position, 1.0, CRY_DB)


## A random Pokémon or form for whoever is picking, one not on its team yet.
func _random_pick() -> void:
	var team: Array = choice[_picks_key()] if team_battle() else []
	var pool := all_forms().filter(func(sp): return not on_team(sp, team))
	if pool.is_empty():
		return
	var sp: String = pool.pick_random()
	cursor = cell_of(sp)
	team_preview = sp
	_take(sp)


func _to_setup() -> void:
	sel_phase = "setup"
	_keep_picked_loadouts()
	var items := setup_items()
	setup_cursor = items.size() - 1          # straight on Fight / Ready
	if online:
		send_choice()


func _setup_input(list: Array) -> void:
	var items := setup_items()
	var item: String = items[setup_cursor]
	var host: bool = not online or (main.net != null and main.net.host)
	if online and me_ready:
		if _pressed("menu_back"):
			_sound("back")
			me_ready = false
			send_choice()
		return
	if _pressed("mov2"):
		_random_battle_moves()
		return
	# The options sit side by side: left and right go through them, up and down change them.
	if _pressed("move_left"):
		setup_cursor = (setup_cursor + items.size() - 1) % items.size()
		_sound("move")
	elif _pressed("move_right"):
		setup_cursor = (setup_cursor + 1) % items.size()
		_sound("move")
	elif _pressed("move_up") or _pressed("move_down"):
		var step := 1 if _pressed("move_up") else -1
		match item:
			"stage":
				if host:
					_cycle_stage(step)
			"diff":
				var i := DIFFICULTIES.find(choice.diff)
				choice.diff = DIFFICULTIES[(i + step + 3) % 3]
				_sound("move")
	if _accept():
		match item:
			"stage":
				if host:
					_cycle_stage(1)
			"diff":
				var i := DIFFICULTIES.find(choice.diff)
				choice.diff = DIFFICULTIES[(i + 1) % 3]
				_sound("move")
			"rules":
				_sound("ok")
				screen = "rules"
				enter_t = 0.0
				rules_cursor = 1
				rules_top = 0
			"build":
				_sound("ok")
				_open_battle_moves()
			"fight":
				_sound("ok")
				_start_vs(choice.p1, choice.p2)
			"ready":
				_sound("ok")
				me_ready = true
				send_choice()
				main.check_start()
	elif _pressed("menu_back"):
		_sound("back")
		sel_phase = "p1" if online else "p2"
		if team_battle():
			_last_pick_back(list)
			send_choice()
		else:
			cursor = cell_of(choice[sel_phase])


# ---------------------------------------------------------------- this battle's moves

## The Moves screen came from the selection: it is about this battle, not the defaults.
func prepping() -> bool:
	return _edit_return == "selection"


## This battle's picks, each as [side, species]. Online, only mine: the rival sets its own.
func battle_picks() -> Array:
	var out: Array = []
	for side in (1 if online else 2):
		var lead: String = choice.p1 if side == 0 else choice.p2
		for sp in (choice["team" if side == 0 else "team2"] if team_battle() else [lead]):
			out.append([side, sp])
	return out


## A pick's moves and ability in this battle: what was rolled for it, or else what is saved for
## that side. The online rival's own come with its choice: until then, the roster's.
func battle_loadout(side: int, sp: String) -> Dictionary:
	var rolled: Dictionary = choice.loadouts[side].get(sp, {})
	return rolled if not rolled.is_empty() else _default_loadout(side, sp)


func _default_loadout(side: int, sp: String) -> Dictionary:
	if side == 0:
		return main.my_loadout(sp)
	return Loadout.default_for(sp) if online else main.ai_loadout(sp)


## What was rolled, for this battle only: a roll never overwrites a saved set.
func _set_battle_loadout(side: int, sp: String, lo: Dictionary) -> void:
	var checked := Loadout.valid(sp, lo)
	if checked == _default_loadout(side, sp):
		choice.loadouts[side].erase(sp)
	else:
		choice.loadouts[side][sp] = checked


## What was rolled for a Pokémon lasts while it stays picked.
func _keep_picked_loadouts() -> void:
	var picks := battle_picks()
	for side in 2:
		for sp in choice.loadouts[side].keys():
			if not [side, sp] in picks:
				choice.loadouts[side].erase(sp)


func _roll_moves(side: int, sp: String) -> void:
	var lo := battle_loadout(side, sp)
	lo.moves = Loadout.random_moves(sp)
	_set_battle_loadout(side, sp, lo)


## Random moves for every pick of this battle, from its options.
func _random_battle_moves() -> void:
	_sound("ok")
	for pick in battle_picks():
		_roll_moves(pick[0], pick[1])
	if online:
		send_choice()


## The random button: whatever fits where it shows.
func _press_random() -> void:
	if screen == "moves":
		if prepping() and edit_phase != "list":
			_sound("ok")
			_roll_moves(edit_side, edit_sp)
	elif sel_phase != "setup":
		_random_pick()
	elif not (online and me_ready):
		_random_battle_moves()


## The Moves screen for this battle's picks. With only one, straight to its slots.
func _open_battle_moves() -> void:
	_edit_return = "selection"
	var keep := sel_phase
	_go("moves")
	sel_phase = keep
	_edit_pick(0)
	edit_slot = 0
	edit_phase = "pokemon" if edit_entries().size() > 1 else "slots"


# ---------------------------------------------------------------- picking a team

## This battle is a 3 vs 3.
func team_battle() -> bool:
	return choice.format == "3v3"


## A whole team for "side": its lead, the picks, then whoever comes next in the roster until it
## is full. No species twice on a team, and no two forms of one.
func team_ids(side: int, lead: String) -> Array:
	var ids: Array = [lead]
	for sp in choice["team" if side == 0 else "team2"] + pokemon_list():
		if ids.size() < Party.SIZE and Roster.POKEMON.has(sp) and not on_team(sp, ids):
			ids.append(sp)
	return ids


func _picks_key() -> String:
	return "team" if sel_phase == "p1" else "team2"


## Pressed on the wall: adds the Pokémon to the team, or takes it out if it was already in. Its
## other form on the team is swapped for this one. The third pick moves on: to the rival's team,
## then to the battle's options.
func _team_pick(sp: String) -> void:
	var picks: Array = choice[_picks_key()]
	if sp in picks:
		picks.erase(sp)
		send_choice()
		return
	if on_team(sp, picks):
		for i in picks.size():
			if Roster.base_of(picks[i]) == Roster.base_of(sp):
				picks[i] = sp
		send_choice()
		return
	picks.append(sp)
	_cry(sp)
	if picks.size() < Party.SIZE:
		send_choice()
		return
	choice[sel_phase] = picks[0]
	if online:
		_to_setup()
	elif sel_phase == "p1":
		sel_phase = "p2"
		cursor = cell_of(choice.p2)
		team_preview = pokemon_list()[cursor]
	else:
		_to_setup()


## Back while picking: out goes the last pick; with none, to the team before or the format.
func _team_back() -> void:
	var list := pokemon_list()
	if not choice[_picks_key()].is_empty():
		_last_pick_back(list)
	elif sel_phase == "p2":
		sel_phase = "p1"
		_last_pick_back(list)
	else:
		_go("format")


## The last pick of whoever is picking comes off the team, with the cursor on it.
func _last_pick_back(list: Array) -> void:
	var sp: String = choice[_picks_key()].pop_back()
	cursor = cell_of(sp)
	team_preview = sp
	send_choice()


## A click on a pick of the team being picked takes it out ("slot": its place on the team).
func _remove_pick(side: int, slot: int) -> void:
	if sel_phase != ("p1" if side == 0 else "p2"):
		return
	var picks: Array = choice[_picks_key()]
	if slot < picks.size():
		picks.remove_at(slot)
		_sound("back")
		send_choice()


# ---------------------------------------------------------------- this battle's rules

const RULES_ROWS := 12           # rows shown at once on the Rules screen (it scrolls)


## Rows of the Rules screen: {id, kind (header, choice, action), label, value (translated),
## help, changed}.
func rules_items() -> Array:
	var out: Array = []
	var group := ""
	for d in BattleRules.DEFS:
		if not team_battle() and not d.get("any_format", false):
			continue
		if d.group != group:
			group = d.group
			out.append({"id": "h_" + group, "kind": "header", "label": tr(group)})
		var v: float = choice.rules[d.id]
		out.append({"id": d.id, "kind": "choice", "label": tr(d.label), "value": BattleRules.text(d.id, v), "changed": v != d.default,
			"help": tr(d.help) + "\n\n" + tr("Default: %s") % BattleRules.text(d.id, d.default)})
	out.append({"id": "restore_rules", "kind": "action", "label": tr("Default rules"), "value": "", "changed": false,
		"help": tr("Puts every rule back on its default.")})
	return out


func _rules_input() -> void:
	var list := rules_items()
	rules_cursor = mini(rules_cursor, list.size() - 1)
	var step := 0
	if _pressed("move_up"):
		step = -1
	elif _pressed("move_down"):
		step = 1
	if step != 0:
		for k in list.size():
			rules_cursor = (rules_cursor + step + list.size()) % list.size()
			if list[rules_cursor].kind != "header":
				break
		_sound("move")
		rules_top = clampi(rules_top, rules_cursor - RULES_ROWS + 1, rules_cursor)
		if rules_cursor == 1:
			rules_top = 0
	var it: Dictionary = list[rules_cursor]
	var change := 0
	if _pressed("move_left"):
		change = -1
	elif _pressed("move_right"):
		change = 1
	if change != 0 and it.kind == "choice" and rules_editable():
		choice.rules[it.id] = BattleRules.stepped(it.id, choice.rules[it.id], change)
		_sound("move")
	if _accept() and rules_editable():
		_sound("move")
		if it.kind == "action":
			choice.rules = BattleRules.defaults()
		else:
			choice.rules[it.id] = BattleRules.stepped(it.id, choice.rules[it.id], 1)
	elif _pressed("menu_back"):
		_sound("back")
		screen = "selection"
		enter_t = 0.0
		setup_cursor = setup_items().find("rules")
		if online:
			send_choice()


## Online only the host sets the rules; the guest can read them.
func rules_editable() -> bool:
	return not online or (main.net != null and main.net.host)


# ---------------------------------------------------------------- profile

## Profile: your name on top, your trainers below. Moving over the trainers only points
## at them; A (or a click) makes the one pointed at yours (saved). A on the name starts
## editing it: the real keyboard types straight into it (Enter ends), and an on-screen
## keyboard comes up for the pad and the mouse (Done ends; B deletes a letter).
func _profile_input() -> void:
	var list := TrainerData.ids()
	if name_edit:
		_name_keyboard()
		return
	var before := profile_cursor
	if profile_cursor < 0:
		if _pressed("move_down"):
			profile_cursor = 0
	else:
		if _pressed("move_right"):
			profile_cursor = mini(profile_cursor + 1, list.size() - 1)
		elif _pressed("move_left"):
			profile_cursor = maxi(profile_cursor - 1, 0)
		elif _pressed("move_down"):
			profile_cursor = mini(profile_cursor + PROFILE_COLUMNS, list.size() - 1)
		elif _pressed("move_up"):
			profile_cursor = profile_cursor - PROFILE_COLUMNS if profile_cursor >= PROFILE_COLUMNS else -1
	if profile_cursor != before:
		_sound("move")
	if _accept():
		_sound("ok")
		if profile_cursor < 0:
			name_edit = true
			name_key = Vector2i.ZERO
		else:
			main.options.trainer = list[profile_cursor]
			main.options.save()
	elif _pressed("menu_back"):
		_sound("back")
		_go("main")
		cursor = 6


## The on-screen keyboard with the pad (the real keyboard's keys are typing then, so they
## do not move it; the mouse presses its keys in _mouse).
func _name_keyboard() -> void:
	if Controls.last_device == "keyboard":
		if _back_click:
			_end_name()
		return
	var before := name_key
	if _pressed("move_right"):
		name_key.x = (name_key.x + (3 if name_key.y == 4 else 1)) % 10
	elif _pressed("move_left"):
		name_key.x = (name_key.x + 10 - (3 if name_key.y == 4 else 1)) % 10
	elif _pressed("move_down"):
		name_key.y = (name_key.y + 1) % 5
	elif _pressed("move_up"):
		name_key.y = (name_key.y + 4) % 5
	if name_key != before:
		_sound("move")
	if _accept():
		_press_name_key()
	elif _pressed("menu_back"):
		var n: String = main.options.player_name
		if n == "":
			_end_name()
		else:
			main.options.player_name = n.substr(0, n.length() - 1)
			_sound("back")


## The key under the on-screen keyboard's cursor (the last row's four keys are 2.5 columns
## wide each).
func name_key_id() -> String:
	if name_key.y == 4:
		return NAME_KEYS[4][mini(int(name_key.x / 2.5), 3)]
	return NAME_KEYS[name_key.y][name_key.x]


func _press_name_key() -> void:
	var k := name_key_id()
	var n: String = main.options.player_name
	match k:
		"shift":
			name_lower = not name_lower
		"space":
			if n.length() < NAME_MAX and n != "":
				n += " "
		"del":
			n = n.substr(0, n.length() - 1)
		"done":
			_end_name()
			return
		_:
			if n.length() < NAME_MAX:
				n += k.to_lower() if name_lower else k
	main.options.player_name = n
	_sound("ok" if k == "done" else "move")


func _type_name(k: InputEventKey) -> void:
	var n: String = main.options.player_name
	if k.keycode == KEY_BACKSPACE:
		n = n.substr(0, n.length() - 1)
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_end_name()
		return
	elif k.unicode > 0 and n.length() < NAME_MAX and (NAME_CHARS.contains(char(k.unicode)) or "ÁÉÍÓÚÑÜáéíóúñü".contains(char(k.unicode))):
		n += char(k.unicode)
	main.options.player_name = n


func _end_name() -> void:
	name_edit = false
	main.options.player_name = main.options.player_name.strip_edges()
	main.options.save()
	_sound("ok")


func _cycle_stage(step: int) -> void:
	var e := STAGES.find(choice.stage)
	choice.stage = STAGES[(e + step + STAGES.size()) % STAGES.size()]
	_sound("move")
	if online and main.net and main.net.host:
		main.net.send_event({"t": "stage", "id": choice.stage})


# ---------------------------------------------------------------- Moves screen

const EDIT_ROWS := 8             # options shown at once in the list


## Moves screen: pick a Pokémon in the list, then one of its four moves (or its ability),
## then what goes there. Every change is saved at once (Loadout), when prepping too, for the side
## of the pick. Y / X shows or hides the details of the highlighted move; X / R restores the
## defaults (see ask_restore); RB / E rolls random moves when prepping.
func _edit_moves() -> void:
	var list := edit_entries()
	var n := list.size()
	if _pressed("menu_info") and edit_phase != "pokemon":
		details = not details
		_sound("move")
	if _pressed("menu_extra"):
		ask_restore()
		return
	if _pressed("mov2"):
		_press_random()
	match edit_phase:
		"pokemon":
			if not prepping() and _pressed("mov1") and _next_form():
				_sound("move")
				_edit_pick(cursor)
				return
			var before := cursor
			cursor = _cycle(cursor, n)
			if cursor != before:
				_edit_pick(cursor)
			if _accept():
				_sound("ok")
				_edit_pick(cursor)
				_cry(edit_sp)
				edit_slot = 0
				edit_phase = "slots"
			elif _pressed("menu_back"):
				_sound("back")
				_leave_moves()
		"slots":
			edit_slot = _cycle(edit_slot, 5)
			# Left and right, to the next pick without going back to the list.
			if prepping() and n > 1 and (_pressed("move_left") or _pressed("move_right")):
				_sound("move")
				_edit_pick((cursor + (1 if _pressed("move_right") else n - 1)) % n)
			if _accept():
				_sound("ok")
				var options := edit_options()
				var lo := edit_loadout()
				edit_cursor = maxi(options.find(lo.moves[edit_slot] if edit_slot < 4 else lo.ability), 0)
				edit_top = clampi(edit_cursor - EDIT_ROWS / 2, 0, maxi(options.size() - EDIT_ROWS, 0))
				edit_phase = "list"
			elif _pressed("menu_back"):
				_sound("back")
				if n == 1:
					_leave_moves()
				else:
					edit_phase = "pokemon"
		"list":
			var options := edit_options()
			_browse_options(options)
			if _accept():
				_sound("ok")
				var lo := edit_loadout()
				var pick: String = options[edit_cursor]
				if edit_slot < 4:
					# Already in another slot: they swap places.
					var other: int = lo.moves.find(pick)
					if other >= 0:
						lo.moves[other] = lo.moves[edit_slot]
					lo.moves[edit_slot] = pick
				else:
					lo.ability = pick
				_store_edit(lo)
				edit_phase = "slots"
			elif _pressed("menu_back"):
				_sound("back")
				edit_phase = "slots"


## Up and down through the options, past the headings; left and right, to the other group of moves.
func _browse_options(options: Array) -> void:
	var n := options.size()
	var before := edit_cursor
	edit_cursor = _cycle(edit_cursor, n)
	if edit_cursor != before and is_heading(options[edit_cursor]):
		edit_cursor = (edit_cursor + (n - 1 if _pressed("move_up") else 1)) % n
	var common := options.find(COMMON_MOVES)
	if common >= 0 and (_pressed("move_left") or _pressed("move_right")):
		_sound("move")
		edit_cursor = 1 if edit_cursor > common else common + 1
	edit_top = clampi(edit_top, edit_cursor - EDIT_ROWS + 1, edit_cursor)
	# A group's first move brings its heading into view.
	if edit_cursor > 0 and is_heading(options[edit_cursor - 1]):
		edit_top = mini(edit_top, edit_cursor - 1)


## Restores the defaults, after asking: from the list, every Pokémon's (prepping, every pick's);
## from its slots or a slot's options, the one being edited's.
func ask_restore() -> void:
	if not restorable():
		_sound("back")
		return
	if restore_all():
		if prepping():
			ask(tr("Restore every pick's default moves and ability?"), func():
				for pick in battle_picks():
					_restore_pick(pick[0], pick[1]))
		else:
			ask(tr("Restore every Pokémon's default moves and abilities?"), func(): Loadout.restore())
		return
	var sp := edit_sp
	var side := edit_side
	ask(tr("Restore %s's default moves and ability?") % tr(Roster.POKEMON[sp].display_name), func():
		if prepping():
			_restore_pick(side, sp)
		else:
			Loadout.restore(sp)
		edit_phase = "slots")


func _restore_pick(side: int, sp: String) -> void:
	choice.loadouts[side].erase(sp)
	Loadout.restore(sp, side)


func restore_all() -> bool:
	return edit_phase == "pokemon"


## Whether there is anything for the restore button to put back.
func restorable() -> bool:
	if prepping():
		if restore_all():
			return battle_picks().any(func(pick): return _pick_changed(pick[0], pick[1]))
		return _pick_changed(edit_side, edit_sp)
	return not (all_forms().all(Loadout.is_default) if restore_all() else Loadout.is_default(edit_sp))


func _pick_changed(side: int, sp: String) -> bool:
	return choice.loadouts[side].has(sp) or not Loadout.is_default(sp, side)


func _leave_moves() -> void:
	if _edit_return == "selection":
		var keep := choice.duplicate()
		screen = "selection"
		enter_t = 0.0
		details = false
		choice = keep
		sel_phase = "setup"
		setup_cursor = setup_items().find("build")
		cursor = cell_of(choice.p1)
		if online:
			send_choice()
	else:
		_go("main")


## Up and down through n rows, wrapping around.
func _cycle(i: int, n: int) -> int:
	if n <= 0:
		return 0
	if _pressed("move_up"):
		_sound("move")
		return (i + n - 1) % n
	if _pressed("move_down"):
		_sound("move")
		return (i + 1) % n
	return i


## What can go in the slot being edited: ability ids for slot 4; for the others, move ids under
## their headings (is_heading), its own moves first and then the common ones.
func edit_options() -> Array:
	if edit_slot < 4:
		var groups := Loadout.move_groups(edit_sp)
		return [OWN_MOVES] + groups[0] + ([COMMON_MOVES] + groups[1] if not groups[1].is_empty() else [])
	return Loadout.abilities_for(edit_sp).map(func(a): return a.id)


func is_heading(option: String) -> bool:
	return option == OWN_MOVES or option == COMMON_MOVES


## Who the Moves screen lists, each as [side, species]: this battle's picks, or (side -1) the wall.
func edit_entries() -> Array:
	if prepping():
		return battle_picks()
	return pokemon_list().map(func(sp): return [-1, sp])


## The Moves screen onto its entry "i".
func _edit_pick(i: int) -> void:
	var who: Array = edit_entries()[i]
	cursor = i
	edit_side = who[0]
	edit_sp = who[1]


## The moves and ability of the Pokémon being edited.
func edit_loadout() -> Dictionary:
	return battle_loadout(edit_side, edit_sp) if prepping() else Loadout.saved(edit_sp)


## A change by hand is saved, in place of a roll if it was on one (so that roll is kept).
func _store_edit(lo: Dictionary) -> void:
	if prepping():
		choice.loadouts[edit_side].erase(edit_sp)
		Loadout.store(edit_sp, lo, edit_side)
	else:
		Loadout.store(edit_sp, lo)


## The move whose details are shown: the highlighted option, or the highlighted slot's.
func shown_move() -> String:
	if edit_phase == "list" and edit_slot < 4:
		var options := edit_options()
		return options[edit_cursor] if not options.is_empty() else ""
	if edit_phase == "slots" and edit_slot < 4:
		return edit_loadout().moves[edit_slot]
	return ""


# ---------------------------------------------------------------- online

## What the rival gets to know of my choice. In a 3 vs 3, until I am ready, only how many I
## have picked: a team seen as it is being picked could just be countered.
func send_choice() -> void:
	if main.net:
		var d := {"t": "choice", "species": choice.p1, "ready": me_ready, "loadout": battle_loadout(0, choice.p1), "trainer": main.options.trainer, "name": main.options.shown_name(),
			"ver": Menu.version()}
		if main.net.host:
			d.stage = choice.stage            # so the rival sees the stage from the start
			d.format = choice.format          # and the room's format and rules
			d.rules = choice.rules
		if team_battle():
			d.count = choice.team.size()
			if me_ready:
				choice.team = team_ids(0, choice.p1)
				d.team = choice.team
				d.loadouts = {}
				for sp in choice.team:
					d.loadouts[sp] = battle_loadout(0, sp)
		main.net.send_event(d)


## The guest: the room's format and rules, which the host decides. A format that changes starts
## the picks over.
func room_settings(d: Dictionary) -> void:
	if main.net == null or main.net.host:
		return
	if d.has("rules"):
		choice.rules = BattleRules.sanitized(d.rules)
	if not d.get("format", choice.format) in ["1v1", "3v3"] or d.get("format", choice.format) == choice.format:
		return
	choice.format = d.format
	choice.team = []
	choice.team2 = []
	choice.loadouts = [{}, {}]
	me_ready = false
	sel_phase = "p1"
	team_preview = choice.p1
	if is_open and screen == "selection":
		cursor = cell_of(choice.p1)
		send_choice()


## A 3 vs 3 rival's picks: how many, and its team and moves once it is ready.
func rival_team_choice(d: Dictionary) -> void:
	rival_count = int(d.get("count", 0))
	rival_team = []
	var team = d.get("team", [])
	if not team is Array or team.size() != Party.SIZE:
		return
	var seen := {}
	for sp in team:
		if not sp is String or not Roster.POKEMON.has(sp) or seen.has(Roster.base_of(sp)):
			return
		seen[Roster.base_of(sp)] = true
	rival_team = team
	var loadouts = d.get("loadouts", {})
	rival_loadouts = loadouts if loadouts is Dictionary else {}


## The online rival changes Pokémon or gets ready.
## The game's version (project settings), sent online so both can tell they match.
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Online: whether the rival plays another version (then the battle does not start).
func version_mismatch() -> bool:
	return rival_version != "" and rival_version != Menu.version()


func rival_choice(sp: String, ready: bool, loadout := {}, trainer := "", rival := "", ver := "") -> void:
	if not Roster.POKEMON.has(sp):
		return
	rival_version = ver if ver != "" else "?"
	rival_name = rival.substr(0, NAME_MAX)
	rival_trainer = TrainerData.valid(trainer) if trainer != "" else ""
	rival_choice_id = sp
	rival_loadout = Loadout.valid(sp, loadout)
	rival_ready = ready
	if is_open and screen == "selection":
		choice.p2 = sp


func _start_vs(mine: String, theirs: String) -> void:
	_vs = [mine, theirs]
	_vs_t = 0.0
	screen = "vs"
	enter_t = 0.0
	main.portraits(mine, theirs)
	main.audio.cry(mine, main.camera.global_position, 1.0, VS_CRY_DB)


func vs_pair() -> Array:
	return _vs


func vs_time() -> float:
	return _vs_t


## From main, online: both are ready.
func show_vs(mine: String, theirs: String) -> void:
	if not is_open:
		open_menu("selection")
	_start_vs(mine, theirs)


# ---------------------------------------------------------------- 3D renders

## A live render of a Pokémon (animated, turning a little) for a slot of the screen.
func render(slot: String, sp: String, px: Vector2i, turn := 0.45) -> Texture2D:
	var r: Dictionary = _renders.get(slot, {})
	if r.is_empty():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		r = {"vp": vp, "model": null, "species": "", "turn": turn}
		_renders[slot] = r
	r.used = true
	var vp: SubViewport = r.vp
	if vp.size != px:
		vp.size = px
	if sp != r.species:
		r.species = sp
		for ch in vp.get_children():
			ch.queue_free()
		var data := _setup_portrait(vp, sp, turn)
		r.model = data.model
		_frame_portrait(data, true, float(px.x) / maxf(px.y, 1.0))
	if r.model:
		r.model.rotation.y = PI + r.turn + sin(_t * 0.6) * 0.2
	return vp.get_texture()


func _free_renders() -> void:
	for slot in _renders:
		_renders[slot].vp.queue_free()
	_renders.clear()


## After drawing: a render this frame did not show goes away (a screen left behind, a pick taken
## out), or it would keep drawing its 3D scene unseen.
func _drop_unused_renders() -> void:
	for slot in _renders.keys():
		if _renders[slot].used:
			_renders[slot].used = false
		else:
			_renders[slot].vp.queue_free()
			_renders.erase(slot)


# ---------------------------------------------------------------- portraits

## Grid icons: each Pokémon rendered once to a texture, the shape of a slanted wall cell.
func _generate_portraits() -> void:
	_generating = true
	for sp in all_forms():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.size = PORTRAIT_SIZE
		vp.msaa_3d = Viewport.MSAA_4X
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


func _frame_portrait(r: Dictionary, body := false, aspect := 1.0) -> void:
	var m: PokeModel = r.model
	if body:
		# The whole body, wings and tails included: far enough for its height and for its
		# width (seen from any side as it turns) in a frame of this aspect.
		var box: AABB = m._res.mesh.get_aabb()
		var k: float = m.scale.x
		var half_w: float = maxf(box.size.x, box.size.z) * 0.5 * k
		var half_h: float = r.height * 0.5
		var t := tan(deg_to_rad(15.0))
		var dist: float = maxf(half_h / t, half_w / (t * aspect)) * 1.06
		var center := Vector3(0, half_h, 0)
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
	# The face above the middle: a wall cell's name covers the picture's bottom.
	var looks := face - Vector3(0, box_height * 0.15, 0)
	r.cam.position = looks + Vector3(0, box_height * 0.1, dist)
	r.cam.look_at(looks)


# ---------------------------------------------------------------- drawing

func draw_ui(h: Hud) -> void:
	draw.draw(h)
	_drop_unused_renders()


# ---------------------------------------------------------------- mouse

## The mouse works everywhere the keys do: over something (MenuDraw's zones) it moves the
## cursor there, a left click accepts it, a right click goes back. Keys on the on-screen
## keyboards are pressed straight away.
func _mouse(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_back_click = true
		return
	# The wheel scrolls like the arrows: up and down (lists, options, the setup tab under
	# the pointer), left and right through the selection's Pokémon.
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var up: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP
		var along := screen == "selection" and sel_phase != "setup"
		_tap(("move_left" if up else "move_right") if along else ("move_up" if up else "move_down"))
		return
	if draw == null:
		return
	var z: Dictionary = draw.zone_at(ev.position)
	if z.is_empty():
		return
	# A question on top: only its answers count.
	if not confirm.is_empty() and z.kind != "confirm":
		return
	_hover(z)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		match z.kind:
			"key":
				_sound("ok")
				_press_key(KEYPAD[_key.y][_key.x])
			"nkey":
				_press_name_key()
			"confirm":
				_clicked = z.i >= 0
			"restore":
				ask_restore()
			"rand":
				_press_random()
			"tslot":
				_remove_pick(z.i / Party.SIZE, z.i % Party.SIZE)
			"form":
				_click_form(z.i / FORM_ZONE, z.i % FORM_ZONE)
			"mvp":
				_click_moves_pokemon(z.i)
			"slot":
				# From the list of Pokémon, straight to that slot of the highlighted one.
				if edit_phase == "pokemon":
					_sound("ok")
					_edit_pick(cursor)
					_cry(edit_sp)
					edit_slot = z.i
					edit_phase = "slots"
				else:
					_clicked = edit_phase == "slots"
			"opt":
				_clicked = edit_phase == "list"
			_:
				_clicked = true


## A click on a Pokémon of the Moves screen: picks it, or from its slots or options
## changes to it.
func _click_moves_pokemon(i: int) -> void:
	if edit_phase == "pokemon":
		_clicked = true
	elif i != cursor:
		_sound("ok")
		_edit_pick(i)
		edit_slot = 0
		edit_phase = "slots"
		details = false
		_cry(edit_sp)


## Presses an action for one frame, as if a key had been tapped.
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func _hover(z: Dictionary) -> void:
	var before := [cursor, profile_cursor, setup_cursor, _key, name_key, edit_slot, edit_cursor, confirm.get("on")]
	match z.kind:
		"confirm":
			if z.i >= 0:
				confirm.on = z.i
		"mvp":
			if screen == "moves" and edit_phase == "pokemon" and z.i != cursor:
				_edit_pick(z.i)
		"slot":
			if edit_phase == "slots":
				edit_slot = z.i
		"opt":
			if edit_phase == "list":
				edit_cursor = z.i
		"rule":
			if rules_cursor != z.i:
				rules_cursor = z.i
				_sound("move")
		"main", "online", "format":
			if screen == z.kind:
				cursor = z.i
		"pf":
			if not name_edit:
				profile_cursor = z.i
		"wall":
			if screen == "selection" and sel_phase != "setup" and z.i != cursor:
				_pick_on_wall(z.i)
				return
		"form":
			if screen == "selection" and sel_phase != "setup" and z.i / FORM_ZONE != cursor:
				_pick_on_wall(z.i / FORM_ZONE)
				return
		"tab":
			if screen == "selection" and sel_phase == "setup" and not (online and me_ready):
				setup_cursor = z.i
		"key":
			_key = Vector2i(z.i % 4, z.i / 4)
		"nkey":
			name_key = Vector2i(z.i % 10, z.i / 10)
	if [cursor, profile_cursor, setup_cursor, _key, name_key, edit_slot, edit_cursor, confirm.get("on")] != before:
		_sound("move")


## The selection's cursor onto Pokémon "i" (keys and mouse alike).
func _pick_on_wall(i: int) -> void:
	var list := pokemon_list()
	cursor = clampi(i, 0, list.size() - 1)
	_sound("move")
	if team_battle():
		team_preview = list[cursor]
	else:
		choice[sel_phase] = list[cursor]
	if online:
		send_choice()
