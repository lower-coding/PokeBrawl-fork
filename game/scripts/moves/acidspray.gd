extends Action
## Acid Spray: a short rear back and a lobbed glob of acid. The weakest hit of the set and the
## quickest back; what it is for is the -2 Sp. Def (Fighter._secondary). It comes down where the
## rival was going ("track" 0: it does not follow), so walking out from under it works, and it
## bursts into a sizzling splash; no puddle, which keeps it apart from Sludge Bomb.


func on_start() -> void:
	turn_mult = 2.5


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.poison
	tint_k = 0.3 * (t / d.startup)


func on_active() -> void:
	tint_k = 0.0
	var from_pos := mouth()
	var dir := aim(0.8)
	# Thrown along that line and upward by just what gravity takes off it on the way, so it
	# arrives at the target's height and the arc is taller the further it goes.
	var dist: float = minf(from_pos.distance_to(l.ctrl.aim_at if l.crosshair_aim() else l.target_center()), d.reach)
	var flight: float = dist / d.speed
	var velocity: Vector3 = dir * d.speed + Vector3.UP * 0.5 * d.gravity * flight
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
	var life: float = d.reach / d.speed + 0.6
	var node: Node3D = vfx.pixel_ball("acidspray_ball", 6, 0.95, Roster.TYPE_COLOR.poison, 12.0, false)
	var p: Dictionary = l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": velocity, "radius": d.radius, "lifetime": life,
		"gravity": d.gravity, "hit": g, "node": node, "on_impact": func(pos: Vector3, _against: String): _burst(pos)})
	var trail := {"t": 0.0}
	vfx.live(node, life + 0.05, func(_k: float):
		trail.t -= vfx.get_process_delta_time()
		if p.alive and trail.t <= 0.0:
			trail.t = 0.06
			vfx.cobble("acidspray_actortrail", p.pos, null, 1.0))
	play_sound("acidspray", -2.0)


func _burst(pos: Vector3) -> void:
	var vfx: Vfx = l.main.vfx
	vfx.cobble("acidspray_targetsizzle", pos, null, 1.0)
	vfx.wave(Vector3(pos.x, l.main.ground_y, pos.z), 1.1, 0.25, Roster.TYPE_COLOR.poison, 0.08)
	l.main.audio.play_sound("acidspray_hit", pos, -3.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.28, "stretch": 0.93, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.2, "stretch": 1.08}
	return {}
