extends Action
## Swift: five star-shaped rays leave in a fan, one every "gap" seconds, then curve in on the target
## from different angles. It never misses in the games: the top turn rate (accuracy 0) plus a strong
## "homing", so running does nothing. They fly slowly enough to answer: a dodge shakes off the ones
## in the air, as for every projectile, and the ones still to leave chase again. Walls stop them.
## Each is one fifth of a use, near enough ("split" against the combo's falloff), and a deflect
## breaks it. Being cut short keeps the stars that have not left.

const COLOR := Color(1.0, 0.88, 0.4)

var _sent := 0
var _sparkle := 0.0


func on_start() -> void:
	turn_mult = 2.5


func in_startup(delta: float) -> void:
	tint_col = COLOR
	tint_k = 0.25 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_sparkle -= delta
	if _sparkle <= 0.0:
		_sparkle = 0.07
		l.main.vfx.burst("stars", l.point("locator_mouth"), Vector3.UP, COLOR, 0.3)


func on_active() -> void:
	tint_k = 0.0
	play_sound(id, -2.0)
	_fire()


func in_active(_delta: float) -> void:
	_fire()


## Whichever stars are due by now.
func _fire() -> void:
	var stars: int = d.stars
	while _sent < stars and t >= _sent * float(d.gap):
		_star(lerpf(-float(d.fan), float(d.fan), float(_sent) / maxf(stars - 1, 1)))
		_sent += 1


func _star(ang: float) -> void:
	var vfx: Vfx = l.main.vfx
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = d.cat
	g.damage = d.damage
	g.stun = d.stun
	g.strength = d.strength
	g.hitstop = d.hitstop
	g.contact = false
	g.quiet = _sent > 0                # "Effective!" once, not five times
	var from_pos := l.point("locator_mouth")
	var dir := aim(0.8).rotated(Vector3.UP, ang)
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
		"homing": d.homing, "hit": g, "node": vfx.pixel_ball("swift_star", 4, 0.8, COLOR, 16.0, false),
		"on_impact": func(pos: Vector3, _against: String):
			vfx.burst("stars", pos, Vector3.UP, COLOR, 0.6)
			l.main.audio.play_sound("swift_hit", pos, -6.0)})


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.14, "stretch": 0.96, "anim": "special", "reset": t < 0.02}
		"active":
			return {"tilt": 0.1, "stretch": 1.04}
	return {}
