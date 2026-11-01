extends Action
## Light Screen: a wall of light rises around the user with Cobblemon's sequence, and its whole side
## takes half the special damage for "buff_dur" (a third less in a 2 vs 2): Main.screen_t, read by
## Damage.screen_mult. The side keeps it when the caster leaves or faints, and casting it again
## restarts the time. It is cast at the end of its active phase, so a hit during the startup stops
## it. Brick Break shatters it (Fighter.receive). Online the caster's owner gives it to every copy
## (Main.give_buff), and each machine works out the cut with its own copy of the clock.

var _aura := 0.0


func on_start() -> void:
	faces_rival = false
	tint_col = Roster.TYPE_COLOR.psychic
	play_sound(id, -2.0)


func in_startup(delta: float) -> void:
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)
	_aura -= delta
	if _aura <= 0.0:
		_aura = 0.06
		var c := l.center()
		var off: Vector3 = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.8), randf_range(-1, 1)).normalized() * l.data.height * 0.9
		l.main.vfx.burst("stars", c + off, -off.normalized(), Roster.TYPE_COLOR.psychic, 0.3)


func on_active() -> void:
	tint_k = 0.0
	var c := l.center()
	if l.main.fx:
		var me := {"root": l.global_position, "middle": c, "target": c, "height": l.data.height}
		l.main.fx.play_sequence(id, me, me)
	l.main.vfx.wave(l.global_position, 2.2, 0.35, Roster.TYPE_COLOR.psychic, 0.08)
	if not l.is_remote:
		l.main.give_buff("lightscreen", l, float(d.buff_dur))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.08, "stretch": 0.95, "anim": "status", "reset": t < 0.02}
		"active":
			return {"tilt": -0.05, "stretch": 1.06}
	return {}
