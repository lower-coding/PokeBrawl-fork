class_name Vfx
extends Node3D
## Battle visual effects. Kept apart from the logic: nothing here deals damage.
## Each effect stacks layers instead of a single recolored particle:
##   impact     flash with rays + distortion ring + short light + particles of the
##              type's material + Cobblemon's pixel impact for the type
##   burst      GPU particles per material (sparks with trails, Cobblemon's animated
##              fire, smoke, dust, drops, frost, debris, leaves, shadow...)
##   bolt       jagged lightning rebuilt every few frames
##   beam       a continuous stream or beam with moving noise
##   ribbon     trail of claws and tails
##   wave       ring that spreads across the ground
##   mark       a burn, crack or frost on the ground that fades out
##   afterimage silhouette of the Pokémon in its current pose (dodges)
## Emitters, lights and texts are reused (not created on every hit).

const TEX := "res://fx/tex/generic/"
const BY_TYPE := {
	"electric": ["sparks", "stars"], "fire": ["fire_fx", "embers"], "water": ["water_fx", "steam"],
	"ice": ["ice_fx", "steam"], "grass": ["leaves"], "ground": ["debris", "dust"], "rock": ["debris", "dust"],
	"steel": ["sparks_metal", "stars"], "ghost": ["shadow"], "poison": ["shadow"], "dark": ["shadow"],
	"dragon": ["sparks_dragon", "shadow"], "psychic": ["stars"], "fairy": ["stars"],
	"flying": ["wind"], "normal": ["dust", "stars"], "fighting": ["dust", "stars"], "bug": ["leaves"],
}

var main: Node
var _pools := {}
var _lights: Array = []
var _texts: Array = []
var _noise: NoiseTexture2D
var _shaders := {}
var _living: Array = []        # effects with their own life: {node, t, dur, step: Callable}
var reduced := false         # accessibility option: less shaking


func _ready() -> void:
	_noise = NoiseTexture2D.new()
	_noise.width = 128
	_noise.height = 128
	_noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.04
	fn.fractal_octaves = 3
	_noise.noise = fn
	for i in 8:
		var o := OmniLight3D.new()
		o.visible = false
		o.shadow_enabled = false
		o.omni_range = 4.0
		add_child(o)
		_lights.append({"light": o, "t": 0.0, "dur": 0.0, "e": 0.0})
	for i in 24:
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.font = main.font(true)
		lb.font_size = 56
		lb.outline_size = 14
		lb.pixel_size = 0.0011
		lb.visible = false
		add_child(lb)
		_texts.append({"lb": lb, "t": 0.0, "dur": 0.0, "v": Vector3.ZERO})


