extends Action
## Earthquake: raises its body (you can see it coming) and stomps. A wave expands up to
## 11 m and only hits whoever is touching the ground: jump right when it arrives.

var _g: Hit
var _center := Vector3.ZERO
var _dust := 0.0


func on_start() -> void:
	faces_rival = false
	play_sound("charge", -8.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ground
	tint_k = 0.2 * (t / d.startup)
	_dust -= delta
	if _dust <= 0.0 and t > d.startup * 0.4:
		_dust = 0.1
		l.main.vfx.burst("dust", l.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), Vector3.UP, Color(0, 0, 0, 0), 0.8)


func on_active() -> void:
	_center = l.global_position
	_center.y = l.main.ground_y
	_g = hit({"shape": "ring", "local": false, "center": _center, "r_in": 0.0, "r_out": 1.0, "ground_only": true})
	var vfx: Vfx = l.main.vfx
	vfx.wave(_center, d.r_max, d.active, Color(0.95, 0.75, 0.4), 0.06)
	vfx.wave(_center, d.r_max * 0.92, d.active * 1.1, Color(0.7, 0.55, 0.3), 0.12)
	vfx.distortion(_center + Vector3.UP * 0.4, 6.0, 0.4, 0.06)
	vfx.mark(_center, "crack", 3.0, 6.0)
	vfx.cobble("bulldoze_targetfloor", _center, null, l.data.height)
	vfx.burst("debris", _center, Vector3.UP, Color(0, 0, 0, 0), 1.3)
	l.main.audio.play_sound("earthquake", _center, 2.0)
	l.main.audio.play_sound("fall", _center, 4.0, 0.6)
	l.main.shake_camera(0.6, _center)


func in_active(delta: float) -> void:
	var k := clampf(t / d.active, 0.0, 1.0)
	var r: float = d.r_max * (1.0 - pow(1.0 - k, 2.0))
	_g.r_out = r
	_g.r_in = maxf(0.0, r - 1.6)
	_dust -= delta
	if _dust <= 0.0:
		_dust = 0.05
		# Dust and stones along the wave front.
		for i in 3:
			var a := randf() * TAU
			var p := _center + Vector3(cos(a), 0, sin(a)) * r
			l.main.vfx.burst("dust" if i < 2 else "debris", p, Vector3.UP, Color(0, 0, 0, 0), 0.7)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = t / d.startup
			return {"stretch": 1.0 + 0.2 * k, "height": 0.5 * k, "tilt": -0.15 * k}
		"active":
			return {"stretch": 0.8 if t < 0.12 else 0.95, "height": 0.0, "tilt": 0.1}
	return {}
