extends Action
## Bulk Up: it tenses its muscles, open to hits: one that cuts the flex costs it the boosts, which
## only come at its end. +1 Attack and +1 Defense through boost(), so the HUD's stat tags show them.
## Stages last until a switch and nothing clears them in 1 vs 1, so it has "uses" per battle.

var _aura := 0.0


func on_start() -> void:
	faces_rival = false
	play_sound("bulkup", -2.0)


func in_startup(delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.fighting
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
		l.main.vfx.burst("stars", from_pos, (c - from_pos).normalized(), Roster.TYPE_COLOR.fighting, 0.25)


func on_recovery() -> void:
	tint_k = 0.0
	l.boost("atk", 1)
	l.boost("def", 1)
	l.main.vfx.burst("stars", l.center(), Vector3.UP, Roster.TYPE_COLOR.fighting, 1.6)
	l.main.vfx.wave(l.global_position, 2.0, 0.3, Roster.TYPE_COLOR.fighting, 0.06)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.08, "stretch": 0.94}
		"active":
			return {"tilt": -0.12, "stretch": 1.05 + 0.03 * sin(total * 30.0)}
	return {"stretch": 1.03}
