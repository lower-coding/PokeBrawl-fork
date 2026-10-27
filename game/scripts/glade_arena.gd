class_name GladeArena
extends Arena
## Outdoor battle field, like the ones in the anime: a clearing with a dirt field marked
## in chalk, grass around it, a low wooden fence, rocks, round-crowned trees and hills in
## the background, with afternoon light.
## Smooth low-poly shapes (no cubes) and every pixel texture at 16 per meter, the density
## of Cobblemon's models. The textures are painted right here in code (no files).
##
## Same limits as the stadium: the field measures LENGTH × WIDTH and the fence has the
## stadium's collision (layer 1) and the invisible wall (layer 3).

const SH_MEADOW := """
shader_type spatial;
render_mode cull_back;
uniform float field_length;
uniform float width;
uniform float px = 16.0;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 dirt : source_color;
uniform vec3 dirt_b : source_color;
uniform vec3 chalk : source_color;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float box(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float stroke(float d, float w) { return step(abs(d), w * 0.5); }

void fragment() {
	vec2 cell = floor(wp.xz * px);
	vec2 p = (cell + 0.5) / px;
	// Lejos, el grano de un píxel parpadea: se va apagando con la distancia.
	float far = clamp(fwidth(wp.x) * px * 0.6 - 0.4, 0.0, 1.0);
	float h = hash(cell);
	float g = mix(h < 0.15 ? 0.85 : (h > 0.9 ? 1.1 : 1.0), 1.0, far);
	// Hierba: manchas grandes de dos verdes (bordes en escalón) y briznas claras.
	float patch = step(0.52, noise(p * 0.18) * 0.7 + noise(p * 0.9) * 0.3);
	vec3 c = mix(grass_a, grass_b, patch) * g;
	c = mix(c, c * 1.15, step(0.94, hash(vec2(cell.x, floor(cell.y / 2.0)))) * (1.0 - far));
	// Campo de tierra pisada, con el borde comido a píxeles por la hierba.
	float hl = field_length * 0.5;
	float ha = width * 0.5;
	float d = box(p, vec2(hl + 0.3, ha + 0.3), 2.0) + (noise(p * 2.2) - 0.5) * 0.9;
	vec3 ground = mix(dirt, dirt_b, step(0.6, noise(p * 0.7))) * g;
	ground = mix(ground, ground * 0.8, step(0.96, h));      // piedrecitas
	float on_dirt = step(d, 0.0);
	c = mix(c, ground, on_dirt);
	// Tiza: perímetro, medio campo, círculo y cajas, con huecos de desgaste.
	float W = 0.125;
	float r = length(p);
	float l = stroke(box(p, vec2(hl - W * 0.5, ha - W * 0.5), 0.0), W);
	l = max(l, stroke(p.x, W) * step(abs(p.y), ha));
	l = max(l, stroke(r - 3.2, W));
	for (float s = -1.0; s <= 1.0; s += 2.0) {
		l = max(l, stroke(box(p - vec2(s * (hl - 2.2), 0.0), vec2(1.4, 2.0), 0.0), W));
	}
	l *= step(0.2, hash(cell + 5.7)) * on_dirt;
	c = mix(c, chalk * mix(1.0, g, 0.5), l * 0.9);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

## Tuft of grass or flowers: two crossed quads with alpha cutout and sway.
## The strip has 4 variants; INSTANCE_CUSTOM.x picks one.
const SH_TUFT := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D strip : source_color, filter_nearest;
varying float variant;
void vertex() {
	variant = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y * 6.2831;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.6 + phase + w.x * 0.3) * 0.06 * VERTEX.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec4 c = texture(strip, vec2((UV.x + floor(variant * 4.0)) / 4.0, UV.y));
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
}
"""

var _tex := {}


func build() -> void:
	_glade_environment()
	_glade_ground()
	_wooden_fence()
	_trees()
	_rocks()
	_tufts()
	_hills()


# ---------------------------------------------------------------- light and sky

func _glade_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4c86d4")
	sky_mat.sky_horizon_color = Color("f0d2a8")
	sky_mat.ground_horizon_color = Color("e7c9a0")
	sky_mat.ground_bottom_color = Color("5d6b4c")
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Fixed warm ambient color: with the sky's, the long shadows of the fence came out
	# blue on the dirt.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4bba6")
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("e8d2b4")
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Low, warm afternoon sun: long shadows.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -50, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.89, 0.74)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.3
	add_child(sun)


