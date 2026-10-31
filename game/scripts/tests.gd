extends Node
## Automated tests (godot --path game -- --test=name):
##   aivsai      headless: AI vs AI for up to 3 battles; prints how it goes and checks
##               that nothing stays active after each KO and rematch
##   moves       each of the player's moves against a still rival, with captures
##   combat      AI vs AI on screen, with captures every few seconds
##   animations  each Pokémon goes through its states and transitions looking for
##               T-poses, sinking and stuck animations (see test_animations.gd)
##   mewtwo      headless: only Mewtwo's cases of mechanics
##   mechanics   headless: concrete cases from the acceptance criteria (dodging a
##               projectile, jumping the wave, punishing a recovery, combo limit,
##               hitstop)
##   team        headless: the rules of 3 vs 3 and switching (Party, BattleRules)
##   menu_rules  with a window: the selection's Rules screen, on to a battle by those rules
##   team_battles --aivsai [--battles=N] [--speed=x] [--diff=...]: random teams, AI against
##               AI; how long they last, how often they switch, who wins
##   hud         with a window: the crosshair with nothing locked on and the stat stage tags,
##               with captures
## Captures go to captures/ and a dated copy to captures/history/.

var main: Node
var test_name := ""
var t := 0.0
var _shots: Array = []
var _taken := 0
var _battles := 0
var _hits := 0
var _last_report := 0.0
var _plan: Array = []
var _steps: Array = []          # menu steps due, played one at a time (_process)
var _step_wait := 0
var _step := 0
var _step_t := 0.0
var _fps_sum := 0
var _fps_n := 0
var _fps_min := 9999
var _flying := {}
var _stream := {}             # aivsai: manual-aim streams, move -> [active seconds, hits]
var _strip: Array = []           # moves --sequence: frames of the current move


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir())
	for l in main.fighters:
		l.hit_taken.connect(func(_q, info):
			_hits += 1
			var mid: String = info.hit.move_id
			if Moves.DATA.has(mid) and Moves.DATA[mid].get("manual_aim", false):
				_stream.get_or_add(mid, [0.0, 0])[1] += 1)
	match test_name:
		"aivsai":
			Engine.max_fps = 0
		"moves":
			main.ai.mode = "still"
			main.player.is_player = false
			main.player.locked = true
			var b: Fighter = main.fighters[1]
			# --gap=N: how far apart they start (6.5 m by default; less for melee moves).
			var gap := float(main._args.get("gap", "6.5"))
			b.reset(Vector3(-3.5, 0, 0), PI * 0.5)
			main.player.reset(Vector3(-3.5 + gap, 0, 0), -PI * 0.5)
			# --side: the camera looks from the side, to see the shape of streams and beams.
			if main._args.has("side"):
				main.camera.set_physics_process(false)
				main.camera.global_position = Vector3(0.0, 3.0, 9.5)
				main.camera.look_at(Vector3(0.0, 1.0, 0.0))
			for i in 4:
				_plan.append("mov%d" % (i + 1))
			_plan.append_array(["dodge", "jump"])
		"portraits":
			main.ai.mode = "still"
		"net":
			var pr: Node = preload("res://scripts/test_net.gd").new()
			pr.main = main
			add_child(pr)
		"menu_net":
			var pm: Node = preload("res://scripts/test_menu_net.gd").new()
			pm.main = main
			add_child(pm)
		"animations":
			var pa: Node = preload("res://scripts/test_animations.gd").new()
			pa.main = main
			add_child(pa)
		"menu":
			# [time, action, capture]: title, main menu, Battle, change Pokémon, rival,
			# then the options (stage to the floating one, difficulty up) and Fight: VS,
			# battle, pause and back to the menu.
			_plan = [[1.5, "", "menu_title"], [1.7, "menu_accept", ""], [2.3, "move_down", ""], [2.6, "", "menu_main"],
				[2.8, "move_up", ""], [3.0, "menu_accept", ""], [3.4, "menu_accept", ""], [3.8, "move_right", ""], [4.1, "move_down", ""],
				[4.8, "", "menu_selection"], [5.0, "menu_accept", ""], [5.4, "move_down", ""], [5.9, "", "menu_rival"],
				[6.1, "menu_accept", ""], [6.4, "move_left", ""], [6.5, "move_left", ""], [6.6, "move_left", ""], [6.7, "move_up", ""],
				[6.8, "move_right", ""], [6.9, "move_up", ""], [7.0, "move_right", ""], [7.1, "move_right", ""],
				[7.3, "", "menu_setup"], [7.5, "menu_accept", ""],
				[7.8, "", "menu_vs"], [10.7, "", "menu_battle"], [10.9, "pause", ""], [11.3, "", "menu_pause"],
				[11.5, "menu_back", ""], [12.2, "", "menu_back"]]
		"menu_rules":
			# Battle, 3 vs 3; your team with the mouse (a pick, one taken out, two more) and the rival's
			# with the keys; the Rules tab, a rule by mouse and keys; back and Fight.
			_plan = [[1.5, "menu_accept", ""], [2.0, "menu_accept", ""], [2.6, "move_right", ""], [2.9, "", "team_format"], [3.1, "menu_accept", ""],
				[3.6, "", "team_empty"], [3.8, "menu_accept", ""], [4.1, "click:wall:4", ""], [4.5, "", "team_two"], [4.7, "click:tslot:1", ""],
				[5.0, "click:wall:5", ""], [5.3, "click:wall:6", ""], [5.7, "", "team_rival"], [5.9, "menu_accept", ""], [6.1, "move_right", ""],
				[6.3, "menu_accept", ""], [6.5, "move_right", ""], [6.7, "menu_accept", ""], [7.2, "", "team_setup"], [7.4, "move_left", ""],
				[7.6, "move_left", ""], [7.8, "menu_accept", ""], [8.3, "", "rules_top"], [8.5, "click:rule:11", ""], [8.8, "move_right", ""],
				[9.0, "move_right", ""], [9.3, "", "rules_heal"], [9.5, "menu_back", ""], [10.0, "", "rules_back"], [10.2, "move_right", ""],
				[10.4, "move_right", ""], [10.6, "menu_accept", ""], [14.2, "", "rules_battle"]]
		"menu_moves":
			# Moves screen: Charizard's first move to Solar Beam, then Air Slash into that slot
			# (it was in the second: they swap). Its own save file, which starts empty.
			Loadout.path = "user://loadouts_test.json"
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Loadout.path))
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_down", ""], [2.4, "", ""],
				[2.6, "", "moves_main"], [2.8, "menu_accept", ""], [3.6, "move_down", ""], [3.8, "move_down", ""], [4.0, "", "moves_grid"],
				[4.2, "menu_accept", ""], [4.5, "", "moves_slots"], [4.7, "menu_accept", ""],
				[5.0, "move_down", ""], [5.2, "move_down", ""], [5.4, "move_down", ""], [5.9, "", "moves_list"],
				[6.1, "menu_accept", ""], [6.4, "", "moves_after"], [6.6, "menu_accept", ""],
				[7.3, "opt:airslash", ""], [7.6, "", "moves_swap_list"], [7.8, "menu_accept", ""],
				[8.1, "", "moves_swapped"], [8.3, "menu_info", ""], [8.6, "", "moves_details"], [8.8, "menu_info", ""],
				# Down to the ability (fifth slot), the second one; then restore: No first, then Yes.
				[9.0, "move_down", ""], [9.2, "move_down", ""], [9.4, "move_down", ""], [9.6, "move_down", ""],
				[9.8, "", "moves_ability_slot"], [10.0, "menu_accept", ""], [10.3, "move_down", ""], [10.5, "", "moves_ability_list"],
				[10.7, "menu_accept", ""], [11.0, "", "moves_ability"], [11.3, "menu_extra", ""], [11.6, "", "moves_restore_ask"],
				[11.8, "menu_accept", ""], [12.2, "menu_extra", ""], [12.4, "move_right", ""], [12.6, "menu_accept", ""],
				[13.0, "", "moves_restored"]]
		"menu_prep":
			# Battle, 1 vs 1: a random pick on the wall by key, the rival's by its button; random moves
			# for both from the options, then the rival's moves and its list of moves, by group.
			_plan = [[1.5, "menu_accept", ""], [2.0, "menu_accept", ""], [2.6, "menu_accept", ""], [3.2, "", "prep_wall"], [3.4, "menu_info", ""],
				[3.8, "", "prep_rival"], [4.0, "click:rand:0", ""], [4.6, "", "prep_setup"], [4.8, "mov2", ""], [5.2, "", "prep_rolled"],
				[5.4, "move_left", ""], [5.6, "menu_accept", ""], [6.2, "", "prep_picks"], [6.4, "move_down", ""], [6.6, "menu_accept", ""],
				[7.0, "", "prep_slots"], [7.2, "menu_accept", ""], [7.6, "", "prep_list"], [7.8, "move_right", ""], [8.2, "", "prep_common"],
				[8.4, "menu_accept", ""], [8.8, "", "prep_chosen"], [9.0, "menu_back", ""], [9.3, "menu_back", ""], [9.8, "", "prep_back"]]
		"menu_prep_team":
			# Battle, 3 vs 3: both teams at random, random moves for all six, then the list of just
			# those six and, from a pick's slots, on to the next one.
			_plan = [[1.5, "menu_accept", ""], [2.0, "menu_accept", ""], [2.4, "move_right", ""], [2.8, "menu_accept", ""], [3.4, "menu_info", ""],
				[3.6, "menu_info", ""], [3.8, "menu_info", ""], [4.0, "menu_info", ""], [4.2, "menu_info", ""], [4.4, "menu_info", ""], [4.8, "mov2", ""],
				[5.2, "", "prep_team_setup"], [5.4, "move_left", ""], [5.6, "menu_accept", ""], [6.1, "", "prep_team_picks"], [6.3, "menu_accept", ""],
				[6.6, "move_right", ""], [7.0, "", "prep_team_slots"]]
		"menu_profile":
			# Profile: up from Online to the badge, in; point at another trainer (it must not
			# change yet), confirm it; up to the name, the on-screen keyboard with the pad:
			# Q, then right and W, then B deletes one; Done; back.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_up", ""],
				[2.6, "", "profile_badge"], [2.8, "menu_accept", ""], [3.4, "", "profile_screen"], [3.6, "move_right", ""],
				[3.8, "move_down", ""], [4.1, "", "profile_point"], [4.3, "menu_accept", ""], [4.6, "", "profile_pick"],
				[4.8, "move_up", ""], [5.0, "move_up", ""], [5.2, "menu_accept", ""], [5.5, "menu_accept", ""],
				[5.7, "move_right", ""], [5.9, "menu_accept", ""], [6.2, "", "profile_keyboard"], [6.4, "menu_back", ""],
				[6.8, "", ""], [7.0, "menu_back", ""], [7.2, "menu_back", ""], [7.6, "", "profile_back"]]
		"menu_wheel":
			# The mouse wheel: into the options, then two notches down move two rows.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_right", ""], [2.4, "move_down", ""],
				[2.9, "menu_accept", ""]]
		"menu_forms":
			# Battle, 1 vs 1: down to the last cell and left to Urshifu's, the form by key and by its tab, picked;
			# the rival, then the Moves screen and back; a 3 vs 3's team with it on.
			_plan = [[1.5, "menu_accept", ""], [2.0, "menu_accept", ""], [2.6, "menu_accept", ""], [3.2, "move_down", ""], [3.4, "move_down", ""],
				[3.6, "move_down", ""], [3.8, "move_left", ""], [4.2, "", "forms_single"], [4.4, "mov1", ""], [5.0, "", "forms_rapid"], [5.2, "click:form:110", ""],
				[5.8, "", "forms_tab"], [6.0, "mov1", ""], [6.4, "menu_accept", ""], [7.0, "", "forms_rival"], [7.2, "menu_accept", ""],
				[7.8, "", "forms_setup"]]
		"menu_forms_team":
			# Battle, 3 vs 3: a pick, then Urshifu's cell picked and flipped on the team, in place.
			_plan = [[1.5, "menu_accept", ""], [2.0, "menu_accept", ""], [2.4, "move_right", ""], [2.8, "menu_accept", ""], [3.4, "menu_accept", ""],
				[3.8, "move_down", ""], [4.0, "move_down", ""], [4.2, "move_down", ""], [4.4, "move_left", ""], [4.6, "menu_accept", ""], [5.2, "", "forms_team_single"],
				[5.4, "mov1", ""], [6.0, "", "forms_team_rapid"]]
		"menu_options":
			# Options: from the main menu, then down a few rows.
			_plan = [[1.5, "", ""], [1.7, "menu_accept", ""], [2.0, "move_right", ""], [2.2, "move_right", ""], [2.4, "move_down", ""],
				[2.6, "", ""], [2.9, "menu_accept", ""], [3.6, "", "options_top"], [3.8, "move_down", ""],
				[4.0, "move_down", ""], [4.2, "move_down", ""], [4.4, "move_down", ""], [4.6, "move_down", ""],
				[4.8, "move_down", ""], [5.0, "move_down", ""], [5.2, "move_down", ""], [5.4, "move_down", ""], [5.6, "move_down", ""],
				[6.0, "", "options_sound"]]
		"combat":
			_shots = [2.0, 4.0, 6.0, 8.0, 10.0, 12.5, 15.0, 18.0, 22.0]
		"mechanics":
			_mechanics()
		"urshifu":
			_urshifu_test()
		"mewtwo":
			_mewtwo_test()
		"prep":
			_prep_test()
		"loadouts":
			_loadouts()
		"abilities":
			_abilities()
		"status":
			_statuses()
		"status_moves":
			_status_moves()
		"stage_shots":
			_stage_shots()
		"stage_previews":
			_stage_previews()
		"result_shot":
			_result_shot()
		"deflect":
			_deflect_test()
		"clash":
			_clash_test()
		"new_moves":
			_new_moves()
		"trainers":
			_trainers_test()
		"league":
			_league_test()
		"lockon":
			_lockon_test()
		"team":
			_team_test()
		"team_battles":
			_team_battles()
		"team_shots":
			_team_shots()
		"hud":
			_hud_test()
		"music":
			# The tracks the game finds (in the exported build, inside its package).
			await get_tree().process_frame
			var groups := {}
			for k in main.music._tracks:
				groups[k] = main.music._tracks[k].size()
			main.music.play("night", true)
			var p: AudioStreamPlayer = main.music._players[main.music._now]
			print("MUSIC ", groups, " playing ", p.stream.resource_path if p.stream else "none")
			get_tree().quit()


## One queued menu step (see the menus' plan). From _physics_process, which runs before the
## menus' _process in a frame: a press made after them would be "just pressed" too late.
func _next_step() -> void:
	if _step_wait > 0:
		_step_wait -= 1
		return
	if _steps.is_empty():
		return
	var st: Array = _steps.pop_front()
	if st[0] == "key" and st[1].begins_with("click:"):
		_click_zone(st[1].get_slice(":", 1), int(st[1].get_slice(":", 2)))
		_step_wait = 4
	elif st[0] == "key" and st[1].begins_with("opt:"):
		main.menu.edit_cursor = main.menu.edit_options().find(st[1].get_slice(":", 1))
	elif st[0] == "key":
		var ev := InputEventAction.new()
		ev.action = st[1]
		ev.pressed = true
		Input.parse_input_event(ev)
		Input.action_press(st[1])
		_release_later(st[1])
		_step_wait = 4
	else:
		print("state: menu ", main.menu.is_open, " pause ", main.paused, " fighters ", main.fighters.size(), " choice ", main.menu.choice)
		_capture(st[1])


## A left click, as the real pointer would give, on what the menus drew as (kind, i).
func _click_zone(kind: String, i: int) -> void:
	for z in main.menu.draw.zones:
		if z.kind == kind and z.i == i:
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = z.rect.get_center()
				ev.global_position = ev.position
				Input.parse_input_event(ev)
			return
	print("FAIL   Nothing to click: %s %d" % [kind, i])


func _release_later(action: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


func _dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../captures")


func _capture(n: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dir().path_join(n + ".png"))
	CaptureLog.save(img, n)
	print("capture ", n)


func _physics_process(delta: float) -> void:
	t += delta
	match test_name:
		"menu", "menu_moves", "menu_options", "menu_profile", "menu_wheel", "menu_rules", "menu_forms", "menu_forms_team", "menu_prep", "menu_prep_team":
			# Due steps go into a queue that _process plays one per few frames: after a slow
			# frame several come due at once, and two presses in one frame lose one.
			for p in _plan:
				if t >= p[0] and t - delta < p[0]:
					if p[1] != "":
						_steps.append(["key", p[1]])
					if p[2] != "":
						_steps.append(["capture", p[2]])
			_next_step()
			if test_name == "menu" and t > 12.5:
				get_tree().quit()
			if test_name == "menu_rules" and t > 14.5:
				_rules_outcome()
				get_tree().quit()
			if test_name == "menu_options" and t > 6.8:
				get_tree().quit()
			if test_name == "menu_forms_team" and t >= 6.4 and t - delta < 6.4:
				var team: Array = main.menu.choice.team
				print("%s  The flip swaps it on the team, in place  %s" % ["OK   " if team == ["pikachu", "urshifurapidstrike"] else "FAIL ", team])
				get_tree().quit()
			if test_name == "menu_forms" and t >= 8.2 and t - delta < 8.2:
				var ok_forms: bool = main.menu.choice.p1 == "urshifurapidstrike"
				print("%s  The form picked on the wall is the one chosen  %s" % ["OK   " if ok_forms else "FAIL ", main.menu.choice.p1])
				get_tree().quit()
			if test_name == "menu_prep" and t > 10.0:
				get_tree().quit()
			if test_name == "menu_prep_team" and t > 7.2:
				var who: Array = main.menu.edit_entries()
				print("%s  Six picks listed, on the second  %s" % ["OK   " if who.size() == 6 and main.menu.cursor == 1 and main.menu.edit_sp == who[1][1] else "FAIL ", who])
				get_tree().quit()
			if test_name == "menu_wheel":
				if t >= 3.6 and t - delta < 3.6:
					_profile_trainer = str(main.options.cursor)
				for at in [3.8, 4.2]:
					if t >= at and t - delta < at:
						var w := InputEventMouseButton.new()
						w.button_index = MOUSE_BUTTON_WHEEL_DOWN
						w.pressed = true
						w.position = Vector2(800, 450)
						Input.parse_input_event(w)
				if t > 4.8:
					var moved: int = main.options.cursor - int(_profile_trainer)
					print("%s  Two wheel notches move two rows  %d" % ["OK   " if moved == 2 else "FAIL ", moved])
					get_tree().quit()
			if test_name == "menu_profile":
				# The pad drives the on-screen keyboard (the actions here come from no device).
				Controls.last_device = "xbox"
				if t >= 4.1 and t - delta < 4.1:
					_profile_trainer = main.options.trainer
				if t >= 4.6 and t - delta < 4.6:
					print("%s  Pointing does not change the trainer  %s" % ["OK   " if _profile_trainer == TrainerData.DEFAULT else "FAIL ", _profile_trainer])
					print("%s  Confirming does  %s" % ["OK   " if main.options.trainer != TrainerData.DEFAULT else "FAIL ", main.options.trainer])
				if t >= 6.8 and t - delta < 6.8:
					var n: String = main.options.player_name
					print("%s  On-screen keyboard: Q, W, delete  '%s'" % ["OK   " if n == "Q" else "FAIL ", n])
				if t > 7.9:
					get_tree().quit()
			if test_name == "menu_moves" and t >= 8.95 and t - delta < 8.95:
				# The move three rows below Flamethrower went into the first slot, then Air Slash
				# (second) took its place: they swapped.
				main.menu.edit_slot = 0
				var rows: Array = main.menu.edit_options().filter(func(o): return not main.menu.is_heading(o))
				var fifth: String = rows[rows.find("flamethrower") + 3]
				var after: Array = Loadout.saved("charizard").moves
				var ok := after == ["airslash", fifth, "dragonclaw", "flareblitz"]
				var stored := FileAccess.get_file_as_string(Loadout.path)
				print("%s  Moves screen: change and swap saved  %s" % ["OK   " if ok else "FAIL ", after])
				print("%s  Saved to file  %s" % ["OK   " if stored.contains(fifth) else "FAIL ", Loadout.path])
			if test_name == "menu_moves" and t >= 11.2 and t - delta < 11.2:
				var ab: String = Loadout.saved("charizard").ability
				var second: String = Loadout.abilities_for("charizard")[1].id
				print("%s  Ability changed from its slot  %s" % ["OK   " if ab == second else "FAIL ", ab])
			if test_name == "menu_moves" and t >= 12.1 and t - delta < 12.1:
				print("%s  Restore, answered No, keeps it  %s" % ["OK   " if not Loadout.is_default("charizard") else "FAIL ", Loadout.saved("charizard")])
			if test_name == "menu_moves" and t > 13.2:
				print("%s  Restore, answered Yes, back to defaults  %s" % ["OK   " if Loadout.is_default("charizard") else "FAIL ", Loadout.saved("charizard")])
				get_tree().quit()
		"portraits":
			if t > 0.6:
				var strip := Image.create(28 * 3 * 2 * 4, 28 * 3 * 4, false, Image.FORMAT_RGBA8)
				for i in main.hud._portraits.size():
					var im: Image = main.hud._portraits[i].vp.get_texture().get_image()
					im.convert(Image.FORMAT_RGBA8)
					im.resize(im.get_width() * 4, im.get_height() * 4, Image.INTERPOLATE_NEAREST)
					strip.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(i * im.get_width(), 0))
				strip.save_png(_dir().path_join("portraits.png"))
				_capture("hud_portraits")
				get_tree().quit()
		"aivsai":
			_ai_vs_ai()
		"moves":
			_movs_test(delta)
		"combat":
			_fps_sum += Engine.get_frames_per_second()
			_fps_n += 1
			_fps_min = mini(_fps_min, Engine.get_frames_per_second()) if t > 2.0 else _fps_min
			if _taken < _shots.size() and t >= _shots[_taken]:
				_capture("combat_%d" % (_taken + 1))
				_taken += 1
			if _taken >= _shots.size() or t > 40.0:
				print("mean FPS %.0f · min %d · %s" % [float(_fps_sum) / _fps_n, _fps_min, RenderingServer.get_video_adapter_name()])
				get_tree().quit()


