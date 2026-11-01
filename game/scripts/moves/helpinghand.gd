extends Action
## Helping Hand: a short clap with a yellow spark. The ally's next damaging move within "buff_dur"
## hits "help_mult" times as hard: starting that move takes the boost (Fighter.start), and every
## hit and shot of that use carries it (Combat._helped). A status move leaves it waiting, a miss
## wastes it. The boost goes out at the active phase, so a hit during the startup means no help.
## Its cooldown is longer than the boost lasts, so it cannot stack.

func on_start() -> void:
	faces_rival = false
	tint_col = Fighter.HELP_COLOR
	l.main.audio.play_sound(id, l.global_position, -2.0, 1.3)


func in_startup(_delta: float) -> void:
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func on_active() -> void:
	tint_k = 0.0
	l.main.vfx.burst("stars", l.point("locator_hand_primary"), Vector3.UP, Fighter.HELP_COLOR, 0.8)
	var mate := l.ally()
	if mate == null or l.is_remote:
		return
	l.main.give_buff("helped", mate, float(d.buff_dur), float(d.help_mult))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"stretch": 0.95, "anim": "status", "reset": t < 0.02}
		"active":
			return {"stretch": 1.06}
	return {}
