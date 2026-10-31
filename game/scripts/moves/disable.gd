extends Action
## Disable: the eyes flash, then a tiny spark flies straight from them for a very short way. No
## damage and no stun: every move of the target with no cooldown running has to wait "disables"
## seconds (Fighter._status_move, Fighter._disable_all). Pink, even though the move is Normal.
## Being a projectile, a move with "deflects": 2 sends it back at its user.

const COLOR := Color(1.0, 0.5, 0.88)


func on_start() -> void:
	turn_mult = 3.0
	# Cobblemon's glint is placed from the feet, by height: this one has to be on the eyes.
	l.main.fx.anim("generic/sparkle/mediumsparkle.png", _eyes() + l.forward() * 0.2, 0.7, 7, d.startup)


func in_startup(_delta: float) -> void:
	tint_col = COLOR
	tint_k = 0.3 * (t / d.startup)


## Between the eyes (Fighter.point falls back to the chest on a body without them).
func _eyes() -> Vector3:
	return (l.point("locator_eye_left") + l.point("locator_eye_right")) * 0.5


func on_active() -> void:
	tint_k = 0.0
	var from_pos := _eyes()
	var dir := aim(0.7)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = d.type
	g.cat = "status"
	g.damage = 0.0
	g.stun = 0.0
	g.hitstop = 0.0
	g.contact = false
	g.strength = 0
	var vfx: Vfx = l.main.vfx
	var node: Node3D = vfx.pixel_ball("disable_spark", 4, 0.45, COLOR, 14.0)
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
		"hit": g, "node": node, "on_impact": func(pos: Vector3, _against: String):
			vfx.burst("stars", pos, Vector3.UP, COLOR, 0.3)})
	vfx.light(from_pos, COLOR, 2.0, 2.5, 0.12)
	play_sound(id, -2.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 0.97, "anim": "disable", "reset": t < 0.02}
		"active":
			return {"tilt": 0.12, "stretch": 1.03}
	return {}
