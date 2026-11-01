class_name BattleCamera
extends Camera3D
## Third-person camera. Free: turned with the right stick or the mouse.
## Locked on: sits behind the player looking at the rival and pulls back as they
## separate, to keep both on screen. Pulls back further for big Pokémon.
## It does not go through walls (it moves in) and its shake can be reduced in the options.
## First person (the "first_person" action): from the player's eyes, with its body out of this
## camera's view only, so its shadow and every other view of it stay. Free or locked on, the same;
## the opening, a KO and the end of a battle go back to third person.
## Aim assist (BattleRules): over the foe, turning is slower and the aim moves with the foe.

const MOUSE_SENS := 0.0026
const STICK_SENS := 2.6
## How far up it can look: further with true free aim, to aim at what flies; further still from
## the eyes, where nothing is in the way.
const PITCH_UP := 0.35
const PITCH_UP_FREE := 0.8
const PITCH_UP_EYES := 1.3
const AIM_RANGE := 100.0
const EYE_HEIGHT := 0.9                # of its height
const BODY_LAYER := 1 << 19            # the render layer only for the body hidden from the eyes
const ASSIST_MAX := 0.85               # how much it holds at 100 %

var main: Node
var target: Fighter
var yaw := 0.0
var pitch := -0.32
var _dist := 6.0
var _aim := Vector3.ZERO
var _trauma := 0.0
var _manual := 0.0          # time since the last manual turn
var _sphere := SphereShape3D.new()
## Locked on, a flick of the right stick (or a sweep of the mouse) moves the lock to the
## next target that side (Fighter.switch_target), souls style.
const FLICK := 0.75
const MOUSE_FLICK := 140.0
var _flick_ready := true
var _mouse_sweep := 0.0
var _was_locked := false
var first_person := false
var _hidden: Fighter                   # whose body is out of view, and the layers it had
var _hidden_layers := 1
var _over: Node3D                      # what the crosshair is on, and the point of its line there
var _over_at := Vector3.ZERO
var _stuck: Node3D                     # the same, a step ago: where on the foe (from its feet)
var _stuck_at := Vector3.ZERO
var _stuck_look := Vector3.FORWARD


func _ready() -> void:
	_sphere.radius = 0.35
	cull_mask &= ~BODY_LAYER


func shake_camera(k: float) -> void:
	_trauma = minf(1.0, _trauma + k * main.options.shake)


## A battle starts: free, the crosshair starts on the rival too, as when letting go of the lock.
func face_rival() -> void:
	_was_locked = true


func toggle_first_person() -> void:
	first_person = not first_person
	pitch = clampf(pitch, -1.1, _pitch_top())


func _pitch_top() -> float:
	if first_person:
		return PITCH_UP_EYES
	return PITCH_UP if main.legacy_aim else PITCH_UP_FREE


## Takes "who"'s body out of this camera's view (null: nobody's).
func _hide_body(who: Fighter) -> void:
	if who == _hidden:
		return
	if is_instance_valid(_hidden):
		_hidden.model.mesh_instance.layers = _hidden_layers
	_hidden = who
	if who:
		_hidden_layers = who.model.mesh_instance.layers
		who.model.mesh_instance.layers = BODY_LAYER


## Aim assist on turning: what is left of it (1 unless free and aimed at the foe).
func _drag() -> float:
	if main.aim_assist > 0.0 and target and is_instance_valid(target) and target.free_aim() and target.aiming_at_foe():
		return 1.0 - main.aim_assist * ASSIST_MAX
	return 1.0


## Aim assist on the foe's moves: whatever moved the spot under the crosshair since the last step
## (the foe or the player), the aim goes part of the way after it.
func _follow_foe() -> void:
	var foe: Node3D = _over if main.aim_assist > 0.0 and not main.paused and is_instance_valid(_over) and target.crosshair_aim() else null
	if foe and foe == _stuck:
		# Against the view of that step, not this one: the view catching up with a turn is not a move.
		var to: Vector3 = foe.global_position + _stuck_at - global_position
		var k: float = main.aim_assist * ASSIST_MAX
		yaw += angle_difference(atan2(-_stuck_look.x, -_stuck_look.z), atan2(-to.x, -to.z)) * k
		var rise := atan2(to.y, Vector2(to.x, to.z).length()) - atan2(_stuck_look.y, Vector2(_stuck_look.x, _stuck_look.z).length())
		pitch = clampf(pitch + rise * k, -1.1, _pitch_top())
	_stuck = foe
	if foe:
		_stuck_at = _over_at - foe.global_position
		_stuck_look = -global_transform.basis.z


