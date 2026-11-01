class_name PlatformStadium
extends NightStadium
## The night stadium with three platforms over the field, in the classic layout of platform
## fighters: a low one on each side and a higher one in the middle.
##
## A fighter goes up through them and lands on top; Descend drops through
## (Fighter._step_platforms). Shots and the camera ignore them (Arena.PLATFORM_LAYER), and
## they are see-through so they never hide anybody from a camera above them.
## Each level is one double jump above the last even for the heaviest: Snorlax and Venusaur
## rise 1.6 m with both jumps. The fighters start between them, on the field.

const LOW_Y := 1.4
const HIGH_Y := 2.8
const THICK := 0.25
const EDGE := 0.12
## Each platform: [center x, top y, half-length (x), half-width (z), color].
const LAYOUT := [
	[-12.0, LOW_Y, 4.5, 4.0, C_PINK],
	[12.0, LOW_Y, 4.5, 4.0, C_BLUE],
	[0.0, HIGH_Y, 6.0, 4.0, C_CYAN],
]


func build() -> void:
	super()
	for p in LAYOUT:
		_platform(p[0], p[1], p[2], p[3], p[4])


func _platform(x: float, top: float, half_x: float, half_z: float, col: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PLATFORM_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(half_x * 2.0, THICK, half_z * 2.0)
	cs.shape = bs
	cs.position.y = -THICK * 0.5
	body.add_child(cs)
	body.position = Vector3(x, top, 0.0)
	add_child(body)
	platforms.append(body)
	# A pane of tinted glass in floor plates, framed in neon like the stands' railings.
	var pane := _material(col.darkened(0.35), 0.25, 0.2, "grid")
	pane.albedo_color.a = 0.45
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.emission_enabled = true
	pane.emission = col
	pane.emission_energy_multiplier = 0.12
	var mid := body.position + Vector3.DOWN * THICK * 0.5
	_box(bs.size, mid, pane)
	var neon := _glowing(col, 1.4)
	for s in [-1.0, 1.0]:
		_box(Vector3(half_x * 2.0 + EDGE, THICK + 0.02, EDGE), mid + Vector3(0.0, 0.0, s * half_z), neon)
		_box(Vector3(EDGE, THICK + 0.02, half_z * 2.0), mid + Vector3(s * half_x, 0.0, 0.0), neon)
	# Its glow on the field, so you can tell from below where it ends.
	var glow := OmniLight3D.new()
	glow.position = mid + Vector3.DOWN * 0.3
	glow.light_color = col
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	glow.light_volumetric_fog_energy = 0.0
	add_child(glow)
