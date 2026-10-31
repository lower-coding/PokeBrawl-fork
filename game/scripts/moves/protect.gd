extends Action
## Protect: a wall. Where Detect is a counter (a short window that stuns whoever hits it), the
## barrier is longer, stays up through everything in its window and does not stun: it buys
## safety rather than a punish. Status moves stop too. If nothing comes it is left open; if it
## stopped something, it comes out of it soon. Contact moves with Unseen Fist go through
## (Fighter.receive).

var _landed := false
var _fx_at := -1.0


func on_start() -> void:
	faces_rival = true
	turn_mult = 3.0
	play_sound("protect", -2.0)


func on_active() -> void:
	tint_col = Color(0.45, 0.85, 0.6)
	tint_k = 0.4
	l.main.vfx.cobble("protect_actorcolor1", l.center(), null, l.data.height)
	l.main.vfx.light(l.center(), Color(0.45, 0.85, 0.6), 2.5, 4.0, d.active)


func in_active(_delta: float) -> void:
	tint_k = 0.15 + 0.25 * (1.0 - t / d.active)


## Called by the fighter when it receives a hit: during the window, it stops it and stays up.
func intercept(_info: Dictionary) -> String:
	if phase != "active":
		return ""
	_landed = true
	landed = true
	# A stream's ticks or a flurry's blows: the barrier answers once in a while.
	if total - _fx_at > 0.15:
		_fx_at = total
		var vfx: Vfx = l.main.vfx
		vfx.cobble("protect_block", l.center(), null, l.data.height)
		vfx.wave(l.global_position, 2.0, 0.25, Color(0.45, 0.85, 0.6), 0.08)
		vfx.text(l.center() + Vector3.UP * 0.9, l.tr("Protected!"), Color(0.6, 0.95, 0.75))
		l.main.audio.play_sound("armor", l.global_position, -2.0)
	return "protected"


func on_recovery() -> void:
	tint_k = 0.0


func in_recovery(_delta: float) -> void:
	if _landed and t >= d.recovery_on_hit:
		finish(false)


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "stretch": 0.96}
		"active":
			return {"tilt": -0.05, "stretch": 0.95}
	return {"tilt": 0.1 * (1.0 - t / d.recovery), "stretch": 0.98}
