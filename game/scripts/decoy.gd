class_name Decoy
extends Node3D
## Substitute decoy: a copy of the Pokémon, standing still in its idle animation, that
## combat treats as one more target. The first hit breaks it (a puff of smoke) and the
## attacker feels it as a normal hit. It can be told apart from the real one: it has
## no shadow and does not breathe in sync with it.

var main: Node
var user: Fighter
var data: Dictionary
var types: Array = []
var _model: PokeModel
var _time_left := 4.0


func setup(m: Node, l: Fighter, dur: float) -> void:
	main = m
	user = l
	data = l.data
	types = l.types
	_time_left = dur
	_model = PokeModel.new()
	_model.setup(l.species)
	_model.scale = l.model.scale
	_model.rotation.y = PI
	add_child(_model)
	_model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = l.global_position
	rotation.y = l.face_yaw
	if data.get("levitates", false):
		_model.position.y = 0.38
	_model.play("air_idle" if data.get("levitates", false) and _model.has_anim("air_idle") else "battle_idle", 0.0)


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		undo()


# ---------------------------------------------------------------- what combat asks

func hittable() -> bool:
	return true


func body() -> Array:
	var r := radius()
	return [global_position + Vector3.UP * r, global_position + Vector3.UP * maxf(r, data.height - r)]


func radius() -> float:
	return data.radius


func center() -> Vector3:
	return global_position + Vector3.UP * data.height * 0.5


func on_floor() -> bool:
	return not data.get("levitates", false)


func receive(_info: Dictionary) -> String:
	undo()
	return "hit"


func undo() -> void:
	if is_queued_for_deletion():
		return
	main.vfx.burst("shadow", center(), Vector3.UP, Color(0, 0, 0, 0), 1.6)
	main.vfx.burst("smoke", center(), Vector3.UP, Color(0, 0, 0, 0), 1.2)
	main.audio.play_sound("dodge", global_position, -4.0, 0.7)
	main.combat.targets.erase(self)
	queue_free()
