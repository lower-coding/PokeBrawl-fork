extends Action
## Confusion: a hand sweeps forward and a purple ripple spreads in front of it, close and wide.
## The hit always confuses ("secondary"), up to what Fighter.confuse allows. Not a projectile: it
## cannot be sent back.

const COLOR := Color(0.72, 0.45, 1.0)
const RING := "res://fx/tex/custom/psy_ring.png"


func on_start() -> void:
	turn_mult = 2.5


func in_startup(_delta: float) -> void:
	tint_col = COLOR
	tint_k = 0.3 * (t / d.startup)


func on_active() -> void:
	tint_k = 0.0
	var pos: Vector3 = l.center()
	hit({"shape": "sphere", "center": Vector3(0, l.data.height * 0.5, l.data.radius + d.reach * 0.5), "radius": d.radius,
		"on_strike": func(o: Node, res: String):
			if res == "hit":
				l.main.audio.play_sound("confusion_hit", o.center(), -3.0)})
	_ripple(pos)
	play_sound(id, -2.0)


## Three rings across the way it faces, widening as they go, up to about what the hit covers.
func _ripple(pos: Vector3) -> void:
	var fwd := l.forward()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	for i in 3:
		var at: Vector3 = pos + fwd * (l.data.radius + 0.5 + i * 0.9)
		var size: float = 1.2 + i * 0.8
		l.main.vfx.flat_sprite(RING, 1, size, at, basis, 0.3, COLOR, 0.0,
			func(n: MeshInstance3D, k: float):
				n.scale = Vector3.ONE * (1.0 + snappedf(k * 0.2, 0.1))
				n.material_override.set_shader_parameter("tint", Color(COLOR, 1.0 - snappedf(k, 0.34))), 0.12)


func on_recovery() -> void:
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.08, "stretch": 0.97, "anim": "confusion", "reset": t < 0.02}
		"active":
			return {"tilt": 0.14, "stretch": 1.04}
	return {}
