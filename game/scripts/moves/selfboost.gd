extends Action
## Bulk Up, Calm Mind and Agility (same script, different data): it gathers itself, open to hits:
## one that cuts it costs it the boosts, which only come at its end. "boosts" through boost(), so
## the HUD's stat tags show them. Stages last until a switch and nothing clears them in 1 vs 1, so
## each has "uses" per battle. "ring": a slow ring closes in on it while it lasts (Calm Mind).

const RING := "res://fx/tex/custom/psy_ring.png"

var _aura := 0.0
var _ring: MeshInstance3D


func on_start() -> void:
	faces_rival = false
	play_sound(id, -2.0)
	if d.get("ring", false):
		var col := _color()
		_ring = l.main.vfx.flat_sprite(RING, 1, 4.2, l.global_position + Vector3.UP * 0.1, Basis(Vector3.RIGHT, -PI * 0.5),
			startup_len() + d.active, col, 0.0, func(n: MeshInstance3D, k: float):
				n.scale = Vector3.ONE * (1.0 - snappedf(k * 0.7, 0.1))
				n.global_position = l.global_position + Vector3.UP * 0.1)


func _color() -> Color:
	return Roster.TYPE_COLOR[d.type]


func in_startup(delta: float) -> void:
	tint_col = _color()
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_gather(delta)


func in_active(delta: float) -> void:
	tint_k = 0.3 * sin(t / d.active * PI) + 0.1
	_gather(delta)


## The aura closing in on the body, Close Combat's.
func _gather(delta: float) -> void:
	_aura -= delta
	if _aura <= 0.0:
		_aura = 0.06
		var c := l.center()
		var from_pos: Vector3 = c + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized() * l.data.height * 0.8
		l.main.vfx.burst("stars", from_pos, (c - from_pos).normalized(), _color(), 0.25)


func on_recovery() -> void:
	tint_k = 0.0
	for stat in d.boosts:
		l.boost(stat, int(d.boosts[stat]))
	l.main.vfx.burst(d.get("particles", "stars"), l.center(), Vector3.UP, _color(), 1.6)
	l.main.vfx.wave(l.global_position, 2.0, 0.3, _color(), 0.06)


func on_end(_interrupted: bool) -> void:
	if is_instance_valid(_ring):
		_ring.visible = false


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.08, "stretch": 0.94, "anim": "status", "reset": t < 0.02}
		"active":
			return {"tilt": -0.12, "stretch": 1.05 + 0.03 * sin(total * 30.0)}
	return {"stretch": 1.03}
