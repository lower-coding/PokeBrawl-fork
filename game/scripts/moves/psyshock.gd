extends Action
## Psyshock: a palm thrust and one fast, straight shard of pink crystal that bursts on impact. It
## does not home, and needs a real aim. Special, but measured against Defense ("hits_def"), so it
## is what breaks the rivals built to take special hits.

const COLOR := Color(1.0, 0.45, 0.85)


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = COLOR
	tint_k = 0.25 * (t / d.startup)


func on_active() -> void:
	tint_k = 0.0
	var from_pos: Vector3 = l.point("locator_hand_primary")
	var dir := aim(0.7)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = d.cat
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.contact = false
	var vfx: Vfx = l.main.vfx
	var life: float = d.reach / d.speed
	var node: Node3D = vfx.pixel_ball("psyshock_shard", 4, 0.95, COLOR, 14.0)
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": life,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, _against: String): _burst(pos)})
	var trail := {"t": 0.0}
	vfx.live(node, life + 0.05, func(_k: float):
		trail.t -= vfx.get_process_delta_time()
		if p.alive and trail.t <= 0.0:
			trail.t = 0.05
			vfx.burst("stars", p.pos, -p.velocity.normalized(), COLOR, 0.2))
	play_sound("psyshock", -2.0)


func _burst(pos: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.burst("stars", pos, Vector3.UP, COLOR, 0.8)
	vfx.light(pos, COLOR, 3.0, 4.0, 0.15)
	l.main.audio.play_sound("psyshock_hit", pos, -3.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.18, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.16, "stretch": 1.06}
	return {}
