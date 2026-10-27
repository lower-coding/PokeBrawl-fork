extends Action
## Iron Tail: the tail turns to steel (it glows during the startup) and strikes head-on,
## launching the target. In the air, it dives onto the rival.

var _air := false
var _shine := 0.0


func on_start() -> void:
	_air = not l.is_on_floor()
	turn_mult = 2.0
	if not _air:
		l.velocity.y = 4.0
	play_sound("charge", -10.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.steel
	tint_k = 0.2 + 0.3 * (t / d.startup)
	_shine -= delta
	if _shine <= 0.0:
		_shine = 0.07
		l.main.vfx.burst("stars", l.point("locator_tail_tip"), Vector3.UP)
	if _air:
		l.velocity.y = maxf(l.velocity.y, 0.5)


func on_active() -> void:
	var height: float = l.data.height
	if _air:
		no_gravity = true
		l.velocity = l.forward() * 5.0 + Vector3.DOWN * 18.0
		hit({"shape": "sphere", "center": Vector3(0, height * 0.2, l.data.radius * 0.5), "radius": 0.9, "push_dir": Vector3(0, 0.2, 1)})
	else:
		hit({"shape": "sphere", "center": Vector3(0, height * 0.45, l.data.radius + 0.7), "radius": 0.95})
	var col := Roster.TYPE_COLOR.steel
	l.main.vfx.ribbon(func():
		var base := l.point("locator_tail")
		var tip := l.point("locator_tail_tip")
		return [base, tip + (tip - base) * 0.9], col, d.active + 0.05, 0.2)
	l.main.vfx.light(l.point("locator_tail_tip"), Color(0.9, 0.95, 1.0), 2.5, 3.0, 0.2)
	l.main.vfx.sprite_anim(Vfx.TEX + "impact/impact_steel.png", l.point("locator_tail_tip"), 1.2, Vector2i(2, 7), 0.2)
	l.main.audio.play_sound("dodge", l.global_position, -4.0, 0.7)


func in_active(_delta: float) -> void:
	if _air and l.is_on_floor():
		_ground_impact()
		_go_to("recovery")


func on_recovery() -> void:
	no_gravity = false
	tint_k = 0.0


func _ground_impact() -> void:
	var p := l.global_position
	l.main.vfx.wave(p, 2.5, 0.35, Roster.TYPE_COLOR.steel)
	l.main.vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 1.5)
	l.main.vfx.mark(p, "crack", 1.0, 3.0)
	l.main.shake_camera(0.2, p)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.3, "stretch": 0.9, "turn": -t / d.startup * 0.6}
		"active":
			return {"tilt": 0.4 if not _air else 0.9, "stretch": 1.1, "turn": TAU * clampf(t / d.active, 0.0, 1.0) if not _air else 0.0, "anim": "physical"}
	return {"tilt": 0.15 * (1.0 - t / d.recovery)}
