extends Action
## Counter: a stance. A physical hit from within "range" meters still deals its full damage, but
## the user does not flinch and the attacker takes "mult" times as much and is stunned. Special
## hits, status moves and physical hits from further away do not count and cut the stance as
## usual. Ghost types take a quarter, as every immunity here (Roster.NOTHING). It goes through
## effect(), as Rough Skin and Detect do, which reaches an online rival; a hit volume would not,
## since the target's machine decides hits. Several small blows beat its payout: the first one
## triggers it.


func on_start() -> void:
	turn_mult = 3.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.fighting
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func in_active(_delta: float) -> void:
	tint_k = 0.3


## Called by the fighter after a hit has dealt its damage: true if it was paid back.
func took_hit(info: Dictionary, damage: float) -> bool:
	var at = info.attacker
	if phase != "active" or info.hit.cat != "physical" or not at or not is_instance_valid(at):
		return false
	if l.global_position.distance_to(at.global_position) > d.range:
		return false
	var back: float = damage * d.mult * (Roster.NOTHING if Roster.immune(d.type, at.types) else 1.0)
	at.effect("damage", back)
	at.effect("stun", d.rival_stun)
	var vfx: Vfx = l.main.vfx
	vfx.number(at.center(), back, 1.0)
	vfx.cobble("closecombat_targetsparks", at.center(), l.center(), at.data.height)
	vfx.text(l.center() + Vector3.UP * 0.9, l.tr("Counter!"), Roster.TYPE_COLOR.fighting)
	l.main.shake_camera(0.2, at.center())
	play_sound("closecombat", 0.0)
	landed = true
	_go_to("recovery")
	return true


func on_recovery() -> void:
	tint_k = 0.0


func in_recovery(_delta: float) -> void:
	if landed and t >= d.recovery_on_hit:
		finish(false)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.18, "stretch": 0.92}
		"active":
			return {"tilt": -0.12, "side": 0.1, "stretch": 0.94}
	if landed:
		return {"tilt": 0.35, "stretch": 1.08, "anim": "physical", "reset": t < 0.02}
	return {"tilt": 0.12 * (1.0 - t / d.recovery)}
