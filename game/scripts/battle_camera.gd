class_name BattleCamera
extends Camera3D
## Third-person camera. Free: turned with the right stick or the mouse.
## Locked on: sits behind the player looking at the rival and pulls back as they
## separate, to keep both on screen. Pulls back further for big Pokémon.
## It does not go through walls (it moves in) and its shake can be reduced in the options.

const MOUSE_SENS := 0.0026
const STICK_SENS := 2.6

var main: Node
var target: Fighter
var yaw := 0.0
var pitch := -0.32
var _dist := 6.0
var _aim := Vector3.ZERO
var _trauma := 0.0
var _manual := 0.0          # time since the last manual turn


func shake_camera(k: float) -> void:
	_trauma = minf(1.0, _trauma + k * main.options.shake)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= ev.relative.x * MOUSE_SENS
		pitch = clampf(pitch - ev.relative.y * MOUSE_SENS, -1.1, 0.35)
		_manual = 0.0


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_manual += delta
	var st := Input.get_vector("cam_left", "cam_right", "cam_down", "cam_up")
	if st.length() > 0.1:
		yaw -= st.x * STICK_SENS * delta
		pitch = clampf(pitch + st.y * STICK_SENS * 0.6 * delta, -1.1, 0.35)
		_manual = 0.0
	var me := target
	var height: float = me.data.height
	var pivot := me.global_position + Vector3.UP * (height * 0.85 + 0.45)
	var base := 2.6 + height * 1.45
	var r: Fighter = me.rival
	var locked_on := me.locked and r and is_instance_valid(r) and r.state != "ko"
	if locked_on:
		var toward := r.global_position - me.global_position
		var sep := Vector2(toward.x, toward.z).length()
		var yaw_target := atan2(-toward.x, -toward.z)
		# The stick can pull it off a little; then it comes back on its own.
		var pull := 6.0 if _manual > 0.4 else 1.5
		yaw = lerp_angle(yaw, yaw_target, 1.0 - exp(-pull * delta))
		var pitch_target := clampf(-0.28 - (r.global_position.y - me.global_position.y) * 0.04 - sep * 0.004, -0.75, -0.12)
		if _manual > 0.6:
			pitch = lerpf(pitch, pitch_target, 1.0 - exp(-3.0 * delta))
		base += clampf(sep * 0.1, 0.0, 2.4) + r.data.height * 0.3
	_dist = lerpf(_dist, base, 1.0 - exp(-4.0 * delta))
	# Big Pokémon would hide the rival: the camera goes a bit higher and over the shoulder.
	var shoulder := clampf(height - 1.0, 0.0, 1.5) * 0.55
	var pitch_final := pitch - clampf(height - 1.0, 0.0, 1.5) * 0.12
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch_final)
	var desired := pivot + b * Vector3(shoulder, 0, _dist)
	# Walls: it moves in so it does not end up behind them (layer 1, not the invisible wall).
	var q := PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		desired = hit.position + (pivot - desired).normalized() * 0.3
	desired.y = maxf(desired.y, main.ground_y + 0.5)
	global_position = global_position.lerp(desired, 1.0 - exp(-14.0 * delta))
	var look_point := pivot + b * Vector3(shoulder, 0, -6.0)
	if locked_on:
		# Looks between the two, closer to the player.
		look_point = pivot.lerp(r.center(), 0.4)
	_aim = _aim.lerp(look_point, 1.0 - exp(-10.0 * delta)) if _aim != Vector3.ZERO else look_point
	look_at(_aim, Vector3.UP)
	# Shake from "trauma" (quadratic: heavy hits shake much more).
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	var s := _trauma * _trauma
	h_offset = (randf() * 2.0 - 1.0) * 0.25 * s
	v_offset = (randf() * 2.0 - 1.0) * 0.18 * s
