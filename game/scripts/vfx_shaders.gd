class_name VfxShaders
extends RefCounted
## Effect shaders (Forward+). They live in code so vfx.gd can build them with their
## parameters. All with HDR energy: the glow comes from there.

## Camera-facing particle with a frame strip (Cobblemon's textures).
## "add" adds light (sparks, fire); without it, normal blending (smoke, dust).
const PARTICLE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, %s;
uniform sampler2D tex : source_color, %s;
uniform float energy = 1.0;
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform float soft = 0.0;  // 1: borde suave aunque la textura sea dura
void vertex() {
	mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float r = INSTANCE_CUSTOM.x;
	m = m * mat4(vec4(cos(r), -sin(r), 0.0, 0.0), vec4(sin(r), cos(r), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float hf = float(h_frames);
	float vf = float(v_frames);
	float total = hf * vf;
	float f = mod(floor(INSTANCE_CUSTOM.z * total), total);
	UV /= vec2(hf, vf);
	UV += vec2(mod(f, hf) / hf, floor(f / hf) / vf);
}
void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	ALBEDO = c.rgb * energy;
	ALPHA = c.a;
}
"""

## Particle stretched in the direction it moves (sparks, drops, wind).
const STREAK := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_add;
uniform float energy = 3.0;
void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
	vec3 side = normalize(cross(axis, to_cam));
	float stretch_len = length(MODEL_MATRIX[1].xyz);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 p = pos + side * VERTEX.x * width + axis * VERTEX.y * stretch_len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}
void fragment() {
	float d = abs(UV.x - 0.5) * 2.0;
	float l = 1.0 - abs(UV.y - 0.5) * 2.0;
	float a = (1.0 - d * d) * smoothstep(0.0, 0.4, l);
	ALBEDO = COLOR.rgb * energy;
	ALPHA = a * COLOR.a;
}
"""

## Pixel impact flash: core, rays and ring in 24 × 24 cells, with two flat tones (white
## and the color) and hard edges, like Cobblemon's.
const FLASH := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 4.0;
uniform float t = 0.0;      // 0 a 1
uniform float bolts = 8.0;
uniform float seed = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = (floor(UV * 24.0) + 0.5) / 24.0 * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float tt = floor(t * 5.0) / 5.0;   // a saltos, como una tira de fotogramas
	float core = step(r, 0.3 * (1.0 - tt));
	float ray = step(0.82, abs(sin(ang * bolts * 0.5 + seed))) * step(r, 0.95 - tt * 0.3) * step(tt, 0.7);
	float ring = step(abs(r - (0.25 + tt * 0.65)), 0.06) * step(tt, 0.85);
	float a = max(core, max(ray, ring));
	if (a < 0.5) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), max(core, ray * step(r, 0.45))) * 1.1;
}
"""

## Flat ring that spreads (shockwaves on the ground, Earthquake), in pixel cells
## ("cells" per side, about 8 per meter): a two-tone ring with a hard edge that, at the
## end, breaks into gaps instead of fading out.
const RING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float thickness = 0.12;
uniform float t = 0.0;
uniform float cells = 24.0;
void fragment() {
	vec2 q = floor(UV * cells);
	vec2 p = (q + 0.5) / cells * 2.0 - 1.0;
	float r = length(p);
	float g = max(thickness, 2.0 / cells);
	float edge = step(abs(r - (1.0 - g)), g);
	float highlight = step(abs(r - (1.0 - g * 1.4)), g * 0.4);
	// Al apagarse se va comiendo a cuadros (sin transparencias suaves).
	float frame_img = fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
	if (edge < 0.5 || frame_img < t * color.a * 1.05 + (1.0 - color.a)) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), highlight * 0.7);
}
"""

## Screen distortion (impact wave): refracts what is behind it.
const DISTORTION := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.04;
uniform float t = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float wave = smoothstep(0.25, 0.0, abs(r - (0.2 + t * 0.75))) * (1.0 - t);
	vec2 off = normalize(p + 0.0001) * wave * strength;
	ALBEDO = textureLod(screen, SCREEN_UV - off, 0.0).rgb;
	ALPHA = step(0.001, wave) * step(r, 1.0);
}
"""

## Beam (streams and rays) in bands: a light core and an edge in the color with no
## gradient, with stepped noise along it (you see the water or light advance in chunks).
const BEAM := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0);
uniform float energy = 3.0;
uniform float flow_speed = 4.0;
uniform float faded = 0.0;
uniform sampler2D noise : repeat_enable, filter_nearest;
void fragment() {
	vec2 uv = vec2(floor(UV.x * 12.0) / 12.0, UV.y);
	float tt = floor(TIME * 14.0) / 14.0;
	float n = texture(noise, vec2(uv.x * 1.5, uv.y * 3.0 - tt * flow_speed)).r;
	float center = abs(dot(NORMAL, VIEW));
	float band = step(0.72, center + (n - 0.5) * 0.35);
	float middle = step(0.4, center + (n - 0.5) * 0.35);
	vec3 c = mix(color.rgb * 0.82, color.rgb, middle);
	c = mix(c, core.rgb, band);
	float a = step(0.3 + faded * 0.7, n + center * 0.5);
	if (a < 0.5) discard;
	ALBEDO = c * 1.1;
}
"""