# ---------------------------------------------------------------- textures

## 32 × 32 color texture per kind, in flat tones (leaves, bark, stone, wood). The
## palette comes from Cobblemon/Minecraft blocks, but it is painted over rounded
## shapes.
func _texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 3
	var img := Image.create(32, 32, true, Image.FORMAT_RGB8)
	var pal: Array
	match kind:
		"leaves":
			pal = [Color("3c7a2e"), Color("4f9238"), Color("62a845"), Color("2f6326"), Color("7cbd52")]
		"leaves_b":
			pal = [Color("356b33"), Color("447f3d"), Color("559448"), Color("29552a"), Color("6aa955")]
		"bark":
			pal = [Color("5e4128"), Color("6f4e31"), Color("4c3420"), Color("80603d")]
		"stone":
			pal = [Color("8d9094"), Color("7a7d82"), Color("a2a5a9"), Color("676a6f")]
		"wood":
			pal = [Color("a2763f"), Color("b68a4f"), Color("8c6334"), Color("c29a5d")]
		_:
			pal = [Color("6fa04a"), Color("5e8f3f"), Color("80b257"), Color("4f7d36")]
	img.fill(pal[0])
	match kind:
		"leaves", "leaves_b", "meadow":
			# 2 × 2 clusters in lighter tones and dark gaps.
			for i in 150:
				var x := rng.randi() % 32
				var y := rng.randi() % 32
				var c: Color = pal[1 + rng.randi() % (pal.size() - 1)]
				for dx in 2:
					for dy in 2:
						if rng.randf() < 0.8:
							img.set_pixel((x + dx) % 32, (y + dy) % 32, c)
		"bark":
			# Vertical streaks.
			for x in 32:
				var c: Color = pal[rng.randi() % pal.size()]
				var y := 0
				while y < 32:
					var length := rng.randi_range(3, 9)
					for k in length:
						img.set_pixel(x, (y + k) % 32, c)
					y += length + rng.randi_range(0, 3)
					c = pal[rng.randi() % pal.size()]
		"stone":
			for y in 32:
				for x in 32:
					var h := rng.randf()
					img.set_pixel(x, y, pal[0] if h < 0.55 else (pal[1] if h < 0.8 else (pal[2] if h < 0.93 else pal[3])))
			# Cracks.
			for i in 3:
				var x := rng.randi() % 32
				var y := rng.randi() % 32
				for k in rng.randi_range(4, 9):
					img.set_pixel(posmod(x, 32), posmod(y, 32), pal[3].darkened(0.2))
					x += rng.randi_range(-1, 1)
					y += 1
		"wood":
			# 8 px horizontal planks with grain and seams.
			for y in 32:
				for x in 32:
					var c: Color = pal[0]
					if y % 8 == 7:
						c = pal[2].darkened(0.15)
					elif rng.randf() < 0.18:
						c = pal[1 + rng.randi() % 3]
					img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]


func _tex_mat(kind: String, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(kind)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	return m


# ---------------------------------------------------------------- floor and fence

func _glade_ground() -> void:
	_box_collider(Vector3(0, -0.5, 0), Vector3(LENGTH + 40, 1.0, WIDTH + 40))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 260)
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_MEADOW
	sm.shader = sh
	sm.set_shader_parameter("field_length", LENGTH)
	sm.set_shader_parameter("width", WIDTH)
	sm.set_shader_parameter("grass_a", Color("5d9a3e"))
	sm.set_shader_parameter("grass_b", Color("6aa746"))
	sm.set_shader_parameter("dirt", Color("b88f5c"))
	sm.set_shader_parameter("dirt_b", Color("a8804f"))
	sm.set_shader_parameter("chalk", Color("f3efe2"))
	mi.material_override = sm
	add_child(mi)


