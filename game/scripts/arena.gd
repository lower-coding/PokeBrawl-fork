class_name Arena
extends Node3D
## Galar-style gym stadium: a grass pitch with its markings, LED screen fences, curved
## stands with seats and a crowd, a roof open to the sky with floodlights and two
## jumbotrons with the portraits.
## Everything is smooth geometry made by script: curved volumes are extruded along a
## rectangle with rounded corners (_extrude).
## Physical limits: floor, fences and the front of the stands on layer 1 (world).

const LENGTH := 36.0          # X axis
const WIDTH := 22.0          # Z axis
const BARRIER := 1.4         # collision height of the fence
const FENCE := 0.9           # distance of the LED fence from the line
const STANDS := 3.4           # distance of the front of the stands
const ROWS := 15
const ROW_DEPTH := 0.85
const ROW_HEIGHT := 0.44
const PODIUM := 2.4           # height of the wall below the first row

var main: Node
var stage := "stadium"
var _screens: Array = []
var _t := 0.0

const SH_FIELD := """
shader_type spatial;
render_mode cull_back;
// Campo en píxel: todo se calcula por celdas de 1/16 m (la densidad de los
// modelos de Cobblemon), con tonos planos y bordes duros, sin suavizado.
uniform float field_length;
uniform float width;
uniform float px = 16.0;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 track : source_color;
uniform vec3 line : source_color;
uniform vec3 red_tint : source_color;
uniform vec3 blue : source_color;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float stroke(float d, float w) { return step(abs(d), w * 0.5); }
float box(vec2 p, vec2 h) {
	vec2 q = abs(p) - h;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
// Tres tonos por grano: oscuro, medio, claro (como una textura de bloque pintada a mano).
float grain(vec2 cell) {
	float h = hash(cell);
	float h2 = hash(floor(cell / 3.0) + 17.0);
	return h < 0.14 ? 0.86 : (h > 0.9 ? 1.1 : 1.0) * (h2 < 0.2 ? 0.95 : 1.0);
}

void fragment() {
	vec2 cell = floor(wp.xz * px);
	vec2 p = (cell + 0.5) / px;
	float hl = field_length * 0.5;
	float ha = width * 0.5;
	float W = 0.125;
	float inside = step(box(p, vec2(hl, ha)), 0.0);
	float g = grain(cell);
	// Césped segado en franjas de 2,5 m; las briznas sueltas (columnas de 1 px
	// algo más claras) le dan dibujo sin ruido suave.
	float stripe = step(0.5, fract(p.x / 5.0));
	vec3 c = mix(grass_a, grass_b, stripe) * g;
	float blade = step(0.93, hash(vec2(cell.x, floor(cell.y / 2.0))));
	c = mix(c, c * 1.12, blade);
	// Cada mitad toma algo del color de su lado, en franja dura.
	float side = step(hl - 5.5, abs(p.x));
	c = mix(c, mix(c, p.x < 0.0 ? red_tint : blue, 0.16), side);
	// Gran Poké Ball en el centro, pintada sobre el césped.
	float r = length(p);
	if (r < 3.6) {
		vec3 paint = p.x < 0.0 ? red_tint : vec3(0.93, 0.92, 0.88);
		c = mix(c, paint * mix(1.0, g, 0.6), 0.75);
		float band = step(abs(p.x), 0.22) * step(0.95, r);
		c = mix(c, vec3(0.08, 0.09, 0.11), band * 0.75);
		c = mix(c, vec3(0.08, 0.09, 0.11), step(r, 0.95) * 0.8);
		c = mix(c, vec3(0.93, 0.92, 0.88), step(r, 0.6) * 0.9);
	}
	// Líneas: perímetro, medio campo, círculo central y cajas de entrenador.
	float l = stroke(box(p, vec2(hl - W * 0.5, ha - W * 0.5)), W);
	l = max(l, stroke(p.x, W) * step(abs(p.y), ha) * step(3.6, r));
	l = max(l, stroke(r - 3.6, W));
	l = max(l, stroke(r - 0.95, W));
	for (float s = -1.0; s <= 1.0; s += 2.0) {
		l = max(l, stroke(box(p - vec2(s * (hl - 2.2), 0.0), vec2(1.4, 2.0)), W));
		l = max(l, stroke(p.x - s * (hl - 6.0), W) * step(abs(p.y), ha));
	}
	// La pintura de las líneas también está gastada a píxeles.
	l *= step(0.08, hash(cell + 3.1));
	c = mix(c, line * mix(1.0, g, 0.5), l);
	// Pista exterior: goma en losetas de 1 m con junta de 1 px.
	vec2 joint = step(fract(p), vec2(1.0 / px));
	vec3 ap = track * grain(cell + 9.0) * (1.0 - 0.18 * max(joint.x, joint.y));
	float edge = stroke(box(p, vec2(hl + 0.45, ha + 0.45)), 0.125);
	ap = mix(ap, line * 0.8, edge);
	ALBEDO = mix(ap, c, max(inside, l));
	ROUGHNESS = mix(0.8, 0.92, inside);
	SPECULAR = 0.25;
}
"""