## Lightning: a ribbon of two hard bands (white center, colored edge), no halo.
const LIGHTNING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform float energy = 5.0;
void fragment() {
	float d = abs(UV.y - 0.5) * 2.0;
	if (d > 0.9 || COLOR.a < 0.35) discard;
	ALBEDO = mix(color.rgb, vec3(1.0, 1.0, 0.94), step(d, 0.38)) * 1.15;
}
"""

## Hit trail (a ribbon following a claw or tail): three flat bands (colored edge, lighter
## body, white edge) that shorten in steps.
const RIBBON := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.5;
void fragment() {
	float a = floor(COLOR.a * 3.0) / 3.0;
	float y = UV.y;
	if (a <= 0.0 || y < 0.2 + (1.0 - a) * 0.5 || y > 0.97) discard;
	vec3 c = mix(color.rgb * 0.85, mix(color.rgb, vec3(1.0), 0.45), step(0.55, y));
	ALBEDO = mix(c, vec3(1.0), step(0.86, y)) * 1.1;
}
"""

## Dodge afterimage: a flat silhouette in the color with a lighter outline, which
## disappears in checkered steps (no glow or soft transparency).
const GHOST := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;
uniform vec4 color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float t = 0.0;
void fragment() {
	float fres = 1.0 - abs(dot(NORMAL, VIEW));
	vec2 q = floor(FRAGCOORD.xy / 3.0);
	float pattern = mod(q.x + q.y, 2.0) * 0.5 + mod(q.x, 2.0) * 0.25 + mod(q.y, 2.0) * 0.125;
	if (pattern < 0.3 + t * 0.7 || t > 0.9) discard;
	ALBEDO = mix(color.rgb * 0.75, mix(color.rgb, vec3(1.0), 0.5), step(0.55, fres));
}
"""

## Energy sphere (Electro Ball, auras): moving noise and a bright edge.
const ORB := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_add;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform float energy = 3.0;
uniform sampler2D noise : repeat_enable;
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float n = texture(noise, UV * vec2(2.0, 1.0) + vec2(TIME * 0.6, TIME * 0.9)).r;
	float veins = smoothstep(0.55, 0.62, n) * (1.0 - smoothstep(0.62, 0.7, n));
	vec3 c = mix(color.rgb, vec3(1.0), veins + fres * 0.4);
	ALBEDO = c * energy;
	ALPHA = clamp(0.25 + fres * 0.9 + veins, 0.0, 1.0);
}
"""

## Loose pixel animation (Cobblemon's impacts): the frame comes in as a parameter.
const SPRITE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_add;
uniform sampler2D tex : source_color, filter_nearest;
uniform float energy = 2.0;
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform int frame = 0;
uniform vec4 color : source_color = vec4(1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	float hf = float(h_frames);
	float vf = float(v_frames);
	float f = float(frame);
	UV /= vec2(hf, vf);
	UV += vec2(mod(f, hf) / hf, floor(f / hf) / vf);
}
void fragment() {
	vec4 c = texture(tex, UV) * color;
	ALBEDO = c.rgb * energy;
	ALPHA = c.a;
}
"""

## Ground warning: an edge and fill that grow until the moment of the hit, in pixel
## cells and two tones.
const WARNING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.45, 0.2, 1.0);
uniform float k = 0.0;
uniform float energy = 1.6;
void fragment() {
	vec2 p = (floor(UV * 32.0) + 0.5) / 32.0 * 2.0 - 1.0;
	float r = length(p);
	float edge = step(abs(r - 0.93), 0.05);
	float front = step(abs(r - k), 0.045);
	float fill = step(r, k) * step(0.5, mod(floor(UV.x * 32.0) + floor(UV.y * 32.0), 2.0));
	float a = max(edge, max(front, fill * 0.5));
	if (a < 0.25 || r > 1.0) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), front * 0.5);
	ALPHA = a < 0.75 ? 0.45 : 1.0;
}
"""


## Animated pixel sprite that always faces the camera (energy balls): a horizontal
## strip of "frames" cells, nearest-neighbor filtered. Half-opaque parts (stepped alpha)
## blend; only the opaque ones glow.
const PIXEL_BALL := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 1.0;
uniform float frame = 0.0;
uniform float brightness = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	// Alfa por niveles (halos, llamas y campos translúcidos de la tira).
	vec4 c = texture(strip, vec2((UV.x + frame) / frames, UV.y));
	if (c.a < 0.04) discard;
	ALBEDO = c.rgb * mix(1.0, brightness, step(0.7, c.a));
	ALPHA = c.a;
}
"""