## Low wooden fence on the stadium's line: posts and two rails.
func _wooden_fence() -> void:
	var a := LENGTH * 0.5 + FENCE
	var b := WIDTH * 0.5 + FENCE
	var r := 1.2
	var wood := _tex_mat("wood", 0.85)
	for y in [0.42, 0.82]:
		_extrude(PackedVector2Array([Vector2(-0.05, y - 0.07), Vector2(0.05, y - 0.07), Vector2(0.05, y + 0.07),
			Vector2(-0.05, y + 0.07), Vector2(-0.05, y - 0.07)]), a, b, r, wood)
	var post := CylinderMesh.new()
	post.top_radius = 0.08
	post.bottom_radius = 0.1
	post.height = 1.05
	post.radial_segments = 6
	post.rings = 1
	var sites := _distribute(a, b, r, 2.4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	mm.instance_count = sites.size()
	for i in sites.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, randf() * TAU), sites[i][0] + Vector3.UP * 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = wood
	add_child(mmi)
	# Collision, like the stadium's.
	var g := 0.5
	for s in [-1.0, 1.0]:
		_box_collider(Vector3(0, BARRIER * 0.5, s * (b + g * 0.5)), Vector3(LENGTH + 2.0 * (FENCE + g), BARRIER, g))
		_box_collider(Vector3(s * (a + g * 0.5), BARRIER * 0.5, 0), Vector3(g, BARRIER, WIDTH + 2.0 * (FENCE + g)))
		_box_collider(Vector3(0, 15, s * (b + 0.35)), Vector3(LENGTH + 2, 30, 0.5), 4)
		_box_collider(Vector3(s * (a + 0.35), 15, 0), Vector3(0.5, 30, WIDTH + 2), 4)


# ---------------------------------------------------------------- vegetation and rocks

## Is this point outside the field and its fence (with a margin)?
func _outside(p: Vector3, margin: float) -> bool:
	return absf(p.x) > LENGTH * 0.5 + FENCE + margin or absf(p.z) > WIDTH * 0.5 + FENCE + margin


## A tree mesh: trunk and a crown of several low-poly balls (two surfaces, each with its
## material). `pine`: a crown of cones.
func _tree_mesh(rng: RandomNumberGenerator, pine: bool, leaves: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	var height := rng.randf_range(1.5, 2.2) if not pine else rng.randf_range(1.2, 1.7)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.3
	trunk.bottom_radius = 0.5
	trunk.height = height
	trunk.radial_segments = 7
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3.UP * height * 0.5))
	st.commit(am)
	am.surface_set_material(0, _tex_mat("bark"))
	var sc := SurfaceTool.new()
	sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		for k in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 2.0 - k * 0.5
			cone.height = 2.4 - k * 0.3
			cone.radial_segments = 8
			cone.rings = 1
			sc.append_from(cone, 0, Transform3D(Basis(), Vector3.UP * (height * 0.6 + k * 1.3 + cone.height * 0.5)))
	else:
		var n := rng.randi_range(3, 5)
		for k in n:
			var ball := SphereMesh.new()
			var rr := rng.randf_range(1.8, 2.5) * (1.0 if k == 0 else 0.75)
			ball.radius = rr
			ball.height = rr * 1.7
			ball.radial_segments = 9
			ball.rings = 5
			var off := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.5, 1.5)) if k > 0 else Vector3.ZERO
			sc.append_from(ball, 0, Transform3D(Basis(), Vector3.UP * (height + 1.3) + off))
	sc.commit(am)
	am.surface_set_material(1, _tex_mat(leaves))
	return am


