extends Node
## Automated tests (godot --path game -- --test=name):
##   aivsai      headless: AI vs AI for up to 3 battles; prints how it goes and checks
##               that nothing stays active after each KO and rematch
##   moves       each of the player's moves against a still rival, with captures
##   combat      AI vs AI on screen, with captures every few seconds
##   animations  each Pokémon goes through its states and transitions looking for
##               T-poses, sinking and stuck animations (see test_animations.gd)
##   mechanics   headless: concrete cases from the acceptance criteria (dodging a
##               projectile, jumping the wave, punishing a recovery, combo limit,
##               hitstop)
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
var _step := 0
var _step_t := 0.0
var _fps_sum := 0
var _fps_n := 0
var _fps_min := 9999
var _flying := {}
var _strip: Array = []           # moves --sequence: frames of the current move


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir())
	for l in main.fighters:
		l.hit_taken.connect(func(_q, _i): _hits += 1)
	match test_name:
		"aivsai":
			Engine.max_fps = 0
		"moves":
			main.ai.mode = "still"
			main.player.is_player = false
			main.player.locked = true
			var b: Fighter = main.fighters[1]
			b.reset(Vector3(-3.5, 0, 0), PI * 0.5)
			main.player.reset(Vector3(3.0, 0, 0), -PI * 0.5)
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
			# [time, action, capture]: title, main menu, Battle, change Pokémon,
			# rival, difficulty and stage (to the glade), VS, battle, pause and back to
			# the menu.
			_plan = [[1.5, "", "menu_title"], [1.7, "menu_accept", ""], [2.3, "move_down", ""], [2.6, "", "menu_main"],
				[2.8, "move_up", ""], [3.0, "menu_accept", ""], [3.8, "move_right", ""], [4.1, "move_down", ""],
				[4.8, "", "menu_selection"], [5.0, "menu_accept", ""], [5.4, "move_down", ""], [5.9, "", "menu_rival"],
				[6.1, "menu_accept", ""], [6.5, "move_right", ""], [6.65, "move_down", ""], [6.8, "", "menu_difficulty"], [7.0, "menu_accept", ""],
				[7.6, "", "menu_vs"], [10.5, "", "menu_battle"], [10.7, "pause", ""], [11.1, "", "menu_pause"],
				[11.3, "menu_back", ""], [12.2, "", "menu_back"]]
		"combat":
			_shots = [2.0, 4.0, 6.0, 8.0, 10.0, 12.5, 15.0, 18.0, 22.0]
		"mechanics":
			_mechanics()


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
		"menu":
			for p in _plan:
				if t >= p[0] and t - delta < p[0]:
					if p[1] != "":
						var ev := InputEventAction.new()
						ev.action = p[1]
						ev.pressed = true
						Input.parse_input_event(ev)
						Input.action_press(p[1])
						var released: String = p[1]
						get_tree().create_timer(0.05, true, false, true).timeout.connect(func(): Input.action_release(released))
					if p[2] != "":
						print("state: menu ", main.menu.is_open, " pause ", main.paused, " fighters ", main.fighters.size(),
							" choice ", main.menu.choice)
						_capture(p[2])
			if t > 12.5:
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
	if _step_t > moment and _step_t - delta <= moment:
		_capture("moves_%s_%d" % [j.species, _step + 1])
	# With --sequence, also a strip of 16 frames (every 0.1 s from the press) to see how
	# the effect moves, not just one instant.
	if main._args.has("sequence") and DisplayServer.get_name() != "headless":
		var k := int(floorf((_step_t - 0.4) / 0.1))
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
	# 3. Avoiding it just by moving sideways (positioning).
	ab = await _setup("pikachu", "charizard", Vector3(-6, 0, 0), Vector3(6, 0, 0))
	a = ab[0]
	b = ab[1]
	a.ctrl.press("mov1")
	await _wait(0.12)
	b.ctrl.yaw = 0.0
	b.ctrl.move_input = Vector2(0, 1)   # with yaw 0, "forward" is -Z: sideways to the shot
	await _wait(1.0)
	b.ctrl.move_input = Vector2.ZERO
	_ok("Thunder Shock avoided by moving sideways", b.hp == b.hp_max, "HP %d" % b.hp)
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
	var fails := _results.filter(func(r): return not r[1]).size()
	print("RESULT: %d of %d" % [_results.size() - fails, _results.size()])
	get_tree().quit()