func shader(key: String, source: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = source
		_shaders[key] = s
	return _shaders[key]


func mat(key: String, source: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(key, source)
	for k in params:
		m.set_shader_parameter(k, params[k])
	if source == VfxShaders.BEAM or source == VfxShaders.ORB:
		m.set_shader_parameter("noise", _noise)
	return m


# ---------------------------------------------------------------- particles

## Data for each particle material.
func _preset(key: String) -> Dictionary:
	match key:
		"sparks":
			return {"n": 26, "lifetime": 0.42, "streak": Vector2(0.05, 0.42), "v": [6.0, 15.0], "spread": 80.0, "g": -8.0, "damp": 3.0, "e": 4.0, "color": Color(1.0, 0.92, 0.45)}
		"sparks_metal":
			return {"n": 22, "lifetime": 0.38, "streak": Vector2(0.04, 0.35), "v": [7.0, 16.0], "spread": 75.0, "g": -14.0, "damp": 2.0, "e": 3.5, "color": Color(1.0, 0.95, 0.85)}
		"sparks_dragon":
			return {"n": 22, "lifetime": 0.5, "streak": Vector2(0.06, 0.4), "v": [5.0, 12.0], "spread": 80.0, "g": -3.0, "damp": 3.0, "e": 3.5, "color": Color(0.65, 0.45, 1.0)}
		"embers":
			return {"n": 18, "lifetime": 0.9, "streak": Vector2(0.04, 0.16), "v": [2.0, 6.0], "spread": 60.0, "g": 3.0, "damp": 1.5, "e": 1.8, "color": Color(1.0, 0.5, 0.12)}
		"water_fx":
			return {"n": 26, "lifetime": 0.55, "streak": Vector2(0.07, 0.3), "v": [4.0, 10.0], "spread": 70.0, "g": -18.0, "damp": 0.5, "e": 1.6, "color": Color(0.6, 0.85, 1.0)}
		"wind":
			return {"n": 16, "lifetime": 0.35, "streak": Vector2(0.05, 0.9), "v": [8.0, 14.0], "spread": 60.0, "g": 0.0, "damp": 6.0, "e": 1.4, "color": Color(0.9, 0.95, 1.0, 0.7)}
		"fire_fx":
			return {"n": 16, "lifetime": 0.6, "tex": "fire/cloudyfire_white.png", "frames": Vector2i(10, 1), "add": false, "v": [1.0, 3.5],
				"spread": 50.0, "g": 3.0, "damp": 2.0, "e": 1.5, "dims": [0.5, 1.0],
				"ramp": [Color(1.0, 0.86, 0.35), Color(1.0, 0.5, 0.1), Color(0.75, 0.16, 0.04, 0.9), Color(0.25, 0.08, 0.05, 0.0)]}
		"smoke":
			return {"n": 10, "lifetime": 1.2, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [0.5, 1.6],
				"spread": 60.0, "g": 1.0, "damp": 1.5, "e": 1.0, "dims": [0.8, 1.6],
				"ramp": [Color(0.35, 0.33, 0.32, 0.8), Color(0.25, 0.24, 0.24, 0.0)]}
		"dust":
			return {"n": 12, "lifetime": 0.7, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [1.5, 4.0],
				"spread": 85.0, "g": 0.5, "damp": 4.0, "e": 1.0, "dims": [0.4, 0.9],
				"ramp": [Color(0.86, 0.8, 0.7, 0.75), Color(0.8, 0.75, 0.66, 0.0)]}
		"steam":
			return {"n": 10, "lifetime": 0.8, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": false, "v": [1.0, 3.0],
				"spread": 80.0, "g": 1.0, "damp": 3.0, "e": 1.0, "dims": [0.5, 1.1],
				"ramp": [Color(0.8, 0.95, 1.0, 0.6), Color(0.6, 0.85, 1.0, 0.0)]}
		"ice_fx":
			return {"n": 14, "lifetime": 0.7, "tex": "ice/iceshard.png", "frames": Vector2i(3, 1), "add": true, "v": [4.0, 9.0],
				"spread": 75.0, "g": -12.0, "damp": 1.0, "e": 2.0, "dims": [0.25, 0.45], "turn": 360.0,
				"ramp": [Color(0.9, 1.0, 1.0), Color(0.6, 0.9, 1.0, 0.0)]}
		"leaves":
			return {"n": 12, "lifetime": 0.9, "tex": "grass/leaf.png", "frames": Vector2i(1, 4), "add": false, "v": [3.0, 7.0],
				"spread": 80.0, "g": -4.0, "damp": 2.5, "e": 1.0, "dims": [0.25, 0.4], "turn": 540.0,
				"ramp": [Color(0.75, 1.0, 0.6), Color(0.5, 0.85, 0.4, 0.0)]}
		"shadow":
			return {"n": 12, "lifetime": 0.8, "tex": "smoke/smoke.png", "frames": Vector2i(1, 6), "add": true, "v": [1.0, 3.0],
				"spread": 80.0, "g": 1.5, "damp": 2.0, "e": 1.6, "dims": [0.5, 1.0],
				"ramp": [Color(0.75, 0.45, 1.0, 0.8), Color(0.3, 0.1, 0.45, 0.0)]}
		"stars":
			return {"n": 8, "lifetime": 0.5, "tex": "sparkle/glowingsparkle.png", "frames": Vector2i(1, 4), "add": true, "v": [3.0, 7.0],
				"spread": 80.0, "g": -6.0, "damp": 2.0, "e": 2.5, "dims": [0.18, 0.32],
				"ramp": [Color(1, 1, 1), Color(1, 1, 0.8, 0.0)]}
		"debris":
			return {"n": 14, "lifetime": 0.9, "cubes": true, "v": [4.0, 9.0], "spread": 55.0, "g": -22.0, "damp": 0.3, "dims": [0.08, 0.2], "turn": 720.0,
				"color": Color(0.55, 0.45, 0.35)}
	return {}


func _create_emitter(key: String) -> GPUParticles3D:
	var p: Dictionary = _preset(key)
	var e := GPUParticles3D.new()
	e.amount = p.n
	e.lifetime = p.lifetime
	e.one_shot = true
	e.explosiveness = 0.95
	e.local_coords = false
	e.emitting = false
	e.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = p.spread
	pm.initial_velocity_min = p.v[0]
	pm.initial_velocity_max = p.v[1]
	pm.gravity = Vector3(0, p.g, 0)
	pm.damping_min = p.damp
	pm.damping_max = p.damp * 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.15))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	if p.has("ramp"):
		var gr := Gradient.new()
		gr.colors = PackedColorArray(p.ramp)
		var offs := PackedFloat32Array()
		for i in p.ramp.size():
			offs.append(float(i) / (p.ramp.size() - 1))
		gr.offsets = offs
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
	elif p.has("color"):
		pm.color = p.color
	if p.has("turn"):
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -p.turn
		pm.angular_velocity_max = p.turn
	if p.has("streak"):
		pm.particle_flag_align_y = true
		var q := QuadMesh.new()
		q.size = p.streak
		q.material = mat("streak", VfxShaders.STREAK, {"energy": p.e})
		e.draw_pass_1 = q
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		var gr2 := Gradient.new()
		gr2.colors = PackedColorArray([p.color, Color(p.color.r, p.color.g, p.color.b, 0.0)])
		var gt2 := GradientTexture1D.new()
		gt2.gradient = gr2
		pm.color_ramp = gt2
	elif p.get("cubes", false):
		var bx := BoxMesh.new()
		bx.size = Vector3.ONE
		var sm := StandardMaterial3D.new()
		sm.albedo_color = p.color
		sm.roughness = 1.0
		sm.vertex_color_use_as_albedo = false
		bx.material = sm
		e.draw_pass_1 = bx
		pm.scale_min = p.dims[0]
		pm.scale_max = p.dims[1]
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var add: bool = p.get("add", true)
		var code: String = VfxShaders.PARTICLE % ["blend_add" if add else "blend_mix", "filter_nearest"]
		q.material = mat("particle_" + ("add" if add else "mix"), code,
			{"tex": load(TEX + p.tex), "energy": p.e, "h_frames": p.frames.x, "v_frames": p.frames.y})
		e.draw_pass_1 = q
		pm.scale_min = p.dims[0]
		pm.scale_max = p.dims[1]
		pm.anim_speed_min = 1.0
		pm.anim_speed_max = 1.0
	e.process_material = pm
	add_child(e)
	return e


