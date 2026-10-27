extends Action
## Solar Beam: a long, very visible charge. A beam of light comes down from the sky onto
## the flower, a sun forms in it and the ground marks the line the beam will follow.
## While charging it turns slowly (it can be circled or punished). On release, a huge
## straight beam that knocks down. Long recovery.

var _pillar: MeshInstance3D
var _sun: Node3D
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _spark := 0.0


func on_start() -> void:
	turn_mult = d.charge_turn
	play_sound("solarbeam_charge", -2.0)
	var vfx: Vfx = l.main.vfx
	_pillar = vfx.beam(Color(1.0, 0.92, 0.55), 0.35, Color(1.0, 1.0, 0.9), 2.0)
	_sun = vfx.pixel_ball("sun_ball", 6, 0.75, Color(1.0, 0.72, 0.2), 8.0)
	# Line on the ground: where the beam will go. Pulses slowly (under 2 times per second).
	_line = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_line.mesh = pm
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.albedo_color = Color(1.0, 0.92, 0.5, 0.0)
	_line.material_override = _line_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vfx.add_child(_line)


func _flower() -> Vector3:
	return l.point("locator_special") + Vector3.UP * 0.35


func _dir() -> Vector3:
	return aim(0.3)


func _reach(from_pos: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir * d.length, 1)
	var r: Dictionary = l.main.get_world_3d().direct_space_state.intersect_ray(q)
	return from_pos.distance_to(r.position) if not r.is_empty() else float(d.length)


func in_startup(delta: float) -> void:
	# On the frame it is released the charge has already been removed.
	if phase != "startup" or not is_instance_valid(_line):
		return
	var k: float = clampf(t / d.startup, 0.0, 1.0)
	tint_col = Color(1.0, 0.9, 0.5)
	tint_k = 0.4 * k
	var flower := _flower()
	var vfx: Vfx = l.main.vfx
	if is_instance_valid(_pillar):
		vfx.place_beam(_pillar, flower + Vector3.UP * 30.0, flower, 0.3 + 1.2 * k)
	if is_instance_valid(_sun):
		_sun.global_position = flower
		_sun.scale = Vector3.ONE * (0.5 + 1.3 * k)
	# Ground line the beam will follow.
	var dir := _dir()
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var length := _reach(flower, dir)
	var center: Vector3 = l.global_position + dir * (l.data.radius + length * 0.5)
	center.y = l.main.ground_y + 0.05
	_line.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(d.radius * 2.0, 1.0, length)), center)
	_line_mat.albedo_color.a = (0.12 + 0.2 * k) * (0.75 + 0.25 * sin(t * TAU * 1.5))
	# Light gathers in the flower.
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.05
		var from_pos := flower + Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * randf_range(1.5, 2.5)
		vfx.burst("stars", from_pos, (flower - from_pos).normalized(), Color(0, 0, 0, 0), 0.25)
		if randf() < 0.3:
			vfx.burst("leaves", l.global_position, Vector3.UP, Color(0, 0, 0, 0), 0.3)


func on_active() -> void:
	turn_mult = 0.0
	var flower := _flower()
	var dir := _dir()
	var o := flower + dir * 0.5
	var length := _reach(o, dir)
	var end_pos := o + dir * length
	hit({"shape": "capsule", "local": false, "a": o, "b": end_pos, "radius": d.radius})
	var vfx: Vfx = l.main.vfx
	_beam = vfx.beam(Color(1.0, 0.85, 0.4), 0.75, Color(1.0, 1.0, 0.92), 16.0)
	vfx.place_beam(_beam, o, end_pos, 1.0)
	vfx.light(o + dir * 2.0, Color(1.0, 0.9, 0.55), 6.0, 10.0, 0.4)
	vfx.distortion(o + dir * 3.0, 6.0, 0.4, 0.05)
	vfx.cobble("leafstorm_actorwind", o, end_pos, l.data.height)
	_remove_charge()
	l.velocity -= dir * 3.0
	l.main.shake_camera(0.35, o)
	play_sound("solarbeam", 2.0)


func in_active(_delta: float) -> void:
	if is_instance_valid(_beam):
		var k: float = t / d.active
		_beam.scale.x = 1.0 + 0.15 * sin(total * 50.0)
		if k > 0.6:
			l.main.vfx.stop_beam(_beam, d.active * 0.5)
			_beam = null


func _remove_charge() -> void:
	if is_instance_valid(_pillar):
		l.main.vfx.stop_beam(_pillar, 0.2)
	_pillar = null
	if is_instance_valid(_sun):
		_sun.queue_free()
	_sun = null
	if is_instance_valid(_line):
		_line.queue_free()
	_line = null


func on_recovery() -> void:
	tint_k = 0.0
	remove_hits()


func on_end(_i: bool) -> void:
	_remove_charge()
	if is_instance_valid(_beam):
		l.main.vfx.stop_beam(_beam, 0.1)


func pose() -> Dictionary:
	match phase:
		"startup":
			var k: float = t / d.startup
			return {"tilt": -0.2 * k, "stretch": 0.94 - 0.04 * k}
		"active":
			return {"tilt": -0.1 + 0.03 * sin(total * 40.0), "stretch": 1.06}
	return {"tilt": 0.1 * (1.0 - t / d.recovery), "stretch": 0.97}
