extends Action
## Tailwind: a wind ring spreads on the floor and whoever is inside when it goes out gets Speed x2
## for "buff_dur" (Fighter.speed_stage): the caster always, an ally only if it is within
## "pulse_radius" then, foes never. Casting again refreshes it for those inside. It does not use a
## stage, so nothing that clears them takes it, but leaving the field ends it. A hit during its
## startup stops it. Like selfboost.gd, without "uses": stages last until a switch, this ends by
## itself. Online who is inside is its owner's call, and goes to every copy (Main.give_buff).

var _aura := 0.0


func on_start() -> void:
	faces_rival = false
	tint_col = Roster.TYPE_COLOR.flying
	play_sound(id, -2.0)


func in_startup(delta: float) -> void:
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_aura -= delta
	if _aura <= 0.0:
		_aura = 0.06
		var c := l.center()
		var off: Vector3 = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * l.data.height
		l.main.vfx.burst("wind", c + off, -off.normalized(), Color(0, 0, 0, 0), 0.5)


func on_active() -> void:
	tint_k = 0.0
	var at := l.global_position
	var radius := float(d.pulse_radius)
	l.main.vfx.wave(Vector3(at.x, l.main.ground_y, at.z), radius, 0.4, Fighter.TAILWIND_COLOR, 0.12)
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0)
		l.main.vfx.burst("wind", at + dir * radius * 0.6 + Vector3.UP * 0.4, Vector3.UP, Color(0, 0, 0, 0), 0.9)
	if l.is_remote:
		return
	l.main.give_buff("tailwind", l, float(d.buff_dur))
	var mate := l.ally()
	if mate and Vector2(mate.global_position.x - at.x, mate.global_position.z - at.z).length() <= radius:
		l.main.give_buff("tailwind", mate, float(d.buff_dur))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 0.95, "anim": "status", "reset": t < 0.02}
		"active":
			return {"tilt": -0.05, "stretch": 1.06}
	return {}
