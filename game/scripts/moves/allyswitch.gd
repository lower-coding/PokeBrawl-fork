extends Action
## Ally Switch: it snaps a hand toward its ally, both flash and each appears where the other
## stood, with a light trail between the two. Each keeps its facing, action, stun and status, but
## not its speed. Shots flying at either now fly at the other, which is the point of it: taking a
## shot meant for a frail partner. Nothing here goes through Combat, so friendly fire and Protect
## do not matter. Fighter.refused turns down a press with no ally under the crosshair; if the ally
## is gone by the time it goes off, it was free. Online its owner decides and tells every copy
## (Combat.swap_allies), or each would swap at a slightly different moment and place.

func on_start() -> void:
	faces_rival = false
	tint_col = Combat.ALLY_SWITCH_COLOR


func in_startup(_delta: float) -> void:
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func on_active() -> void:
	tint_k = 0.0
	if l.is_remote:
		return
	var mate := l.ally()
	if not _can_swap(mate):
		l.energy = minf(Fighter.ENERGY_MAX, l.energy + float(d.cost))
		free_of_cost = true
		l.main.vfx.text(l.center() + Vector3.UP * 0.9, l.tr("But it failed!"), Color(0.75, 0.77, 0.85))
		return
	var here := l.global_position
	var there := mate.global_position
	l.main.combat.swap_allies(l, mate, there, here)
	if l.main.net:
		l.main.net.send_event({"t": "ally_switch", "by": l.main.net.seat_of(l.slot), "to": l.main.net.seat_of(mate.slot), "by_to": there, "to_to": here})
	l.main.session.event("ally_switch", {"by": l.species, "with": mate.species})


## Still there, as it was when the press was let through: on the field, in sight, and neither over
## a void (the caster would drop into the pit instead).
func _can_swap(mate: Fighter) -> bool:
	if mate == null or mate.state in ["recall", "enter"] or mate.out_of_sight():
		return false
	var arena: Arena = l.main.arena
	return arena.void_y == -INF or (arena.inside(l.global_position) and arena.inside(mate.global_position))


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": 0.12, "stretch": 0.96, "anim": "status", "reset": t < 0.02}
		"active":
			return {"tilt": 0.05, "stretch": 1.04}
	return {}
