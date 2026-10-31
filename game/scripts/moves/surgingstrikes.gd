extends Action
## Surging Strikes: suds at its feet, then three blows of water, hands in turn, each with a
## splash and a trail. All critical (Damage.CRIT) and, as in the games, each one counts as a
## contact hit. The same damage as Wicked Blow, but spread out: a flurry cut short loses part of
## it. Blows after the first count as a combo (less each), so each is worth more to make the
## whole flurry its "damage".

## What the three blows add up to with the combo falloff (Fighter.receive: 1, 0.88, 0.76).
const COMBO_SUM := 2.64

var _done := 0


func on_start() -> void:
	turn_mult = 2.5
	_done = 0
	play_sound("surgingstrikes", -2.0)


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.3 * clampf(t / maxf(startup_len(), 0.01), 0.0, 1.0)


func in_active(_delta: float) -> void:
	var blows: int = d.blows
	var due := mini(int(t / (d.active / blows)) + 1, blows)
	while _done < due:
		_blow(_done, _done == blows - 1)
		_done += 1


func _blow(i: int, last: bool) -> void:
	tint_k = 0.0
	advance_by(d.advance / d.active * 0.6)
	var hand := "locator_hand_primary" if i % 2 == 0 else "locator_hand_secondary"
	var side: float = (0.35 if i % 2 == 0 else -0.35) * l.data.radius
	var g := hit({"shape": "sphere", "center": Vector3(side, l.data.height * 0.6, l.data.radius + d.reach * 0.5), "radius": d.radius,
		"lifetime": 0.07, "damage": d.damage / COMBO_SUM, "quiet": i > 0, "stun": d.stun if not last else d.stun_last,
		"hitstop": 0.05 if not last else 0.1})
	var main: Node = l.main
	g.on_strike = func(o: Node, _res: String):
		if o is Node3D:
			main.audio.play_sound("surgingstrikes_hit", (o as Node3D).global_position, -3.0)
	var vfx: Vfx = main.vfx
	vfx.ribbon(func(): return [l.center(), l.point(hand)], Roster.TYPE_COLOR.water, 0.12, 0.16)
	var front: Vector3 = l.center() + l.forward() * (l.data.radius + d.reach * 0.6)
	vfx.cobble("waterpulse_actorsplash", front, front + l.forward(), 1.0)
	vfx.burst("water_fx", front, l.forward(), Color(0, 0, 0, 0), 0.5)
	main.audio.play_sound("dodge", l.global_position, -8.0, 1.1 + 0.05 * i)
	if last:
		main.shake_camera(0.15, front)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.2, "stretch": 0.9}
		"active":
			var k := float(_done % 2)
			# Each blow starts the swing over, so the one punch the model has reads as three.
			return {"tilt": 0.3 + 0.08 * k, "side": 0.12 - 0.24 * k, "stretch": 1.04 + 0.04 * k, "anim": "physical", "reset": fmod(t, float(d.active) / d.blows) < 0.02}
	return {"tilt": 0.2 * (1.0 - t / maxf(float(d.recovery), 0.01))}
