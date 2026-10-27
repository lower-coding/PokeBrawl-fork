extends Action
## Hydro Pump: the cannons charge (swirling water, audible) and, while held, a
## high-pressure stream fires in a straight line from both. Pushes very hard and hits
## several times; while firing it cannot move and turns very slowly. The stream stops at
## walls. It ends when energy runs out.

var _g: Hit
var _beam: MeshInstance3D
var _foam: GPUParticles3D
var _sound_t := 0.0
var _drop := 0.0


func on_start() -> void:
	turn_mult = 1.6
	play_sound("charge", -10.0)


func _cannons() -> Array:
	return [l.point("locator_cannon_left"), l.point("locator_cannon_right")]


func _origin_pos() -> Vector3:
	var c := _cannons()
	return (c[0] + c[1]) * 0.5 + l.forward() * 0.3


func _dir() -> Vector3:
	return aim_stream(_origin_pos())


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.3 * (t / d.startup)
	_drop -= delta
	if _drop <= 0.0:
		_drop = 0.05
		for c in _cannons():
			l.main.vfx.burst("water_fx", c, Vector3.UP, Color(0, 0, 0, 0), 0.35)


## How far the stream reaches: the nearest wall along its line.
func _reach(from_pos: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir * d.length, 1)
	var r: Dictionary = l.main.get_world_3d().direct_space_state.intersect_ray(q)
	return from_pos.distance_to(r.position) if not r.is_empty() else float(d.length)


func on_active() -> void:
	turn_mult = d.emit_turn
	var o := _origin_pos()
	var dir := _dir()
	var length := _reach(o, dir)
	_g = hit({"shape": "capsule", "local": false, "a": o, "b": o + dir * length, "radius": d.radius,
		"interval": d.interval})
	_beam = l.main.vfx.beam(Color(0.35, 0.65, 1.0), 0.32, Color(0.9, 0.97, 1.0), 9.0)
	_foam = l.main.vfx.continuous_emitter("water_fx", 120, 0.45, Vector2(3.0, 8.0), 60.0, Vector2(0.1, 0.3))
	l.velocity -= dir * 2.5
	play_sound("hydropump", 0.0)


func in_active(delta: float) -> void:
	l.energy -= d.drain * delta
	if l.energy <= 0.0:
		l.energy = 0.0
		_go_to("recovery")
		return
	var o := _origin_pos()
	var dir := _dir()
	var length := _reach(o, dir)
	_g.a = o
	_g.b = o + dir * length
	if is_instance_valid(_beam):
		var thickness := 1.0 + 0.12 * sin(total * 40.0)
		l.main.vfx.place_beam(_beam, o, o + dir * length, thickness)
	if is_instance_valid(_foam):
		_foam.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), o + dir * length)
	# Recoil pushes it back a little while firing.
	l.velocity.x = -dir.x * 0.8
	l.velocity.z = -dir.z * 0.8
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = 0.5
		play_sound("hydropump", -4.0)
		l.main.shake_camera(0.06, o)
	tint_k = 0.15


func on_recovery() -> void:
	_turn_off()
	tint_k = 0.0
	turn_mult = 0.6


func on_end(_i: bool) -> void:
	_turn_off()


func _turn_off() -> void:
	if is_instance_valid(_beam):
		l.main.vfx.stop_beam(_beam, 0.18)
	_beam = null
	l.main.vfx.stop_emitter(_foam)
	_foam = null


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2 * (t / d.startup), "stretch": 0.94, "anim": "special"}
		"active":
			return {"tilt": -0.12 + 0.02 * sin(total * 45.0), "stretch": 0.97}
	return {"tilt": 0.05}
