class_name TeamOutline
extends CanvasLayer
## In a 2 vs 2, a blue outline on your ally and a red one on your foes (Settings.team_outline), so
## four bodies can be told apart at a glance. A screen-space outline from a mask rather than a grown
## copy of the mesh, which would not suit these models: each box face keeps its own normal (growing
## opens gaps at the corners) and ribbons, fins and ears are cut out of their boxes by the texture
## (a copy would outline the invisible parts too).
##   1. A SubViewport shares the battle's world, with a camera that copies the battle's and sees only
##      LAYER. It draws the marked bodies in flat color, on nothing.
##   2. Each marked body adds LAYER to its mesh and has its color in the "mark" uniform: decoys too,
##      with their user's, or the outline would give away a trick. The player's own body does not.
##   3. pokemon.gdshader, seeing that camera is looking, outputs "mark" instead of its look.
##   4. A ColorRect under the HUD (WIDTH screen pixels): an empty pixel of the mask with a neighbor
##      that is not takes that neighbor's color. Bodies stay untouched.
## What cannot be seen is left out: Substitute's user, Dig, the bench. It shows through walls and
## other bodies, since the mask has no depth from the main view.

const LAYER := 1 << 18                  # free: the camera's is bit 19, the stages' are lower
const WIDTH := 2.0                      # screen pixels
const MASK_SCALE := 1.0                 # the lever on what it costs: half-size mask at 0.5

const SH_OUTLINE := """
shader_type canvas_item;
uniform sampler2D mask : filter_nearest, repeat_disable;
uniform vec2 step_uv;
void fragment() {
	COLOR = vec4(0.0);
	if (texture(mask, UV).a < 0.5) {
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				vec4 n = texture(mask, UV + vec2(float(x), float(y)) * step_uv);
				if (n.a >= 0.5) {
					COLOR = vec4(n.rgb, 1.0);
				}
			}
		}
	}
}
"""

var main: Node
var _vp: SubViewport
var _cam: Camera3D
var _rect: ColorRect
var _mat: ShaderMaterial
var _marked: Array = []                 # the meshes that have LAYER now


func _ready() -> void:
	layer = 4
	process_priority = 100              # after the battle camera and the fighters
	# No view to draw it in, in tests without a window.
	if DisplayServer.get_name() == "headless":
		return
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = LAYER
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The battle's environment would tone the flat colors and glow around them.
	_cam.environment = Environment.new()
	_cam.environment.background_mode = Environment.BG_CLEAR_COLOR
	_vp.add_child(_cam)
	_cam.current = true
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SH_OUTLINE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("mask", _vp.get_texture())
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## A new battle: whatever was marked is gone.
func begin_battle() -> void:
	_marked.clear()


func _active() -> bool:
	return main.doubles and main.options.team_outline and not main.menu.is_open and main.player != null


func _process(_delta: float) -> void:
	_mark_bodies()
	if _vp == null:
		return
	var on := _active()
	_rect.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var size := Vector2i((Vector2(get_viewport().get_visible_rect().size) * MASK_SCALE).round())
	if _vp.size != size:
		_vp.size = size
	_mat.set_shader_parameter("step_uv", Vector2(WIDTH, WIDTH) / get_viewport().get_visible_rect().size)
	var from: Camera3D = main.camera
	_cam.global_transform = from.get_global_transform_interpolated()
	_cam.fov = from.fov
	_cam.h_offset = from.h_offset
	_cam.v_offset = from.v_offset


## Who is marked now: everyone on the field but the player and its own decoys. A KO drops out.
func _mark_bodies() -> void:
	var now: Array = []
	if _active():
		for o in main.combat.targets:
			var who: Fighter = o.user if o is Decoy else o
			if not is_instance_valid(who) or who == main.player or who.state == "ko" or (o is Fighter and o.out_of_sight()):
				continue
			var model: PokeModel = o._model if o is Decoy else o.model
			var col: Color = Hud.BLUE_MARK if who.team == main.player.team else Hud.RED_MARK
			model.mat.set_shader_parameter("mark", col)
			now.append(model.mesh_instance)
	for mesh in _marked:
		if is_instance_valid(mesh) and not mesh in now:
			mesh.layers &= ~LAYER
	for mesh in now:
		mesh.layers |= LAYER
	_marked = now


## Whether "o" (a Fighter or a Decoy) is in the mask (tests).
func marked(o: Node3D) -> bool:
	var model: PokeModel = o._model if o is Decoy else o.model
	return model.mesh_instance in _marked and (model.mesh_instance.layers & LAYER) != 0