func _ai_vs_ai() -> void:
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	for l in [a, b]:
		if l.flying:
			_flying[l.species] = _flying.get(l.species, 0.0) + get_physics_process_delta_time()
		if l.action and l.action.d.get("manual_aim", false) and l.action.phase == "active":
			_stream.get_or_add(l.action.id, [0.0, 0])[0] += get_physics_process_delta_time()
		# Stages with a void: what each one was doing when it went off the edge.
		if main.arena.void_y != -INF and l.global_position.y < -0.5 and not _off_edge.has(l):
			_off_edge[l] = true
			var who: AI = main.ai if l == b else main.player_ai
			print("  off the edge: %s %s %s · AI \"%s\" · pos %s vel %s input %s" % [l.species, l.state, l.action.id if l.action else "",
				who.state_text if who else "", l.global_position.snapped(Vector3.ONE * 0.1), l.velocity.snapped(Vector3.ONE * 0.1), l.ctrl.move_input])
		elif l.global_position.y > -0.1 and l.is_on_floor():
			_off_edge.erase(l)
	if t - _last_report >= 10.0:
		_last_report = t
		print("t=%3ds  %s %4d (%s)  %s %4d (%s)  hits %d  fps %d" % [int(t), a.species, a.hp, a.state, b.species, b.hp, b.state,
			_hits, Engine.get_frames_per_second()])
	if main._end_t > 1.0:
		_battles += 1
		var winner: Fighter = a if a.state != "ko" else b
		var flights := ""
		for k in _flying:
			flights += " · %s flying %.0f s" % [k, _flying[k]]
		for k in _stream:
			flights += " · %s %d hits in %.1f s firing" % [k, _stream[k][1], _stream[k][0]]
		print("BATTLE %d: %s wins in %.0f s · %d hits%s" % [_battles, winner.species, t, _hits, flights])
		main.rematch()
		await get_tree().physics_frame
		print("  after the rematch: active hits %d · projectiles %d · %s %s · %s %s" % [main.combat.hits.size(),
			main.combat.projectiles.size(), a.species, a.state, b.species, b.state])
		_hits = 0
		if _battles >= 3:
			get_tree().quit()
	if t > 300.0:
		print("timed out without a KO")
		get_tree().quit()


