extends Action
## Chilling Water: a quick, straight burst of cold water, Rapid Strike's only ranged move. It
## always lowers the target's Attack (Fighter._secondary), which is why it is there rather than
## for its damage, and frosts where it lands.


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ice
	tint_k = 0.25 * (t / d.startup)


func on_active() -> void:
	tint_k = 0.0
	var from_pos := mouth()
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
	var node: Node3D = vfx.pixel_ball("chillingwater_ball", 6, 0.85, Roster.TYPE_COLOR.ice, 14.0, false)
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": life,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, against: String): _splash(pos, against)})
	var trail := {"t": 0.0}
	vfx.live(node, life + 0.05, func(_k: float):
		trail.t -= vfx.get_process_delta_time()
		if p.alive and trail.t <= 0.0:
			trail.t = 0.05
			vfx.burst("water_fx", p.pos, -p.velocity.normalized(), Color(0, 0, 0, 0), 0.3))
	vfx.cobble("waterpulse_actorsplash", from_pos, from_pos + dir * 3.0, 1.0)
	play_sound("chillingwater", -2.0)


func _splash(pos: Vector3, against: String) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.burst("water_fx", pos, Vector3.UP, Color(0, 0, 0, 0), 0.7)
	vfx.burst("ice_fx", pos, Vector3.UP, Color(0, 0, 0, 0), 0.5)
	if against != "":
		vfx.mark(Vector3(pos.x, l.main.ground_y, pos.z), "wet", 0.8, 2.5)
	l.main.audio.play_sound("chillingwater_hit", pos, -3.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.18, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.16, "stretch": 1.06}
	return {}
