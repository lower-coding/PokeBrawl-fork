extends Action
## Mud Shot: a quick lean back and a straight glob of mud. Fast and flat, it always lowers
## the target's Speed (Fighter._secondary) and leaves a small stain where it lands; no lob
## and no zone, which keeps it apart from Sludge Bomb.


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ground
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
	var node: Node3D = vfx.pixel_ball("mudshot_ball", 6, 0.85, Roster.TYPE_COLOR.ground, 14.0, false)
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": life,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, against: String): _splat(pos, against)})
	var trail := {"t": 0.0}
	vfx.live(node, life + 0.05, func(_k: float):
		trail.t -= vfx.get_process_delta_time()
		if p.alive and trail.t <= 0.0:
			trail.t = 0.05
			vfx.cobble("mudbomb_actortrail", p.pos, null, 1.0))
	vfx.cobble("mudbomb_actorfling", from_pos, from_pos + dir * 3.0, 1.0)
	play_sound("mudshot", -2.0)
	l.velocity -= dir * 1.2


func _splat(pos: Vector3, against: String) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.cobble("mudbomb_actorfling", pos, null, 1.0)
	if against != "":
		vfx.mark(Vector3(pos.x, l.main.ground_y, pos.z), "mud", 0.7, 3.0)
	l.main.audio.play_sound("mudshot_hit", pos, -3.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.22, "stretch": 0.94, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.18, "stretch": 1.08}
	return {}
