extends Action
## Water Shuriken: three shuriken in a row during the active phase, each one aimed at the
## rival as it is released (pressure with several projectiles: you have to move in a
## curve). Uses Cobblemon's three-throw animation.

var _thrown := 0


func on_start() -> void:
	turn_mult = 3.0
	no_gravity = not l.is_on_floor()
	if no_gravity:
		l.velocity.y = 1.0


func in_startup(_delta: float) -> void:
	tint_col = Roster.TYPE_COLOR.water
	tint_k = 0.2 * (t / d.startup)


func in_active(_delta: float) -> void:
	var touches := int(t / (d.active / d.count))
	while _thrown <= mini(touches, d.count - 1):
		_throw(_thrown)
		_thrown += 1


func _throw(i: int) -> void:
	var hand := "locator_hand_primary" if i % 2 == 0 else "locator_hand_secondary"
	var from_pos := l.point(hand) + l.forward() * 0.3
	var dir := aim(0.9)
	var g := Hit.new()
	g.user = l
	g.move_id = id
	g.type = "water"
	g.cat = "special"
	g.damage = d.damage
	g.push = d.push
	g.stun = d.stun
	g.strength = d.strength
	g.contact = false
	var vfx: Vfx = l.main.vfx
	l.main.combat.projectile({"user": l, "pos": from_pos, "velocity": dir * d.speed, "radius": d.radius, "lifetime": d.reach / d.speed,
		"hit": g, "node": _shuriken(), "on_impact": func(pos: Vector3, _c: String):
			vfx.burst("water_fx", pos, -dir, Color(0, 0, 0, 0), 0.6)})
	vfx.burst("water_fx", from_pos, dir, Color(0, 0, 0, 0), 0.3)
	play_sound("watershuriken", -4.0)


## A Cobblemon shuriken that spins edge-on as it flies.
func _shuriken() -> Node3D:
	var root := Node3D.new()
	var s := Sprite3D.new()
	s.texture = load("res://fx/tex/moves/watershuriken.png")
	s.pixel_size = 0.03
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.rotation.x = -PI * 0.5
	s.modulate = Color(0.8, 0.95, 1.0)
	root.add_child(s)
	l.main.vfx.add_child(root)
	var vfx: Vfx = l.main.vfx
	vfx.live(root, d.reach / d.speed + 0.1, func(_k: float):
		if is_instance_valid(s):
			s.rotation.y += 0.6)
	return root


func on_recovery() -> void:
	no_gravity = false
	tint_k = 0.0


func pose() -> Dictionary:
	match phase:
		"startup":
			return {"tilt": -0.1, "anim": d.get("anim", ""), "reset": t < 0.02}
		"active":
			return {"tilt": 0.12, "side": 0.2 * sin(t * 30.0)}
	return {}