## A burst of one material at a point, in a direction (or upward).
func burst(key: String, pos: Vector3, dir := Vector3.UP, color := Color(0, 0, 0, 0), size_mult := 1.0) -> void:
	if not _pools.has(key):
		_pools[key] = []
	var free: GPUParticles3D = null
	for e in _pools[key]:
		if not e.emitting:
			free = e
			break
	if free == null:
		if _pools[key].size() >= 8:
			free = _pools[key][0]
			_pools[key].push_back(_pools[key].pop_front())
		else:
			free = _create_emitter(key)
			_pools[key].append(free)
	free.global_position = pos
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	free.global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	free.speed_scale = 1.0
	free.scale = Vector3.ONE * size_mult
	if color.a > 0.0:
		(free.process_material as ParticleProcessMaterial).color = color
	free.restart()
	free.emitting = true


func sparks(pos: Vector3, color: Color, n := 1) -> void:
	for i in maxi(1, n / 20):
		burst("sparks", pos, Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), color)


func dust(pos: Vector3, dims := 1.0) -> void:
	burst("dust", pos + Vector3.UP * 0.1, Vector3.UP, Color(0, 0, 0, 0), clampf(dims, 0.5, 2.5))


# ---------------------------------------------------------------- impacts

## Launches a Cobblemon particle piece (game/fx/particles). `facing` is the point it
## faces, like the target in a Cobblemon battle.
func cobble(id: String, pos: Vector3, facing = null, height := 1.0) -> Dictionary:
	if main.fx == null:
		return {}
	return main.fx.play(id, pos, facing, {"height": height, "width": height * 0.8})