## Each action in the plan, with a capture in the middle of the active phase.
func _movs_test(delta: float) -> void:
	var j: Fighter = main.player
	_step_t += delta
	if _step >= _plan.size():
		if _step_t > 1.5:
			get_tree().quit()
		return
	var action: String = _plan[_step]
	if _step_t > 0.4 and _step_t - delta <= 0.4:
		if action.begins_with("move"):
			j.ctrl.press(action)
			# Held or charged moves, for a good while.
			j.ctrl.held[action] = true
		else:
			j.ctrl.press(action)
			if action == "dodge":
				j.ctrl.move_input = Vector2(1, 0)
	if _step_t > 1.6:
		j.ctrl.release(action)
		j.ctrl.move_input = Vector2.ZERO
	var move_name: String = j.data.moves[int(action.substr(3)) - 1] if action.begins_with("move") else action
	var moment := 0.4 + float(Moves.DATA.get(move_name, {}).get("startup", 0.1)) + 0.06
	if Moves.DATA.get(move_name, {}).get("chargeable", false) or Moves.DATA.get(move_name, {}).get("hold", false):
		moment = 1.2
	if action == "dodge" or action == "jump":
		moment = 0.55
	# --shot=S: the full-size capture S seconds after the press instead.
	if main._args.has("shot"):
		moment = 0.4 + float(main._args.shot)
	if _step_t > moment and _step_t - delta <= moment:
		_capture("moves_%s_%d" % [j.species, _step + 1])
	# With --sequence, also a strip of 16 frames (every 0.1 s from the press) to see how
	# the effect moves, not just one instant. --every=S and --from=S (after the press)
	# narrow it down to a quick moment, like a bolt's discharge.
	if main._args.has("sequence") and DisplayServer.get_name() != "headless":
		var every := float(main._args.get("every", "0.1"))
		var k := int(floorf((_step_t - 0.4 - float(main._args.get("from", "0"))) / every))
		if k >= 0 and k < 16 and _strip.size() == k:
			# Crop of the center (where the action happens) instead of the whole screen.
			var full := get_viewport().get_texture().get_image()
			var fw := full.get_width()
			var fh := full.get_height()
			var im := full.get_region(Rect2i(fw / 4, fh * 3 / 10, fw / 2, fh / 2))
			im.resize(fw / 3, fh / 3, Image.INTERPOLATE_BILINEAR)
			_strip.append(im)
		if k == 16 and _strip.size() == 16:
			var w: int = _strip[0].get_width()
			var h: int = _strip[0].get_height()
			var sheet := Image.create(w * 4, h * 4, false, _strip[0].get_format())
			for i in 16:
				sheet.blit_rect(_strip[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
			sheet.save_png(_dir().path_join("strip_%s_%s.png" % [j.species, move_name]))
			print("strip ", move_name)
			_strip.append(null)
	if _step_t > 3.2:
		_strip.clear()
		_step += 1
		_step_t = 0.0
		j.cds.clear()
		j.energy = Fighter.ENERGY_MAX
		var b: Fighter = main.fighters[1]
		b.reset(Vector3(-3.5, 0, 0) if j.species != "snorlax" else Vector3(-4.5, 0, 0), PI * 0.5)
		j.reset(Vector3(3.0, 0, 0), -PI * 0.5)
		j.cds.clear()


# ---------------------------------------------------------------- mechanics

var _results: Array = []
var _profile_trainer := ""
var _off_edge := {}


func _setup(p1: String, p2: String, pos_a: Vector3, pos_b: Vector3) -> Array:
	main.start_battle(p1, p2, "normal")
	await get_tree().physics_frame
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	main.ai.mode = "still"
	b.ctrl.move_input = Vector2.ZERO
	a.ctrl.move_input = Vector2.ZERO
	a.is_player = false
	a.reset(pos_a, atan2(pos_b.x - pos_a.x, pos_b.z - pos_a.z))
	b.reset(pos_b, atan2(pos_a.x - pos_b.x, pos_a.z - pos_b.z))
	a.locked = true
	b.locked = true
	await _wait(0.3)
	return [a, b]


func _wait(s: float) -> void:
	var end_pos := t + s
	while t < end_pos:
		await get_tree().physics_frame


func _ok(case_name: String, passes: bool, detail := "") -> void:
	_results.append([case_name, passes])
	print("%s  %s  %s" % ["OK   " if passes else "FAIL ", case_name, detail])


## The selection's random picks and random moves, each battle's moves over the defaults, and the
## groups of the Moves screen's list.
func _prep_test() -> void:
	await get_tree().physics_frame
	Loadout.path = "user://loadouts_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Loadout.path))
	Loadout.restore()
	var ordered := true
	var whole := true
	var rolls_ok := true
	for sp in Roster.POKEMON:
		var groups := Loadout.move_groups(sp)
		var listed: Array = groups[0] + groups[1]
		var can := Loadout.moves_for(sp)
		whole = whole and listed.size() == can.size() and can.all(func(mv): return mv in listed) \
			and Roster.POKEMON[sp].moves.all(func(mv): return mv in groups[0])
		for group in groups:
			for i in range(1, group.size()):
				ordered = ordered and not Loadout._listed_before(group[i], group[i - 1])
				var ta := UiKit.TYPE_ORDER.find(Moves.DATA[group[i - 1]].type)
				ordered = ordered and ta <= UiKit.TYPE_ORDER.find(Moves.DATA[group[i]].type)
		for roll in 50:
			var four := Loadout.random_moves(sp)
			rolls_ok = rolls_ok and Loadout.valid(sp, {"moves": four, "ability": ""}).moves == four \
				and four.any(func(mv): return Moves.DATA[mv].get("power", 0) > 0)
	_ok("Groups: every move once, the default four among its own", whole)
	_ok("Groups: by type, then by name", ordered)
	_ok("Groups: what most learn is common, what few learn is not", Loadout.is_common("protect") and not Loadout.is_common("flamethrower"))
	_ok("Random moves: always four it can use, one an attack", rolls_ok)

	var m: Menu = main.menu
	m._edit_return = "main"
	m.edit_sp = "charizard"
	m.edit_slot = 0
	var options := m.edit_options()
	_ok("List: its own under a heading, then the common under another", options[0] == Menu.OWN_MOVES and options.has(Menu.COMMON_MOVES) \
		and options.find("flamethrower") < options.find(Menu.COMMON_MOVES) and options.find("protect") > options.find(Menu.COMMON_MOVES))

	# Picking: 1 vs 1 and 3 vs 3, all at random.
	m.screen = "selection"
	m.choice.format = "1v1"
	m.sel_phase = "p1"
	m._random_pick()
	_ok("Random pick: moves on to the rival", m.sel_phase == "p2" and Roster.POKEMON.has(m.choice.p1), m.choice.p1)
	m._random_pick()
	_ok("Random pick: the rival's goes to the options", m.sel_phase == "setup", m.choice.p2)
	m.choice.format = "3v3"
	m.choice.team = []
	m.choice.team2 = []
	m.sel_phase = "p1"
	for i in Party.SIZE * 2:
		m._random_pick()
	var bases: Array = m.choice.team.map(func(sp): return Roster.base_of(sp))
	_ok("Random pick: fills both teams with no one twice", m.sel_phase == "setup" and m.choice.team.size() == 3 and m.choice.team2.size() == 3 \
		and bases.all(func(b): return bases.count(b) == 1), "%s %s" % [m.choice.team, m.choice.team2])
	m.setup_cursor = 0
	m._open_battle_moves()
	_ok("3 vs 3: the Moves screen lists just the six picks", m.edit_entries().size() == 6 and m.edit_phase == "pokemon" and m.edit_side == 0)
	m._leave_moves()

	# This battle's moves: over the defaults, for that side only, gone with the pick.
	m.choice.format = "1v1"
	m.choice.team = []
	m.choice.team2 = []
	m.choice.p1 = "charizard"
	m.choice.p2 = "charizard"
	m._to_setup()
	m._open_battle_moves()
	_ok("1 vs 1: the Moves screen lists both picks", m.edit_entries() == [[0, "charizard"], [1, "charizard"]])
	m._edit_pick(1)
	var set_moves: Array = ["airslash", "dragonclaw", "flareblitz", "earthquake"]
	m._store_edit({"moves": set_moves, "ability": "solarpower"})
	_ok("Set for the battle: the rival's pick has it", m.battle_loadout(1, "charizard").moves == set_moves and m.battle_loadout(1, "charizard").ability == "solarpower")
	_ok("Set for the battle: my same Pokémon does not", Loadout.is_default("charizard") and m.battle_loadout(0, "charizard") == Loadout.default_for("charizard"))
	m._leave_moves()
	main.start_battle("charizard", "charizard", "normal")
	_ok("Set for the battle: it fights with it", main.fighters[1].data.moves == set_moves and main.fighters[1].data.passive.id == "solarpower" \
		and main.fighters[0].data.moves == Roster.POKEMON["charizard"].moves, "%s" % [main.fighters[1].data.moves])
	_ok("Set for the battle: the defaults stay saved as they were", Loadout.is_default("charizard"))
	m._store_edit(Loadout.default_for("charizard"))
	_ok("Set back to the default, nothing is left to restore", m.choice.loadouts[1].is_empty())
	m._store_edit({"moves": set_moves, "ability": "solarpower"})
	m.choice.p2 = "snorlax"
	m._to_setup()
	_ok("Another pick drops what was set for the old one", m.choice.loadouts[1].is_empty() and m.battle_loadout(1, "snorlax") == Loadout.default_for("snorlax"))
	m._random_battle_moves()
	_ok("Random moves from the options: for both sides", m.choice.loadouts[0].has("charizard") or m.choice.loadouts[1].has("snorlax"))
	main.start_battle("charizard", "snorlax", "normal")
	_ok("Random moves: they reach the fighters", main.fighters[1].data.moves == m.battle_loadout(1, "snorlax").moves)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Every move each Pokémon can take in the Moves menu besides its own four, used once
## against a still rival: it must run without errors and, if it attacks, hit. With a window,
## a capture of each one mid-move (loadout_<pokemon>_<move>.png).
func _loadouts() -> void:
	await get_tree().physics_frame
	var fails := 0
	var count := 0
	for sp in Roster.POKEMON:
		# --p1: only that Pokémon (the whole roster takes about a quarter of an hour).
		if main._args.has("p1") and main._args.p1 != sp:
			continue
		var own: Array = Roster.POKEMON[sp].moves
		for m in Loadout.moves_for(sp):
			if m in own:
				continue
			count += 1
			main._args.moves = ",".join([m] + own.slice(0, 3))
			var d: Dictionary = Moves.DATA[m]
			var ai: Dictionary = d.get("ai", {})
			var dist := clampf((float(ai.get("min", 0.0)) + float(ai.get("max", 3.0))) * 0.5, 1.6, 9.0)
			# Blastoise takes everything (no immunities to these moves).
			var rival := "blastoise" if sp != "blastoise" else "venusaur"
			var ab: Array = await _setup(sp, rival, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
			var a: Fighter = ab[0]
			var b: Fighter = ab[1]
			var hp0: float = b.hp
			var own_hp: float = a.hp
			a.ctrl.press("mov1")
			var hold := 0.1
			if d.get("hold", false):
				hold = float(d.get("max", 1.5))
			elif d.get("chargeable", false):
				hold = float(d.get("startup_max", 1.0))
			var used := false
			var t0 := t
			var shot := false
			while t - t0 < hold + 2.5:
				await get_tree().physics_frame
				if a.action and a.action.id == m:
					used = true
				if not shot and t - t0 >= minf(hold, 0.35):
					shot = true
					_capture("loadout_%s_%s" % [sp, m])
				if t - t0 >= hold:
					a.ctrl.release("mov1")
			var kind: String = ai.get("kind", "")
			var self_move: bool = kind in ["heal", "guard", "decoy", "buff"] or d.get("cat", "") == "status"
			var hit := b.hp < hp0
			used = used or hit or a.hp != own_hp
			# Sucker Punch only connects against an attack, and this rival stands still.
			var passes: bool = used and (hit or self_move or d.get("needs_attacking", false))
			if not passes:
				fails += 1
			_ok("%s with %s" % [sp, m], passes, "damage %d, %s" % [int(hp0 - b.hp), "self move" if self_move else "attack"])
	main._args.erase("moves")
	print("RESULT: %d of %d" % [count - fails, count])
	get_tree().quit()


## One fighter hits the other once with "slot" from "dist" meters; returns the damage the
## target took. "ability_a" / "ability_b" set their abilities (ids) for the test.
func _one_hit(sp_a: String, sp_b: String, slot: String, dist: float, ability_a := "", ability_b := "", weather := "") -> float:
	var ab: Array = await _setup(sp_a, sp_b, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
	if weather != "":
		main.weather.start(weather)
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	if ability_a != "":
		a.data.passive = Loadout.ability(sp_a, ability_a)
	if ability_b != "":
		b.data.passive = Loadout.ability(sp_b, ability_b)
	b.status_lock = 99.0              # only the hit: no chip damage from a secondary status
	var hp0: float = b.hp
	a.ctrl.press(slot)
	await _wait(0.15)
	a.ctrl.release(slot)
	await _wait(1.6)
	return hp0 - b.hp


## Each ability does what it does in the games (adapted where real time needs it).
func _abilities() -> void:
	var ball: Dictionary = Stats.battle_data("pikachu").stats
	var plain: int = Stats.at_level(Species.DATA.pikachu.stats.spa)
	_ok("Light Ball: Ash's Pikachu has double Attack and Sp. Atk", ball.spa == plain * 2 and ball.atk == Stats.at_level(Species.DATA.pikachu.stats.atk) * 2,
		"Sp. Atk %d (plain %d)" % [ball.spa, plain])
	await get_tree().physics_frame
	# Lightning Rod: Thunder Shock does nothing and raises Sp. Atk.
	var dmg := await _one_hit("pikachu", "pikachu", "mov1", 6.0, "", "lightningrod")
	var b: Fighter = main.fighters[1]
	_ok("Lightning Rod: Electric does nothing and raises Sp. Atk", dmg == 0.0 and b.stages.spa == 1, "damage %d, Sp. Atk %+d" % [dmg, b.stages.spa])
	# Thick Fat: half from Fire (Charizard's Flare Blitz on Snorlax, with and without).
	var with_fat := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "thickfat")
	var without := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "immunity")
	_ok("Thick Fat: half damage from Fire", absf(with_fat / maxf(without, 1.0) - 0.5) < 0.05, "%d vs %d" % [with_fat, without])
	# Technician: Bullet Punch (40 power) x1.5 against Swarm.
	var tech := await _one_hit("scizor", "snorlax", "mov1", 1.6, "technician")
	var swarm := await _one_hit("scizor", "snorlax", "mov1", 1.6, "swarm")
	_ok("Technician: 60 power or less x1.5", absf(tech / maxf(swarm, 1.0) - 1.5) < 0.05, "%d vs %d" % [tech, swarm])
	# Justified: a Dark move (Night Slash) raises Lucario's Attack.
	await _one_hit("greninja", "lucario", "mov2", 1.6, "", "justified")
	b = main.fighters[1]
	_ok("Justified: a Dark move raises Attack", b.stages.atk == 1, "Attack %+d" % b.stages.atk)
	# Immunity: Sludge Bomb does not poison Snorlax.
	await _one_hit("venusaur", "snorlax", "mov3", 8.0, "", "immunity")
	b = main.fighters[1]
	await _wait(1.0)
	_ok("Immunity: cannot be poisoned", b.status == "", "status '%s'" % b.status)
	# Gluttony: at half HP it eats its berry and heals a quarter.
	var ab: Array = await _setup("charizard", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	b = ab[1]
	b.data.passive = Loadout.ability("snorlax", "gluttony")
	b.hp = b.hp_max * 0.52
	var before: float = b.hp
	ab[0].ctrl.press("mov4")
	await _wait(0.15)
	ab[0].ctrl.release("mov4")
	await _wait(1.6)
	_ok("Gluttony: eats a Sitrus Berry at half HP", b._berry_used and b.hp > before - 0.4 * b.hp_max, "HP %d -> %d of %d" % [before, b.hp, b.hp_max])
	# Steadfast: cut short while winding up, Lucario's Speed rises.
	ab = await _setup("pikachu", "lucario", Vector3(-5.0, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = ab[0]
	b = ab[1]
	b.data.passive = Loadout.ability("lucario", "steadfast")
	b.ctrl.press("mov1")              # Aura Sphere charges: long wind-up
	await _wait(0.1)
	a.ctrl.press("mov2")              # Quick Attack (medium) cuts it
	await _wait(0.15)
	a.ctrl.release("mov2")
	await _wait(1.0)
	b.ctrl.release("mov1")
	_ok("Steadfast: flinching raises Speed", b.stages.spe == 1, "Speed %+d, HP %d/%d, state %s" % [b.stages.spe, b.hp, b.hp_max, b.state])
	# Cursed Body: over many hits, about 30% disable the move (it goes on a long cooldown).
	var disabled := 0
	for i in 20:
		ab = await _setup("pikachu", "gengar", Vector3(-6, 0, 0), Vector3(0, 0, 0))
		ab[1].data.passive = Loadout.ability("gengar", "cursedbody")
		ab[0].ctrl.press("mov1")
		await _wait(0.15)
		ab[0].ctrl.release("mov1")
		await _wait(0.9)
		if ab[0].cds.get("thundershock", 0.0) > 8.0:
			disabled += 1
	_ok("Cursed Body: about 30% of hits disable the move", disabled >= 2 and disabled <= 11, "%d of 20" % disabled)
	# Weather: harsh sunlight makes Fire 1.5x and Water half; rain the other way round.
	var fire_plain := await _one_hit("charizard", "snorlax", "mov4", 6.0)
	var fire_sun := await _one_hit("charizard", "snorlax", "mov4", 6.0, "", "", "sun")
	var water_sun := await _one_hit("blastoise", "snorlax", "mov1", 6.0, "", "", "sun")
	var water_plain := await _one_hit("blastoise", "snorlax", "mov1", 6.0)
	_ok("Sun: Fire x1.5", absf(fire_sun / maxf(fire_plain, 1.0) - 1.5) < 0.05, "%d vs %d" % [fire_sun, fire_plain])
	_ok("Sun: Water x0.5", absf(water_sun / maxf(water_plain, 1.0) - 0.5) < 0.05, "%d vs %d" % [water_sun, water_plain])
	# Sandstorm: wears down Pikachu, not Garchomp (Ground), and not with Sand Veil.
	ab = await _setup("pikachu", "garchomp", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	main.weather.start("sand")
	await _wait(3.3)
	_ok("Sandstorm wears down, not Ground types", ab[0].hp < ab[0].hp_max and ab[1].hp == ab[1].hp_max,
		"Pikachu %d/%d, Garchomp %d/%d" % [ab[0].hp, ab[0].hp_max, ab[1].hp, ab[1].hp_max])
	main.weather.clear()
	# Rain Dish heals in the rain.
	ab = await _setup("blastoise", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].data.passive = Loadout.ability("blastoise", "raindish")
	ab[0].hp = ab[0].hp_max * 0.5
	main.weather.start("rain")
	await _wait(3.3)
	_ok("Rain Dish heals in the rain", ab[0].hp > ab[0].hp_max * 0.5, "HP %d/%d" % [ab[0].hp, ab[0].hp_max])
	main.weather.clear()
	# Chlorophyll: faster in the sun.
	ab = await _setup("venusaur", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].data.passive = Loadout.ability("venusaur", "chlorophyll")
	var plain_k: float = ab[0].speed_stage()
	main.weather.start("sun")
	_ok("Chlorophyll: faster in the sun", ab[0].speed_stage() > plain_k * 1.4, "x%.2f vs x%.2f" % [ab[0].speed_stage(), plain_k])
	main.weather.clear()
	# Sunny Day as a move starts the sun; Solar Beam then barely charges.
	main._args.moves = "sunnyday,razorleaf,sludgebomb,solarbeam"
	ab = await _setup("venusaur", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.2)
	var sunny: bool = main.weather.is_on("sun")
	ab[0].ctrl.press("mov4")
	await _wait(0.1)
	ab[0].ctrl.release("mov4")
	var short_charge: float = ab[0].action.startup_len() if ab[0].action else -1.0
	await _wait(2.0)
	_ok("Sunny Day starts the sun; Solar Beam charges fast", sunny and short_charge > 0.0 and short_charge < Moves.DATA.solarbeam.startup * 0.5,
		"sun %s, charge %.2f s of %.2f" % [sunny, short_charge, Moves.DATA.solarbeam.startup])
	main.weather.clear()
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Major status conditions as in the games (Status), adapted to real time.
func _statuses() -> void:
	await get_tree().physics_frame
	# Burn: 1/16 per turn, physical moves at half power; Fire types are immune.
	var ab: Array = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	_ok("Fire types cannot be burned", not b.inflict("brn") and b.status == "", "status '%s'" % b.status)
	a.inflict("brn")
	var hp0: float = a.hp
	await _wait(Status.DURATION.brn + 0.4)
	var lost: float = (hp0 - a.hp) / a.hp_max
	_ok("Burn: its chip damage in full", absf(lost - Status.TOTAL.brn) < 0.01, "%.3f of max HP" % lost)
	_ok("Burn wears off", a.status == "", "status '%s'" % a.status)
	_ok("Just cured: no new status for a while", not a.inflict("psn"), "status '%s'" % a.status)
	await _wait(Status.IMMUNE_AFTER)
	_ok("Then it can get one again", a.inflict("psn"), "status '%s'" % a.status)
	var plain := await _one_hit("snorlax", "pikachu", "mov1", 6.0)
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	ab[0].inflict("brn")
	var hp_b: float = ab[1].hp
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.6)
	var burned_hit: float = hp_b - ab[1].hp
	_ok("Burn: physical moves hit half as hard", absf(burned_hit / maxf(plain, 1.0) - 0.5) < 0.06, "%d vs %d" % [burned_hit, plain])
	# Paralysis: half speed; Electric types are immune.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	_ok("Electric types cannot be paralyzed", not ab[1].inflict("par"), "status '%s'" % ab[1].status)
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = 0.0
	a.ctrl.move_input = Vector2(0, 1)
	var z0: float = a.global_position.z
	await _wait(1.0)
	var free_run: float = absf(a.global_position.z - z0)
	a.ctrl.move_input = Vector2.ZERO
	await _wait(0.6)
	a.inflict("par")
	a._para_roll = 99.0             # no full paralysis during the measurement
	a.ctrl.move_input = Vector2(0, 1)
	z0 = a.global_position.z
	await _wait(1.0)
	a.ctrl.move_input = Vector2.ZERO
	var para_run: float = absf(a.global_position.z - z0)
	_ok("Paralysis: half speed", para_run < free_run * 0.62, "%.1f m vs %.1f m" % [para_run, free_run])
	# Badly poisoned: it gets worse every turn.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("tox")
	hp0 = ab[0].hp
	await _wait(3.0)
	var early: float = hp0 - ab[0].hp
	await _wait(Status.DURATION.tox - 6.0)
	hp0 = ab[0].hp
	await _wait(3.0)
	var late: float = hp0 - ab[0].hp
	_ok("Badly poisoned grows as it goes on", late > early * 1.5, "%d then %d" % [early, late])
	# Poison: longer and slower than Toxic, less in all.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("psn")
	hp0 = ab[0].hp
	await _wait(Status.DURATION.tox)
	var psn_part: float = (hp0 - ab[0].hp) / ab[0].hp_max
	_ok("Poison is slower than Toxic", psn_part < Status.TOTAL.tox * 0.5 and ab[0].status == "psn", "%.3f of max HP in %.0f s" % [psn_part, Status.DURATION.tox])
	ab = await _setup("scizor", "gengar", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	_ok("Poison and Steel types cannot be poisoned", not ab[0].inflict("psn") and not ab[1].inflict("tox"), "Scizor '%s', Gengar '%s'" % [ab[0].status, ab[1].status])
	# Sleep: it cannot act.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	a.inflict("slp")
	await _wait(0.3)
	a.ctrl.press("mov1")
	await _wait(0.3)
	a.ctrl.release("mov1")
	_ok("Asleep, it cannot act", a.action == null and a.state == "stunned", "state %s" % a.state)
	await _wait(3.2)
	_ok("It wakes up", a.status == "" and a.state != "stunned", "status '%s', state %s" % [a.status, a.state])
	# Freeze: a Fire hit thaws it out.
	ab = await _setup("charizard", "snorlax", Vector3(-5, 0, 0), Vector3(0, 0, 0))
	ab[1].inflict("frz")
	ab[1].status_t = 99.0
	ab[0].ctrl.press("mov1")
	await _wait(0.8)
	ab[0].ctrl.release("mov1")
	await _wait(0.3)
	_ok("A Fire hit thaws it out", ab[1].status == "", "status '%s'" % ab[1].status)
	# Hex and Facade: double against / with a status condition.
	var hex_plain := await _one_hit("gengar", "snorlax", "mov3", 6.0)
	ab = await _setup("gengar", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	ab[1].inflict("par")
	ab[1]._para_roll = 99.0
	var hp_h: float = ab[1].hp
	ab[0].ctrl.press("mov3")
	await _wait(0.15)
	ab[0].ctrl.release("mov3")
	await _wait(1.6)
	var hex_double: float = hp_h - ab[1].hp
	_ok("Hex: double against a status condition", hex_double > hex_plain * 1.7, "%d vs %d" % [hex_double, hex_plain])
	# Rest cures it.
	ab = await _setup("snorlax", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	ab[0].inflict("psn")
	ab[0].ctrl.press("mov4")
	await _wait(0.15)
	ab[0].ctrl.release("mov4")
	await _wait(1.0)
	_ok("Rest cures the status", ab[0].status == "", "status '%s'" % ab[0].status)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Status moves: each gives its status, and fails where the games say (types, powders).
func _status_moves() -> void:
	await get_tree().physics_frame
	var b := await _use("venusaur", "sleeppowder,poisonpowder,toxic,solarbeam", "snorlax", 2.5)
	_ok("Sleep Powder puts it to sleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("venusaur", "sleeppowder,poisonpowder,toxic,solarbeam", "venusaur", 2.5)
	_ok("Grass types ignore powders", b.status == "", "status '%s'" % b.status)
	b = await _use("venusaur", "poisonpowder,sleeppowder,toxic,solarbeam", "pikachu", 2.5)
	_ok("Poison Powder poisons", b.status == "psn", "status '%s'" % b.status)
	b = await _use("venusaur", "toxic,sleeppowder,poisonpowder,solarbeam", "pikachu", 8.0, 2.4)
	_ok("Toxic badly poisons", b.status == "tox", "status '%s'" % b.status)
	# Jumping as the ground bubbles avoids it: it only reaches who stands on the ground.
	main._args["moves"] = "toxic,sleeppowder,poisonpowder,solarbeam"
	var tj: Array = await _setup("venusaur", "pikachu", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	tj[0].ctrl.press("mov1")
	await _wait(0.15)
	tj[0].ctrl.release("mov1")
	# The stain runs about 6 m at 13 m/s after a 0.3 s startup: the warning is on by 0.8 s.
	await _wait(0.8)
	var warned: bool = tj[1].status == ""
	tj[1].ctrl.press("jump")
	await _wait(0.1)
	tj[1].ctrl.release("jump")
	await _wait(1.0)
	_ok("Toxic: jumping on the warning avoids it", warned and tj[1].status == "", "status '%s'" % tj[1].status)
	b = await _use("charizard", "willowisp,flamethrower,airslash,dragonclaw", "snorlax", 7.0)
	_ok("Will-O-Wisp burns", b.status == "brn", "status '%s'" % b.status)
	b = await _use("pikachu", "thunderwave,nuzzle,thundershock,quickattack", "snorlax", 6.0)
	_ok("Thunder Wave paralyzes", b.status == "par", "status '%s'" % b.status)
	b = await _use("pikachu", "thunderwave,nuzzle,thundershock,quickattack", "garchomp", 6.0)
	_ok("Thunder Wave does nothing to Ground types", b.status == "", "status '%s'" % b.status)
	b = await _use("gengar", "hypnosis,shadowball,hex,substitute", "snorlax", 5.0)
	_ok("Hypnosis puts it to sleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("snorlax", "yawn,bodyslam,icepunch,rest", "pikachu", 4.0)
	_ok("Yawn makes it drowsy", b.drowsy > 0.0 and b.status == "", "drowsy %.1f, status '%s'" % [b.drowsy, b.status])
	await _wait(Status.YAWN + 0.2)
	_ok("Then it falls asleep", b.status == "slp", "status '%s'" % b.status)
	b = await _use("pikachu", "nuzzle,thunderwave,thundershock,quickattack", "snorlax", 3.0)
	_ok("Nuzzle always paralyzes", b.status == "par", "status '%s'" % b.status)
	b = await _use("pikachu", "nuzzle,thunderwave,thundershock,quickattack", "garchomp", 3.0)
	_ok("Nuzzle does not paralyze Ground types", b.status == "", "status '%s'" % b.status)
	# Just cured: it says so and nothing happens.
	main._args["moves"] = "thunderwave,nuzzle,thundershock,quickattack"
	var ab: Array = await _setup("pikachu", "snorlax", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[1].status_lock = 3.0
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(0.7)
	var said: bool = main.vfx.texts.any(func(x): return x.s == tr("Temporary immunity"))
	_ok("Temporary immunity: no status, and it says so", said and ab[1].status == "", "status '%s'" % ab[1].status)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## sp_a, with these four moves, uses the first one on sp_b standing "dist" meters away.
func _use(sp_a: String, moves: String, sp_b: String, dist: float, wait := 1.6) -> Fighter:
	main._args["moves"] = moves
	var ab: Array = await _setup(sp_a, sp_b, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	var a: Fighter = ab[0]
	if a.data.moves[0] != moves.get_slice(",", 0):
		_ok("Loadout %s" % moves, false, "got %s" % [a.data.moves])
	a.ctrl.press("mov1")
	await _wait(0.15)
	a.ctrl.release("mov1")
	await _wait(wait)
	return ab[1]


## Fixed views of the stage for checking it by eye (captures/stage_*.png): the night
## stadium's scoreboard, the camera at a corner (it must stay out of the stands) and the
## floating stadium's floor under its floodlights.
func _stage_shots() -> void:
	main.ai.mode = "still"
	await _wait(2.0)
	var a: Fighter = main.fighters[0]
	a.is_player = false
	a.hp = a.hp_max * 0.6
	await _wait(1.5)
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(8.0, 17.0, 0.0)
	main.camera.look_at(Vector3(32.1, 21.0, 0.0))
	await _wait(0.4)
	_capture("stage_board")
	main.camera.set_physics_process(true)
	# A corner: the fighter backs into it and the camera turns toward the stands.
	a.locked = false
	a.global_position = Vector3(18.5, 0.0, 10.5)
	main.camera.yaw = deg_to_rad(-140.0)
	main.camera.pitch = 0.2
	await _wait(1.0)
	_capture("stage_corner")
	main.camera.yaw = deg_to_rad(-120.0)
	main.camera.pitch = -0.5
	await _wait(1.0)
	_capture("stage_corner_high")
	# The final blow: the strip turns the winner's color with WINNER all round.
	main.camera.yaw = deg_to_rad(-90.0)
	main.camera.pitch = -0.1
	a.global_position = Vector3(0.0, 0.0, 4.0)
	main.arena.on_ko(a)
	await _wait(1.2)
	_capture("stage_winner")
	main.arena.on_rematch()
	main.set_stage("floating")
	await _wait(1.5)
	a.global_position = Vector3(-6.0, 0.0, 0.0)
	main.camera.yaw = deg_to_rad(90.0)
	main.camera.pitch = -0.35
	await _wait(1.0)
	_capture("stage_floor")
	main.camera.pitch = -0.7
	await _wait(0.8)
	_capture("stage_floor_high")
	get_tree().quit()


## The stage pictures of the selection screen (gui/stages/<id>.png, 640 × 360): a wide
## view of each stage, no HUD or Pokémon. Run with a window; commit the result.
func _stage_previews() -> void:
	main.ai.mode = "still"
	main.hud.visible = false
	for f in main.fighters:
		f.visible = false
	main.camera.set_physics_process(false)
	var views := {"night": [Vector3(-26.0, 13.0, 22.0), Vector3(2.0, 0.0, -2.0)],
		"floating": [Vector3(-30.0, 12.0, 26.0), Vector3(0.0, -1.0, 0.0)],
		"league": [Vector3(-13.0, 10.0, 13.0), Vector3(3.0, 2.0, -8.0)]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://gui/stages"))
	for id in Menu.STAGES:
		main.set_stage(id)
		for f in main.fighters:
			f.visible = false
		main.camera.global_position = views[id][0]
		main.camera.look_at(views[id][1])
		await _wait(2.0)
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://gui/stages/%s.png" % id)
		print("preview ", id)
	get_tree().quit()


## The end of a battle and the pause, captured (captures/result.png, pause.png).
func _result_shot() -> void:
	main.ai.mode = "still"
	main.player.is_player = false
	await _wait(1.5)
	main.toggle_pause()
	await _wait(0.5)
	_capture("pause")
	main.toggle_pause()
	await _wait(0.3)
	main.fighters[1]._damage_direct(99999.0)
	await _wait(main.CHOICES_AT + 0.6)
	_capture("result")
	get_tree().quit()


## Projectiles stopped by moves that deflect (Combat.deflect): a hit of that move is put in
## front of the defender, as if it swung right on time, and the rival fires into it.
func _deflect_test() -> void:
	await get_tree().physics_frame
	var cases := [["xscissor", "thundershock", "pikachu", "mov1", "Sent back: the thrower takes it, the deflector nothing"],
		["shadowclaw", "thundershock", "pikachu", "mov1", "Broken: neither takes anything"],
		["xscissor", "sludgebomb", "venusaur", "mov3", "A lobbed bomb is never sent back"]]
	for c in cases:
		var ab: Array = await _setup("scizor", c[2], Vector3(-6, 0, 0), Vector3(4, 0, 0))
		var a: Fighter = ab[0]
		var b: Fighter = ab[1]
		var g := Hit.new()
		g.user = a
		g.move_id = c[0]
		g.shape = "sphere"
		g.center = Vector3(0, 1.0, 1.2)
		g.radius = 1.8
		g.damage = 0.0
		g.lifetime = 2.0
		# The swing comes out just as the shot gets close (within its window).
		var swing := func():
			for t in 120:
				await get_tree().physics_frame
				for p in main.combat.projectiles:
					var gap: float = p.pos.distance_to(a.center())
					if p.user == b and gap < 2.0 + p.velocity.length() * 0.05:
						main.combat.add_hit(g)
						return
		swing.call()
		var hp_a: float = a.hp
		var hp_b: float = b.hp
		main.camera.set_physics_process(false)
		main.camera.global_position = Vector3(-2.5, 2.0, 6.0)
		main.camera.look_at(Vector3(-3.5, 1.0, 0.0))
		b.ctrl.press(c[3])
		await _wait(0.15)
		b.ctrl.release(c[3])
		# Pictures around the moment it meets the swing (only with a window).
		for k in 8:
			await _wait(0.04)
			_capture("deflect_%s_%s_%d" % [c[0], c[1], k])
		await _wait(1.5)
		main.camera.set_physics_process(true)
		var ok := false
		match c[0]:
			"xscissor":
				# A lobbed bomb is never sent back (it may land or break; the thrower is untouched).
				ok = (a.hp == hp_a and b.hp < hp_b) if c[1] == "thundershock" else b.hp == hp_b
			"shadowclaw":
				ok = a.hp == hp_a and b.hp == hp_b
		_ok(c[4], ok, "deflector %d/%d, thrower %d/%d" % [a.hp, hp_a, b.hp, hp_b])
	# With the real move: Scizor swings X-Scissor when the shot is this far away. A fair
	# window means several of these timings work, not just one exact frame.
	var sent := 0
	var tries := [2.5, 4.0, 5.5, 7.0, 8.5, 10.0]
	for trigger in tries:
		main._args["moves"] = "xscissor,bulletpunch,swordsdance,wingattack"
		var ab: Array = await _setup("scizor", "pikachu", Vector3(-6, 0, 0), Vector3(4, 0, 0))
		main._args.erase("moves")
		var a: Fighter = ab[0]
		var b: Fighter = ab[1]
		a.locked = true
		var hp_b: float = b.hp
		var hp_a: float = a.hp
		var swing := func():
			for t in 120:
				await get_tree().physics_frame
				for p in main.combat.projectiles:
					if p.user == b and p.pos.distance_to(a.center()) < trigger:
						a.ctrl.press("mov1")
						await get_tree().physics_frame
						a.ctrl.release("mov1")
						return
		swing.call()
		b.ctrl.press("mov1")
		await _wait(0.15)
		b.ctrl.release("mov1")
		await _wait(1.6)
		if b.hp < hp_b and a.hp == hp_a:
			sent += 1
	_ok("Real X-Scissor sends Thunder Shock back at several timings", sent >= 3, "%d of %d timings" % [sent, tries.size()])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Holds a move's button for a while (streams).
func _hold(f: Fighter, action: String, secs := 1.6) -> void:
	f.ctrl.press(action)
	f.ctrl.held[action] = true
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(f):
			f.ctrl.held[action] = false
			f.ctrl.release(action))


## Shots that meet (Combat.clash): even ones burst, a stronger one goes on weaker.
func _clash_test() -> void:
	await get_tree().physics_frame
	# Even: two Thunder Shocks head on.
	var ab: Array = await _setup("pikachu", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var hp := [ab[0].hp, ab[1].hp]
	for f in ab:
		f.ctrl.press("mov1")
	await _wait(0.15)
	for f in ab:
		f.ctrl.release("mov1")
	await _wait(1.2)
	_ok("Even shots burst and nobody is hit", ab[0].hp == hp[0] and ab[1].hp == hp[1], "%d/%d, %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	# Stronger: Shadow Ball (80) through Thunder Shock (40), half as strong after.
	var plain := await _one_hit("gengar", "pikachu", "mov1", 12.0)
	ab = await _setup("gengar", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(0.0, 2.6, 8.5)
	main.camera.look_at(Vector3(0.0, 1.0, 0.0))
	for f in ab:
		f.ctrl.press("mov1")
	await _wait(0.15)
	for f in ab:
		f.ctrl.release("mov1")
	for k in 8:
		await _wait(0.05)
		_capture("clash_%d" % k)
	main.camera.set_physics_process(true)
	await _wait(1.2)
	var took: float = hp[1] - ab[1].hp
	_ok("The stronger shot goes on, weaker", ab[0].hp == hp[0] and took > 0.0 and took < plain * 0.75, "Pikachu took %d (plain %d), Gengar %d/%d" % [took, plain, ab[0].hp, hp[0]])
	# Streams: Hydro Pump against Flamethrower, head on. Water wins: the fire is cut where
	# they meet and never reaches Blastoise; the water reaches Charizard.
	ab = await _setup("blastoise", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	main.camera.set_physics_process(false)
	main.camera.global_position = Vector3(2.0, 3.5, 13.0)
	main.camera.look_at(Vector3(2.0, 1.2, 0.0))
	_hold(ab[0], "mov2", 2.4)
	await _wait(0.6)
	_hold(ab[1], "mov1")
	for k in 4:
		await _wait(0.12)
		_capture("streams_%d" % k)
	main.camera.set_physics_process(true)
	await _wait(1.0)
	_ok("Water cuts fire: only Charizard is hit", ab[0].hp == hp[0] and ab[1].hp < hp[1], "Blastoise %d/%d, Charizard %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	# Even streams: both cut, nobody hit.
	ab = await _setup("charizard", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	hp = [ab[0].hp, ab[1].hp]
	_hold(ab[0], "mov1")
	_hold(ab[1], "mov1")
	await _wait(1.8)
	_ok("Even streams cut each other", ab[0].hp == hp[0] and ab[1].hp == hp[1], "%d/%d, %d/%d" % [ab[0].hp, hp[0], ab[1].hp, hp[1]])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Each move added lately lands on a still Snorlax from its own distance: [user, its four
## moves (the one tried first), distance].
const NEW_MOVES := [
	["charizard", "firepunch,thunderpunch,flamethrower,airslash", 3.0],
	["charizard", "thunderpunch,firepunch,flamethrower,airslash", 2.4],
	["pikachu", "thunderbolt,quickattack,irontail,electroball", 9.0],
	["charizard", "bite,flamethrower,airslash,dragonclaw", 2.6],
	["garchomp", "crunch,dragonclaw,earthquake,stoneedge", 3.4],
	["charizard", "fireblast,flamethrower,airslash,dragonclaw", 7.0],
	["lucario", "closecombat,aurasphere,bulletpunch,extremespeed", 2.8],
	["gengar", "shadowclaw,shadowball,hex,substitute", 3.2],
	["garchomp", "rockslide,dragonclaw,earthquake,stoneedge", 8.0],
	["blastoise", "surf,hydropump,icebeam,rapidspin", 8.0],
	["gengar", "psychic,shadowball,hex,substitute", 8.0],
	["greninja", "darkpulse,watershuriken,nightslash,hydropump", 4.5],
	["venusaur", "energyball,solarbeam,sludgebomb,razorleaf", 8.0],
	["charizard", "dragonpulse,flamethrower,airslash,dragonclaw", 8.0],
	["pikachu", "thunder,quickattack,irontail,electroball", 8.0],
	["pikachu", "volttackle,quickattack,irontail,electroball", 6.0],
	["lucario", "focusblast,aurasphere,bulletpunch,extremespeed", 6.0],
	["lucario", "flashcannon,aurasphere,bulletpunch,extremespeed", 9.0],
	["garchomp", "outrage,dragonclaw,earthquake,stoneedge", 3.0],
]


func _new_moves() -> void:
	await get_tree().physics_frame
	for c in NEW_MOVES:
		var move: String = str(c[1]).get_slice(",", 0)
		main._args["moves"] = c[1]
		var dealt := await _one_hit(c[0], "snorlax", "mov1", c[2])
		main._args.erase("moves")
		_ok("%s lands from %.1f m" % [move, c[2]], dealt > 0.0, "%d damage" % dealt)
	# Thunderbolt: dodging as its ring locks avoids it.
	main._args["moves"] = "thunderbolt,quickattack,irontail,electroball"
	var ab: Array = await _setup("pikachu", "pikachu", Vector3(-5, 0, 0), Vector3(4, 0, 0))
	main._args.erase("moves")
	var hp: float = ab[1].hp
	ab[0].ctrl.press("mov1")
	await _wait(0.33)
	ab[0].ctrl.release("mov1")
	ab[1].ctrl.move_input = Vector2(0, 1)
	ab[1].ctrl.press("dodge")
	await _wait(0.1)
	ab[1].ctrl.release("dodge")
	await _wait(0.8)
	ab[1].ctrl.move_input = Vector2.ZERO
	_ok("Thunderbolt: a dodge as the ring locks avoids it", ab[1].hp == hp, "%d/%d" % [ab[1].hp, hp])
	# Outrage: after it, the user is confused: its attack buttons are shuffled, its movement is not.
	main._args["moves"] = "outrage,dragonclaw,earthquake,stoneedge"
	ab = await _setup("garchomp", "snorlax", Vector3(-3, 0, 0), Vector3(1, 0, 0))
	main._args.erase("moves")
	var g: Fighter = ab[0]
	var straight: Vector3 = g._world_dir(Vector2(1, 0))
	g.ctrl.press("mov1")
	await _wait(0.1)
	g.ctrl.release("mov1")
	await _wait(2.6)
	var after: Vector3 = g._world_dir(Vector2(1, 0))
	_ok("Outrage leaves it confused, its buttons shuffled and its movement as it was", g.confused > 0.0 and g.button_moves != Fighter.BUTTONS_STRAIGHT and after.dot(straight) > 0.9,
		"confused %.1f s, buttons %s, dot %.2f" % [g.confused, g.button_moves, after.dot(straight)])
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


func _mechanics() -> void:
	await get_tree().physics_frame
	# 1. A projectile that is not dodged hits.
	var ab: Array = await _setup("pikachu", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.ctrl.press("mov1")
	await _wait(1.0)
	_ok("Thunder Shock without dodging hits", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 2. Dodging it sideways with the dodge (invulnerability window).
	ab = await _setup("pikachu", "charizard", Vector3(-4, 0, 0), Vector3(4, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var dodged := false
	for i in 90:
		await get_tree().physics_frame
		for p in main.combat.projectiles:
			if not dodged and p.pos.distance_to(b.center()) < 5.0:
				dodged = true
				b.ctrl.yaw = atan2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
				b.ctrl.move_input = Vector2(1, 0)
				b.ctrl.press("dodge")
	_ok("Thunder Shock dodged with the dodge", b.hp == b.hp_max, "HP %d" % b.hp)
	# 3. Stepping aside does not shake it off at mid range: it follows (only a dodge
	# breaks the lock).
	ab = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.12)
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(0, 1)   # with yaw 0, "forward" is -Z: sideways to the shot
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Thunder Shock follows a rival that steps aside", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3d. A dodge breaks the lock: dodging early (its invulnerability over before the shot
	# arrives) still makes it miss, because the shot flies straight from then on.
	ab = await _setup("pikachu", "charizard", Vector3(-8, 0, 0), Vector3(8, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var fired := false
	for i in 30:
		await get_tree().physics_frame
		if not fired and not main.combat.projectiles.is_empty():
			fired = true
			b.locked = false
			b.ctrl.yaw = 0.0
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("A dodge breaks the lock: dodging early still avoids it", fired and b.hp == b.hp_max, "HP %d" % b.hp)
	# 3b. Running in a straight line does not dodge: projectiles lead a moving target.
	ab = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(0, 1)
	await _wait(0.6)
	a.ctrl.press("mov1")
	await _wait(0.9)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Thunder Shock hits a rival running in a straight line (lead)", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3c. Knockback by power: a light hit barely moves the target, a heavy one sends it
	# back, a push move further; and light Pokémon fly further than heavy ones.
	var slides := {}
	# [attacker, target, slot, attacker's distance, name]
	for c in [["pikachu", "charizard", "mov1", 6.0, "thundershock"], ["pikachu", "charizard", "mov3", 1.6, "irontail"],
			["snorlax", "charizard", "mov1", 6.0, "bodyslam"], ["charizard", "pikachu", "mov4", 6.0, "flareblitz_on_pikachu"],
			["charizard", "snorlax", "mov4", 6.0, "flareblitz_on_snorlax"]]:
		ab = await _setup(c[0], c[1], Vector3(-c[3], 0, 0), Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		var hp0: float = b.hp
		a.ctrl.press(c[2])
		await _wait(0.15)
		a.ctrl.release(c[2])
		var t0 := t
		while b.hp >= hp0 and t - t0 < 2.5:
			await get_tree().physics_frame
		var x_hit: float = b.global_position.x
		await _wait(1.6)
		slides[c[4]] = b.global_position.x - x_hit
	print("    slides: ", slides)
	_ok("Knockback by power: light < heavy < push move", slides.thundershock < 0.8 and slides.irontail > slides.thundershock * 2.0 and slides.bodyslam > slides.irontail * 0.6,
		"Thunder Shock %.1f m, Iron Tail %.1f m, Body Slam %.1f m" % [slides.thundershock, slides.irontail, slides.bodyslam])
	_ok("Knockback by weight: Pikachu flies further than Snorlax", slides.flareblitz_on_pikachu > slides.flareblitz_on_snorlax * 2.0,
		"Flare Blitz: Pikachu %.1f m, Snorlax %.1f m" % [slides.flareblitz_on_pikachu, slides.flareblitz_on_snorlax])
	# 3e. A move that cancels into moves cannot chain into itself, and the cancelled one
	# still goes on cooldown.
	ab = await _setup("greninja", "snorlax", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	var slashes := [0]
	b.hit_taken.connect(func(_q, info): if info.hit.move_id == "nightslash": slashes[0] += 1)
	for i in 6:
		a.ctrl.press("mov2")
		await _wait(0.12)
		a.ctrl.release("mov2")
		await _wait(0.12)
	await _wait(0.6)
	_ok("Night Slash cannot be chained into itself", slashes[0] == 1 and a.cds.get("nightslash", 0.0) > 1.5,
		"%d slashes, cooldown %.1f s" % [slashes[0], a.cds.get("nightslash", 0.0)])
	# 3f. Ice Beam travels: from afar, stepping aside as it fires gets out of its line;
	# standing still, it hits.
	for moving in [false, true]:
		ab = await _setup("blastoise", "pikachu", Vector3(-14, 0, 0), Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press("mov4")
		await _wait(0.15)
		a.ctrl.release("mov4")
		var shot := false
		for i in 90:
			await get_tree().physics_frame
			if not shot and a.action and a.action.phase == "active":
				shot = true
				if moving:
					b.ctrl.yaw = 0.0
					b.ctrl.move_input = Vector2(0, 1)   # yaw 0: -Z, across the beam
		b.ctrl.move_input = Vector2.ZERO
		if moving:
			_ok("Ice Beam from afar: stepping aside avoids it", b.hp == b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
		else:
			_ok("Ice Beam from afar: standing still, it hits", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 3g. Hex's mark follows a rival that walks away, and bursts on it.
	ab = await _setup("gengar", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(1, 0)
	a.ctrl.press("mov3")
	await _wait(0.15)
	a.ctrl.release("mov3")
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Hex follows a rival that walks away", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 4. Earthquake without jumping hits; jumping in time, it does not.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov3")
	await _wait(2.0)
	_ok("Earthquake hits whoever does not jump", b.hp < b.hp_max, "HP %d" % b.hp)
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov3")
	var jump := false
	for i in 150:
		await get_tree().physics_frame
		if a.action and a.action.id == "earthquake" and a.action.phase == "active" and not jump:
			var d: Dictionary = a.action.d
			var k: float = clampf(a.action.t / d.active, 0.0, 1.0)
			var r: float = d.r_max * (1.0 - pow(1.0 - k, 2.0))
			if r > 6.0 - 2.4:
				jump = true
				b.ctrl.press("jump")
	_ok("Earthquake jumped in time", b.hp == b.hp_max, "HP %d" % b.hp)
	# 4b. Poise: Snorlax prepares Earthquake (poise 1 + 1 for being heavy). A medium hit
	# (Thunder Shock) does not interrupt it; a heavy one (Iron Tail) does.
	for case_d in [["mov1", Vector3(-7, 0, 0), false], ["mov3", Vector3(-2.2, 0, 0), true]]:
		ab = await _setup("pikachu", "snorlax", case_d[1], Vector3(0, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press(case_d[0])
		await _wait(0.12 if case_d[0] == "mov1" else 0.0)
		b.ctrl.press("mov3")
		var cut := false
		for i in 70:
			await get_tree().physics_frame
			if b.action == null or b.action.id != "earthquake":
				cut = true
				break
			if b.action.phase == "active":
				break
		if case_d[2]:
			_ok("A heavy hit (Iron Tail) interrupts Earthquake", cut, "HP %d" % b.hp)
		else:
			_ok("A medium hit (Thunder Shock) does not interrupt Earthquake", not cut and b.hp < b.hp_max, "HP %d" % b.hp)
	# 4c. Streams without lockdown: inside a Flamethrower you can dodge out.
	ab = await _setup("charizard", "pikachu", Vector3(-3.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var exits := false
	for i in 120:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
		if i == 50:
			b.ctrl.yaw = 0.0
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
		if i > 50 and b.state == "dodge":
			exits = true
	a.ctrl.release("mov1")
	b.ctrl.move_input = Vector2.ZERO
	_ok("Inside a Flamethrower you can dodge out", exits and b.hp < b.hp_max, "HP %d" % b.hp)
	# 4c2. Inside Flamethrower the dodge covers half: dodging backward does not leave the cone.
	ab = await _setup("charizard", "pikachu", Vector3(-3.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	var before_x := 0.0
	var after_x := 0.0
	for i in 110:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
		if i == 50:
			before_x = b.global_position.x
			b.ctrl.yaw = -PI * 0.5   # the gamepad's "forward" is +X: away from Charizard
			b.ctrl.move_input = Vector2(0, 1)
			b.ctrl.press("dodge")
		if i == 75:
			after_x = b.global_position.x
	a.ctrl.release("mov1")
	b.ctrl.move_input = Vector2.ZERO
	var traveled := absf(after_x - before_x)
	var dodge_total: float = b.data.dodge.dist
	_ok("Inside Flamethrower, dodging backward does not leave the cone",
		# The dodge covers half; the stream also pushes back a little.
		after_x > before_x and traveled < dodge_total * 0.85 and after_x - a.global_position.x < Moves.DATA.flamethrower.length,
		"travels %.1f m of %.1f; ends %.1f m away (the stream reaches %.1f)" % [traveled, dodge_total, after_x - a.global_position.x, Moves.DATA.flamethrower.length])
	# 4d. Flight: Charizard takes off (jump and air jump), stays up and falls without stamina.
	ab = await _setup("charizard", "pikachu", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("jump")
	await _wait(0.25)
	a.ctrl.press("jump")
	await _wait(0.1)
	var takeoff: bool = a.flying
	for i in 40:
		a.ctrl.held["jump"] = true
		await get_tree().physics_frame
	await _wait(1.0)
	var flight_height: float = a.global_position.y
	var poise_before: float = a.flight
	_ok("Flight: takes off and stays in the air", takeoff and a.flying and flight_height > 2.0, "height %.1f m, stamina %.1f" % [flight_height, poise_before])
	await _wait(a.flight + 1.5)
	_ok("Flight: without stamina it stops flying and falls", not a.flying and a.global_position.y < 0.3, "height %.1f m" % a.global_position.y)
	# 4e. Ground move in the air: Earthquake during a jump dives down and fires on landing.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("jump")
	await _wait(0.25)
	a.ctrl.press("mov3")
	var saw_dive := false
	var did := false
	for i in 120:
		await get_tree().physics_frame
		if a.state == "dive":
			saw_dive = true
		if a.action and a.action.id == "earthquake":
			did = true
			break
	_ok("Earthquake in the air: dives down and fires on touching the ground", saw_dive and did, "dive %s, earthquake %s" % [saw_dive, did])
	# 4f. Height assist: Blastoise's Hydro Pump reaches a flying Charizard.
	ab = await _setup("blastoise", "charizard", Vector3(-6, 0, 0), Vector3(2, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(2, 4.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	# One frame so it stops counting as grounded; then, fly.
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov2")
	var impact_height := -1.0
	for i in 90:
		a.ctrl.held["mov2"] = true
		await get_tree().physics_frame
		if impact_height < 0.0 and b.hp < b.hp_max:
			impact_height = b.global_position.y
	a.ctrl.release("mov2")
	_ok("Hydro Pump aims at the flyer's height on its own", impact_height > 3.0, "first impact at %.1f m" % impact_height)
	# 4g. Physical hits with vertical assist: upward, downward and a diagonal dash.
	for case_d in [["charizard", "snorlax", "mov3", Vector3(-2.2, 3.0, 0), Vector3(0, 0, 0), "Flying Charizard's Dragon Claw reaches Snorlax below"],
			["pikachu", "charizard", "mov2", Vector3(-6, 0, 0), Vector3(0, 4.0, 0), "Quick Attack from the ground reaches Charizard in the air"]]:
		ab = await _setup(case_d[0], case_d[1], case_d[3], Vector3(case_d[4].x, 0, 0))
		a = ab[0]
		b = ab[1]
		for l in [a, b]:
			var pos: Vector3 = case_d[3] if l == a else case_d[4]
			l.global_position = pos
			l.velocity = Vector3.ZERO
			l.reset_physics_interpolation()
		await get_tree().physics_frame
		await get_tree().physics_frame
		for l in [a, b]:
			if l.global_position.y > 0.5 and l.data.has("flight"):
				l.flying = true
		a.face_now(b.global_position)
		a.ctrl.press(case_d[2])
		var hit_at := -1.0
		for i in 60:
			await get_tree().physics_frame
			if hit_at < 0.0 and b.hp < b.hp_max:
				hit_at = b.global_position.y - a.global_position.y
		_ok(case_d[5], hit_at != -1.0, "HP %d, height difference on hit %.1f m" % [b.hp, hit_at])
	# 4g2. If the target dodges a dash rising toward it, the attacker does not shoot into the sky.
	ab = await _setup("pikachu", "charizard", Vector3(-2.5, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(0, 4.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov2")
	var ceiling := 0.0
	for i in 70:
		b.invulnerable = 0.1
		await get_tree().physics_frame
		ceiling = maxf(ceiling, a.global_position.y)
	_ok("Dodged dash: does not shoot over the rival", ceiling < b.center().y + 0.5, "max height %.1f m (rival's center at %.1f)" % [ceiling, b.center().y])
	# 4g3. A ground Pokémon does not "fly" chasing a high Charizard: Lucario's Extreme
	# Speed against a rival 8 m up and 9 m away (before the fix it rose to 47 m from
	# inertia) rises at most to its ceiling.
	ab = await _setup("lucario", "charizard", Vector3(-9, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	b.global_position = Vector3(0, 8.0, 0)
	b.velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.flying = true
	a.face_now(b.global_position)
	a.ctrl.press("mov3")
	var ceiling_l := 0.0
	for i in 70:
		b.invulnerable = 0.1
		b.velocity = Vector3.ZERO
		b.global_position.y = 8.0
		await get_tree().physics_frame
		ceiling_l = maxf(ceiling_l, a.global_position.y)
	_ok("A ground Pokémon does not fly after a high rival", ceiling_l < a.attack_ceiling() + 0.5, "max height %.1f m (ceiling %.1f, rival at 8)" % [ceiling_l, a.attack_ceiling()])
	# 4h. Flying, attacking makes it stop (it does not carry the movement's inertia).
	ab = await _setup("charizard", "pikachu", Vector3(-6, 3.0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	await get_tree().physics_frame
	await get_tree().physics_frame
	a.flying = true
	a.velocity = Vector3(0, 0, 7.0)
	a.ctrl.press("mov1")
	await _wait(0.3)
	var before_z: float = a.global_position.z
	for i in 40:
		a.ctrl.held["mov1"] = true
		await get_tree().physics_frame
	a.ctrl.release("mov1")
	_ok("Flying, Flamethrower does not carry inertia", absf(a.global_position.z - before_z) < 0.6, "moved %.2f m" % absf(a.global_position.z - before_z))
	# 4i. Body Slam lands on a rival that stands still.
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(7, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	await _wait(1.6)
	_ok("Body Slam hits a rival that stands still", b.hp < b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	# 5. Punishing Body Slam's recovery (0.7 s lying down).
	ab = await _setup("snorlax", "pikachu", Vector3(0, 0, 0), Vector3(9, 0, 0))
	a = ab[0]
	b = ab[1]
	b.invulnerable = 1.6   # so the fall does not knock it down: this tests the punish
	a.ctrl.press("mov1")
	while not (a.action and a.action.id == "bodyslam" and a.action.phase == "recovery"):
		await get_tree().physics_frame
		if t > 30.0:
			break
	b.global_position = a.global_position + Vector3(2.0, 0, 0)
	b.reset_physics_interpolation()
	b.face_now(a.global_position)
	var before := a.hp
	b.ctrl.press("mov2")      # Pikachu's Quick Attack
	await _wait(0.35)
	_ok("Punish during Body Slam's recovery", a.hp < before, "HP %d -> %d" % [before, a.hp])
	# 6. Hitstop and combo limit (the fifth hit knocks down).
	ab = await _setup("pikachu", "snorlax", Vector3(-1.4, 0, 0), Vector3(0.0, 0, 0))
	a = ab[0]
	b = ab[1]
	var pause := false
	var count := [0]
	var lockout := 0.0
	var worst := 0.0
	b.hit_taken.connect(func(_q, _i): count[0] += 1)
	for i in 360:
		# No cooldowns or cost: Thunder Shock and Iron Tail nonstop, the worst case.
		a.cds.clear()
		a.energy = Fighter.ENERGY_MAX
		if i % 6 == 0:
			a.ctrl.press("mov1" if (i / 6) % 2 == 0 else "mov3")
		# The attacker chases to try to combo forever.
		var toward := b.global_position - a.global_position
		a.ctrl.yaw = atan2(-toward.x, -toward.z)
		a.ctrl.move_input = Vector2(0, 1) if toward.length() > 1.6 else Vector2.ZERO
		await get_tree().physics_frame
		if a.frozen():
			pause = true
		if b.state in ["stunned", "knocked_down", "lying"]:
			lockout += get_physics_process_delta_time()
			worst = maxf(worst, lockout)
		else:
			lockout = 0.0
	_ok("Hitstop on hit", pause)
	_ok("No infinite chains: the longest lockdown is short", worst < 3.0 and count[0] > 3, "%d hits, max lockdown %.1f s" % [count[0], worst])
	# 7. After a KO nothing stays active.
	b.hp = 1.0
	a.ctrl.press("mov1")
	await _wait(2.0)
	main.rematch()
	await get_tree().physics_frame
	_ok("After KO and rematch no hits or projectiles remain", main.combat.hits.is_empty() and main.combat.projectiles.is_empty(),
		"hits %d projectiles %d" % [main.combat.hits.size(), main.combat.projectiles.size()])
	# 8. Floating stadium: standing on the platform holds; a push move by the edge sends
	# the rival into the void and that is a KO (ring-out).
	var stage_before: String = main.arena.stage
	main.set_stage("floating")
	ab = await _setup("snorlax", "pikachu", Vector3(11, 0, 0), Vector3(19, 0, 0))
	a = ab[0]
	b = ab[1]
	await _wait(0.5)
	var y_on: float = b.global_position.y
	var stands: bool = absf(y_on) < 0.2 and main.arena.inside(b.global_position)
	a.ctrl.press("mov1")
	await _wait(0.15)
	a.ctrl.release("mov1")
	await _wait(3.5)
	_ok("Floating stadium: the platform holds the fighters", stands, "y %.2f" % y_on)
	_ok("Floating stadium: knocked off the edge is a KO", b.state == "ko" and b.global_position.y < 0.0,
		"state %s, position %s" % [b.state, b.global_position])
	# 9. A move never carries its user off (Extreme Speed toward the edge stops at it), but
	# dodging out or walking out does fall.
	ab = await _setup("lucario", "snorlax", Vector3(14, 0, 0), Vector3(21, 0, 0))
	a = ab[0]
	a.ctrl.press("mov3")
	await _wait(0.15)
	a.ctrl.release("mov3")
	await _wait(2.0)
	_ok("Floating stadium: Extreme Speed toward the edge stops at it", a.state != "ko" and a.global_position.y > -0.5,
		"state %s, position %s" % [a.state, a.global_position.snapped(Vector3.ONE * 0.1)])
	ab = await _setup("pikachu", "snorlax", Vector3(22, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = -PI * 0.5           # facing +X, toward the edge
	a.ctrl.move_input = Vector2(0, 1)
	a.ctrl.press("dodge")
	await _wait(2.5)
	a.ctrl.move_input = Vector2.ZERO
	_ok("Floating stadium: dodging out of the edge falls", a.state == "ko", "state %s" % a.state)
	ab = await _setup("snorlax", "pikachu", Vector3(21, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = -PI * 0.5
	a.ctrl.move_input = Vector2(0, 1)
	await _wait(3.0)
	a.ctrl.move_input = Vector2.ZERO
	_ok("Floating stadium: walking out of the edge falls", a.state == "ko", "state %s" % a.state)
	# 10. Flyers knocked off fly back (the AI recovers): Charizard and Gengar.
	for flyer in ["charizard", "gengar"]:
		ab = await _setup("snorlax", flyer, Vector3(14.5, 0, 0), Vector3(22.5, 0, 0))
		a = ab[0]
		b = ab[1]
		a.ctrl.press("mov1")
		await _wait(0.15)
		a.ctrl.release("mov1")
		var went_off := false
		var t0 := t
		while t - t0 < 1.5:
			await get_tree().physics_frame
			if not main.arena.inside(b.global_position, 0.0):
				went_off = true
		main.ai.mode = "active"          # from now on the AI plays it: it has to fly back
		await _wait(6.0)
		var back: bool = b.state != "ko" and b.global_position.y > -0.5 and main.arena.inside(b.global_position, -0.5)
		_ok("Floating stadium: %s knocked off flies back" % flyer, went_off and back,
			"off %s, state %s, position %s" % [went_off, b.state, b.global_position.snapped(Vector3.ONE * 0.1)])
		main.ai.mode = "still"
	main.set_stage(stage_before)
	await _goodra_cases()
	await _urshifu_cases()
	await _mewtwo_cases()
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Only Mewtwo's cases (--test=mewtwo), without the rest of the mechanics.
func _mewtwo_test() -> void:
	await get_tree().physics_frame
	await _mewtwo_cases()
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Only Urshifu's cases (--test=urshifu), without the rest of the mechanics.
func _urshifu_test() -> void:
	await get_tree().physics_frame
	await _urshifu_cases()
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## Goodra: its abilities, its three moves and where its moves come out of.
func _goodra_cases() -> void:
	# Gooey: contact hits only, and one use of a move is one stage (Dragon Claw is two hits).
	var dealt := await _one_hit("garchomp", "goodra", "mov2", 2.2)
	var a: Fighter = main.fighters[0]
	_ok("Gooey: Dragon Claw's two hits lower Speed only once", dealt > 0.0 and a.stages.spe == -1, "damage %d, Speed %+d" % [dealt, a.stages.spe])
	dealt = await _one_hit("pikachu", "goodra", "mov1", 6.0)
	a = main.fighters[0]
	_ok("Gooey: a projectile does not", dealt > 0.0 and a.stages.spe == 0, "damage %d, Speed %+d" % [dealt, a.stages.spe])
	# Sap Sipper: Grass does nothing and raises Attack; status moves too (Sleep Powder).
	main._args["moves"] = "energyball,solarbeam,sludgebomb,razorleaf"
	dealt = await _one_hit("venusaur", "goodra", "mov1", 8.0, "", "sapsipper")
	main._args.erase("moves")
	var b: Fighter = main.fighters[1]
	_ok("Sap Sipper: Grass does nothing and raises Attack", dealt == 0.0 and b.stages.atk == 1, "damage %d, Attack %+d" % [dealt, b.stages.atk])
	# Hydration: in the rain a status clears within a turn; without rain it stays.
	var ab: Array = await _setup("pikachu", "goodra", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	b = ab[1]
	b.data.passive = Loadout.ability("goodra", "hydration")
	main.weather.start("rain")
	b.inflict("brn")
	await _wait(Weather.TURN + 0.2)
	_ok("Hydration: in the rain its status clears within a turn", b.status == "", "status '%s'" % b.status)
	b.status_lock = 0.0
	b.inflict("slp")
	await _wait(Weather.TURN + 0.5)
	_ok("Hydration: it wakes up and can act right away", b.status == "" and b.state == "free", "status '%s', state %s" % [b.status, b.state])
	main.weather.clear()
	b.status_lock = 0.0
	b.inflict("brn")
	await _wait(Weather.TURN + 0.2)
	_ok("Hydration: without rain it stays", b.status == "brn", "status '%s'" % b.status)
	# Overcoat: no sandstorm damage, no powders. It is Goodra's exception and nobody else's.
	ab = await _setup("pikachu", "goodra", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	b = ab[1]
	b.data.passive = Loadout.ability("goodra", "overcoat")
	main.weather.start("sand")
	await _wait(Weather.TURN + 0.2)
	_ok("Overcoat: the sandstorm does not hurt it", b.hp == b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	main.weather.clear()
	main._args["moves"] = "sleeppowder,poisonpowder,toxic,solarbeam"
	ab = await _setup("venusaur", "goodra", Vector3(-2.5, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	b = ab[1]
	b.data.passive = Loadout.ability("goodra", "overcoat")
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.2)
	_ok("Overcoat: Sleep Powder has no effect", b.status == "", "status '%s'" % b.status)
	var set_with := {"moves": Roster.POKEMON.goodra.moves, "ability": "overcoat"}
	_ok("Overcoat: valid for Goodra", Loadout.valid("goodra", set_with).ability == "overcoat")
	set_with = {"moves": Roster.POKEMON.snorlax.moves, "ability": "overcoat"}
	_ok("Overcoat: rejected for everyone else", Loadout.valid("snorlax", set_with).ability != "overcoat")
	# Acid Spray: -2 Sp. Def, and the next special hit deals more; nothing on Steel types.
	main._args["moves"] = "acidspray,dragonpulse,surf,icebeam"
	var plain := await _one_hit("goodra", "snorlax", "mov2", 8.0)
	ab = await _setup("goodra", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(1.6)
	var drop: int = ab[1].stages.spd
	var hp0: float = ab[1].hp
	_ok("Acid Spray: -2 Sp. Def on a hit", drop == -2 and hp0 < ab[1].hp_max, "Sp. Def %+d, HP %d/%d" % [drop, hp0, ab[1].hp_max])
	ab[0].ctrl.press("mov2")
	await _wait(0.15)
	ab[0].ctrl.release("mov2")
	await _wait(1.6)
	_ok("Acid Spray: later special hits deal more", hp0 - ab[1].hp > plain * 1.5, "%d after it, %d without" % [hp0 - ab[1].hp, plain])
	b = await _use("goodra", "acidspray,dragonpulse,surf,icebeam", "lucario", 8.0)
	_ok("Acid Spray: no drop on Steel types", b.stages.spd == 0 and b.hp < b.hp_max, "Sp. Def %+d, HP %d/%d" % [b.stages.spd, b.hp, b.hp_max])
	# It comes down where the rival was going: walking out from under it works.
	main._args["moves"] = "acidspray,dragonpulse,surf,icebeam"
	ab = await _setup("goodra", "pikachu", Vector3(-10, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[0].ctrl.press("mov1")
	await _wait(0.45)
	ab[0].ctrl.release("mov1")
	ab[1].ctrl.yaw = 0.0
	ab[1].ctrl.move_input = Vector2(0, 1)
	await _wait(1.5)
	ab[1].ctrl.move_input = Vector2.ZERO
	_ok("Acid Spray: walking out from under it avoids it", ab[1].hp == ab[1].hp_max, "HP %d/%d" % [ab[1].hp, ab[1].hp_max])
	# Mud Shot: -1 Speed on a hit; nothing on an immune type.
	b = await _use("goodra", "mudshot,dragonpulse,surf,icebeam", "snorlax", 8.0)
	_ok("Mud Shot: -1 Speed on a hit", b.stages.spe == -1 and b.hp < b.hp_max, "Speed %+d, HP %d/%d" % [b.stages.spe, b.hp, b.hp_max])
	b = await _use("goodra", "mudshot,dragonpulse,surf,icebeam", "charizard", 8.0)
	_ok("Mud Shot: no drop on Charizard", b.stages.spe == 0 and b.hp < b.hp_max, "Speed %+d, HP %d/%d" % [b.stages.spe, b.hp, b.hp_max])
	# Water Pulse: it widens as it flies, and its 20% can confuse (the roll forced here).
	main._args["moves"] = "waterpulse,dragonpulse,surf,icebeam"
	ab = await _setup("goodra", "snorlax", Vector3(-14, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	ab[0].ctrl.press("mov1")
	await _wait(0.15)
	ab[0].ctrl.release("mov1")
	await _wait(0.6)
	var widest := 0.0
	for p in main.combat.projectiles:
		widest = maxf(widest, p.radius)
	_ok("Water Pulse: it widens as it flies", widest > float(Moves.DATA.waterpulse.radius) * 1.3, "radius %.2f" % widest)
	await _wait(1.2)
	_ok("Water Pulse: it hits", ab[1].hp < ab[1].hp_max, "HP %d/%d" % [ab[1].hp, ab[1].hp_max])
	b = ab[1]
	b.confused = 0.0
	var g := Hit.new()
	g.type = "water"
	b._secondary({"secondary": {"chance": 1.0, "confuse": 3.0}}, {"hit": g}, null)
	_ok("Water Pulse: a secondary can confuse", b.confused > 2.0, "confused %.1f s" % b.confused)
	b.confused = 0.0
	b.effect("confuse", 3.0)
	_ok("Confusion arrives as an effect (what an online rival gets)", b.confused > 2.0, "confused %.1f s" % b.confused)
	# Moves written for other bodies come out of its mouth, not its chest.
	ab = await _setup("goodra", "snorlax", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	var mouth_at: Vector3 = ab[0].model.bone_world("mouth")
	_ok("Points: cannons map to Goodra's mouth", ab[0].point("locator_cannon_left").distance_to(mouth_at) < 0.01, "%s" % mouth_at.snapped(Vector3.ONE * 0.01))
	var low: float = absf(mouth_at.y - float(ab[0].data.height) * 0.7)
	_ok("Mouth height: moves that use Action.mouth() leave from around its real mouth", low < 0.3, "bone %.2f m up, off by %.2f m" % [mouth_at.y, low])


# ---------------------------------------------------------------- Urshifu

## A hit of "move" from "by" on "to" right now, as Combat resolves it (the result: "hit",
## "protected", "failed"...), without waiting for it to connect.
func _strike(by: Fighter, to: Fighter, move: String) -> String:
	var d: Dictionary = Moves.DATA[move]
	var g := Hit.new()
	g.user = by
	g.move_id = move
	g.type = d.type
	g.cat = d.cat
	g.damage = d.get("damage", 50.0)
	g.stun = d.get("stun", 0.3)
	g.strength = d.get("strength", 1)
	g.contact = d.get("contact", true)
	g.local = false
	return main.combat.apply(g, to, to.center())


## Damage of one whole use of "move", from the formula alone.
func _formula(move: String, a: Fighter, b: Fighter) -> float:
	var g := Hit.new()
	g.user = a
	g.move_id = move
	g.type = Moves.DATA[move].type
	g.cat = Moves.DATA[move].cat
	g.damage = Moves.DATA[move].damage
	return Damage.dealt(g, a, b, 1.0)


## Presses "slot" and returns how long until it is free again.
func _time_to_free(a: Fighter, slot := "mov1") -> float:
	await _wait(0.2)                 # a hit's hitstop would swallow the press
	a.ctrl.press(slot)
	await get_tree().physics_frame
	a.ctrl.release(slot)
	var t0 := t
	while a.state == "free" and t - t0 < 0.5:
		await get_tree().physics_frame
	while a.state != "free" and t - t0 < 4.0:
		await get_tree().physics_frame
	return t - t0


## Sets up "sp_a" with these moves against "sp_b", "dist" meters apart.
func _with_moves(sp_a: String, moves: String, sp_b: String, dist: float) -> Array:
	main._args["moves"] = moves
	var ab: Array = await _setup(sp_a, sp_b, Vector3(-dist, 0, 0), Vector3(0, 0, 0))
	main._args.erase("moves")
	return ab


## Urshifu: crits, Unseen Fist, the new guards and reads, its forms and the wall's single cell.
func _urshifu_cases() -> void:
	var single := "wickedblow,suckerpunch,closecombat,bulkup"
	var rapid := "surgingstrikes,liquidation,chillingwater,closecombat"
	# Crits: a raised Defense and its own lowered Attack do nothing; x1.5; a burn still halves it.
	var ab: Array = await _setup("urshifu", "snorlax", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	var crit := _formula("wickedblow", a, b)
	var plain := _formula("lashout", a, b)
	_ok("Crit: x1.5 a non-crit of equal power", absf(crit / plain - 1.5) < 0.02, "%.1f vs %.1f" % [crit, plain])
	a.stages.atk = -1
	_ok("Crit: ignores its own lowered Attack", absf(_formula("wickedblow", a, b) - crit) < 0.01, "%.1f" % _formula("wickedblow", a, b))
	a.stages.atk = 0
	b.stages.def = 2
	_ok("Crit: ignores the target's raised Defense", absf(_formula("wickedblow", a, b) - crit) < 0.01, "%.1f" % _formula("wickedblow", a, b))
	b.stages.def = 0
	a.stages.atk = 2
	_ok("Crit: keeps its own raised Attack", _formula("wickedblow", a, b) > crit * 1.5, "%.1f" % _formula("wickedblow", a, b))
	a.stages.atk = 0
	a.status = "brn"
	var burned := _formula("wickedblow", a, b)
	a.status = ""
	_ok("Crit: a burn still halves it", burned < crit * 0.6, "%.1f vs %.1f" % [burned, crit])
	var dealt := await _one_hit("urshifu", "snorlax", "mov1", 3.0)
	_ok("Wicked Blow: it lands for the whole formula", absf(dealt - crit) < crit * 0.15, "%.1f vs %.1f" % [dealt, crit])
	# Surging Strikes: three blows on a still rival add up to one use.
	ab = await _setup("urshifurapidstrike", "snorlax", Vector3(-2, 0, 0), Vector3(0, 0, 0))
	var whole := _formula("surgingstrikes", ab[0], ab[1])
	dealt = await _one_hit("urshifurapidstrike", "snorlax", "mov1", 2.0)
	_ok("Surging Strikes: three blows add up to one use", absf(dealt - whole) < whole * 0.1, "%.1f vs %.1f" % [dealt, whole])
	# Unseen Fist: contact goes through Protect and Detect; a shot does not; nor without the ability.
	ab = await _setup("urshifu", "lucario", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	for guard in ["protect", "detect"]:
		b.reset(Vector3(0, 0, 0), -PI * 0.5)
		a.reset(Vector3(-3, 0, 0), PI * 0.5)
		a.data.passive = Loadout.ability("urshifu", "unseenfist")
		b.start(guard, "mov1")
		await _wait(0.1)
		var res := _strike(a, b, "wickedblow")
		_ok("Unseen Fist: contact goes through %s" % guard, res == "hit" and b.hp < b.hp_max, "%s, HP %d/%d" % [res, b.hp, b.hp_max])
		b.reset(Vector3(0, 0, 0), -PI * 0.5)
		a.reset(Vector3(-3, 0, 0), PI * 0.5)
		b.start(guard, "mov1")
		await _wait(0.1)
		res = _strike(a, b, "darkpulse")
		_ok("Unseen Fist: a shot does not go through %s" % guard, res in ["protected", "detected"] and b.hp == b.hp_max, "%s, HP %d/%d" % [res, b.hp, b.hp_max])
		b.reset(Vector3(0, 0, 0), -PI * 0.5)
		a.reset(Vector3(-3, 0, 0), PI * 0.5)
		a.data.passive = Loadout.ability("urshifu", "innerfocus")
		b.start(guard, "mov1")
		await _wait(0.1)
		res = _strike(a, b, "wickedblow")
		_ok("Without Unseen Fist, %s stops contact" % guard, res in ["protected", "detected"] and b.hp == b.hp_max, "%s, HP %d/%d" % [res, b.hp, b.hp_max])
	# Protect: every blow of a flurry, and the attacker is not stunned.
	ab = await _with_moves("urshifurapidstrike", rapid, "lucario", 2.0)
	a = ab[0]
	b = ab[1]
	a.data.passive = Loadout.ability("urshifurapidstrike", "innerfocus")
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	b.start("protect", "mov1")
	var stunned := false
	var t0 := t
	while t - t0 < 0.5:
		await get_tree().physics_frame
		stunned = stunned or a.state == "stunned"
	_ok("Protect: stops every blow of a flurry", b.hp == b.hp_max, "HP %d/%d" % [b.hp, b.hp_max])
	_ok("Protect: does not stun the attacker", not stunned)
	# Counter: a physical hit costs the user its damage and the attacker double.
	ab = await _setup("urshifu", "snorlax", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.start("counter", "mov1")
	await _wait(0.15)
	var res := _strike(b, a, "bodyslam")
	var taken: float = a.hp_max - a.hp
	var back: float = b.hp_max - b.hp
	_ok("Counter: pays a physical hit back double", res == "armor" and absf(back - taken * 2.0) < 1.0, "%s, took %d, back %d" % [res, taken, back])
	_ok("Counter: the user does not flinch, the attacker is stunned", a.state == "action" and b.state == "stunned", "%s, %s" % [a.state, b.state])
	a.reset(Vector3(-3, 0, 0), PI * 0.5)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.start("counter", "mov1")
	await _wait(0.15)
	res = _strike(b, a, "darkpulse")
	_ok("Counter: a special hit cuts the stance, nothing comes back", res == "hit" and a.state == "stunned" and b.hp == b.hp_max, "%s, %s, HP %d/%d" % [res, a.state, b.hp, b.hp_max])
	a.reset(Vector3(-7, 0, 0), PI * 0.5)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.start("counter", "mov1")
	await _wait(0.15)
	res = _strike(b, a, "bodyslam")
	_ok("Counter: a physical hit from beyond 5 m does not trigger it", res == "hit" and b.hp == b.hp_max, "%s, HP %d/%d" % [res, b.hp, b.hp_max])
	a.reset(Vector3(-3, 0, 0), PI * 0.5)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.start("counter", "mov1")
	await _wait(0.15)
	a.hp = 1.0
	_strike(b, a, "bodyslam")
	_ok("Counter: no payback on a KO", a.state == "ko" and b.hp == b.hp_max, "%s, HP %d/%d" % [a.state, b.hp, b.hp_max])
	ab = await _setup("urshifu", "gengar", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	a.start("counter", "mov1")
	await _wait(0.15)
	_strike(b, a, "bodyslam")
	_ok("Counter: Ghost types take a quarter of it", absf((b.hp_max - b.hp) - (a.hp_max - a.hp) * 0.5) < 1.0, "took %d, back %d" % [a.hp_max - a.hp, b.hp_max - b.hp])
	# Sucker Punch: only against a rival about to deal damage.
	ab = await _with_moves("urshifu", single.replace("wickedblow,suckerpunch", "suckerpunch,wickedblow"), "snorlax", 4.0)
	a = ab[0]
	b = ab[1]
	res = _strike(a, b, "suckerpunch")
	_ok("Sucker Punch: fails against an idle rival", res == "failed" and b.hp == b.hp_max, "%s" % res)
	b.start("earthquake", "mov1")
	await _wait(0.02)
	res = _strike(a, b, "suckerpunch")
	_ok("Sucker Punch: connects against a rival in startup", res in ["hit", "armor"] and b.hp < b.hp_max, "%s, phase %s" % [res, b.action.phase if b.action else ""])
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	b.start("earthquake", "mov1")
	b.action._go_to("recovery")
	res = _strike(a, b, "suckerpunch")
	_ok("Sucker Punch: fails against a rival in recovery", res == "failed", "%s" % res)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	b.start("bulkup", "mov1")
	await _wait(0.02)
	res = _strike(a, b, "suckerpunch")
	_ok("Sucker Punch: fails against a status move", res == "failed", "%s" % res)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.reset(Vector3(-4, 0, 0), PI * 0.5)
	var missed := await _time_to_free(a)
	_ok("Sucker Punch: the failure has the long recovery", missed > 1.0, "%.2f s" % missed)
	a.reset(Vector3(-4, 0, 0), PI * 0.5)
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.cds.clear()
	await _wait(0.2)
	b.start("earthquake", "mov1")
	var connected := await _time_to_free(a)
	_ok("Sucker Punch: connecting recovers soon", connected < missed - 0.3, "%.2f s, %.2f s failing" % [connected, missed])
	# Lash Out: doubled for 3 s after any drop.
	ab = await _setup("urshifu", "snorlax", Vector3(-2, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	var lash: Dictionary = Moves.DATA.lashout
	_ok("Lash Out: normal with no drop", Damage.power_of(lash, a, b) == 75.0)
	b = await _use("goodra", "mudshot,dragonpulse,surf,icebeam", "urshifu", 8.0)
	_ok("Lash Out: doubled after a rival's drop", b.stages.spe == -1 and Damage.power_of(lash, b, null) == 150.0, "Speed %+d, power %d" % [b.stages.spe, Damage.power_of(lash, b, null)])
	await _wait(3.1)
	_ok("Lash Out: normal again after 3 s", Damage.power_of(lash, b, null) == 75.0, "power %d" % Damage.power_of(lash, b, null))
	await _use("urshifu", "closecombat,wickedblow,suckerpunch,bulkup", "snorlax", 2.0, 1.6)
	a = main.fighters[0]
	_ok("Lash Out: doubled after its own Close Combat", a.stages.def == -1 and Damage.power_of(lash, a, null) == 150.0, "Def %+d, power %d" % [a.stages.def, Damage.power_of(lash, a, null)])
	await _use("urshifu", "closecombat,wickedblow,suckerpunch,bulkup", "snorlax", 14.0, 1.0)
	a = main.fighters[0]
	_ok("Lash Out: normal after a Close Combat that missed", a.stages.def == 0 and Damage.power_of(lash, a, null) == 75.0, "Def %+d, power %d" % [a.stages.def, Damage.power_of(lash, a, null)])
	ab = await _with_moves("urshifu", "lashout,wickedblow,closecombat,bulkup", "snorlax", 14.0)
	var whiff := await _time_to_free(ab[0])
	_ok("Lash Out: a miss has the long recovery", whiff > 1.7, "%.2f s" % whiff)
	ab = await _with_moves("urshifu", "lashout,wickedblow,closecombat,bulkup", "snorlax", 2.0)
	var landed := await _time_to_free(ab[0])
	_ok("Lash Out: a hit has the short recovery", landed < whiff - 0.5, "%.2f s" % landed)
	ab = await _with_moves("urshifu", "lashout,wickedblow,closecombat,bulkup", "lucario", 2.0)
	a = ab[0]
	b = ab[1]
	a.data.passive = Loadout.ability("urshifu", "innerfocus")
	a.ctrl.press("mov1")
	await _wait(0.45)
	a.ctrl.release("mov1")
	b.start("protect", "mov1")
	var t1 := t
	while a.state != "free" and t - t1 < 3.0:
		await get_tree().physics_frame
	_ok("Lash Out: a blocked hit counts as a miss", b.hp == b.hp_max and t - t1 > 1.0, "HP %d/%d, %.2f s more" % [b.hp, b.hp_max, t - t1])
	# Bulk Up: +1 and +1; a hit during the flex gives nothing; three uses a battle.
	ab = await _with_moves("urshifu", "bulkup,wickedblow,closecombat,suckerpunch", "snorlax", 8.0)
	a = ab[0]
	b = ab[1]
	await _time_to_free(a)
	_ok("Bulk Up: +1 Attack and +1 Defense", a.stages.atk == 1 and a.stages.def == 1, "Atk %+d, Def %+d" % [a.stages.atk, a.stages.def])
	a.reset(Vector3(-2, 0, 0), PI * 0.5)
	a.start("bulkup", "mov1")
	await _wait(0.4)
	_strike(b, a, "bodyslam")
	await _wait(1.0)
	_ok("Bulk Up: a hit during the flex gives nothing", a.stages.atk == 0 and a.stages.def == 0, "Atk %+d, Def %+d" % [a.stages.atk, a.stages.def])
	a.reset(Vector3(-8, 0, 0), PI * 0.5)
	for i in 3:
		a.cds.clear()
		a.energy = Fighter.ENERGY_MAX
		await _time_to_free(a)
	a.cds.clear()
	a.energy = Fighter.ENERGY_MAX
	_ok("Bulk Up: a 4th use is refused", not a.ready("bulkup") and a.stages.atk == 3, "uses left %d, Atk %+d" % [a.uses.get("bulkup", -1), a.stages.atk])
	# Chilling Water: always -1 Attack. Liquidation: its drop, with the roll forced.
	b = await _use("urshifurapidstrike", rapid.replace("surgingstrikes,liquidation,chillingwater", "chillingwater,surgingstrikes,liquidation"), "snorlax", 8.0)
	_ok("Chilling Water: -1 Attack on a hit", b.stages.atk == -1 and b.hp < b.hp_max, "Atk %+d, HP %d/%d" % [b.stages.atk, b.hp, b.hp_max])
	var liquidation: Dictionary = Moves.DATA.liquidation.duplicate(true)
	liquidation.secondary.chance = 1.0
	var water := Hit.new()
	water.type = "water"
	b.stages.def = 0
	b._secondary(liquidation, {"hit": water}, null)
	_ok("Liquidation: -1 Defense when the roll comes up", b.stages.def == -1, "Def %+d" % b.stages.def)
	dealt = await _one_hit("urshifurapidstrike", "snorlax", "mov2", 4.0)
	_ok("Liquidation: it hits", dealt > 0.0, "%.1f" % dealt)
	# The AI: reads only when they work, guards only against what they stop.
	ab = await _setup("urshifu", "lucario", Vector3(-3, 0, 0), Vector3(0, 0, 0))
	var ai: AI = main.ai
	var idle := {"state": "free", "phase": "", "action": ""}
	_ok("AI: no Sucker Punch against an idle rival", not ai._only_if(Moves.DATA.suckerpunch.ai, idle))
	_ok("AI: Sucker Punch against a seen attack", ai._only_if(Moves.DATA.suckerpunch.ai, {"state": "action", "phase": "startup", "action": "bodyslam"}))
	_ok("AI: no Sucker Punch against a seen status move", not ai._only_if(Moves.DATA.suckerpunch.ai, {"state": "action", "phase": "startup", "action": "bulkup"}))
	_ok("AI: Lash Out only while it is doubled", not ai._only_if(Moves.DATA.lashout.ai, idle))
	_ok("AI: no Detect against Unseen Fist's contact moves", not ai._guard_fits("detect", "wickedblow") and ai._guard_fits("detect", "darkpulse"))
	_ok("AI: Counter only against physical hits from close by", ai._guard_fits("counter", "wickedblow") and not ai._guard_fits("counter", "darkpulse"))
	# Its forms: their own types and moves, the same ability.
	_ok("Forms: each with its own types", Species.DATA.urshifu.types == ["fighting", "dark"] and Species.DATA.urshifurapidstrike.types == ["fighting", "water"])
	_ok("Forms: the same stats", Species.DATA.urshifu.stats == Species.DATA.urshifurapidstrike.stats and Species.DATA.urshifu.stats.atk == 130)
	_ok("Forms: Single Strike cannot use Surging Strikes", not "surgingstrikes" in Loadout.moves_for("urshifu") and "wickedblow" in Loadout.moves_for("urshifu"))
	_ok("Forms: Rapid Strike cannot use Wicked Blow", not "wickedblow" in Loadout.moves_for("urshifurapidstrike") and "surgingstrikes" in Loadout.moves_for("urshifurapidstrike"))
	var with_focus := {"moves": Roster.POKEMON.urshifu.moves, "ability": "innerfocus"}
	_ok("Forms: Inner Focus is valid for Single Strike", Loadout.valid("urshifu", with_focus).ability == "innerfocus")
	with_focus = {"moves": Roster.POKEMON.urshifurapidstrike.moves, "ability": "innerfocus"}
	_ok("Forms: Inner Focus is valid for Rapid Strike", Loadout.valid("urshifurapidstrike", with_focus).ability == "innerfocus")
	with_focus = {"moves": Roster.POKEMON.pikachu.moves, "ability": "innerfocus"}
	_ok("Forms: Inner Focus is rejected for Pikachu", Loadout.valid("pikachu", with_focus).ability != "innerfocus")
	# The wall: one cell, a flip changes the pick, each side keeps its form.
	var m: Menu = main.menu
	var keep: Dictionary = m.choice.duplicate(true)
	var phase := m.sel_phase
	var cursor := m.cursor
	m.form_pick = {}
	m.choice.format = "1v1"
	m.sel_phase = "p1"
	var cells := m.pokemon_list().filter(func(sp): return Roster.base_of(sp) == "urshifu")
	_ok("Wall: one cell for Urshifu", cells == ["urshifu"], "%s" % [cells])
	m.cursor = m.cell_of("urshifu")
	m._pick_on_wall(m.cursor)
	m._flip_form()
	_ok("Wall: a flip changes the pick and the cell", m.choice.p1 == "urshifurapidstrike" and m.pokemon_list()[m.cursor] == "urshifurapidstrike", "%s" % m.choice.p1)
	m.sel_phase = "p2"
	m.cursor = m.cell_of("urshifu")
	m._pick_on_wall(m.cursor)
	m.sel_phase = "p1"
	m.cursor = m.cell_of(m.choice.p1)
	_ok("Wall: a side's form survives the other side picking", m.choice.p1 == "urshifurapidstrike" and m.choice.p2 == "urshifu" and m.pokemon_list()[m.cursor] == "urshifurapidstrike", "%s, %s" % [m.choice.p1, m.choice.p2])
	m.choice.format = "3v3"
	m.choice.team = ["pikachu", "urshifu"]
	m.cursor = m.cell_of("urshifu")
	m._flip_form()
	_ok("Wall: a flip swaps it on the team, in place", m.choice.team == ["pikachu", "urshifurapidstrike"], "%s" % [m.choice.team])
	m._team_pick("urshifurapidstrike")
	_ok("Wall: picking the form on the team takes it out", m.choice.team == ["pikachu"], "%s" % [m.choice.team])
	m.choice.team = ["urshifurapidstrike"]
	var ids := m.team_ids(0, "urshifu")
	_ok("Team: never both forms", ids.filter(func(sp): return Roster.base_of(sp) == "urshifu").size() == 1, "%s" % [ids])
	m.rival_team_choice({"count": 3, "team": ["urshifu", "urshifurapidstrike", "pikachu"]})
	_ok("Team: an online rival's cannot hold both forms", m.rival_team.is_empty())
	_ok("Wall: both forms get a portrait", "urshifu" in m.all_forms() and "urshifurapidstrike" in m.all_forms())
	m.choice = keep
	m.sel_phase = phase
	m.cursor = cursor
	m.form_pick = {}


## Mewtwo: Pressure, its six new moves and what they need from the shared rules.
func _mewtwo_cases() -> void:
	await _mewtwo_pressure()
	await _mewtwo_disable()
	await _mewtwo_confusion()
	await _mewtwo_teleport()
	await _mewtwo_boosts()
	await _mewtwo_ai()


## Pressure: the rival's cooldowns tick 1.1 times slower, only while Mewtwo is on the field.
func _mewtwo_pressure() -> void:
	var ab: Array = await _setup("mewtwo", "pikachu", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	b.cds["quickattack"] = 4.0
	a.cds["psychic"] = 4.0
	var t0 := t
	while b.cd("quickattack") > 0.0 and t - t0 < 6.0:
		await get_tree().physics_frame
	_ok("Pressure: a rival's 4 s cooldown takes 4.4 s", absf(t - t0 - 4.4) < 0.1, "%.2f s" % [t - t0])
	b.cds["quickattack"] = 4.0
	a.cds["psychic"] = 4.0
	t0 = t
	while a.cd("psychic") > 0.0 and t - t0 < 6.0:
		await get_tree().physics_frame
	_ok("Pressure: its own side's 4 s cooldown takes 4 s", absf(t - t0 - 4.0) < 0.1, "%.2f s" % [t - t0])
	var left := b.cd("quickattack")
	a._damage_direct(999999.0)
	b.cds["quickattack"] = 2.0
	await _wait(1.0)
	_ok("Pressure: normal speed once Mewtwo is KO", absf(b.cd("quickattack") - 1.0) < 0.05, "%.2f left (%.2f before)" % [b.cd("quickattack"), left])
	# 3 vs 3: it stops when Mewtwo goes back and resumes when it returns.
	ab = await _team_battle("mewtwo", "mewtwo,pikachu,snorlax", "lucario", "lucario,gengar,goodra")
	a = ab[0]
	b = ab[1]
	b.cds["meteormash"] = 9.0
	await _wait(1.0)
	var slowed: float = 9.0 - b.cd("meteormash")
	await _team_switch(a.party, 0)
	await _wait(0.8)
	b.cds["meteormash"] = 9.0
	await _wait(1.0)
	var free: float = 9.0 - b.cd("meteormash")
	_ok("Pressure 3 vs 3: slower while Mewtwo is out", absf(slowed - 1.0 / Fighter.PRESSURE) < 0.05, "%.2f" % slowed)
	_ok("Pressure 3 vs 3: normal once it is switched out", absf(free - 1.0) < 0.05, "%.2f" % free)
	# Past the return lockout, with a switch to spend.
	var party: Party = a.party
	party.lockout.clear()
	party.charges = 2
	await _team_switch(party, 0 if party.slot_member(0) == a else 1)
	await _wait(0.8)
	b.cds["meteormash"] = 9.0
	await _wait(1.0)
	var again: float = 9.0 - b.cd("meteormash")
	_ok("Pressure 3 vs 3: slower again when it returns", party.active == a and absf(again - 1.0 / Fighter.PRESSURE) < 0.05, "%.2f, Mewtwo out: %s" % [again, party.active == a])
	main.menu.choice.format = "1v1"
	# A cooldown longer than the move's own (a Disable) draws no negative line.
	_ok("HUD: more cooldown left than its own is not negative", Hud.cooldown_done(3.0, "quickattack") == 0.0 and Hud.cooldown_done(0.0, "quickattack") == 1.0)


func _mewtwo_disable() -> void:
	var loadout := "disable,psychic,shadowball,confusion"
	var ab: Array = await _with_moves("mewtwo", loadout, "lucario", 2.0)
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	var m: Array = b.data.moves
	b.cds[m[1]] = 1.0
	b.cds[m[2]] = 6.0
	_strike(a, b, "disable")
	_ok("Disable: moves with no cooldown go to 3 s", b.cd(m[0]) == 3.0 and b.cd(m[3]) == 3.0, "%.2f, %.2f" % [b.cd(m[0]), b.cd(m[3])])
	_ok("Disable: 1 s left stays 1 s and 6 s left stays 6 s", b.cd(m[1]) == 1.0 and b.cd(m[2]) == 6.0, "%.2f, %.2f" % [b.cd(m[1]), b.cd(m[2])])
	_ok("Disable: no damage and no stun", b.hp == b.hp_max and b.state == "free", "HP %d/%d, %s" % [b.hp, b.hp_max, b.state])
	for k in m:
		b.cds[k] = 5.0
	var res := _strike(a, b, "disable")
	_ok("Disable: all four cooling, it changes nothing", res == "status" and m.all(func(k): return b.cd(k) == 5.0), "%s" % res)
	for guard in ["protect", "detect"]:
		b.reset(Vector3(0, 0, 0), -PI * 0.5)
		a.reset(Vector3(-2, 0, 0), PI * 0.5)
		b.start(guard, "mov1")
		await _wait(0.1)
		res = _strike(a, b, "disable")
		_ok("Disable: %s stops it" % guard, res in ["protected", "detected"] and b.cd(m[0]) == 0.0, "%s" % res)
	# A dodge avoids the real spark; the real spark lands otherwise, and flies straight.
	b.reset(Vector3(0, 0, 0), -PI * 0.5)
	a.reset(Vector3(-2.5, 0, 0), PI * 0.5)
	a.ctrl.press("mov1")
	await _wait(0.2)
	a.ctrl.release("mov1")
	b.ctrl.move_input = Vector2(1, 0)
	b.ctrl.press("dodge")
	await _wait(0.5)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Disable: a dodge avoids it", b.cd(m[0]) == 0.0, "%.2f" % b.cd(m[0]))
	# A move running when it lands finishes, then takes its full cooldown.
	ab = await _with_moves("mewtwo", loadout, "lucario", 2.0)
	a = ab[0]
	b = ab[1]
	b.start("meteormash", "mov2")
	_strike(a, b, "disable")
	var running: bool = b.action != null and b.action.id == "meteormash"
	var t0 := t
	while b.action and t - t0 < 3.0:
		await get_tree().physics_frame
	_ok("Disable: a move running goes on, then takes its full cooldown", running and b.cd("meteormash") > Moves.cooldown("meteormash") - 0.1, "%.2f of %.2f" % [b.cd("meteormash"), Moves.cooldown("meteormash")])
	# Point-blank on Pikachu, whose head is below Mewtwo's eyes.
	ab = await _with_moves("mewtwo", loadout, "pikachu", 1.0)
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	await _wait(0.5)
	_ok("Disable: connects at point-blank on Pikachu", b.cd("thundershock") > 2.0, "%.2f" % b.cd("thundershock"))
	# Sent back by a move with "deflects": 2, it disables Mewtwo.
	ab = await _with_moves("mewtwo", loadout, "lucario", 3.0)
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	var shot := {}
	t0 = t
	while shot.is_empty() and t - t0 < 0.6:
		await get_tree().physics_frame
		for p in main.combat.projectiles:
			if p.hit.move_id == "disable":
				shot = p
	main.combat.deflect(shot, b, 2)
	await _wait(0.5)
	_ok("Disable: sent back, it disables its user", a.cd("psychic") > 2.0 and b.cd("meteormash") == 0.0, "%.2f, %.2f" % [a.cd("psychic"), b.cd("meteormash")])
	_ok("Disable: reaches Gengar's moves too", "disable" in Loadout.moves_for("gengar"))


func _mewtwo_confusion() -> void:
	var loadout := "confusion,psychic,shadowball,teleport"
	var ab: Array = await _with_moves("mewtwo", loadout, "lucario", 2.0)
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.1)
	a.ctrl.release("mov1")
	var t0 := t
	while b.hp == b.hp_max and t - t0 < 1.0:
		await get_tree().physics_frame
	_ok("Confusion: a hit always confuses for 2.5 s", b.hp < b.hp_max and absf(b.confused - 2.5) < 0.1, "HP %d/%d, %.2f s" % [b.hp, b.hp_max, b.confused])
	await _wait(0.5)
	var left := b.confused
	_strike(a, b, "confusion")
	_ok("Confusion: a second hit does not refresh it", b.confused <= left, "%.2f, was %.2f" % [b.confused, left])
	b.confused = 0.02
	await _wait(0.1)
	b.confuse(2.5)
	_ok("Confusion: nothing right after it ends", b.confused == 0.0, "%.2f" % b.confused)
	await _wait(2.8)
	b.confuse(2.5)
	_ok("Confusion: nothing for 3 s after it ends", b.confused == 0.0, "%.2f" % b.confused)
	await _wait(0.3)
	b.confuse(2.5)
	_ok("Confusion: then it works again", b.confused == 2.5, "%.2f" % b.confused)
	# Every attack button fires another of its moves, and nothing else changes.
	ab = await _with_moves("mewtwo", loadout, "snorlax", 6.0)
	a = ab[0]
	var straight: Vector3 = a._world_dir(Vector2(1, 0))
	a.confuse(2.5)
	var order: Array = a.button_moves.duplicate()
	var sorted_order := order.duplicate()
	sorted_order.sort()
	_ok("Confusion: all four moves stay, none on its own button", sorted_order == Fighter.BUTTONS_STRAIGHT and range(4).all(func(i): return order[i] != i), "%s" % [order])
	_ok("Confusion: movement stays as it was", a._world_dir(Vector2(1, 0)).dot(straight) > 0.9)
	_ok("Confusion: the order fits the byte sent online", Net.buttons_from(Net.buttons_code(order)) == order, "%s" % [order])
	a.ctrl.press("mov1")
	await _wait(0.05)
	a.ctrl.release("mov1")
	_ok("Confusion: a button fires the move shuffled onto it and still holds it", a.action != null and a.action.id == a.data.moves[order[0]] and a.action.button == "mov1",
		"%s, wanted %s" % [a.action.id if a.action else "nothing", a.data.moves[order[0]]])
	a.confused = 0.02
	await _wait(0.1)
	_ok("Confusion: the buttons go back when it ends", a.button_moves == Fighter.BUTTONS_STRAIGHT, "%s" % [a.button_moves])
	ab = await _setup("mewtwo", "urshifu", Vector3(-2, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	_strike(a, b, "confusion")
	_ok("Confusion: a Dark type takes a little and is not confused", b.confused == 0.0 and b.hp < b.hp_max, "%.2f, HP %d/%d" % [b.confused, b.hp, b.hp_max])
	# It reaches further to the side than Disable: the same spot, off to one side.
	for move in ["confusion", "disable"]:
		ab = await _with_moves("mewtwo", move + ",psychic,shadowball,teleport", "pikachu", 2.0)
		a = ab[0]
		b = ab[1]
		b.global_position = a.global_position + a.forward() * 1.5 + a.forward().cross(Vector3.UP) * 1.9
		a.start(move, "mov1")
		a.action.faces_rival = false
		await _wait(0.6)
		var reached: bool = b.hp < b.hp_max or b.cd("thundershock") > 0.0
		_ok("%s, 1.9 m off to the side: %s" % [move, "it reaches" if move == "confusion" else "it misses"], reached == (move == "confusion"), "HP %d/%d" % [b.hp, b.hp_max])
	# Psyshock: against Defense, not Sp. Def.
	ab = await _setup("mewtwo", "goodra", Vector3(-8, 0, 0), Vector3(0, 0, 0))
	a = ab[0]
	b = ab[1]
	var shock := _formula("psyshock", a, b)
	var plain := _formula("psychic", a, b)
	_ok("Psyshock: beats Psychic against high Sp. Def", shock > plain * 1.4, "%.1f vs %.1f" % [shock, plain])
	b.stages.spd = 2
	_ok("Psyshock: a Sp. Def boost changes nothing", absf(_formula("psyshock", a, b) - shock) < 0.01, "%.1f" % _formula("psyshock", a, b))
	b.stages.spd = 0
	b.stages.def = 2
	_ok("Psyshock: a Defense boost does", _formula("psyshock", a, b) < shock * 0.6, "%.1f" % _formula("psyshock", a, b))
	b.stages.def = 0
	var target: Fighter = await _use("mewtwo", "psyshock,psychic,shadowball,teleport", "goodra", 8.0, 1.2)
	var dealt: float = target.hp_max - target.hp
	_ok("Psyshock: the shard lands for the whole formula", absf(dealt - shock) < shock * 0.15, "%.1f vs %.1f" % [dealt, shock])
	# Shadow Ball's look: a clip named after the move, on Mewtwo alone.
	_ok("Clips: Mewtwo has all six", ["shadowball", "confusion", "disable", "special", "physical", "status"].all(func(c): return main.fighters[0].model.has_anim(c)))
	ab = await _setup("gengar", "pikachu", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	_ok("Clips: Gengar's Shadow Ball keeps its own", not ab[0].model.has_anim("shadowball"))


## Presses Teleport (its fourth move) and waits until it is back on its feet.
func _teleports(a: Fighter) -> void:
	a.ctrl.press("mov4")
	await get_tree().physics_frame
	a.ctrl.release("mov4")
	var t0 := t
	while a.state == "free" and t - t0 < 0.3:
		await get_tree().physics_frame
	while a.state != "free" and t - t0 < 1.5:
		await get_tree().physics_frame


func _mewtwo_teleport() -> void:
	var ab: Array = await _setup("mewtwo", "snorlax", Vector3(-4, 0, 6), Vector3(0, 0, 8))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.locked = false
	a.ctrl.yaw = 0.0                 # the stick's forward is -Z
	var from: Vector3 = a.global_position
	await _teleports(a)
	var went: Vector3 = a.global_position - from
	_ok("Teleport: never moved, it goes where it faces", absf(went.length() - 8.0) < 0.5 and went.normalized().dot(a.forward()) > 0.95, "%.2f m" % went.length())
	a.cds.clear()
	a.ctrl.move_input = Vector2(0, 1)
	await _wait(0.25)
	from = a.global_position
	await _teleports(a)
	a.ctrl.move_input = Vector2.ZERO
	went = a.global_position - from
	_ok("Teleport: 8 m along the last movement", absf(went.length() - 8.0) < 1.2 and went.normalized().dot(Vector3.FORWARD) > 0.95, "%s" % went.snapped(Vector3.ONE * 0.01))
	a.cds.clear()
	a.ctrl.move_input = Vector2(1, 0)
	await _wait(0.2)
	a.ctrl.move_input = Vector2.ZERO
	await _wait(0.5)
	from = a.global_position
	await _teleports(a)
	went = a.global_position - from
	_ok("Teleport: the same with the stick released", absf(went.length() - 8.0) < 0.5 and went.normalized().dot(Vector3.RIGHT) > 0.95, "%s" % went.snapped(Vector3.ONE * 0.01))
	_ok("Teleport: it keeps its height", absf(went.y) < 0.05, "%.2f" % went.y)
	# A dodge counts as movement; being hit does not.
	a.cds.clear()
	a.ctrl.move_input = Vector2(-1, 0)
	a.ctrl.press("dodge")
	await _wait(0.05)
	a.ctrl.move_input = Vector2.ZERO
	await _wait(0.7)
	_ok("Teleport: a dodge counts as movement", a.last_move.dot(Vector3.LEFT) > 0.95, "%s" % a.last_move)
	# It cannot be hit while gone and the body is back when it ends, also if it is cut.
	a.cds.clear()
	a.ctrl.press("mov4")
	await get_tree().physics_frame
	a.ctrl.release("mov4")
	var t0 := t
	while not (a.action and a.action.phase == "active") and t - t0 < 0.3:
		await get_tree().physics_frame
	await _wait(0.04)
	var res := _strike(b, a, "bodyslam")
	_ok("Teleport: it cannot be hit while gone", res == "dodged" and a.hp == a.hp_max, "%s" % res)
	_ok("Teleport: the body is gone", not a.model.visible)
	await _wait(0.6)
	_ok("Teleport: the body is back when it ends", a.model.visible)
	a.cds.clear()
	a.ctrl.press("mov4")
	await get_tree().physics_frame
	a.ctrl.release("mov4")
	t0 = t
	while not (a.action and a.action.phase == "active") and t - t0 < 0.3:
		await get_tree().physics_frame
	await _wait(0.04)
	a.stun_target(0.2)
	await _wait(0.05)
	_ok("Teleport: the body is back if it is cut", a.model.visible and a.action == null)
	await _wait(0.5)
	# Confused it still goes the way it moved: only the attack buttons change.
	ab = await _setup("mewtwo", "snorlax", Vector3(-4, 0, 0), Vector3(0, 0, 8))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = 0.0
	a.confused = 5.0
	a.ctrl.move_input = Vector2(0, 1)
	await _wait(0.2)
	a.ctrl.move_input = Vector2.ZERO
	from = a.global_position
	await _teleports(a)
	went = a.global_position - from
	_ok("Teleport: confused, it still goes the way it moved", went.normalized().dot(Vector3.FORWARD) > 0.9, "%s" % went.snapped(Vector3.ONE * 0.01))
	# Walls stop it short, and it can leave a stage's edge, which no other move does.
	var stage_before: String = main.arena.stage
	ab = await _setup("mewtwo", "snorlax", Vector3(0, 0, -Arena.WIDTH * 0.5 + 3.0), Vector3(0, 0, 8))
	a = ab[0]
	a.locked = false
	a.ctrl.yaw = 0.0
	a.last_move = Vector3.FORWARD
	from = a.global_position
	await _teleports(a)
	_ok("Teleport: a wall stops it short", from.distance_to(a.global_position) < 6.0, "%.2f m, z %.2f" % [from.distance_to(a.global_position), a.global_position.z])
	main.set_stage("floating")
	ab = await _setup("mewtwo", "snorlax", Vector3(0, 0, FloatingStadium.PLAT_Z - 3.0), Vector3(0, 0, 0))
	a = ab[0]
	a.locked = false
	a.last_move = Vector3.BACK
	from = a.global_position
	await _teleports(a)
	_ok("Teleport: it can leave a stage's edge", from.distance_to(a.global_position) > 6.5 and not main.arena.inside(a.global_position), "%s to %s" % [from.snapped(Vector3.ONE * 0.01), a.global_position.snapped(Vector3.ONE * 0.01)])
	main.set_stage(stage_before)
	# Its only way to have it is being one of its four defaults.
	_ok("Teleport: offered to Mewtwo", "teleport" in Loadout.moves_for("mewtwo"))
	var others := Roster.POKEMON.keys().filter(func(sp): return sp != "mewtwo" and "teleport" in Loadout.moves_for(sp))
	_ok("Teleport: offered to nobody else", others.is_empty(), "%s" % [others])


## Calm Mind and Agility, on the script they share with Bulk Up (whose cases are Urshifu's).
func _mewtwo_boosts() -> void:
	var ab: Array = await _with_moves("mewtwo", "calmmind,agility,psychic,teleport", "snorlax", 8.0)
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.start("calmmind", "mov1")
	await _wait(0.4)
	_strike(b, a, "bodyslam")
	_ok("Calm Mind: a hit during it gives nothing", a.stages.spa == 0 and a.stages.spd == 0, "Sp. Atk %+d" % a.stages.spa)
	await _wait(1.5)
	a.cds.clear()
	a.uses.clear()
	a.energy = 100.0
	a.ctrl.press("mov1")
	await _wait(0.05)
	a.ctrl.release("mov1")
	await _wait(1.3)
	_ok("Calm Mind: +1 Sp. Atk and +1 Sp. Def", a.stages.spa == 1 and a.stages.spd == 1, "%+d, %+d" % [a.stages.spa, a.stages.spd])
	a.cds.clear()
	a.energy = 100.0
	a.ctrl.press("mov1")
	await _wait(0.05)
	a.ctrl.release("mov1")
	await _wait(1.3)
	a.cds.clear()
	a.energy = 100.0
	_ok("Calm Mind: a 3rd use is refused", not a.ready("calmmind") and a.stages.spa == 2, "uses left %d, %+d" % [a.uses.get("calmmind", -1), a.stages.spa])
	a.ctrl.press("mov2")
	await _wait(0.05)
	a.ctrl.release("mov2")
	await _wait(0.7)
	a.cds.clear()
	a.energy = 100.0
	_ok("Agility: +2 Speed, 13.6 m/s", a.stages.spe == 2 and absf(a.data.speed * a.speed_stage() - 13.6) < 0.1, "%+d, %.1f m/s" % [a.stages.spe, a.data.speed * a.speed_stage()])
	_ok("Agility: a 2nd use is refused", not a.ready("agility"), "uses left %d" % a.uses.get("agility", -1))
	for sp in ["pikachu", "scizor", "lucario"]:
		_ok("Agility: reaches %s" % sp, "agility" in Loadout.moves_for(sp))
	_ok("Calm Mind: reaches Lucario", "calmmind" in Loadout.moves_for("lucario"))


func _mewtwo_ai() -> void:
	var ab: Array = await _setup("pikachu", "mewtwo", Vector3(-6, 0, 0), Vector3(0, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	var ai: AI = main.ai
	_ok("AI: Disable while the rival has moves to lose", ai._only_if(Moves.DATA.disable.ai, {}))
	# "hold" means a held move (Action, AI._use): a number there would make the AI fail on it.
	_ok("Data: \"hold\" is only ever true", Moves.DATA.values().all(func(d): return d.get("hold", false) is bool))
	for k in a.data.moves.slice(0, 3):
		a.cds[k] = 5.0
	_ok("AI: no Disable with only one left to lose", not ai._only_if(Moves.DATA.disable.ai, {}))
	a.cds.clear()
	# It teleports the way out it chose, not the way it last walked.
	var used := false
	for i in 80:
		b.last_move = Vector3.BACK
		ai._dodge_toward(Vector3.LEFT, "thunderbolt")
		used = b.ctrl.pressed.has("mov4")
		if used:
			break
		b.ctrl.clear()
	_ok("AI: Teleport goes the way out", used and b.last_move.dot(Vector3.LEFT) > 0.99, "%s" % b.last_move)
	await _wait(0.6)
	# Where a dodge stays on a floating stage and Teleport, going further, would not: it dodges.
	var stage_before: String = main.arena.stage
	main.set_stage("floating")
	ab = await _setup("pikachu", "mewtwo", Vector3(-6, 0, 0), Vector3(FloatingStadium.PLAT_X - 8.0, 0, 0))
	b = ab[1]
	ai = main.ai
	used = false
	for i in 80:
		ai._dodge_toward(Vector3.RIGHT, "thunderbolt")
		used = used or b.ctrl.pressed.has("mov4")
		b.ctrl.clear()
	_ok("AI: no Teleport off the edge", not used)
	main.set_stage(stage_before)


# ---------------------------------------------------------------- trainers

## Trainers on both stages: the opening (throws, the Pokémon coming out), a wide shot with
## both trainers, your own from behind your Pokémon, their reactions and the end. Checks
## that they stand out of reach, that nobody moves during the opening and that both
## Pokémon are out when it ends. Rendered (not headless) for the pictures.
func _trainers_test() -> void:
	await get_tree().physics_frame
	main._args["intro"] = "1"
	for stage in ["night", "floating"]:
		main.set_stage(stage)
		main.start_battle("pikachu", "charizard", "normal")
		var a: Fighter = main.fighters[0]
		var b: Fighter = main.fighters[1]
		main.ai.mode = "still"
		a.is_player = false
		var b_start := b.global_position
		var strip: Array = []
		var times := [0.15, 0.4, 0.6, 0.8, 1.05, 1.3, 1.6, 2.1]
		var t0 := t
		for tt in times:
			await _wait(t0 + tt - t)
			if DisplayServer.get_name() != "headless":
				var im := get_viewport().get_texture().get_image()
				im.resize(im.get_width() / 2, im.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				strip.append(im)
		_ok("%s: nobody moves during the opening" % stage, b.global_position.distance_to(b_start) < 0.2, "%.2f m" % b.global_position.distance_to(b_start))
		await _wait(main.INTRO + 0.25 - (t - t0))
		_capture("trainers_%s_start" % stage)
		_ok("%s: both Pokémon are out after the opening" % stage, a.appear >= 1.0 and b.appear >= 1.0 and main.intro_t <= 0.0, "%.2f %.2f" % [a.appear, b.appear])
		var limit := 19.5 if stage == "night" else FloatingStadium.PLAT_X + 2.0
		_ok("%s: trainers stand out of reach" % stage, main.trainers.size() == 2 and main.trainers.all(func(tr): return absf(tr.global_position.x) > limit), str(main.trainers.map(func(tr): return tr.global_position.x)))
		if strip.size() == 8:
			var w: int = strip[0].get_width()
			var h: int = strip[0].get_height()
			var sheet := Image.create(w * 4, h * 2, false, strip[0].get_format())
			for i in 8:
				sheet.blit_rect(strip[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
			sheet.save_png(_dir().path_join("trainers_%s_intro.png" % stage))
		# Wide: both trainers and the field, from the side.
		main.camera.target = null
		main.camera.global_position = Vector3(0, 11, 14)
		main.camera.look_at(Vector3(0, 0, -2), Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_wide" % stage)
		# Your own trainer, seen from your Pokémon's side of the field.
		main.camera.global_position = a.global_position + Vector3(-4.0 * signf(a.global_position.x), 3.0, 4.0)
		main.camera.look_at(main.trainers[0].global_position + Vector3.UP * 1.0, Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_mine" % stage)
		# Reactions: your Pokémon hits (your trainer cheers, theirs flinches), then KOs.
		main.camera.target = a
		a.locked = true
		b.hp = 1.0
		a.ctrl.press("mov1")
		await _wait(0.1)
		a.ctrl.release("mov1")
		await _wait(2.0)
		main.camera.target = null
		main.camera.global_position = Vector3(0, 11, 14)
		main.camera.look_at(Vector3(0, 0, -2), Vector3.UP)
		await _wait(0.3)
		_capture("trainers_%s_end" % stage)
		main.camera.target = a
		Engine.time_scale = 1.0
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


# ---------------------------------------------------------------- League stadium

## The League stadium: pictures (wide, from behind the player, the field closing in) and
## the closing field's rules: its radius over time, damage outside and none inside.
func _league_test() -> void:
	await get_tree().physics_frame
	var stage_id := "league"
	main.set_stage(stage_id)
	main.start_battle("pikachu", "charizard", "normal")
	var a: Fighter = main.fighters[0]
	var b: Fighter = main.fighters[1]
	main.ai.mode = "still"
	a.is_player = false
	var st: LeagueStadium = main.arena
	_ok("Field radius over time", is_equal_approx(LeagueStadium.radius_at(0.0), 16.0) and is_equal_approx(LeagueStadium.radius_at(40.0), 12.5)
		and is_equal_approx(LeagueStadium.radius_at(300.0), 5.0) and LeagueStadium.radius_at(32.5) < 16.0 and LeagueStadium.radius_at(32.5) > 12.5,
		"%.1f %.1f %.1f" % [LeagueStadium.radius_at(0.0), LeagueStadium.radius_at(32.5), LeagueStadium.radius_at(40.0)])
	await _wait(1.0)
	_capture(stage_id + "_battle")
	main.camera.target = null
	main.camera.global_position = Vector3(-13.0, 10.0, 13.0)
	main.camera.look_at(Vector3(3.0, 2.0, -8.0), Vector3.UP)
	await _wait(0.5)
	_capture(stage_id + "_wide")
	main.camera.global_position = Vector3(0.0, 4.0, 14.0)
	main.camera.look_at(Vector3(0.0, 10.0, -26.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_statues")
	main.camera.global_position = Vector3(-6.0, 9.0, 8.0)
	main.camera.look_at(Vector3(-24.0, 13.0, 12.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_sails")
	main.camera.global_position = Vector3(0.0, 16.0, 26.0)
	main.camera.look_at(Vector3(0.0, 4.0, -10.0), Vector3.UP)
	await _wait(0.4)
	_capture(stage_id + "_canopy")
	# The next ring announced, then closing.
	st.zone_t = 27.5
	main.camera.global_position = Vector3(-13.0, 10.0, 13.0)
	main.camera.look_at(Vector3(2.0, 0.0, -2.0), Vector3.UP)
	await _wait(0.6)
	_capture(stage_id + "_warning")
	st.zone_t = 33.0
	await _wait(0.6)
	_capture(stage_id + "_closing")
	st.zone_t = 60.0
	await _wait(0.3)
	# The wall: whoever is past it is put back inside, with no damage.
	a.global_position = Vector3(0.0, 0.0, 3.0)
	b.global_position = Vector3(14.0, 0.0, 0.0)
	var hb := b.hp
	await _wait(0.5)
	var rb := Vector2(b.global_position.x, b.global_position.z).length()
	_ok("The wall keeps it inside", rb <= st.zone_r + 0.05, "%.2f m, ring %.2f m" % [rb, st.zone_r])
	_ok("The wall does no damage", b.hp == hb, "%d -> %d" % [hb, b.hp])
	# After the final blow the field stops closing.
	var frozen := st.zone_t
	st._win_t = 0.0
	await _wait(0.5)
	_ok("The field stops closing after the battle", is_equal_approx(st.zone_t, frozen), "%.2f -> %.2f" % [frozen, st.zone_t])
	st._win_t = -1.0
	_capture(stage_id + "_outside")
	# Playing near the closed edge: the camera behind you, out past the aurora.
	main.camera.target = a
	a.locked = true
	a.global_position = Vector3(0.0, 0.0, 7.5)
	b.global_position = Vector3(0.0, 0.0, -3.0)
	await _wait(1.2)
	_capture(stage_id + "_camera_out")
	main.camera.target = null
	main.camera.global_position = Vector3(0.0, 2.2, 15.5)
	main.camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _wait(0.3)
	_capture(stage_id + "_aurora")
	main.camera.target = a
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


# ---------------------------------------------------------------- 3 vs 3

func _team_battle(lead_a: String, team_a: String, lead_b: String, team_b: String, gap := 6.0) -> Array:
	main.menu.choice.format = "3v3"
	main.menu.choice.team = Array(team_a.split(","))
	main.menu.choice.team2 = Array(team_b.split(","))
	return await _setup(lead_a, lead_b, Vector3(-gap, 0, 0), Vector3(gap, 0, 0))


## A hit from "by" on "to", straight into combat.
func _team_hit(by: Fighter, to: Fighter, strength := 1) -> String:
	var g := Hit.new()
	g.user = by
	g.local = false
	g.move_id = "thundershock"
	g.type = "electric"
	g.cat = "special"
	g.strength = strength
	g.damage = 52.0
	return main.combat.apply(g, to, to.center())


## A plain shot of "by"'s, for what happens to shots in flight.
func _team_shot(by: Fighter, pos: Vector3, velocity: Vector3, life: float, target: Node3D) -> Dictionary:
	var g := Hit.new()
	g.user = by
	g.move_id = "shadowball"
	g.type = "ghost"
	g.cat = "special"
	g.damage = 50.0
	var node := Node3D.new()
	main.add_child(node)
	return main.combat.projectile({"user": by, "pos": pos, "velocity": velocity, "radius": 0.3, "lifetime": life, "hit": g, "node": node, "track": 0.0, "target": target})


## Presses switch "slot" and waits until the switch is over; the seconds it took.
func _team_switch(p: Party, slot: int) -> float:
	var out: Fighter = p.active
	var t0 := t
	out.ctrl.press("switch%d" % (slot + 1))
	while p.active == out and t - t0 < 4.0:
		await get_tree().physics_frame
	return t - t0


func _team_faint_and_wait(p: Party) -> Fighter:
	var out: Fighter = p.active
	out._damage_direct(999999.0)
	var t0 := t
	while p.active == out and t - t0 < 7.0:
		await get_tree().physics_frame
	return p.active


func _team_test() -> void:
	await get_tree().physics_frame
	var R: Dictionary = BattleRules.defaults()
	var ab: Array = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	var pa: Party = main.parties[0]
	var luc: Fighter = pa.members[1]
	var ven: Fighter = pa.members[2]
	_ok("Each side has its three, in order", pa.members.map(func(f): return f.species) == ["charizard", "lucario", "venusaur"]
		and main.parties[1].members[1].species == "gengar")
	_ok("Only two are on the field", main.fighters == [a, b] and main.combat.targets.size() == 2)
	_ok("The bench does not run or show", luc.process_mode == Node.PROCESS_MODE_DISABLED and not luc.visible)
	_ok("Starts with one switch", pa.charges == int(R.start_charges))

	# The switch itself.
	a.energy = 37.0
	a.cds["dragonclaw"] = 3.0
	a.boost("atk", 2)
	a.hp = 500.0
	a.inflict("psn")
	var took: float = await _team_switch(pa, 0)
	_ok("A switch takes as long as designed", pa.active == luc and took >= R.recall + R.ball_near and took <= R.recall + R.ball_far + 0.1, "%.2f s" % took)
	_ok("Spends the charge", pa.charges == 0)
	_ok("Everyone points at the new one", main.fighters[0] == luc and b.rival == luc and luc.rival == b and main.ai.rival == luc and main.camera.target == luc and main.trainers[0].fighter == luc)
	_ok("Only the new one can be hit", luc in main.combat.targets and not a in main.combat.targets)
	_ok("Energy goes with the team", luc.energy >= 37.0 and luc.energy < 55.0, "%.1f" % luc.energy)
	_ok("Lands where the other one stood", luc.global_position.distance_to(a.global_position) < 0.5)
	_ok("A moment before it can act, without invulnerability", luc.state == "enter" and luc.invulnerable <= 0.0, luc.state)
	_ok("Stat stages are lost on leaving", a.stages.atk == 0)

	# On the bench nothing changes.
	var hp0: float = a.hp
	var cd0: float = a.cd("dragonclaw")
	var st0: float = a.status_t
	await _wait(1.5)
	_ok("On the bench HP, cooldowns and status wait", a.hp == hp0 and a.cd("dragonclaw") == cd0 and a.status_t == st0 and a.status == "psn" and cd0 > 0.0,
		"hp %.0f cd %.2f status %s %.2f" % [a.hp, cd0, a.status, st0])

	# Cost and lockout.
	_ok("No charge, no switch", not pa.can_switch(1))
	luc.ctrl.press("switch2")
	await _wait(0.1)
	_ok("Pressing without a charge does nothing", luc.state == "free" and pa.active == luc, luc.state)
	pa._recharge = 0.1
	await _wait(0.2)
	_ok("Charges come back with time", pa.charges == 1 and pa._recharge > R.recharge - 1.0, "%d, %.1f" % [pa.charges, pa._recharge])
	var waited: float = pa._recharge
	_ok("A landed hit shortens the wait", _team_hit(luc, b) == "hit" and pa._recharge <= waited - R.hit_bonus + 0.001, "%.2f -> %.2f" % [waited, pa._recharge])
	_ok("The one that left is locked out", pa.slot_member(0) == a and pa.locked_for(a) > 0.0 and not pa.can_switch(0), "%.1f s" % pa.locked_for(a))
	await _wait(0.5)
	_ok("The other one can come", pa.can_switch(1))
	pa.lockout[a] = 0.05
	await _wait(0.2)
	_ok("The lockout ends", pa.can_switch(0))

	# Teammates and shots in flight.
	_ok("Shots of the one that left spare its team", main.combat.spares(a, luc) and main.combat.spares(luc, a) and not main.combat.spares(a, b))
	var hp1: float = luc.hp
	_team_shot(a, luc.center() + Vector3(2.0, 0, 0), Vector3(-10.0, 0, 0), 0.5, null)
	await _wait(0.4)
	_ok("Passes through its teammate", luc.hp == hp1, "%.0f -> %.0f" % [hp1, luc.hp])
	var shot: Dictionary = _team_shot(b, b.center() + Vector3(0, 6.0, 0), Vector3(0, 0.1, 0), 3.0, luc)
	var took2: float = await _team_switch(pa, 1)
	_ok("Shots in flight turn to the new one", pa.active == ven and shot.target == ven, "%.2f s" % took2)

	# Hits cut it; the charge stays spent.
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	b = ab[1]
	pa = main.parties[0]
	a.ctrl.press("switch1")
	await _wait(0.1)
	_ok("Recalling, it can be hit", a.state == "recall" and a.hittable() and a.invulnerable <= 0.0, a.state)
	var res: String = _team_hit(b, a)
	_ok("A hit cuts it", res == "hit" and a.state in ["stunned", "knocked_down"] and pa.pending == null and pa.active == a and pa.cut == 1, "%s %s" % [res, a.state])
	_ok("The charge stays spent", pa.charges == 0)
	await _wait(1.3)
	_ok("Nobody comes out afterwards", main.fighters[0] == a and a.appear_glow == 0.0)
	# The Pokémon's poise holds against light hits, as with a move.
	ab = await _team_battle("blastoise", "blastoise,lucario,venusaur", "garchomp", "garchomp,gengar,charizard")
	a = ab[0]
	b = ab[1]
	pa = main.parties[0]
	a.ctrl.press("switch1")
	await _wait(0.1)
	_ok("A heavy Pokémon holds against a light hit", _team_hit(b, a, 0) == "armor" and a.state == "recall", a.state)
	_ok("Not against a medium one", _team_hit(b, a, 1) == "hit" and a.state != "recall", a.state)
	# Nothing to do but dodge while stunned: a switch does not get you out.
	a.ctrl.press("switch1")
	await _wait(0.03)
	_ok("Stunned, no switch", a.state != "recall" and pa.pending == null, a.state)

	# After a KO.
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	b = ab[1]
	pa = main.parties[0]
	a.energy = 20.0
	b.boost("atk", 2)
	var charges0: int = pa.charges
	a._damage_direct(999999.0)
	_ok("A KO does not end the battle", main._end_t < 0.0 and pa.replacing)
	var t0 := t
	while pa.active == a and t - t0 < 6.0:
		await get_tree().physics_frame
	var next: Fighter = pa.active
	_ok("Someone comes out by itself", next != a and next.state != "ko" and main.fighters[0] == next and t - t0 <= R.ko_choice + Party.KO_FLIGHT + 0.1, "%s in %.2f s" % [next.species, t - t0])
	_ok("Lands on its side, safe for a moment", next.global_position.distance_to(next.start_pos) < 0.5 and next.invulnerable > 0.5, "%.2f" % next.invulnerable)
	_ok("The team gets energy", next.energy >= 50.0 and next.energy < 80.0, "%.1f" % next.energy)
	_ok("It costs no switch", pa.charges == charges0)
	_ok("The one that made the KO loses its stages", b.stages.atk == 0)
	await _wait(1.2)
	_ok("Then it is free and can be hit", next.state == "free" and next.invulnerable <= 0.0, next.state)

	# The player picks the next one; with no answer, the healthiest.
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	pa = main.parties[0]
	a.is_player = true
	main._no_input = 0.0
	a._damage_direct(999999.0)
	await _wait(0.2)
	Input.action_press("switch2")
	await _wait(0.1)
	Input.action_release("switch2")
	t0 = t
	while pa.active == a and t - t0 < 6.0:
		await get_tree().physics_frame
	_ok("The player picks", pa.active.species == "venusaur" and pa.active.is_player and not a.is_player, pa.active.species)
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	pa = main.parties[0]
	a.is_player = true
	pa.members[1].hp = 10.0
	t0 = t
	a._damage_direct(999999.0)
	while pa.active == a and t - t0 < 6.0:
		await get_tree().physics_frame
	_ok("Out of time, the healthiest", pa.active.species == "venusaur" and t - t0 >= R.ko_choice, "%s in %.2f s" % [pa.active.species, t - t0])
	pa.active.is_player = false

	# To the last one, then a rematch.
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	b = ab[1]
	pa = main.parties[0]
	await _team_faint_and_wait(pa)
	_ok("Two down: still on", main._end_t < 0.0)
	await _team_faint_and_wait(pa)
	_ok("One left: still on", main._end_t < 0.0 and pa.alive_count() == 1)
	pa.active._damage_direct(999999.0)
	_ok("All three down: the battle ends", main._end_t >= 0.0, "%.2f" % main._end_t)
	_ok("No switching once it is over", not main.parties[1].can_switch(0))
	main.rematch()
	await _wait(0.2)
	_ok("A rematch brings back the lead, everyone whole", main.fighters[0] == a and pa.active == a and pa.alive_count() == 3 and pa.members.all(func(f): return f.hp == f.hp_max) and a.process_mode == Node.PROCESS_MODE_INHERIT and a.visible and not pa.members[1].visible and pa.charges == int(R.start_charges) and b.rival == a and main.combat.targets.has(a))
	var took3: float = await _team_switch(pa, 0)
	_ok("And it can switch again", pa.active == pa.members[1], "%.2f s" % took3)

	# A stage with a void.
	main.set_stage("floating")
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	pa = main.parties[0]
	_ok("Over the platform, it can switch", pa.can_switch(0))
	a.global_position = Vector3(60.0, -1.0, 0.0)
	_ok("Over the pit, it cannot", not pa.can_switch(0))
	_ok("Nobody lands over the pit", main.arena.inside(pa._entry_spot(Vector3(60.0, 0.0, 0.0)), 0.5))
	a.global_position = Vector3(-6.0, 0.0, 0.0)

	# The League's field closes slower.
	main.set_stage("league")
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	var st: LeagueStadium = main.arena
	st.zone_t = 0.0
	await _wait(1.0)
	if DisplayServer.get_name() == "headless":
		_ok("The League's clock goes slower in 3 vs 3", main.field_pace == R.field_pace)
	else:
		_ok("The League's clock goes slower in 3 vs 3", main.field_pace == R.field_pace and st.zone_t < 0.6, "%.2f" % st.zone_t)
	main.set_stage("night")

	# The AI against a bad matchup.
	ab = await _team_battle("pikachu", "pikachu,charizard,blastoise", "garchomp", "garchomp,gengar,scizor", 9.0)
	var pp: Party = main.parties[0]
	var rival_ai := AI.new()
	rival_ai.main = main
	rival_ai.me = ab[0]
	rival_ai.rival = ab[1]
	rival_ai.difficulty = "hard"
	rival_ai.process_physics_priority = -10
	main.add_child(rival_ai)
	main.player_ai = rival_ai
	pp.charges = 2
	var t1 := t
	while pp.switches == 0 and t - t1 < 25.0:
		await get_tree().physics_frame
	_ok("The AI gets out of a bad matchup", pp.switches > 0, "%.1f s" % (t - t1))
	main.player_ai = null
	rival_ai.queue_free()

	# The rules are this battle's.
	var parsed: Dictionary = BattleRules.parsed("recall:0.1,lockout:999,nonsense:3,landing:x")
	_ok("--rules takes what it knows, within limits", parsed.recall == 0.1 and parsed.lockout == 30.0 and parsed.landing == R.landing and not parsed.has("nonsense"))
	_ok("Steps stay within limits", BattleRules.stepped("bench_heal", 0.0, -1) == 0.0 and BattleRules.stepped("bench_heal", 0.0, 1) == 0.25 and is_equal_approx(BattleRules.stepped("recall", 0.5, 1), 0.55))
	_ok("Values read well", BattleRules.text("bench_heal", 0.0) == "Off" and BattleRules.text("bench_heal", 0.5) == "0.5 %/s" and BattleRules.text("recall", 0.5) == "0.5 s" and BattleRules.text("max_charges", 2) == "2",
		"%s, %s, %s, %s" % [BattleRules.text("bench_heal", 0.0), BattleRules.text("bench_heal", 0.5), BattleRules.text("recall", 0.5), BattleRules.text("max_charges", 2)])
	_ok("Healing on the bench is off by default", R.bench_heal == 0.0)
	main.menu.choice.rules = BattleRules.parsed("recall:0.2,ball_near:0.1,ball_far:0.1,landing:0.5,lockout:0,start_charges:3,max_charges:4,recharge:5,hit_bonus:0,ko_energy:0,ko_invuln:0,field_pace:4,bench_heal:2")
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	b = ab[1]
	pa = main.parties[0]
	_ok("A battle starts by its rules", pa.charges == 3 and pa.max_charges() == 4 and main.field_pace == 4.0)
	var quick: float = await _team_switch(pa, 0)
	_ok("The switch takes the time asked for", quick <= 0.35, "%.2f s" % quick)
	_ok("So does the landing", pa.active.state == "enter", pa.active.state)
	await _wait(0.35)
	_ok("Still landing after the old time", pa.active.state == "enter", pa.active.state)
	await _wait(0.25)
	_ok("Then it is free", pa.active.state == "free", pa.active.state)
	_ok("No lockout: the one that left can come back", pa.locked_for(a) == 0.0 and pa.can_switch(0))
	var r0: float = pa._recharge
	_team_hit(pa.active, b)
	_ok("No time off per hit when set to none", pa._recharge <= r0 and pa._recharge > r0 - 0.1, "%.2f -> %.2f" % [r0, pa._recharge])
	# Bench healing: 2% a second here. Not over the top, not the one out, not the fainted.
	var ven2: Fighter = pa.members[2]
	a.hp = 100.0
	ven2.hp = ven2.hp_max - 1.0
	var out_hp: float = pa.active.hp
	var t2 := t
	await _wait(2.0)
	var healed: float = (a.hp - 100.0) / a.hp_max * 100.0 / (t - t2)
	_ok("The bench heals at the rate asked for", healed > 1.8 and healed < 2.2, "%.2f %%/s" % healed)
	_ok("Not past its max HP", ven2.hp == ven2.hp_max)
	_ok("The one out does not heal", pa.active.hp <= out_hp)
	ven2._damage_direct(999999.0)
	await _wait(0.2)
	_ok("Fainted on the bench: no replacement, no healing", ven2.hp == 0.0 and ven2.state == "ko" and not pa.replacing, "%.1f" % ven2.hp)
	main.rematch()
	await _wait(0.1)
	_ok("A rematch keeps the rules", pa.charges == 3 and main.field_pace == 4.0 and pa.rules.bench_heal == 2.0)
	# They belong to the battle that took them.
	main.menu.choice.rules.recall = 1.0
	_ok("The menu changing them does not touch a battle under way", pa.rules.recall == 0.2)
	main.menu.choice.rules = BattleRules.defaults()
	# Teams from the menu.
	main.menu.choice.team = ["lucario", "lucario", "nobody", "venusaur"]
	_ok("A team has no repeats and nobody unknown", main.menu.team_ids(0, "charizard") == ["charizard", "lucario", "venusaur"])
	main.menu.choice.team = ["charizard"]
	_ok("Picking the lead as a teammate does not repeat it", main.menu.team_ids(0, "charizard").count("charizard") == 1 and main.menu.team_ids(0, "charizard").size() == 3)
	# Rules from the other player.
	var from_net: Dictionary = BattleRules.sanitized({"recall": 99.0, "lockout": "x", "other": 1, "bench_heal": 2.0})
	_ok("Rules from the network stay within limits", from_net.recall == 1.5 and from_net.lockout == R.lockout and from_net.bench_heal == 2.0 and not from_net.has("other"))
	_ok("And nonsense gives the defaults", BattleRules.sanitized("nonsense") == R)
	# The rival's copy of a team follows what its owner says, and does nothing by itself.
	main.menu.choice.format = "3v3"
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	a = ab[0]
	b = ab[1]
	var pr: Party = main.parties[1]
	pr.remote = true
	var gengar: Fighter = pr.members[1]
	var blast: Fighter = pr.members[2]
	pr.net_event({"t": "recall", "to": "gengar", "total": 0.2})
	_ok("The copy recalls when told", b.state == "recall" and pr.pending == gengar, b.state)
	await _wait(0.5)
	_ok("And waits for its owner, however long", pr.active == b and b.state == "recall" and pr.pending == gengar, b.state)
	pr.net_recall_cut()
	_ok("A cut on the owner's side cuts it here", b.state == "free" and pr.pending == null and pr.cut == 1, b.state)
	pr.net_recall("gengar", 0.2)
	gengar.hp = 300.0
	pr.net_swap({"to": "gengar", "pos": Vector3(3, 0, 1), "yaw": 1.0, "hp": 123.0, "out_hp": 456.0, "out_status": "psn", "out_status_t": 5.0})
	_ok("The switch comes with what the bench kept", pr.active == gengar and main.fighters[1] == gengar and gengar.hp == 123.0 and b.hp == 456.0 and b.status == "psn" and b.status_t == 5.0 and gengar.state == "enter" and gengar.global_position.distance_to(Vector3(3, 0, 1)) < 0.5 and a.rival == gengar,
		"%s %.0f %.0f" % [pr.active.species, gengar.hp, b.hp])
	_ok("And its lockout", pr.locked_for(b) > 0.0)
	pr.net_charges(1, 0.5)
	_ok("Its charges come from its owner", pr.charges == 1 and is_equal_approx(pr.recharge_share(), 0.5))
	await _wait(0.3)
	_ok("Which it does not recharge by itself", pr.charges == 1 and is_equal_approx(pr.recharge_share(), 0.5), "%.2f" % pr.recharge_share())
	pr.net_recall("nobody", 0.2)
	pr.net_swap({"to": "nobody"})
	_ok("It ignores a member it does not have", pr.active == gengar and pr.pending == null)
	a.boost("atk", 2)
	gengar._damage_direct(999999.0)
	_ok("A faint does not make it pick by itself", pr.replacing and pr.active == gengar and main._end_t < 0.0)
	await _wait(pr.AI_PICK + 1.5)
	_ok("It waits for its owner's pick", pr.active == gengar and pr.replacing)
	pr.net_replace({"to": "blastoise", "pos": Vector3(6, 0, 0), "yaw": 0.0, "hp": 200.0})
	_ok("The pick comes with its KO rules", pr.active == blast and blast.hp == 200.0 and blast.invulnerable > 0.0 and not pr.replacing and a.stages.atk == 0, "%s" % pr.active.species)
	pr.net_bench_ko("garchomp")
	_ok("A faint on the bench reaches the copy", b.state == "ko" and pr.alive_count() == 1 and main._end_t < 0.0)
	pr.remote = false
	# A pick that overtakes the faint: the copy faints it first.
	ab = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	b = ab[1]
	pr = main.parties[1]
	pr.remote = true
	pr.net_replace({"to": "gengar", "pos": Vector3(6, 0, 0), "yaw": 0.0, "hp": 200.0})
	_ok("A pick that overtakes the faint", b.state == "ko" and pr.active.species == "gengar" and not pr.replacing and main.fighters[1].species == "gengar")
	pr.remote = false
	main.menu.choice.rules = BattleRules.defaults()

	# Picking on the wall, as the selection does.
	var mn: Menu = main.menu
	mn.choice.format = "3v3"
	mn.choice.team = []
	mn.choice.team2 = []
	mn.sel_phase = "p1"
	mn._team_pick("charizard")
	mn._team_pick("lucario")
	mn._team_pick("lucario")
	_ok("Pressing a pick again takes it out", mn.choice.team == ["charizard"] and mn.sel_phase == "p1", str(mn.choice.team))
	mn._team_pick("lucario")
	mn._team_pick("venusaur")
	_ok("The third pick moves on to the rival, first pick leading", mn.sel_phase == "p2" and mn.choice.p1 == "charizard")
	mn._team_pick("garchomp")
	mn._team_back()
	_ok("Back takes out the last pick", mn.choice.team2.is_empty() and mn.team_preview == "garchomp")
	mn._team_back()
	_ok("Back from an empty team, to the one before", mn.sel_phase == "p1" and mn.choice.team == ["charizard", "lucario"] and mn.team_preview == "venusaur")
	mn._team_pick("venusaur")
	for sp in ["garchomp", "gengar", "blastoise"]:
		mn._team_pick(sp)
	_ok("The rival's third pick goes to the battle's options", mn.sel_phase == "setup" and mn.choice.p2 == "garchomp")
	_ok("A 3 vs 3 has its Rules tab", "rules" in mn.setup_items())
	_ok("The Rules screen only has rules", not mn.rules_items().any(func(it): return it.id == "format" or it.id.begins_with("mate_")))
	mn._remove_pick(0, 0)
	_ok("A click only takes out a pick while that side is picking", mn.choice.team.size() == 3)
	mn.sel_phase = "p1"
	mn._go("selection")
	_ok("Back from a battle both teams stay, on the battle's options", mn.sel_phase == "setup" and mn.choice.team.size() == 3)
	mn.choice.format = "1v1"
	_ok("A 1 vs 1 has no Rules tab", not "rules" in mn.setup_items())
	mn.choice.team = []
	mn.choice.team2 = []
	mn.sel_phase = "p1"

	# And a 1 vs 1 is as it was.
	main.menu.choice.format = "1v1"
	ab = await _setup("charizard", "garchomp", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	a.ctrl.press("switch1")
	await _wait(0.1)
	_ok("In a 1 vs 1 nothing changes", main.parties.is_empty() and a.party == null and a.state == "free" and main.field_pace == 1.0, a.state)
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()


## What the Rules screen's choices (the menu_rules test) gave the battle.
func _rules_outcome() -> void:
	var p: Party = main.parties[0] if not main.parties.is_empty() else null
	print("%s  The menu started a 3 vs 3" % ("OK   " if p else "FAIL "))
	if p:
		var team: Array = p.members.map(func(f): return f.species)
		var rival: Array = main.parties[1].members.map(func(f): return f.species)
		print("%s  Your team by mouse, one taken out  %s" % ["OK   " if team == ["pikachu", "lucario", "gengar"] else "FAIL ", team])
		print("%s  The rival's by keys  %s" % ["OK   " if rival == ["snorlax", "charizard", "blastoise"] else "FAIL ", rival])
		print("%s  A rule by mouse and keys  %s" % ["OK   " if BattleRules.changed(p.rules) == {"bench_heal": 0.75} else "FAIL ", BattleRules.changed(p.rules)])
		print("%s  The leads are the first picks" % ("OK   " if main.fighters[0].species == "pikachu" and main.fighters[1].species == "snorlax" else "FAIL "))


## With a window: the HUD of a 3 vs 3, a recall, the one coming in and the pick after a KO, and
## the longest frame around a switch (it builds a portrait).
func _team_shots() -> void:
	await get_tree().physics_frame
	var ab: Array = await _team_battle("charizard", "charizard,lucario,venusaur", "garchomp", "garchomp,gengar,blastoise")
	var a: Fighter = ab[0]
	var pa: Party = main.parties[0]
	a.is_player = true
	main._no_input = 0.0
	await _wait(0.5)
	_capture("team_hud")
	a.ctrl.press("switch1")
	await _wait(0.45)
	_capture("team_recall")
	var t0 := t
	while pa.active == a and t - t0 < 2.0:
		await get_tree().process_frame
	await _wait(0.12)
	_capture("team_coming_in")
	await _wait(0.8)
	_capture("team_after_switch")
	# Measured without captures, which take longer than any frame.
	await _wait(0.5)
	pa.charges = 2
	var baseline := 0.0
	t0 = t
	while t - t0 < 1.0:
		await get_tree().process_frame
		baseline = maxf(baseline, get_process_delta_time())
	var longest := 0.0
	pa.active.ctrl.press("switch2")
	t0 = t
	while t - t0 < 1.5:
		await get_tree().process_frame
		longest = maxf(longest, get_process_delta_time())
	print("longest frame: %.1f ms standing, %.1f ms around a switch" % [baseline * 1000.0, longest * 1000.0])
	pa.active._damage_direct(999999.0)
	await _wait(0.6)
	_capture("team_pick_next")
	await _wait(3.5)
	_capture("team_next_out")
	pa.active.is_player = false
	get_tree().quit()


## Random teams, AI against AI: the numbers the design aims at. Without the window, --speed
## runs it faster than real time.
func _team_battles() -> void:
	await get_tree().physics_frame
	var total := int(main._args.get("battles", "10"))
	var speed := float(main._args.get("speed", "1"))
	var diff: String = main._args.get("diff", "normal")
	var rows: Array = []
	var wins_by_species := {}
	var games_by_species := {}
	for n in total:
		seed(1000 + n)
		var names: Array = Roster.POKEMON.keys()
		names.shuffle()
		main.menu.choice.format = "3v3"
		main.menu.choice.team = names.slice(0, 3)
		main.menu.choice.team2 = names.slice(3, 6)
		main.start_battle(names[0], names[3], diff)
		# More ticks a second, not longer ones: time_scale alone would stretch each physics step
		# and the battle would no longer be the one played at 60 Hz.
		Engine.physics_ticks_per_second = roundi(60.0 * speed)
		Engine.max_physics_steps_per_frame = maxi(8, roundi(8.0 * speed))
		Engine.time_scale = speed
		await get_tree().physics_frame
		if n == 0:
			print("physics step: %.1f ms of battle" % (get_physics_process_delta_time() * 1000.0))
		var t0 := t
		while main._end_t < 0.0 and t - t0 < 900.0:
			await get_tree().physics_frame
		var p0: Party = main.parties[0]
		var p1: Party = main.parties[1]
		var left := [p0.alive_count(), p1.alive_count()]
		var row := {"t": t - t0, "sw": p0.switches + p1.switches, "cut": p0.cut + p1.cut, "kos": 6 - left[0] - left[1], "left": left, "done": main._end_t >= 0.0}
		rows.append(row)
		for k in 2:
			var won: bool = left[k] > 0 and left[1 - k] == 0
			for sp in names.slice(k * 3, k * 3 + 3):
				games_by_species[sp] = int(games_by_species.get(sp, 0)) + 1
				wins_by_species[sp] = int(wins_by_species.get(sp, 0)) + (1 if won else 0)
		print("battle %d: %s vs %s  %.0f s  switches %d (cut %d)  KOs %d  left %d-%d%s" % [n + 1, names.slice(0, 3), names.slice(3, 6), row.t, row.sw, row.cut, row.kos, left[0], left[1], "" if row.done else "  UNFINISHED"])
	var sum_t := 0.0
	var sum_sw := 0
	var sum_cut := 0
	var sum_ko := 0
	var unfinished := 0
	for r in rows:
		sum_t += r.t
		sum_sw += r.sw
		sum_cut += r.cut
		sum_ko += r.kos
		unfinished += 0 if r.done else 1
	print("SUMMARY: %d battles, mean %.0f s (min %.0f, max %.0f), %.1f KOs, %.1f switches each (a switch every %.0f s), %.0f%% of switches cut, %d unfinished" % [total, sum_t / total,
		rows.map(func(r): return r.t).min(), rows.map(func(r): return r.t).max(), float(sum_ko) / total, float(sum_sw) / total, sum_t / maxf(sum_sw, 1), 100.0 * sum_cut / maxf(sum_sw, 1), unfinished])
	var by := wins_by_species.keys()
	by.sort_custom(func(x, y): return float(wins_by_species[x]) / games_by_species[x] > float(wins_by_species[y]) / games_by_species[y])
	print("WINS: ", ", ".join(by.map(func(sp): return "%s %d/%d" % [sp, wins_by_species[sp], games_by_species[sp]])))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	get_tree().quit()


# ---------------------------------------------------------------- lock-on and free aim

## Substitute locks the rival on the doll; a flick switches to the real one and back; when
## the doll goes, the camera is free. Free, a shot leaves where the camera looks and still
## follows its target. Locking on picks what the camera looks at.
func _hud_test() -> void:
	await get_tree().physics_frame
	var ab: Array = await _setup("pikachu", "snorlax", Vector3(-5, 0, 0), Vector3(5, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	# Showdown's words and multipliers, in its order, and nothing for a stat left alone.
	_ok("No tags without changes", main.hud.stage_tags(a).is_empty())
	var raised := [["1.5× Atk", true], ["0.67× Def", false], ["2× SpA", true], ["0.25× SpD", false], ["4× Spe", true]]
	a.boost("spe", 6)
	a.boost("atk", 1)
	a.boost("spd", -6)
	a.boost("def", -1)
	a.boost("spa", 2)
	_ok("A tag per changed stat", main.hud.stage_tags(a) == raised, str(main.hud.stage_tags(a)))
	# Free aim on the rival: the crosshair lands on the rival. Locked on, there is an arrow.
	a.is_player = true
	main._no_input = 0.0
	a.locked = false
	var toward: Vector3 = b.global_position - a.global_position
	main.camera.yaw = atan2(-toward.x, -toward.z)
	main.camera.pitch = -0.2
	await _wait(0.8)
	# The crosshair is an option, off unless turned on.
	_ok("The crosshair starts off", not main.options.crosshair)
	_capture("hud_crosshair_off")
	var row: Array = main.options.items().filter(func(it): return it.id == "crosshair")
	_ok("The Options screen has it, as a toggle", row.size() == 1 and row[0].kind == "toggle" and row[0].value == tr("Off"), str(row))
	main.options._change("crosshair", 1)
	_ok("Changing the option turns it on", main.options.crosshair)
	await _wait(0.1)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	var on_rival: Vector2 = cam.unproject_position(b.center()) / main.hud._s
	var cross: Vector2 = main.hud.crosshair_at(a)
	_ok("Aimed at the rival, the crosshair is on it", absf(cross.x - on_rival.x) < 16.0 and absf(cross.y - on_rival.y) < 30.0,
		"crosshair %s, rival %s" % [cross, on_rival])
	_capture("hud_free_aim")
	main.camera.yaw += 0.5
	await _wait(0.5)
	_capture("hud_free_aim_off_target")
	# Looking steeply down it stays on screen.
	main.camera.pitch = -1.1
	await _wait(0.5)
	cross = main.hud.crosshair_at(a)
	_ok("With the camera steeply down it stays on screen", cross.y >= 30.0 and cross.y < main.get_viewport().get_visible_rect().size.y / main.hud._s, str(cross))
	_capture("hud_camera_down")
	main.camera.pitch = -0.2
	a.locked = true
	a.inflict("brn")
	b.boost("atk", 2)
	b.boost("spe", -1)
	b.inflict("par")
	await _wait(0.5)
	_capture("hud_locked_tags_status")
	a.clear_stages()
	_ok("Stages gone, tags gone", main.hud.stage_tags(a).is_empty())
	a.is_player = false
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit(1 if fails > 0 else 0)


func _lockon_test() -> void:
	await get_tree().physics_frame
	var ab: Array = await _setup("pikachu", "gengar", Vector3(-5, 0, 0), Vector3(3, 0, 0))
	var a: Fighter = ab[0]
	var b: Fighter = ab[1]
	a.locked = true
	a.ctrl.yaw = atan2(-(b.global_position - a.global_position).x, -(b.global_position - a.global_position).z)
	b.ctrl.press("mov4")
	await _wait(0.1)
	b.ctrl.release("mov4")
	await _wait(0.5)
	var decoy: Node3D = a.aim_target()
	_ok("Substitute locks the rival on its doll", decoy is Decoy, str(decoy))
	a.switch_target(1)
	var after_right: Node3D = a.aim_target()
	a.switch_target(-1)
	var after_left: Node3D = a.aim_target()
	_ok("A flick switches between the doll and the real one", (after_right == b) != (after_left == b) or after_right == b or after_left == b,
		"right %s, left %s" % [after_right, after_left])
	# Back on the doll, then it goes: the camera is free.
	if a.aim_target() == b:
		a.switch_target(1)
		if a.aim_target() == b:
			a.switch_target(-1)
	if is_instance_valid(decoy):
		decoy.undo()
	await _wait(0.2)
	_ok("When the doll goes, the lock goes", not a.locked, "locked %s" % a.locked)
	# Free aim: looking 90 degrees off the rival, the shot leaves where the camera looks.
	ab = await _setup("pikachu", "snorlax", Vector3(-5, 0, 0), Vector3(3, 0, 0))
	a = ab[0]
	b = ab[1]
	a.locked = false
	var toward: Vector3 = (b.global_position - a.global_position).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	a.ctrl.yaw = atan2(-side.x, -side.z)
	await _wait(0.3)
	a.ctrl.press("mov1")
	await _wait(0.05)
	a.ctrl.release("mov1")
	var shot_dir := Vector3.ZERO
	var follows := false
	for k in 40:
		await get_tree().physics_frame
		for p in main.combat.projectiles:
			if p.user == a:
				shot_dir = p.velocity.normalized()
				follows = p.target == b
		if shot_dir != Vector3.ZERO:
			break
	_ok("Free camera: the shot leaves where the camera looks and still follows", shot_dir.dot(side) > 0.7 and follows,
		"dot %.2f, follows %s" % [shot_dir.dot(side), follows])
	# Locking on picks what the camera looks at.
	a.ctrl.yaw = atan2(-toward.x, -toward.z)
	a.lock_on_looked()
	_ok("Locking on picks what the camera looks at", a.locked and a.aim_target() == b, str(a.aim_target()))
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()