## True free aim: the point in the world at the center of the screen. The first rival's body, wall
## or floor along the view (what projectiles stop at), or far off into the sky. The line starts
## level with the player: what is between the camera and the player is not aimed at.
func crosshair_point() -> Vector3:
	var look := -global_transform.basis.z
	var from := global_position + look * maxf(look.dot(target.center() - global_position), 0.0)
	var to := from + look * AIM_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, Combat.WORLD_LAYER)
	var wall: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if wall:
		to = wall.position
	var at := to
	_over = null
	for o in main.combat.targets:
		if main.combat.spares(target, o) or not o.hittable():
			continue
		var seg: Array = o.body()
		var near := Geometry3D.get_closest_points_between_segments(from, to, seg[0], seg[1])
		if near[0].distance_to(near[1]) < o.radius():
			to = near[0]
			at = near[1]
			_over = o
			_over_at = near[0]
	return at


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if target and is_instance_valid(target) and target.locked:
			_mouse_sweep += ev.relative.x
			if absf(_mouse_sweep) > MOUSE_FLICK:
				target.switch_target(1 if _mouse_sweep > 0.0 else -1)
				_mouse_sweep = 0.0
		var drag := _drag()
		yaw -= ev.relative.x * MOUSE_SENS * drag
		pitch = clampf(pitch - ev.relative.y * MOUSE_SENS * drag, -1.1, _pitch_top())
		_manual = 0.0


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_manual += delta
	_follow_foe()
	var st := Input.get_vector("cam_left", "cam_right", "cam_down", "cam_up")
	_mouse_sweep = move_toward(_mouse_sweep, 0.0, delta * 400.0)
	if target.locked:
		# A flick switches target; the stick has to come back before the next one.
		if absf(st.x) > FLICK and _flick_ready:
			_flick_ready = false
			target.switch_target(1 if st.x > 0.0 else -1)
		elif absf(st.x) < 0.3:
			_flick_ready = true
		st.x = 0.0
	if st.length() > 0.1:
		var drag := _drag()
		yaw -= st.x * STICK_SENS * delta * drag
		pitch = clampf(pitch + st.y * STICK_SENS * 0.6 * delta * drag, -1.1, _pitch_top())
		_manual = 0.0
	var me := target
	var height: float = me.data.height
	var eyes: bool = first_person and me.state != "ko" and main._end_t < 0.0
	var eye := me.global_position + Vector3.UP * height * EYE_HEIGHT
	eye.y = maxf(eye.y, main.ground_y + 0.2)
	var pivot := eye if eyes else me.global_position + Vector3.UP * (height * 0.85 + 0.45)
	var bend := 0.0 if eyes else clampf(height - 1.0, 0.0, 1.5) * 0.12
	var base := 2.6 + height * 1.45
	# Locked on whatever it aims at: the rival, or Substitute's doll if it fell for it.
	var r: Node3D = me.aim_target()
	var locked_on: bool = me.locked and r != null and is_instance_valid(r) and not (r is Fighter and r.state == "ko")
	# Letting go of the lock with true free aim: the crosshair starts on the rival, not on the floor.
	if _was_locked and not me.locked and not main.legacy_aim and r != null and is_instance_valid(r):
		var to: Vector3 = r.center() - pivot
		pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()) + bend, -1.1, _pitch_top())
	_was_locked = me.locked
	if locked_on:
		var toward := r.global_position - me.global_position
		var sep := Vector2(toward.x, toward.z).length()
		var yaw_target := atan2(-toward.x, -toward.z)
		# The stick can pull it off a little; then it comes back on its own.
		var pull := 6.0 if _manual > 0.4 else 1.5
		yaw = lerp_angle(yaw, yaw_target, 1.0 - exp(-pull * delta))
		var pitch_target := clampf(-0.28 - (r.global_position.y - me.global_position.y) * 0.04 - sep * 0.004, -0.75, -0.12)
		if eyes:
			var to_rival: Vector3 = r.center() - eye
			pitch_target = clampf(atan2(to_rival.y, Vector2(to_rival.x, to_rival.z).length()), -1.1, _pitch_top())
		if _manual > 0.6:
			pitch = lerpf(pitch, pitch_target, 1.0 - exp(-(6.0 if eyes else 3.0) * delta))
		base += clampf(sep * 0.1, 0.0, 2.4) + float(r.data.height) * 0.3
	_dist = lerpf(_dist, base, 1.0 - exp(-4.0 * delta))
	# Big Pokémon would hide the rival: the camera goes a bit higher and over the shoulder.
	var shoulder := clampf(height - 1.0, 0.0, 1.5) * 0.55
	var pitch_final := pitch - bend
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch_final)
	if eyes:
		var ahead := eye + b * Vector3(0, 0, -6.0)
		if _opening(eye, ahead):
			_hide_body(null)
			return
		_hide_body(me)
		global_position = eye
		_aim = ahead
		look_at(_aim, Vector3.UP)
	else:
		_hide_body(null)
		var desired := pivot + b * Vector3(shoulder, 0, _dist)
		# Walls and stands: a small sphere swept from the pivot, so it moves in before going
		# behind them or into the seats (layer 1 and the camera's layer, not the invisible wall).
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _sphere
		q.transform = Transform3D(Basis(), pivot)
		q.motion = desired - pivot
		q.collision_mask = 1 | Arena.CAMERA_LAYER
		var safe: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(q)
		if safe.size() > 0 and safe[0] < 1.0:
			desired = pivot + (desired - pivot) * safe[0]
		desired.y = maxf(desired.y, main.ground_y + 0.5)
		if _opening(desired, pivot.lerp(r.center(), 0.4) if locked_on else pivot + b * Vector3(shoulder, 0, -6.0)):
			return
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


## The battle's opening (main.intro_t): it starts beside your trainer, who throws the ball
## toward the field, and glides to its place behind your Pokémon as it comes out. True
## while it is in charge.
func _opening(desired: Vector3, look_point: Vector3) -> bool:
	if main.intro_t <= 0.0 or main.trainers.is_empty() or not is_instance_valid(main.trainers[0]):
		return false
	var e: float = main.INTRO - main.intro_t
	var w := 1.0 - smoothstep(1.1, 2.0, e)
	if w <= 0.0:
		return false
	var tr: Node3D = main.trainers[0]
	var field := Vector3(-signf(tr.global_position.x), 0.0, 0.0)
	var shot: Vector3 = tr.global_position + Vector3(0.0, 1.6, 4.6) + field * 1.4
	var look: Vector3 = tr.global_position + Vector3.UP * 1.1 + field * 2.2
	global_position = desired.lerp(shot, w)
	_aim = look_point.lerp(look, w)
	look_at(_aim, Vector3.UP)
	h_offset = 0.0
	v_offset = 0.0
	return true
