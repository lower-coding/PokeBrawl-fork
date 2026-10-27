extends Action
## Ice Beam: the cannons frost over (you can see it coming) and a short straight beam
## fires, hitting along its whole line and chilling the rival (slowed). Where it passes
## it leaves a strip of ice on the ground for a few seconds: whoever steps on it is
## slowed. This is how Blastoise splits the field in two.

var _beam: MeshInstance3D
var _frost := 0.0
var _done := false


func on_start() -> void:
	turn_mult = 2.0
	play_sound("charge", -12.0)


func _origin_pos() -> Vector3:
	var a := l.point("locator_cannon_left")
	var b := l.point("locator_cannon_right")
	return (a + b) * 0.5 + l.forward() * 0.3


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.ice
	tint_k = 0.35 * (t / d.startup)
	_frost -= delta
	if _frost <= 0.0:
		_frost = 0.06
		for loc in ["locator_cannon_left", "locator_cannon_right"]:
			l.main.vfx.burst("steam", l.point(loc), Vector3.UP, Color(0, 0, 0, 0), 0.3)
			l.main.vfx.burst("ice_fx", l.point(loc), l.forward(), Color(0, 0, 0, 0), 0.25)


func on_active() -> void:
	var o := _origin_pos()
	var dir := aim(0.6)
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * d.length, 1)
	var r: Dictionary = l.main.get_world_3d().direct_space_state.intersect_ray(q)
	var end_point: Vector3 = r.position if not r.is_empty() else o + dir * d.length
	hit({"shape": "capsule", "local": false, "a": o, "b": end_point, "radius": d.radius})
	var vfx: Vfx = l.main.vfx
	_beam = vfx.beam(Color(0.55, 0.9, 1.0), 0.2, Color(0.95, 1.0, 1.0), 14.0)
	vfx.place_beam(_beam, o, end_point, 1.0)
	vfx.light(o, Roster.TYPE_COLOR.ice, 3.0, 5.0, 0.2)
	vfx.cobble("icebeam_actorspray", o, end_point, l.data.height)
	_stripe(o, end_point)
	play_sound("icebeam", 0.0)
	l.velocity -= dir * 1.5


## The ice strip: marks on the ground along the beam and a zone that slows whoever
## steps on it while it lasts.
func _stripe(from_pos: Vector3, to_pos: Vector3) -> void:
	var main: Node = l.main
	var ground: float = main.ground_y
	var a := Vector3(from_pos.x, ground, from_pos.z)
	var b := Vector3(to_pos.x, ground, to_pos.z)
	var length := a.distance_to(b)
	var n := int(length / 1.2)
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxf(n, 1))
		main.vfx.mark(p, "frost", d.ice_width * randf_range(0.9, 1.2), d.ice_dur)
	var user := l
	var width: float = d.ice_width
	var zone := Node3D.new()
	main.vfx.add_child(zone)
	main.vfx.live(zone, d.ice_dur, func(_k: float):
		for o in main.fighters:
			if o == user or not is_instance_valid(o) or not o.on_floor():
				continue
			var pos: Vector3 = o.global_position
			var p := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, ground, pos.z), a, b)
			if p.distance_to(Vector3(pos.x, ground, pos.z)) < width + o.radius() * 0.5:
				o.slow_down(0.6, 0.4))


func in_active(_delta: float) -> void:
	if is_instance_valid(_beam) and t > d.active * 0.5 and not _done:
		_done = true
		l.main.vfx.stop_beam(_beam, d.active * 0.6)


func on_recovery() -> void:
	tint_k = 0.0
	remove_hits()


func on_end(_i: bool) -> void:
	if is_instance_valid(_beam) and not _done:
		l.main.vfx.stop_beam(_beam, 0.1)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.15 * (t / d.startup), "stretch": 0.95, "anim": "special"}
		"active":
			return {"tilt": -0.18, "stretch": 1.02}
	return {"tilt": 0.05}
