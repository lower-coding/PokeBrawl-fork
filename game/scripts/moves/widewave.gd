extends Action
## Dazzling Gleam and Hyper Voice: a wide front that rolls across the field like Surf. It rises
## "tall" m up close, drops over the first metres and rolls on "low" m high at "speed" m/s until
## "reach" metres; its hit follows its height, so up close it must be dodged and further away it can
## be jumped. It hits once and is not a projectile: it cannot be sent back or broken. "look" draws it:
##   gleam  a sheet of pink-white light across the front, sparkling along it, lighting the ground.
##   voice  three arches of sound one behind the other, following the front.

const RISE := 0.22            # s rising in place
const CRASH := 0.35           # s dropping while it surges ahead
const GLEAM := Color(1.0, 0.78, 0.92)
const VOICE := Color(0.92, 0.94, 1.0)
const BAND := "res://fx/tex/custom/gleam_band.png"
const ARC := "res://fx/tex/custom/voice_arc.png"
const ARCS := 3
const ARC_GAP := 0.9          # m between the arches


func _color() -> Color:
	return GLEAM if d.look == "gleam" else VOICE


func on_start() -> void:
	turn_mult = 2.0


func in_startup(_delta: float) -> void:
	tint_col = _color()
	tint_k = 0.35 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	var aim_dir := aim(0.8)
	var dir := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var start: Vector3 = l.global_position + dir * (l.data.radius + 0.8)
	start.y = l.main.ground_y
	var width: float = d.width
	var tall: float = d.tall
	var low: float = d.low
	var speed: float = d.speed
	# Time to roll the whole way: rising in place, the drop (surging at 1.4x) and the rest.
	var life: float = RISE + CRASH + maxf(0.0, d.reach - speed * 1.4 * CRASH) / speed
	var basis := Basis.looking_at(dir, Vector3.UP)
	var pieces: Array = []
	if d.look == "gleam":
		pieces.append(vfx.flat_sprite(BAND, 4, 1.0, start, basis, life + 0.2, Color.WHITE, 10.0))
	else:
		for i in ARCS:
			pieces.append(vfx.flat_sprite(ARC, 1, 1.0, start, basis, life + 0.2, VOICE))
	# Its hit: a capsule across the front, as high as the front is.
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.local = false
	g.shape = "capsule"
	g.type = d.type
	g.cat = d.cat
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.hitstop = 0.08
	g.contact = false
	g.lifetime = life
	g.radius = 0.5
	g.a = start - side * width * 0.42 + Vector3.UP * g.radius
	g.b = start + side * width * 0.42 + Vector3.UP * g.radius
	g.on_strike = func(o: Node, res: String):
		if res == "hit":
			l.main.audio.play_sound(id + "_hit", o.center(), -3.0)
	l.main.combat.add_hit(g)
	var state := {"t": 0.0, "run": 0.0, "fx": 0.0}
	vfx.live(Node3D.new(), life + 0.2, func(_k: float):
		var dt := vfx.get_process_delta_time()
		state.t += dt
		var tt: float = state.t
		var h: float
		if tt < RISE:
			h = lerpf(0.35, 1.0, tt / RISE) * tall
			state.run += speed * 0.15 * dt
		elif tt < RISE + CRASH:
			var c: float = (tt - RISE) / CRASH
			h = lerpf(tall, low, c * c)
			state.run += speed * 1.4 * dt
		else:
			h = low
			state.run += speed * dt
		# It fades away at the end.
		h *= 1.0 - clampf((tt - life + 0.2) / 0.2, 0.0, 1.0)
		var at: Vector3 = start + dir * state.run
		var r: float = clampf(h * 0.5, 0.5, 1.9)
		g.radius = r
		g.a = at - side * width * 0.42 + Vector3.UP * r
		g.b = at + side * width * 0.42 + Vector3.UP * r
		if h < 0.05:
			g.active = false
		_draw_front(pieces, at, dir, width, h)
		state.fx -= dt
		if state.fx <= 0.0 and h > 0.05:
			state.fx = 0.09
			_along_front(at, dir, side, width, h))
	if d.look == "gleam":
		play_sound(id, 2.0)
	else:
		# Sing is a gentle sound: lower and louder, it reads as a shout.
		l.main.audio.play_sound(id, l.global_position, 5.0, 0.65)
		l.main.shake_camera(0.1, l.global_position)


## The sheet, or the arches one behind the other, fitted to the front's width and height and
## standing on the ground.
func _draw_front(pieces: Array, at: Vector3, dir: Vector3, width: float, h: float) -> void:
	for i in pieces.size():
		var n: Node3D = pieces[i]
		if not is_instance_valid(n):
			continue
		var grow: float = 1.0 - i * 0.14
		n.global_position = at - dir * (i * ARC_GAP) + Vector3.UP * h * grow * 0.5
		n.scale = Vector3(maxf(width * grow, 0.01), maxf(h * grow, 0.01), 1.0)


## What runs along the front while it rolls.
func _along_front(at: Vector3, dir: Vector3, side: Vector3, width: float, h: float) -> void:
	var vfx: Vfx = l.main.vfx
	var along: Vector3 = at + side * randf_range(-0.5, 0.5) * width
	if d.look == "gleam":
		l.main.fx.anim("generic/sparkle/mediumsparkle.png", along + Vector3.UP * h * randf_range(0.2, 1.0), 0.7, 7, 0.3)
		vfx.burst("stars", along + Vector3.UP * h * 0.5, dir + Vector3.UP, GLEAM, 0.4)
		vfx.light(at + Vector3.UP * 0.4, GLEAM, 1.8, width * 0.7, 0.12)
	else:
		vfx.cobble("sing_actorwave", along + Vector3.UP * h * 0.6, along + dir, 1.0)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
			return {"stretch": 1.0 + 0.08 * k, "tilt": -0.2 * k, "anim": "special", "reset": t < 0.02}
		"active":
			return {"stretch": 1.06, "tilt": 0.2}
	return {}