const SH_LED := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D icons : source_color, filter_nearest;
uniform vec3 colors[18];
uniform float height = 0.9;
uniform float block = 3.2;
uniform float flow_speed = 0.5;
uniform float brightness = 1.6;
uniform float mode = 0.0;
uniform vec3 tone : source_color = vec3(1.0, 0.3, 0.25);
uniform vec3 tone_b : source_color = vec3(0.25, 0.45, 1.0);

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

void fragment() {
	// Pantalla de LED gordos: 16 por metro, como los píxeles de los modelos.
	vec2 uvp = (floor(UV * 16.0) + 0.5) / 16.0;
	float scroll = floor(TIME * flow_speed * 16.0) / 16.0;
	vec3 c;
	if (mode < 0.5) {
		// Valla: un icono de tipo por bloque sobre su color, desplazándose.
		float x = uvp.x - scroll;
		float cell = floor(x / block);
		float i = floor(hash(cell) * 18.0);
		vec3 background = colors[int(i)];
		float lx = (fract(x / block) - 0.5) * block;
		float v = uvp.y / height;
		c = background * 0.32;
		// Franjas finas en los bordes del bloque.
		float edge = step(abs(lx), block * 0.5 - 0.06);
		c *= mix(0.4, 1.0, edge);
		vec2 iu = vec2(lx / (height * 0.82) + 0.5, 1.0 - (v - 0.09) / 0.82);
		if (iu.x > 0.0 && iu.x < 1.0 && iu.y > 0.0 && iu.y < 1.0) {
			vec4 ic = texture(icons, vec2((i + iu.x) / 18.0, iu.y));
			c = mix(c, ic.rgb * 1.15, ic.a);
		}
		// Aro fino alrededor del icono, que respira despacio.
		float hoop = abs(length(vec2(lx, (v - 0.5) * height)) - height * 0.47);
		c += background * step(hoop, 0.04) * 0.5;
	} else {
		// Cinta de la grada: chevrones lentos en el color de cada mitad.
		float x = uvp.x - scroll;
		float v = uvp.y / height;
		float ch = fract(x * 0.9 + abs(v - 0.5) * 0.9);
		float m = step(ch, 0.45);
		vec3 t = mix(tone, tone_b, step(0.0, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).x));
		c = mix(t * 0.18, t, m);
	}
	// Junta oscura de 1 px entre LED, solo de cerca.
	vec2 g = fract(UV * 16.0);
	float joint = step(0.88, max(g.x, g.y)) * (1.0 - clamp(fwidth(UV.x) * 24.0, 0.0, 1.0));
	c *= 1.0 - 0.35 * joint;
	ALBEDO = vec3(0.02);
	EMISSION = c * brightness;
	ROUGHNESS = 0.25;
}
"""

const SH_CROWD := """
shader_type spatial;
// Público en píxel: cabeza con pelo, ropa con dibujo por persona (lisa, a
// rayas o de dos colores) en celdas de 1/16 m y luz plana, sin el degradado
// de las cápsulas lisas.
uniform float head_height = 0.82;
varying float height;
varying vec3 local;
varying float phase;
void vertex() {
	height = VERTEX.y;
	local = VERTEX;
	phase = INSTANCE_CUSTOM.x;
	float cheer = INSTANCE_CUSTOM.y;
	VERTEX.y += max(0.0, sin(TIME * (2.4 + cheer * 2.0) + phase * 6.2831)) * 0.07 * cheer;
	VERTEX.x += sin(TIME * 1.3 + phase * 6.2831) * 0.03 * VERTEX.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec2 cell = floor(vec2(local.x, local.y) * 16.0);
	float sel = fract(COLOR.a * 7.31);
	vec3 skin = sel < 0.33 ? vec3(0.95, 0.78, 0.63) : (sel < 0.66 ? vec3(0.78, 0.57, 0.42) : vec3(0.45, 0.3, 0.2));
	float hs = fract(phase * 13.7);
	vec3 hair = hs < 0.3 ? vec3(0.16, 0.11, 0.08) : (hs < 0.55 ? vec3(0.45, 0.28, 0.14) : (hs < 0.75 ? vec3(0.85, 0.7, 0.35) : vec3(0.25, 0.25, 0.3)));
	vec3 clothes = COLOR.rgb;
	float pattern = fract(phase * 5.3);
	if (pattern < 0.3) {
		clothes = mix(clothes, clothes * 0.6 + 0.35, step(0.5, mod(cell.y, 3.0)) * 0.6);      // rayas
	} else if (pattern < 0.5) {
		clothes = mix(clothes, vec3(0.92), step(0.55, (height - 0.4) / 0.3));                 // dos colores
	}
	vec3 c = clothes;
	if (height > head_height) {
		c = skin;
		if (height > head_height + 0.24 || local.z > 0.09) c = hair;
	}
	ALBEDO = c * (0.92 + 0.08 * step(0.5, fract(sin(dot(cell, vec2(12.9, 78.2))) * 43758.5)));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""

const SH_SCREEN := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D a : source_color, filter_nearest;
uniform sampler2D b : source_color, filter_nearest;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
void fragment() {
	vec2 uv = UV;
	vec3 c;
	float left = step(uv.x, 0.5);
	// Fondo del color del primer tipo de cada Pokémon, con diagonal al centro.
	float cut_line = uv.x + (uv.y - 0.5) * 0.12;
	c = cut_line < 0.5 ? col_a * 0.55 : col_b * 0.55;
	c *= 0.8 + 0.2 * (1.0 - uv.y);
	float diag = 1.0 - smoothstep(0.004, 0.012, abs(cut_line - 0.5));
	vec2 ua = vec2((uv.x - 0.06) / 0.38, (uv.y - 0.06) / 0.88 * 1.0);
	vec2 ub = vec2((uv.x - 0.56) / 0.38, (uv.y - 0.06) / 0.88 * 1.0);
	if (ua.x > 0.0 && ua.x < 1.0 && ua.y > 0.0 && ua.y < 1.0) {
		vec4 t = texture(a, ua);
		c = mix(c, t.rgb, t.a);
	}
	if (ub.x > 0.0 && ub.x < 1.0 && ub.y > 0.0 && ub.y < 1.0) {
		vec4 t = texture(b, ub);
		c = mix(c, t.rgb, t.a);
	}
	c = mix(c, vec3(0.95), diag);
	float line = 0.92 + 0.08 * step(0.5, fract(UV.y * 90.0));
	ALBEDO = c * line * 1.25;
}
"""


func build() -> void:
	_environment()
	_ground()
	_fences()
	_stands()
	_roof()
	_scoreboards()
	_spotlights()


func inside(p: Vector3, margin := 0.0) -> bool:
	return absf(p.x) < LENGTH * 0.5 - margin and absf(p.z) < WIDTH * 0.5 - margin


func _process(delta: float) -> void:
	_t += delta


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3d78c9")
	sky_mat.sky_horizon_color = Color("a9c8e8")
	sky_mat.ground_horizon_color = Color("a9c8e8")
	sky_mat.ground_bottom_color = Color("4a5568")
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(5, 0.35)
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color("b8cde4")
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -68, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.3
	add_child(sun)


## Smooth material with a pixel texture on top (16 per meter, in world space: works for
## any mesh without depending on its UVs). "kind": concrete, metal or plain.
func _material(col: Color, rough := 0.85, metal := 0.0, kind := "plain") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.albedo_texture = _grain(kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5        # the texture is 32 px: 2 m
	return m


var _grains := {}


## 32 × 32 texture in flat tones, generated here (no files): specks in three tones;
## metal also gets a panel seam every meter and rivets.
func _grain(kind: String) -> ImageTexture:
	if _grains.has(kind):
		return _grains[kind]
	var img := Image.create(32, 32, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in 32:
		for x in 32:
			var h := rng.randf()
			var v := 1.0
			match kind:
				"concrete":
					v = 0.86 if h < 0.12 else (1.06 if h > 0.9 else 0.97)
					if y % 16 == 15:
						v *= 0.82
				"metal":
					v = 0.95 if h < 0.2 else 1.0
					if x % 16 == 0 or y % 16 == 0:
						v = 0.78
					elif x % 16 == 1 or y % 16 == 1:
						v = 1.08
					if (x % 16 == 3 or x % 16 == 13) and (y % 16 == 3 or y % 16 == 13):
						v = 0.7
				_:
					v = 0.93 if h < 0.15 else 1.0
			img.set_pixel(x, y, Color(v * 0.92, v * 0.92, v * 0.92))
	img.generate_mipmaps()
	_grains[kind] = ImageTexture.create_from_image(img)
	return _grains[kind]


# ---------------------------------------------------------------- geometry

## Points of a rectangle with half-sides (a, b) and corners of radius r, on the ground
## and counterclockwise seen from above: [position, outward normal].
func _path(a: float, b: float, r: float, seg := 12) -> Array:
	var pts: Array = []
	var centers := [Vector2(a - r, b - r), Vector2(-(a - r), b - r), Vector2(-(a - r), -(b - r)), Vector2(a - r, -(b - r))]
	for k in 4:
		for i in seg + 1:
			var ang := (k + float(i) / seg) * PI * 0.5
			var n := Vector3(cos(ang), 0.0, sin(ang))
			var c: Vector2 = centers[k]
			pts.append([Vector3(c.x, 0.0, c.y) + n * r, n])
	return pts


## Points every `step` meters along the same rounded rectangle.
func _distribute(a: float, b: float, r: float, step: float) -> Array:
	var dense := _path(a, b, r, 24)
	var lengths: Array[float] = [0.0]
	for i in dense.size():
		var p0: Vector3 = dense[i][0]
		var p1: Vector3 = dense[(i + 1) % dense.size()][0]
		lengths.append(lengths[-1] + p0.distance_to(p1))
	var total: float = lengths[-1]
	var n := int(total / step)
	var out: Array = []
	var j := 0
	for k in n:
		var s := k * total / n
		while lengths[j + 1] < s:
			j += 1
		var p0: Vector3 = dense[j][0]
		var p1: Vector3 = dense[(j + 1) % dense.size()][0]
		var f := (s - lengths[j]) / maxf(lengths[j + 1] - lengths[j], 0.0001)
		var nn: Vector3 = dense[j][1].lerp(dense[(j + 1) % dense.size()][1], f).normalized()
		out.append([p0.lerp(p1, f), nn, s])
	return out


## Extrudes a profile [(d, y)] along the path: d outward, y upward.
## UV: u = meters along the path, v = meters along the profile.
## Smooth along the path and with sharp edges between profile segments.
func _extrude(profile: PackedVector2Array, a: float, b: float, r: float, mat: Material, shadow := true) -> MeshInstance3D:
	var cam := _path(a, b, r, maxi(6, int(r * 3.0)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u: Array[float] = [0.0]
	for i in range(1, cam.size() + 1):
		var p0: Vector3 = cam[i - 1][0]
		var p1: Vector3 = cam[i % cam.size()][0]
		u.append(u[-1] + p0.distance_to(p1))
	var v: Array[float] = [0.0]
	for j in range(1, profile.size()):
		v.append(v[-1] + profile[j - 1].distance_to(profile[j]))
	for i in cam.size():
		var i2 := (i + 1) % cam.size()
		var pa: Vector3 = cam[i][0]
		var na: Vector3 = cam[i][1]
		var pb: Vector3 = cam[i2][0]
		var nb: Vector3 = cam[i2][1]
		for j in profile.size() - 1:
			var q0 := profile[j]
			var q1 := profile[j + 1]
			var t := (q1 - q0).normalized()
			var n2 := Vector2(-t.y, t.x)
			var v00 := pa + na * q0.x + Vector3.UP * q0.y
			var v01 := pa + na * q1.x + Vector3.UP * q1.y
			var v10 := pb + nb * q0.x + Vector3.UP * q0.y
			var v11 := pb + nb * q1.x + Vector3.UP * q1.y
			var nA := (na * n2.x + Vector3.UP * n2.y).normalized()
			var nB := (nb * n2.x + Vector3.UP * n2.y).normalized()
			var quad := [[v00, nA, Vector2(u[i], v[j])], [v10, nB, Vector2(u[i + 1], v[j])], [v11, nB, Vector2(u[i + 1], v[j + 1])], [v01, nA, Vector2(u[i], v[j + 1])]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var A: Vector3 = quad[tri[0]][0]
				var B: Vector3 = quad[tri[1]][0]
				var C: Vector3 = quad[tri[2]][0]
				var order: Array = tri
				# Godot: front faces are clockwise seen from the front.
				if (B - A).cross(C - A).dot(nA) > 0.0:
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					st.set_normal(quad[k][1])
					st.set_uv(quad[k][2])
					st.add_vertex(quad[k][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box_collider(center: Vector3, dims: Vector3, layer := 1) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = dims
	cs.shape = bs
	body.add_child(cs)
	body.position = center
	add_child(body)


# ---------------------------------------------------------------- pieces

func _ground() -> void:
	_box_collider(Vector3(0, -0.5, 0), Vector3(LENGTH + 40, 1.0, WIDTH + 40))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LENGTH + 2.0 * (STANDS + 1.0), WIDTH + 2.0 * (STANDS + 1.0))
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_FIELD
	sm.shader = sh
	sm.set_shader_parameter("field_length", LENGTH)
	sm.set_shader_parameter("width", WIDTH)
	sm.set_shader_parameter("grass_a", Color("4f9a3c"))
	sm.set_shader_parameter("grass_b", Color("5fad47"))
	sm.set_shader_parameter("track", Color("3a4150"))
	sm.set_shader_parameter("line", Color("f4f4ee"))
	sm.set_shader_parameter("red_tint", Color("d8473a"))
	sm.set_shader_parameter("blue", Color("3b6fd6"))
	mi.material_override = sm
	add_child(mi)


func _led_material(mode: float, height: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_LED
	sm.shader = sh
	sm.set_shader_parameter("icons", load("res://gui/cobblemon/types.png"))
	var cols := PackedVector3Array()
	for t in ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison", "ground",
			"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]:
		var c: Color = Roster.TYPE_COLOR[t]
		cols.append(Vector3(c.r, c.g, c.b))
	sm.set_shader_parameter("colors", cols)
	sm.set_shader_parameter("mode", mode)
	sm.set_shader_parameter("height", height)
	return sm


## LED screen fences around the pitch: a rounded casing and a screen tilted toward the
## pitch. Collision is the same as before (straight boxes, layer 1) plus the tall
## invisible wall on layer 3 so nobody flies out.
func _fences() -> void:
	var a := LENGTH * 0.5 + FENCE
	var b := WIDTH * 0.5 + FENCE
	var r := 1.2
	var casing := _material(Color("262a33"), 0.5, 0.2, "metal")
	_extrude(PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.06, 0.08), Vector2(0.0, 0.1)]), a, b, r, casing)
	_extrude(PackedVector2Array([Vector2(0.02, 1.04), Vector2(0.08, 1.12), Vector2(0.24, 1.14), Vector2(0.38, 1.06), Vector2(0.46, 0.0)]), a, b, r, casing)
	_extrude(PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.02, 1.04)]), a, b, r, _led_material(0.0, 0.94))
	var g := 0.5
	for s in [-1.0, 1.0]:
		_box_collider(Vector3(0, BARRIER * 0.5, s * (b + g * 0.5)), Vector3(LENGTH + 2.0 * (FENCE + g), BARRIER, g))
		_box_collider(Vector3(s * (a + g * 0.5), BARRIER * 0.5, 0), Vector3(g, BARRIER, WIDTH + 2.0 * (FENCE + g)))
	# Invisible wall (layer 3): fighters touch it, the camera and projectiles do not.
	for s in [-1.0, 1.0]:
		_box_collider(Vector3(0, 15, s * (b + 0.35)), Vector3(LENGTH + 2, 30, 0.5), 4)
		_box_collider(Vector3(s * (a + 0.35), 15, 0), Vector3(0.5, 30, WIDTH + 2), 4)


## Stands: podium with an LED strip, stepped rows, seats and crowd.
func _stands() -> void:
	var a := LENGTH * 0.5 + STANDS
	var b := WIDTH * 0.5 + STANDS
	var r := 7.0
	var concrete := _material(Color("d4d7de"), 0.92, 0.0, "concrete")
	var podium := _material(Color("1f2a44"), 0.6)
	# Podium: low wall with an LED strip on top.
	_extrude(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, PODIUM - 0.75)]), a, b, r, podium)
	var ribbon := _led_material(1.0, 0.5)
	ribbon.set_shader_parameter("flow_speed", 0.35)
	ribbon.set_shader_parameter("brightness", 1.3)
	_extrude(PackedVector2Array([Vector2(0.0, PODIUM - 0.75), Vector2(0.0, PODIUM - 0.25)]), a, b, r, ribbon)
	_extrude(PackedVector2Array([Vector2(0.0, PODIUM - 0.25), Vector2(0.0, PODIUM), Vector2(0.35, PODIUM)]), a, b, r, podium)
	# Rows: riser and tread.
	var profile := PackedVector2Array([Vector2(0.35, PODIUM)])
	for k in ROWS:
		var d := 0.35 + k * ROW_DEPTH
		var y := PODIUM + k * ROW_HEIGHT
		profile.append(Vector2(d, y + ROW_HEIGHT))
		profile.append(Vector2(d + ROW_DEPTH, y + ROW_HEIGHT))
	var last := profile[profile.size() - 1]
	profile.append(Vector2(last.x + 0.3, last.y))
	profile.append(Vector2(last.x + 0.3, last.y + 4.2))
	_extrude(profile, a, b, r, concrete)
	# Solid front of the stands for the camera (layer 1).
	for s in [-1.0, 1.0]:
		_box_collider(Vector3(0, 4, s * (b + 0.4)), Vector3(LENGTH + 2.0 * STANDS, 8, 0.8))
		_box_collider(Vector3(s * (a + 0.4), 4, 0), Vector3(0.8, 8, WIDTH + 2.0 * STANDS))
	_seats(a, b, r)


func _seats(a: float, b: float, r: float) -> void:
	# Seat: base and backrest in a single mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := BoxMesh.new()
	base.size = Vector3(0.44, 0.07, 0.38)
	var resp := BoxMesh.new()
	resp.size = Vector3(0.44, 0.42, 0.06)
	st.append_from(base, 0, Transform3D(Basis(), Vector3(0, 0.36, 0)))
	st.append_from(resp, 0, Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.56, 0.2)))
	var seat := st.commit()
	var seat_mat := _material(Color.WHITE, 0.55)
	seat_mat.vertex_color_use_as_albedo = true
	# Seated person: torso and head; the shader paints the head in a skin tone.
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CapsuleMesh.new()
	trunk.radius = 0.19
	trunk.height = 0.62
	trunk.radial_segments = 8
	trunk.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	head.radial_segments = 8
	head.rings = 4
	sp.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 0.62, 0.05)))
	sp.append_from(head, 0, Transform3D(Basis(), Vector3(0, 1.02, 0.03)))
	var person := sp.commit()
	var crowd_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SH_CROWD
	crowd_mat.shader = sh
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var sites: Array = []
	for k in ROWS:
		var d := 0.35 + k * ROW_DEPTH + ROW_DEPTH * 0.45
		var y := PODIUM + (k + 1) * ROW_HEIGHT
		for p in _distribute(a + d, b + d, r + d, 0.56):
			var s: float = p[2]
			# Aisles with stairs every 11 m.
			if fmod(s, 11.0) < 1.1:
				continue
			sites.append([p[0] + Vector3.UP * y, p[1], k, s])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = seat
	mm.instance_count = sites.size()
	var mp := MultiMesh.new()
	mp.transform_format = MultiMesh.TRANSFORM_3D
	mp.use_colors = true
	mp.use_custom_data = true
	mp.mesh = person
	var crowd: Array = []
	var shirts := [Color("c8473c"), Color("3a62c4"), Color("e9e6dc"), Color("2a2f3a"), Color("e3b740"), Color("5f8a4a"),
		Color("8a8f9c"), Color("b04a7a"), Color("d9793a")]
	for i in sites.size():
		var pos: Vector3 = sites[i][0]
		var n: Vector3 = sites[i][1]
		var row: int = sites[i][2]
		var looks := Basis.looking_at(-n, Vector3.UP)
		var tr := Transform3D(looks, pos)
		mm.set_instance_transform(i, tr)
		# Red seats on the red half, blue on the blue one; the top rows, white in a band.
		var col := Color("b8413a") if pos.x < 0.0 else Color("2f5cb8")
		if row >= ROWS - 3:
			col = Color("e4e2dc")
		elif row % 5 == 4:
			col = col.darkened(0.35)
		mm.set_instance_color(i, col)
		if rng.randf() < 0.62:
			crowd.append(tr)
	mp.instance_count = crowd.size()
	for i in crowd.size():
		mp.set_instance_transform(i, crowd[i])
		var c: Color = shirts[rng.randi() % shirts.size()]
		c.a = rng.randf()
		mp.set_instance_color(i, c)
		mp.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.0, 0.7), 0, 0))
	var mia := MultiMeshInstance3D.new()
	mia.multimesh = mm
	mia.material_override = seat_mat
	add_child(mia)
	var mip := MultiMeshInstance3D.new()
	mip.multimesh = mp
	mip.material_override = crowd_mat
	add_child(mip)


## Cantilevered roof over the stands, open in the center, with floodlights on the edge.
func _roof() -> void:
	var a := LENGTH * 0.5 + STANDS
	var b := WIDTH * 0.5 + STANDS
	var r := 7.0
	var background := 0.35 + ROWS * ROW_DEPTH + 0.3
	var y0 := PODIUM + ROWS * ROW_HEIGHT + 4.2
	var white_mat := _material(Color("f6f7f8"), 0.6, 0.1, "metal")
	var grey := _material(Color("a6acb7"), 0.7, 0.2, "metal")
	var edge := 2.2
	# Underside (seen from the pitch), front edge and top side.
	_extrude(PackedVector2Array([Vector2(background, y0), Vector2(edge, y0 + 1.4)]), a, b, r, grey)
	_extrude(PackedVector2Array([Vector2(edge, y0 + 1.4), Vector2(edge - 0.05, y0 + 2.1)]), a, b, r, white_mat)
	_extrude(PackedVector2Array([Vector2(edge - 0.05, y0 + 2.1), Vector2(background + 0.5, y0 + 2.6), Vector2(background + 0.5, y0 - 0.2), Vector2(background, y0)]), a, b, r, white_mat)
	# Row of floodlights under the edge.
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(0.9, 0.9, 0.9)
	light.emission_enabled = true
	light.emission = Color(1.0, 0.97, 0.9)
	light.emission_energy_multiplier = 5.0
	var dl := 1.2
	var yl := y0 + 1.4 - (edge + dl - edge) * (1.4 / (background - edge))
	_extrude(PackedVector2Array([Vector2(edge + dl, yl - 0.03), Vector2(edge + 0.15, y0 + 1.37)]), a, b, r, light, false)
	# Ribs under the roof.
	var cost := BoxMesh.new()
	cost.size = Vector3(0.22, 0.35, background - edge)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cost
	var pts := _distribute(a, b, r, 6.0)
	mm.instance_count = pts.size()
	var tilt := atan2(1.4, background - edge)
	for i in pts.size():
		var p: Vector3 = pts[i][0]
		var n: Vector3 = pts[i][1]
		var mid := (edge + background) * 0.5
		var bas := Basis.looking_at(n, Vector3.UP)
		bas = bas * Basis(Vector3.RIGHT, -tilt)
		mm.set_instance_transform(i, Transform3D(bas, p + n * mid + Vector3.UP * (y0 + 0.7 - 0.2)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = white_mat
	add_child(mi)


## Jumbotrons at both ends, hanging from the roof. They show the portraits.
func _scoreboards() -> void:
	var y := PODIUM + ROWS * ROW_HEIGHT + 1.6
	var x := LENGTH * 0.5 + STANDS + 9.0
	var frame_box := _material(Color("15181f"), 0.4, 0.3)
	for s in [-1.0, 1.0]:
		var root := Node3D.new()
		root.position = Vector3(s * x, y, 0)
		root.rotation.y = -s * PI * 0.5
		add_child(root)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(10.4, 5.0, 0.5)
		box.mesh = bm
		box.material_override = frame_box
		box.position.z = -0.27
		root.add_child(box)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(9.8, 4.4)
		q.mesh = qm
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SH_SCREEN
		sm.shader = sh
		q.material_override = sm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
		_screens.append(sm)


## Called by main at the start of each battle.
func screens(tex_a: Texture2D, tex_b: Texture2D, col_a: Color, col_b: Color) -> void:
	for sm in _screens:
		sm.set_shader_parameter("a", tex_a)
		sm.set_shader_parameter("b", tex_b)
		sm.set_shader_parameter("col_a", col_a)
		sm.set_shader_parameter("col_b", col_b)


func _spotlights() -> void:
	# Floodlight light over the pitch, soft and without shadows.
	for x in [-14.0, 14.0]:
		for z in [-1.0, 1.0]:
			var f := SpotLight3D.new()
			f.position = Vector3(x, 15.0, z * (WIDTH * 0.5 + STANDS + 3.0))
			f.look_at_from_position(f.position, Vector3(x * 0.4, 0, 0))
			f.spot_angle = 40.0
			f.spot_range = 40.0
			f.light_energy = 1.4
			f.light_color = Color(1.0, 0.97, 0.9)
			f.shadow_enabled = false
			add_child(f)