func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	# Six tree models (four round and two pines), repeated with MultiMesh.
	var models: Array = []
	for i in 6:
		models.append(_tree_mesh(rng, i >= 4, "leaves" if i % 2 == 0 else "leaves_b"))
	var sites: Array = []
	for i in models.size():
		sites.append([])
	# A grove around the clearing: denser the farther out, with gaps.
	var placed_n := 0
	var tries := 0
	while placed_n < 230 and tries < 4000:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.0, 1.0)
		var p := Vector3(cos(ang) * (LENGTH * 0.5 + 10.0 + dist * 38.0), 0.0, sin(ang) * (WIDTH * 0.5 + 9.0 + dist * 32.0))
		# Away from the fence: the camera goes behind the player and must not enter the crowns.
		if not _outside(p, 7.0):
			continue
		if rng.randf() > 0.35 + dist * 0.65:
			continue
		var which := rng.randi() % models.size()
		var esc := rng.randf_range(0.85, 1.35)
		sites[which].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * esc), p))
		placed_n += 1
	for i in models.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = models[i]
		mm.instance_count = sites[i].size()
		for k in sites[i].size():
			mm.set_instance_transform(k, sites[i][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


## Rock: a low-poly sphere deformed with noise, flattened.
func _rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 8
	sph.rings = 5
	var arr := sph.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.3
	for i in v.size():
		var p := v[i]
		var k := 1.0 + noise.get_noise_3dv(p) * 0.45
		v[i] = Vector3(p.x * k, maxf(p.y * k * 0.62, -0.25), p.z * k)
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	return st.commit()


func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mat := _tex_mat("stone", 0.95)
	for m in 4:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh(rng)
		var trs: Array = []
		var tries := 0
		while trs.size() < 12 and tries < 500:
			tries += 1
			var p := Vector3(rng.randf_range(-45, 45), 0.0, rng.randf_range(-38, 38))
			if not _outside(p, 1.5):
				continue
			var esc := rng.randf_range(0.5, 1.6) * (1.0 if _outside(p, 8.0) else 0.6)
			trs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(esc, esc * rng.randf_range(0.7, 1.2), esc)), p))
		mm.instance_count = trs.size()
		for k in trs.size():
			mm.set_instance_transform(k, trs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)


## Strip of 4 tufts of 16 × 16: two of grass and two with flowers.
func _tuft_strip() -> ImageTexture:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var greens := [Color("4f8f36"), Color("66a845"), Color("3d7429"), Color("7dbd55")]
	for v in 4:
		for b in 7:
			var x := 1 + rng.randi() % 14
			var height := rng.randi_range(6, 14)
			var lean := rng.randi_range(-1, 1)
			var c: Color = greens[rng.randi() % greens.size()]
			for k in height:
				var xx := clampi(x + int(lean * k / 5.0), 0, 15)
				img.set_pixel(v * 16 + xx, 15 - k, c)
		if v >= 2:
			var flower := Color("f5f1e6") if v == 2 else Color("f2c94a")
			for f in 3:
				var fx := 2 + rng.randi() % 12
				var fy := 3 + rng.randi() % 5
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					img.set_pixel(v * 16 + clampi(fx + d.x, 0, 15), clampi(fy + d.y, 0, 15), flower)
				img.set_pixel(v * 16 + fx, fy, Color("e08a2e"))
	return ImageTexture.create_from_image(img)


func _tufts() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.center_offset = Vector3(0, 0.3, 0)
	st.append_from(q, 0, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO))
	st.append_from(q, 0, Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3.ZERO))
	var tuft := st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_TUFT
	mat.shader = sh
	mat.set_shader_parameter("strip", _tuft_strip())
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var trs: Array = []
	var data: Array = []
	var tries := 0
	while trs.size() < 5000 and tries < 30000:
		tries += 1
		var p := Vector3(rng.randf_range(-55, 55), 0.0, rng.randf_range(-45, 45))
		# Outside the field; inside, only the odd tuft against the fence.
		if not _outside(p, 0.3):
			if absf(p.x) < LENGTH * 0.5 + 0.2 and absf(p.z) < WIDTH * 0.5 + 0.2:
				continue
		var esc := rng.randf_range(0.7, 1.4)
		trs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * esc), p))
		var variant := 0.1 if rng.randf() < 0.45 else (0.35 if rng.randf() < 0.75 else (0.6 if rng.randf() < 0.5 else 0.85))
		data.append(Color(variant, rng.randf(), 0, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = tuft
	mm.instance_count = trs.size()
	for i in trs.size():
		mm.set_instance_transform(i, trs[i])
		mm.set_instance_custom_data(i, data[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Hills in the background: soft grassy slopes with trees on top.
func _hills() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var mat := _tex_mat("meadow", 0.95)
	for i in 14:
		var ang := float(i) / 14.0 * TAU + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(85.0, 115.0)
		var mound := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = rng.randf_range(22.0, 34.0)
		sph.height = sph.radius * 2.0
		sph.radial_segments = 16
		sph.rings = 8
		mound.mesh = sph
		mound.material_override = mat
		mound.scale = Vector3(1.0, rng.randf_range(0.35, 0.6), 1.0)
		mound.position = Vector3(cos(ang) * dist, -sph.radius * mound.scale.y * 0.35, sin(ang) * dist)
		mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mound)
