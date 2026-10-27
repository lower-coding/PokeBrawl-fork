extends Action
## Body Slam: crouches, jumps and lands with all its weight. During the startup and the
## jump it has armor (light hits do not interrupt it). After landing it stays down for a
## good while: that is the punish window.

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _warning: MeshInstance3D


func on_start() -> void:
	turn_mult = 1.2
	play_sound("charge", -12.0)


func in_startup(_delta: float) -> void:
	tint_col = Color(1, 0.85, 0.6)
	tint_k = 0.15 * (t / d.startup)
	if t > d.startup * 0.5 and _warning == null:
		_compute_target()
		_warning = l.main.vfx.telegraph(_to, 2.8, d.startup * 0.5 + d.active, Color(1.0, 0.55, 0.25))


func _compute_target() -> void:
	_from = l.global_position
	var dist: float = d.dist
	if l.rival and is_instance_valid(l.rival):
		dist = clampf(Vector2(l.rival.global_position.x - _from.x, l.rival.global_position.z - _from.z).length(), 2.0, d.dist)
	_to = _from + l.forward() * dist
	_to.y = l.main.ground_y


func on_active() -> void:
	if _warning == null:
		_compute_target()
	faces_rival = false
	no_gravity = true
	no_brake = true
	play_sound("bodyslam", 0.0)
	l.main.vfx.dust(l.global_position, 2.0)


func in_active(_delta: float) -> void:
	var k := clampf(t / d.active, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	p.y = _from.y + sin(k * PI) * 3.2
	l.velocity = (p - l.global_position) / maxf(l.get_physics_process_delta_time(), 0.001)
	if k >= 1.0:
		_landing()


func _landing() -> void:
	l.velocity = Vector3.ZERO
	hit({"shape": "sphere", "local": false, "center": l.global_position + Vector3.UP * 0.5, "radius": 2.8, "lifetime": 0.06})
	var p := l.global_position
	var vfx: Vfx = l.main.vfx
	vfx.wave(p, 4.5, 0.4, Color(0.95, 0.85, 0.65), 0.1)
	vfx.distortion(p + Vector3.UP * 0.5, 7.0, 0.35, 0.05)
	vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 2.5)
	vfx.burst("debris", p, Vector3.UP, Color(0, 0, 0, 0), 1.0)
	vfx.mark(p, "crack", 2.2, 5.0)
	vfx.cobble("bodyslam_impactfloor", p, l.rival.center() if l.rival else null, l.data.height)
	vfx.cobble("bodyslam_actor_smoke", p, null, l.data.height)
	l.main.audio.play_sound("fall", p, 2.0, 0.7)
	l.main.audio.play_sound("bodyslam_hit", p, 0.0)
	l.main.shake_camera(0.5, p)


func on_recovery() -> void:
	no_gravity = false
	no_brake = false
	tint_k = 0.0


func on_end(_i: bool) -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = t / d.startup
			return {"stretch": 1.0 - 0.28 * k, "tilt": -0.1 * k}
		"active":
			return {"stretch": 1.15 if t < d.active * 0.5 else 0.9, "tilt": 0.3 + t / d.active * 0.9}
	var r: float = t / d.recovery
	return {"tilt": lerpf(1.2, 0.0, smoothstep(0.5, 1.0, r)), "stretch": 0.85 + 0.15 * r}
