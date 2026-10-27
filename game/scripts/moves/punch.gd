extends Action
## Elemental punch (Ice Punch, Meteor Mash, Bullet Punch): the fist charges with its
## element during the startup, then advances and hits in front. The data sets the
## effect (freeze).

var _shine := 0.0


func on_start() -> void:
	turn_mult = 2.0


func _particles() -> String:
	return {"ice": "steam", "fire": "fire_fx", "electric": "sparks", "steel": "sparks_metal"}.get(d.type, "dust")


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR[d.type]
	tint_k = 0.25 * (t / d.startup)
	_shine -= delta
	if _shine <= 0.0:
		_shine = 0.06
		var hand := l.point("locator_hand_primary")
		l.main.vfx.burst(_particles(), hand, Vector3.UP, Color(0, 0, 0, 0), 0.35)
		if d.type == "ice":
			l.main.vfx.burst("ice_fx", hand, Vector3.UP, Color(0, 0, 0, 0), 0.5)


func on_active() -> void:
	advance_by(d.advance / d.active * 0.5)
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.5, l.data.radius + d.reach * 0.5), "radius": d.radius})
	var col: Color = Roster.TYPE_COLOR[d.type]
	l.main.vfx.ribbon(func(): return [l.center(), l.point("locator_hand_primary")], col, d.active + 0.05, 0.15)
	l.main.audio.play_sound("dodge", l.global_position, -6.0, 0.8)


func on_recovery() -> void:
	tint_k = 0.0
	if landed:
		play_sound("icepunch", 0.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "side": 0.25, "stretch": 0.95}
		"active":
			return {"tilt": 0.35, "side": -0.3, "stretch": 1.08, "anim": "physical"}
	return {"tilt": 0.15 * (1.0 - t / d.recovery)}
