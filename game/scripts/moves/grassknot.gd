extends Action
## Grass Knot: Whimsicott stamps and a line of grass runs along the ground to the rival, a tuft rising
## where it passes. Under the rival it curls up for "warn" seconds, still chasing at "follow" m/s
## (about what a rival can run: running does not help), and then snaps shut around the feet in a
## ring hit. The answer is always to leave the ground or to dodge: it breaks at a dodge and a flyer in
## the air is safe, but the ring reaches whatever is lower than "reach_up" above the floor, so a
## levitating Gengar is caught. The damage goes by the target's weight (Damage.base_power). Modeled
## on toxic.gd, which also runs under the ground and ends in a ring, and which is not the same:
## Toxic's warning stands still.

const SNAP := 0.5                    # how long the knot stays closed (visual)
const BURST := 0.15                  # the hit lasts this long
const COLOR := Color(0.2, 0.85, 0.12)


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = COLOR
	tint_k = 0.3 * (t / startup_len())


func on_active() -> void:
	tint_k = 0.0
	var start: Vector3 = l.global_position + l.forward() * (l.data.radius + 0.4)
	start.y = l.main.ground_y
	var run := {"pos": start, "dir": l.forward(), "gone": 0.0, "phase": "run", "t": 0.0, "trail": 0.0,
		"speed": d.speed, "track": Combat.track_for(id), "target": l.shot_target()}
	var node := Node3D.new()
	l.main.vfx.add_child(node)
	l.main.vfx.burst("leaves", start + Vector3.UP * 0.2, Vector3.UP, COLOR, 0.8)
	l.main.vfx.wave(start, 1.0, 0.25, COLOR, 0.08)
	l.main.shake_camera(0.05, start)
	play_sound(id, -2.0)
	l.main.vfx.live(node, d.reach / run.speed + d.warn + SNAP + 0.2, func(_k: float): _knot_step(run))


## One frame of the knot: running, curling up or closed.
func _knot_step(run: Dictionary) -> void:
	var vfx: Vfx = l.main.vfx
	var dt := vfx.get_process_delta_time()
	run.t += dt
	match run.phase:
		"run":
			if _chase(run, run.speed, run.track, dt):
				return
			run.gone += run.speed * dt
			if run.gone >= d.reach:
				_warn(run)
				return
			run.trail -= dt
			if run.trail <= 0.0:
				run.trail = 0.05
				vfx.burst("leaves", run.pos + Vector3.UP * 0.1, Vector3.UP, COLOR, 0.25)
				vfx.solid_anim("res://fx/tex/custom/grassknot_tuft.png", 6, run.pos + Vector3.UP * 0.5, 1.0, 0.45)
		"warn":
			# It keeps chasing the rival while it curls up, as fast as the rival can run.
			_chase(run, d.follow, deg_to_rad(720.0), dt)
			run.trail -= dt
			if run.trail <= 0.0:
				run.trail = 0.06
				var off: Vector3 = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * d.radius
				vfx.burst("leaves", run.pos + off + Vector3.UP * 0.05, Vector3.UP, COLOR, 0.2)
			if run.t >= d.warn:
				_snap(run)
		"snap":
			if run.t >= SNAP:
				run.phase = "done"


## Moves the knot toward its target; true once it has arrived and started to curl up. It stops
## chasing when its target dodges or is gone.
func _chase(run: Dictionary, speed: float, track: float, dt: float) -> bool:
	var tg = run.target
	if tg and is_instance_valid(tg) and not (tg is Fighter and (tg.state in ["dodge", "ko"])):
		var to: Vector3 = tg.global_position - run.pos
		var flat := Vector2(to.x, to.z)
		if run.phase == "run" and flat.length() < 0.5:
			_warn(run)
			return true
		var v := Vector2(run.dir.x, run.dir.z)
		v = v.rotated(clampf(v.angle_to(flat), -track * dt, track * dt))
		run.dir = Vector3(v.x, 0, v.y)
		if run.phase == "warn":
			run.pos += run.dir * minf(speed * dt, maxf(flat.length() - 0.05, 0.0))
		else:
			run.pos += run.dir * speed * dt
	else:
		run.target = null
		if run.phase == "run":
			run.pos += run.dir * speed * dt
	return false


func _warn(run: Dictionary) -> void:
	run.phase = "warn"
	run.t = 0.0
	run.trail = 0.0
	l.main.vfx.telegraph(run.pos, d.radius, d.warn + 0.05, COLOR)
	l.main.audio.play_sound(id, run.pos, -10.0, 0.7)


func _snap(run: Dictionary) -> void:
	run.phase = "snap"
	run.t = 0.0
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = "special"
	g.damage = d.damage
	g.stun = d.stun
	g.hitstop = 0.06
	g.contact = true
	g.strength = d.strength
	g.local = false
	g.shape = "ring"
	g.center = run.pos
	g.r_in = 0.0
	g.r_out = d.radius
	g.reach_up = d.reach_up
	g.lifetime = BURST
	g.help = help
	l.main.combat.add_hit(g)
	var vfx: Vfx = l.main.vfx
	vfx.burst("leaves", run.pos + Vector3.UP * 0.3, Vector3.UP, COLOR, 1.2)
	vfx.wave(run.pos, d.radius * 1.15, 0.3, COLOR, 0.1)
	vfx.cobble("leafage_target", run.pos + Vector3.UP * 0.4, null, l.data.height)
	l.main.audio.play_sound(id + "_hit", run.pos, -4.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 1.04}
		"active":
			# A stamp on the ground.
			return {"tilt": 0.1, "stretch": 0.9}
	return {}
