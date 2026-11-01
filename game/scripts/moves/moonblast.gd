extends Action
## Moonblast: a bright purple glow gathers at the mouth, then a ball of moonlight flies out, slow
## enough to see coming and barely turning ("track"), with a soft light on the ground under it and
## a burst where it lands. It can lower the target's Sp. Atk ("secondary"). Purple, not the type's
## pink. It can be broken or sent back.

const COLOR := Color(0.72, 0.5, 1.0)
const SIZE := 2.0

var _ball: Node3D


func _hold() -> Vector3:
	return l.point("locator_mouth") + l.forward() * 0.3


func on_start() -> void:
	turn_mult = 2.5
	_ball = l.main.vfx.pixel_ball("moonblast_ball", 8, SIZE, COLOR, 12.0)
	_ball.scale = Vector3.ONE * 0.15


func in_startup(_delta: float) -> void:
	var k := clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	tint_col = COLOR
	tint_k = 0.15 + 0.25 * k
	if is_instance_valid(_ball):
		_ball.global_position = _hold()
		_ball.scale = Vector3.ONE * lerpf(0.15, 1.0, k)


func on_active() -> void:
	tint_k = 0.0
	var vfx: Vfx = l.main.vfx
	var dir := aim(0.8)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = d.cat
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.contact = false
	var ball := _ball
	_ball = null
	if not is_instance_valid(ball):
		ball = vfx.pixel_ball("moonblast_ball", 8, SIZE, COLOR, 12.0)
	ball.scale = Vector3.ONE
	var life: float = d.reach / d.speed
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": _hold(), "velocity": dir * d.speed, "radius": d.radius, "lifetime": life,
		"hit": g, "node": ball, "on_impact": func(pos: Vector3, _against: String): _burst(pos)})
	var trail := {"t": 0.0}
	vfx.live(Node3D.new(), life + 0.05, func(_k: float):
		trail.t -= vfx.get_process_delta_time()
		if p.alive and trail.t <= 0.0:
			trail.t = 0.1
			vfx.burst("stars", p.pos, -p.velocity.normalized(), COLOR, 0.3)
			vfx.light(Vector3(p.pos.x, l.main.ground_y + 0.3, p.pos.z), COLOR, 1.6, 3.5, 0.14))
	play_sound(id, 0.0)
	l.velocity -= dir * 1.0


func _burst(pos: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.burst("stars", pos, Vector3.UP, COLOR, 1.4)
	vfx.wave(Vector3(pos.x, l.main.ground_y, pos.z), 2.2, 0.3, COLOR, 0.08)
	vfx.light(pos, COLOR, 4.0, 5.0, 0.2)
	l.main.audio.play_sound("moonblast_hit", pos, -2.0)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ball):
		_ball.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.18, "stretch": 1.08}
	return {}