func impact(pos: Vector3, type: String, strength: int, contact := true) -> void:
	var col: Color = Roster.TYPE_COLOR.get(type, Color.WHITE)
	var dims := 1.0 + 0.7 * strength
	_flash(pos, col, dims * (0.75 if contact else 0.65), 0.12 + 0.04 * strength)
	light(pos, col, 1.5 + 2.0 * strength, 3.0 + strength * 2.0, 0.1 + 0.05 * strength)
	if strength >= 1 and not reduced:
		distortion(pos, 2.0 + strength * 1.6, 0.3, 0.03 + 0.02 * strength)
	for pr in BY_TYPE.get(type, ["dust"]):
		burst(pr, pos, Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)), Color(0, 0, 0, 0), 0.7 + 0.3 * strength)
	sprite_anim(TEX + "impact/impact_%s.png" % type, pos, 0.55 + 0.2 * strength, Vector2i(1, 7), 0.24, col.lerp(Color.WHITE, 0.3))


func _flash(pos: Vector3, col: Color, dims: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := mat("flash_col", VfxShaders.FLASH, {"color": col, "energy": 2.0, "seed": randf() * 6.0, "bolts": float(randi_range(6, 10))})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * dims
	live(mi, dur, func(k: float): m.set_shader_parameter("t", k); mi.scale = Vector3.ONE * dims * (0.8 + k * 0.6))


func distortion(pos: Vector3, dims: float, dur: float, strength := 0.04) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := mat("distortion", VfxShaders.DISTORTION, {"strength": strength})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * dims
	live(mi, dur, func(k: float): m.set_shader_parameter("t", k))


func light(pos: Vector3, col: Color, energy: float, reach: float, dur: float) -> void:
	var l: Dictionary = _lights[0]
	for c in _lights:
		if c.t >= c.dur:
			l = c
			break
	l.light.global_position = pos
	l.light.light_color = col
	l.light.omni_range = reach
	l.light.visible = true
	l.t = 0.0
	l.dur = dur
	l.e = energy


## One-shot pixel animation (Cobblemon's impacts).
func sprite_anim(file_path: String, pos: Vector3, dims: float, frames: Vector2i, dur: float, col := Color.WHITE) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := mat("sprite", VfxShaders.SPRITE, {"tex": load(file_path), "energy": 1.5, "h_frames": frames.x, "v_frames": frames.y, "color": col})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * dims
	var total := frames.x * frames.y
	live(mi, dur, func(k: float): m.set_shader_parameter("frame", mini(int(k * total), total - 1)))


func armor(l: Node) -> void:
	var c: Vector3 = l.center()
	_flash(c, Color(1.0, 0.65, 0.2), l.data.height * 1.3, 0.14)
	burst("sparks_metal", c, Vector3.UP, Color(1.0, 0.7, 0.3))
	main.audio.play_sound("armor", c, -2.0)


# ---------------------------------------------------------------- texts

func text(pos: Vector3, s: String, col: Color, dims := 0.75) -> void:
	_text(pos + Vector3.UP * 0.5, s, col, 0.9, dims, Vector3(randf_range(-0.2, 0.2), 1.2, 0))


func number(pos: Vector3, damage: float, affinity: float) -> void:
	var col := Color(1, 1, 1)
	if affinity > 1.05:
		col = Color("ffd93a")
	elif affinity < 0.95:
		col = Color("a9adb8")
	_text(pos + Vector3(randf_range(-0.3, 0.3), 0.3, 0), str(int(round(damage))), col, 0.7, 1.15 if damage > 90 else 0.9,
		Vector3(randf_range(-0.6, 0.6), 2.2, 0))


func _text(pos: Vector3, s: String, col: Color, dur: float, dims: float, v: Vector3) -> void:
	var c: Dictionary = _texts[0]
	for x in _texts:
		if x.t >= x.dur:
			c = x
			break
	if c == _texts[0]:
		_texts.push_back(_texts.pop_front())
	c.lb.text = s
	c.lb.modulate = col
	c.lb.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	c.lb.global_position = pos
	c.lb.pixel_size = 0.0011 * dims
	c.lb.visible = true
	c.t = 0.0
	c.dur = dur
	c.v = v


# ---------------------------------------------------------------- lasting shapes

## Removes everything in progress (when going back to the menu: many effects follow a
## Pokémon that stops existing).
func clear() -> void:
	for v in _living:
		if is_instance_valid(v.node):
			v.node.queue_free()
	_living.clear()
	if main.fx:
		main.fx.clear()


## Registers a node that lives "dur" seconds; "step" receives the progress from 0 to 1.
func live(node: Node3D, dur: float, step := Callable()) -> void:
	_living.append({"node": node, "t": 0.0, "dur": dur, "step": step})


func _process(delta: float) -> void:
	var i := 0
	while i < _living.size():
		var v: Dictionary = _living[i]
		v.t += delta
		if not is_instance_valid(v.node):
			_living.remove_at(i)
			continue
		var k := clampf(v.t / maxf(v.dur, 0.001), 0.0, 1.0)
		if v.step.is_valid():
			v.step.call(k)
		if v.t >= v.dur:
			v.node.queue_free()
			_living.remove_at(i)
		else:
			i += 1
	for l in _lights:
		if l.t < l.dur:
			l.t += delta
			var k: float = clampf(l.t / l.dur, 0.0, 1.0)
			l.light.light_energy = l.e * (1.0 - k) * (1.0 - k)
			if l.t >= l.dur:
				l.light.visible = false
	for c in _texts:
		if c.t < c.dur:
			c.t += delta
			c.lb.global_position += c.v * delta
			c.v.y -= 4.0 * delta
			var k: float = c.t / c.dur
			c.lb.modulate.a = 1.0 - smoothstep(0.6, 1.0, k)
			c.lb.outline_modulate.a = c.lb.modulate.a * 0.9
			if c.t >= c.dur:
				c.lb.visible = false


## Jagged lightning between two points. Rebuilt every 0.07 s while it lasts (in jumps,
## like a frame strip, not smoothly).
func bolt(a: Vector3, b: Vector3, col: Color, dur := 0.15, width := 0.18, branches := 2) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = mat("lightning", VfxShaders.LIGHTNING, {"color": col, "energy": 5.0})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var state := {"t": 0.0}
	_draw_bolt(im, a, b, width, branches, 1.0)
	live(mi, dur, func(k: float):
		state.t += get_process_delta_time()
		if state.t > 0.07:
			state.t = 0.0
			_draw_bolt(im, a, b, width * (1.0 - k * 0.5), branches, 1.0 - k))


func _draw_bolt(im: ImmediateMesh, a: Vector3, b: Vector3, width: float, branches: int, opacity: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam := get_viewport().get_camera_3d()
	var points := _zigzag(a, b, maxi(6, int(a.distance_to(b) * 2.5)), a.distance_to(b) * 0.09)
	_ribbon(im, points, width, opacity, cam)
	for r in branches:
		var i0 := randi_range(1, points.size() - 2)
		var p0: Vector3 = points[i0]
		var end_pos := p0 + (b - a).normalized().rotated(Vector3.UP, randf_range(-0.9, 0.9)) * a.distance_to(b) * randf_range(0.15, 0.3) \
			+ Vector3(0, randf_range(-0.5, 0.5), 0)
		_ribbon(im, _zigzag(p0, end_pos, 4, p0.distance_to(end_pos) * 0.15), width * 0.5, opacity * 0.8, cam)
	im.surface_end()


func _zigzag(a: Vector3, b: Vector3, n: int, deviation: float) -> Array:
	var out := [a]
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir)
	for i in range(1, n):
		var k := float(i) / n
		var amp := deviation * sin(k * PI)
		out.append(a.lerp(b, k) + side * randf_range(-amp, amp) + up * randf_range(-amp, amp))
	out.append(b)
	return out


func _ribbon(im: ImmediateMesh, pts: Array, width: float, opacity: float, cam: Camera3D) -> void:
	var eye := cam.global_position if cam else Vector3(0, 10, 10)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0).normalized()
		var side := d.cross((eye - p0).normalized()).normalized() * width * 0.5
		var c := Color(1, 1, 1, opacity)
		for v in [[p0 - side, Vector2(0, 0)], [p0 + side, Vector2(0, 1)], [p1 + side, Vector2(1, 1)],
				[p0 - side, Vector2(0, 0)], [p1 + side, Vector2(1, 1)], [p1 - side, Vector2(1, 0)]]:
			im.surface_set_color(c)
			im.surface_set_uv(v[1])
			im.surface_add_vertex(v[0])


