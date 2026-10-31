extends Action
## Teleport: gone for "active" seconds and back "dist" metres along the way it last moved
## (Fighter.last_move), at the height it left. It travels as very fast movement, so walls stop it,
## and it can leave a stage's edge ("off_edge"). It cannot be hit while gone.

const COLOR := Color(0.7, 0.35, 0.85)

var _dir := Vector3.FORWARD


func on_start() -> void:
	faces_rival = false
	no_brake = true
	_dir = l.last_move if l.last_move != Vector3.ZERO else l.forward()


func on_active() -> void:
	no_gravity = true
	hides_body = true
	l.invulnerable = 0.02
	_flash()
	play_sound(id, -2.0)


func in_active(_delta: float) -> void:
	l.invulnerable = 0.02
	# Online, the copy just follows the rival's position.
	if not l.is_remote:
		l.velocity = _dir * d.dist / d.active


func on_recovery() -> void:
	no_gravity = false
	no_brake = false
	hides_body = false
	l.velocity = Vector3.ZERO
	_flash()


func _flash() -> void:
	l.main.vfx.burst("shadow", l.center(), Vector3.UP, COLOR, 1.2)
	l.main.vfx.light(l.center(), COLOR, 3.0, 4.0, 0.15)
