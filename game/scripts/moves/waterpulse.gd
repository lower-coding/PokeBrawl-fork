extends Action
## Water Pulse: suds gather at its feet and a ring of water flies straight, widening as it
## goes, and what it touches widens with it ("widen": how much it has grown by the end of its
## reach). Up close it is narrow; from afar it is hard to step out of. It can confuse
## (Fighter._secondary).

const RING := "res://fx/tex/generic/ring/warblingring.png"


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.3 * (t / d.startup)


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
	# Across its way: the projectile turns the root along it, so the ring faces back at the
	# user and the camera.
	var root := Node3D.new()
	vfx.add_child(root)
	root.global_position = from_pos
	var ring: MeshInstance3D = vfx.flat_sprite(RING, 24, d.radius * 2.8, Vector3.ZERO, Basis.IDENTITY, life + 0.1, Roster.TYPE_COLOR.water, 18.0)
	ring.reparent(root, false)
	ring.transform = Transform3D.IDENTITY
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": life,
		"hit": g, "node": root, "on_impact": func(pos: Vector3, against: String): _splash(pos, against)})
	var trail := {"t": 0.0}
	vfx.live(root, life + 0.05, func(k: float):
		if not p.alive:
			return
		var grown: float = 1.0 + float(d.widen) * k
		p.radius = d.radius * grown
		if is_instance_valid(ring):
			ring.scale = Vector3.ONE * snappedf(grown, 0.2)
		# Warbling rings and drops left behind: together they make the pulse.
		trail.t -= vfx.get_process_delta_time()
		if trail.t <= 0.0:
			trail.t = 0.09
			vfx.cobble("waterpulse_actorring", p.pos, p.pos + p.velocity, 1.0)
			vfx.burst("water_fx", p.pos, -p.velocity.normalized(), Color(0, 0, 0, 0), 0.3 * grown))
	vfx.cobble("waterpulse_actorsplash", from_pos, from_pos + dir * 3.0, 1.0)
	play_sound("waterpulse", -2.0)


func _splash(pos: Vector3, against: String) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.burst("water_fx", pos, Vector3.UP, Color(0, 0, 0, 0), 0.8)
	if against != "":
		vfx.mark(Vector3(pos.x, l.main.ground_y, pos.z), "wet", 1.0, 2.5)
	l.main.audio.play_sound("waterpulse_hit", pos, -3.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.12, "stretch": 0.95, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.14, "stretch": 1.07}
	return {}