## Continuous beam (water stream, ice beam...). Returns the node to move it every step
## with "place_beam"; it is turned off with "stop_beam".
func beam(col: Color, radius: float, core := Color.WHITE, flow_speed := 5.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat("beam", VfxShaders.BEAM, {"color": col, "core": core, "energy": 3.0, "flow_speed": flow_speed})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func place_beam(mi: MeshInstance3D, from_pos: Vector3, to_pos: Vector3, thickness := 1.0) -> void:
	var d := to_pos - from_pos
	var length := maxf(d.length(), 0.01)
	var b := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	# The cylinder runs along Y: it is rotated so Y points toward "to".
	b = b * Basis(Vector3.RIGHT, -PI * 0.5)
	# Scale along the cylinder's own axes (scaled() would scale along the world's).
	mi.global_transform = Transform3D(b * Basis.from_scale(Vector3(thickness, length, thickness)), from_pos + d * 0.5)


func stop_beam(mi: MeshInstance3D, dur := 0.15) -> void:
	if not is_instance_valid(mi):
		return
	var m: ShaderMaterial = mi.material_override
	live(mi, dur, func(k: float): m.set_shader_parameter("faded", k))


## Trail following a body point (claw, tail): "points" returns [base, tip] in the world
## every frame.
func ribbon(points: Callable, col: Color, dur: float, point_life := 0.14) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = mat("ribbon", VfxShaders.RIBBON, {"color": col, "energy": 1.7})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var samples: Array = []
	var clock := {"t": 0.0}
	live(mi, dur + point_life, func(_k: float):
		var dt := get_process_delta_time()
		clock.t += dt
		for s in samples:
			s.age_t += dt
		while not samples.is_empty() and samples[0].age_t > point_life:
			samples.pop_front()
		if clock.t <= dur:
			var p: Array = points.call()
			samples.append({"a": p[0], "b": p[1], "age_t": 0.0})
		im.clear_surfaces()
		if samples.size() < 2:
			return
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in samples.size() - 1:
			var s0: Dictionary = samples[i]
			var s1: Dictionary = samples[i + 1]
			var a0: float = 1.0 - s0.age_t / point_life
			var a1: float = 1.0 - s1.age_t / point_life
			for v in [[s0.a, 0.0, a0], [s0.b, 1.0, a0], [s1.b, 1.0, a1], [s0.a, 0.0, a0], [s1.b, 1.0, a1], [s1.a, 0.0, a1]]:
				im.surface_set_color(Color(1, 1, 1, v[2]))
				im.surface_set_uv(Vector2(0, v[1]))
				im.surface_add_vertex(v[0])
		im.surface_end())


## Ring that spreads across the ground up to "radius" in "dur" seconds.
func wave(center: Vector3, radius: float, dur: float, col: Color, thickness := 0.08) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := mat("ring", VfxShaders.RING, {"color": col, "energy": 2.2, "thickness": thickness,
		"cells": clampf(roundf(radius * 16.0), 12.0, 72.0)})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3.UP * 0.05
	live(mi, dur, func(k: float):
		var r := maxf(0.05, radius * (1.0 - pow(1.0 - k, 2.0)))
		mi.scale = Vector3(r, 1.0, r)
		m.set_shader_parameter("t", maxf(0.0, (k - 0.6) / 0.4)))


## Mark on the ground (burn, crack, frost) that fades out.
func mark(pos: Vector3, kind: String, radius: float, dur := 4.0) -> void:
	var d := Decal.new()
	d.texture_albedo = _mark_tex(kind)
	d.size = Vector3(radius * 2.0, 1.0, radius * 2.0)
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	add_child(d)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	live(d, dur, func(k: float): d.modulate.a = 1.0 - smoothstep(0.6, 1.0, k))


var _marks := {}

func _mark_tex(kind: String) -> Texture2D:
	if _marks.has(kind):
		return _marks[kind]
	# Painted at 32 px, like a Cobblemon texture.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind)
	for y in 32:
		for x in 32:
			var p := Vector2(x - 15.5, y - 15.5)
			var dist := p.length() / 16.0
			var n := r.randf()
			var a := 0.0
			var c := Color.BLACK
			match kind:
				"burned":
					a = clampf(1.0 - dist + n * 0.25, 0.0, 1.0) * 0.85
					c = Color(0.08, 0.05, 0.04)
				"crack":
					var ang := atan2(p.y, p.x)
					var bolts := absf(sin(ang * 3.5 + n * 0.3))
					a = (1.0 if bolts > 0.93 and dist < 0.95 else 0.0) + clampf(0.5 - dist * 2.0, 0.0, 1.0)
					c = Color(0.12, 0.1, 0.09)
				"frost":
					a = clampf(1.0 - dist + n * 0.3, 0.0, 1.0) * 0.8
					c = Color(0.8, 0.95, 1.0) if n > 0.4 else Color(0.6, 0.85, 1.0)
				"poison_puddle":
					# Puddle with ragged edges, purple with light bubbles.
					var edge := 0.82 + 0.12 * sin(atan2(p.y, p.x) * 5.0 + n * 0.5)
					a = (0.85 if dist < edge else 0.0)
					c = Color(0.42, 0.2, 0.55) if n > 0.12 else Color(0.75, 0.5, 0.9)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_marks[kind] = t
	return t


## Silhouette of the fighter in its current pose (dodges, speed).
func afterimage(l: Node, col := Color(0.6, 0.8, 1.0)) -> void:
	var skel: Skeleton3D = l.model.skel
	var copy: Node3D = skel.duplicate(0)
	for h in copy.get_children():
		if h is SkeletonModifier3D:
			h.queue_free()
	var m := mat("fantasma", VfxShaders.GHOST, {"color": col})
	for h in copy.get_children():
		if h is MeshInstance3D:
			h.material_override = m
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(copy)
	copy.global_transform = skel.global_transform
	live(copy, 0.28, func(k: float): m.set_shader_parameter("t", k))


## Pixel energy ball (fx/tex/custom/*.png, from tools/move_sprites.py): a quad that
## faces the camera and runs through its strip, with a soft light of its color.
## It replaces the smooth glowing sphere (orb), which did not fit Cobblemon.
## It moves and scales like the orb; it lasts until its creator removes it.
func pixel_ball(key: String, frames: int, dims: float, col: Color, fps := 14.0) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * dims
	mi.mesh = q
	var m := mat("pixel_ball", VfxShaders.PIXEL_BALL, {"strip": load("res://fx/tex/custom/%s.png" % key),
		"frames": float(frames), "brightness": 1.15})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = 1.6
	o.omni_range = dims * 4.0
	root.add_child(o)
	add_child(root)
	var clock := {"t": randf() * 10.0}
	live(root, 3600.0, func(_k: float):
		clock.t += get_process_delta_time()
		m.set_shader_parameter("frame", float(int(clock.t * fps) % frames)))
	return root


## Smooth energy sphere (formerly used for the balls; now only as a fallback). Its creator moves it.
func orb(col: Color, radius: float) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat("orb", VfxShaders.ORB, {"color": col, "energy": 1.7})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = 2.0
	o.omni_range = radius * 6.0
	root.add_child(o)
	add_child(root)
	return root


## Continuous emitter (fire or water stream, sparks while charging). Its creator moves
## and stops it; once stopped it is removed when its particles are done.
func continuous_emitter(key: String, amount: int, hp: float, v: Vector2, spread: float, dims: Vector2, parent_n: Node3D = null) -> GPUParticles3D:
	var e := _create_emitter(key)
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = amount
	e.lifetime = hp
	var pm: ParticleProcessMaterial = e.process_material
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.spread = spread
	pm.scale_min = dims.x
	pm.scale_max = dims.y
	if parent_n:
		e.reparent(parent_n, false)
	e.emitting = true
	return e


func stop_emitter(e: GPUParticles3D) -> void:
	if not is_instance_valid(e):
		return
	e.emitting = false
	var t := get_tree().create_timer(e.lifetime + 0.1)
	t.timeout.connect(func(): if is_instance_valid(e): e.queue_free())


## Warning circle on the ground that fills up in "dur" seconds (where something will land).
func telegraph(center: Vector3, radius: float, dur: float, col := Color(1.0, 0.45, 0.2)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := mat("telegraph", VfxShaders.WARNING, {"color": col})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3.UP * 0.04
	mi.scale = Vector3(radius, 1.0, radius)
	live(mi, dur, func(k: float): m.set_shader_parameter("k", k))
	return mi
