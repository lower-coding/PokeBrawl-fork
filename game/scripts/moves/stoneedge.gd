extends Action
## Stone Edge: Garchomp strikes the ground; during the startup, cracks open in a line
## toward the rival (the line is then locked) and rock spikes burst out one after
## another along it. Each spike launches whoever stands on it; the rival only takes one
## hit even if it touches several. Avoid it by leaving the line or jumping the spike.

var _dir := Vector3.FORWARD
var _origin_pos := Vector3.ZERO
var _exits := 0
var _on_hit := false
var _spikes: Array = []


func on_start() -> void:
	turn_mult = 2.5
	play_sound("charge", -10.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.rock
	tint_k = 0.25 * (t / d.startup)
	# The line locks halfway through the startup; before that it follows the rival.
	if t < d.startup * 0.5 or _origin_pos == Vector3.ZERO:
		var a := aim(0.9)
		_dir = Vector3(a.x, 0, a.z).normalized()
		_origin_pos = l.global_position + _dir * (l.data.radius + 0.9)
		_origin_pos.y = l.main.ground_y
	if t >= d.startup * 0.5 and not has_meta("cracks"):
		set_meta("cracks", true)
		for i in d.spikes:
			l.main.vfx.mark(_origin_pos + _dir * (i * d.spacing), "crack", 0.8, d.startup + d.active + 0.8)


func on_active() -> void:
	l.main.shake_camera(0.15, l.global_position)
	play_sound("stoneedge", 0.0)


func in_active(_delta: float) -> void:
	var should := int(clampf(t / d.active, 0.0, 1.0) * d.spikes) + 1
	while _exits < mini(should, d.spikes):
		_spike(_origin_pos + _dir * (_exits * d.spacing))
		_exits += 1


func _spike(p: Vector3) -> void:
	var g := hit({"shape": "sphere", "local": false, "center": p + Vector3.UP * 0.7, "radius": d.radius, "lifetime": 0.12})
	g.on_strike = func(_o, _r): _on_hit = true
	if _on_hit:
		g.active = false
	# Rock spike: rises fast, stays for a moment and sinks.
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.42
	cm.height = 1.8
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8d7a62")
	m.roughness = 0.95
	mi.material_override = m
	var vfx: Vfx = l.main.vfx
	vfx.add_child(mi)
	mi.global_position = p + Vector3.DOWN * 0.9
	mi.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
	vfx.live(mi, 1.1, func(k: float):
		var y: float = -0.9 + 1.8 * clampf(k / 0.12, 0.0, 1.0) - 1.8 * clampf((k - 0.7) / 0.3, 0.0, 1.0)
		mi.global_position = p + Vector3.UP * y)
	vfx.burst("debris", p, Vector3.UP, Color(0, 0, 0, 0), 0.8)
	vfx.burst("dust", p, Vector3.UP, Color(0, 0, 0, 0), 0.6)
	l.main.audio.play_sound("stoneedge_hit", p, -6.0)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2 * (t / d.startup), "stretch": 1.05, "anim": "physical_blunt" if t < 0.05 else ""}
		"active":
			return {"tilt": 0.35, "stretch": 0.92}
	return {"tilt": 0.1}
