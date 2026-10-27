class_name Combat
extends Node
## Resolves hits: tests every active volume against each target's body, applies damage
## with the type chart, knockback, stun and hitstop, and notifies effects, sound and
## rumble. Projectiles move here with a swept test (they never pass through anything,
## however fast) and collide with walls. The logic does not depend on the visual
## effects.

const WORLD_LAYER := 1

var main: Node
var hits: Array = []
var projectiles: Array = []
var targets: Array = []        # fighters and decoys (anything that can be hit)
var clock := 0.0


func add_hit(g: Hit) -> Hit:
	hits.append(g)
	return g


func remove(g: Hit) -> void:
	if g:
		g.active = false


## When a battle ends nothing must be left active.
func clear() -> void:
	for p in projectiles:
		if is_instance_valid(p.node):
			p.node.queue_free()
	hits.clear()
	projectiles.clear()


func remove_from(user: Node) -> void:
	for g in hits:
		if g.user == user:
			g.active = false


# ---------------------------------------------------------------- projectiles

## p: {user, pos, velocity, radius, lifetime, gravity, hit (a Hit in the world), node
## (visual that moves with it), on_impact (Callable(pos, against)), pierces}
func projectile(p: Dictionary) -> Dictionary:
	p.merge({"radius": 0.3, "lifetime": 2.0, "gravity": 0.0, "pierces": false, "age_t": 0.0, "alive": true,
		"homing": 0.0, "target": null}, false)
	p.hit.local = false
	p.hit.shape = "sphere"
	p.hit.radius = p.radius
	projectiles.append(p)
	return p


func _physics_process(delta: float) -> void:
	clock += delta
	_move_projectiles(delta)
	var i := 0
	while i < hits.size():
		var g: Hit = hits[i]
		if not g.active or (g.user != null and not is_instance_valid(g.user)):
			hits.remove_at(i)
			continue
		if g.lifetime >= 0.0:
			g.lifetime -= delta
			if g.lifetime < 0.0:
				hits.remove_at(i)
				continue
		if g.user == null or not g.user.frozen():
			for o in targets:
				_try(g, o)
		i += 1


func _move_projectiles(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var i := 0
	while i < projectiles.size():
		var p: Dictionary = projectiles[i]
		p.age_t += delta
		if p.homing > 0.0 and p.target and is_instance_valid(p.target):
			var toward: Vector3 = (p.target.center() - p.pos).normalized() * p.velocity.length()
			p.velocity = p.velocity.lerp(toward, clampf(p.homing * delta, 0.0, 1.0))
		p.velocity.y -= p.gravity * delta
		var before: Vector3 = p.pos
		var after: Vector3 = before + p.velocity * delta
		var finished: bool = p.age_t >= p.lifetime
		var against := ""
		var where := after
		# Wall or floor in the way.
		var q := PhysicsRayQueryParameters3D.create(before, after + p.velocity.normalized() * p.radius, WORLD_LAYER)
		var hit: Dictionary = space.intersect_ray(q)
		if hit:
			finished = true
			against = "world"
			where = hit.position
		# Bodies in the way (swept as a capsule).
		if not finished or against == "world":
			for o in targets:
				if o == p.user or not o.hittable():
					continue
				var seg: Array = o.body()
				var d := dist_seg_seg(before, where, seg[0], seg[1])
				if d < p.radius + o.radius():
					p.hit.center = closest_on_seg(o.center(), before, where)
					var res := apply(p.hit, o, p.hit.center)
					if res != "" and not p.pierces:
						finished = true
						against = "body"
						where = p.hit.center
						break
		p.pos = where
		if is_instance_valid(p.get("node")):
			p.node.global_position = where
			if p.velocity.length() > 0.1:
				p.node.look_at(where + p.velocity, Vector3.UP if absf(p.velocity.normalized().y) < 0.98 else Vector3.RIGHT)
		if finished:
			p.alive = false
			if p.has("on_impact") and p.on_impact.is_valid():
				p.on_impact.call(where, against)
			if is_instance_valid(p.get("node")):
				p.node.queue_free()
			projectiles.remove_at(i)
		else:
			i += 1


# ---------------------------------------------------------------- tests

func _try(g: Hit, o: Node) -> void:
	if o == g.user or not o.hittable():
		return
	var id := o.get_instance_id()
	if g.hit_list.has(id) and (g.interval <= 0.0 or clock - g.hit_list[id] < g.interval):
		return
	var point = _touches(g, o)
	if point == null:
		return
	apply(g, o, point)


## Returns the contact point, or null if there is no contact.
func _touches(g: Hit, o: Node):
	var m := g.base()
	var seg: Array = o.body()
	var r: float = o.radius()
	match g.shape:
		"sphere":
			var c := m * g.center
			var p := closest_on_seg(c, seg[0], seg[1])
			if c.distance_to(p) < g.radius + r:
				return p.lerp(c, 0.5)
		"capsule":
			var a := m * g.a
			var b := m * g.b
			if dist_seg_seg(a, b, seg[0], seg[1]) < g.radius + r:
				return closest_on_seg(o.center(), a, b)
		"cone":
			var org := m * g.center
			var dir := (m.basis * g.dir).normalized()
			for k in 5:
				var s: Vector3 = seg[0].lerp(seg[1], k / 4.0)
				var v := s - org
				var d := v.length()
				if d - r > g.length or d < 0.01:
					continue
				var ang := v.angle_to(dir)
				if ang <= g.angle + atan2(r, d):
					return s
		"ring":
			var c := m * g.center
			if g.ground_only and not o.on_floor():
				return null
			var h := Vector2(o.global_position.x - c.x, o.global_position.z - c.z).length()
			if h >= g.r_in - r and h <= g.r_out + r and absf(o.global_position.y - c.y) < 1.5:
				return o.global_position + Vector3.UP * 0.2
	return null


## Applies a hit to a target. Returns the result ("hit", "armor", "dodged",
## "detect"...) or "" if nothing happened.
func apply(g: Hit, o: Node, point: Vector3) -> String:
	# Streams (hits that repeat): from the second impact on it counts as "flow".
	var flow := g.interval > 0.0 and g.hit_list.has(o.get_instance_id())
	g.hit_list[o.get_instance_id()] = clock
	var attacker: Node = g.user
	var mult := Roster.affinity(g.type, o.types)
	var info := {"hit": g, "attacker": attacker, "point": point, "affinity": mult, "flow": flow}
	# Online, on the rival's copy: damage is decided by the receiver. Here we only
	# predict the feel of the hit so it responds instantly.
	if o is Fighter and o.is_remote:
		return _predicted_hit(g, o, point, mult, flow)
	var hp_before: float = o.hp if o is Fighter else 0.0
	var res: String = o.receive(info)
	# Online, if the attacker is the rival's copy, the hit is confirmed to it.
	if attacker is Fighter and attacker.is_remote and res != "" and main.net:
		main.net.send_event({"t": "hit", "res": res, "damage": hp_before - (o.hp if o is Fighter else 0.0),
			"affinity": mult, "point": point, "move": g.move_id})
	if res == "":
		return ""
	if g.on_strike.is_valid():
		g.on_strike.call(o, res)
	if res in ["hit", "armor"]:
		var strength := g.strength
		if attacker and is_instance_valid(attacker):
			attacker.on_strike(o, g, res)
			attacker.freeze(g.hitstop)
		main.vfx.impact(point, g.type, strength, g.contact)
		var now := Time.get_ticks_msec()
		if now - int(g.get_meta("fx_ms", -100000)) > 280:
			g.set_meta("fx_ms", now)
			var looks = attacker.center() if attacker and is_instance_valid(attacker) else null
			for piece in Moves.DATA.get(g.move_id, {}).get("fx_hit", []):
				main.vfx.cobble(piece, point, looks, o.data.height)
		main.audio.impact(g.type, strength, point)
		main.shake_camera(0.08 + 0.12 * strength, point)
		for l in [attacker, o]:
			if l and is_instance_valid(l) and l.has_method("rumble_pad"):
				l.rumble_pad(0.2 + 0.25 * strength, 0.35 + 0.3 * strength, 0.08 + 0.06 * strength)
		if mult > 1.05:
			main.vfx.text(point + Vector3.UP * 0.8, main.tr("Effective!"), Color("ffd93a"))
			main.hud.log_entry(main.tr("It's super effective!"))
		elif mult < 0.95:
			main.vfx.text(point + Vector3.UP * 0.8, main.tr("Not very effective"), Color("b8bcc8"))
			main.hud.log_entry(main.tr("It's not very effective..."))
	return res


## Own hit on the rival's copy online: effects, hitstop, landing (for combos) and
## energy right away. No damage: the rival confirms that.
func _predicted_hit(g: Hit, o: Fighter, point: Vector3, mult: float, flow: bool) -> String:
	if o.invulnerable > 0.0 or o.state == "ko":
		return ""
	var attacker: Node = g.user
	var strength := g.strength
	if attacker is Fighter and is_instance_valid(attacker):
		attacker.on_strike(o, g, "hit")
		attacker.energy = minf(Fighter.ENERGY_MAX, attacker.energy + 3.0)
		if attacker.boosted_hits > 0 and g.cat == "physical":
			attacker.boosted_hits -= 1
		if not flow:
			attacker.freeze(g.hitstop)
			o.freeze(g.hitstop)
	if not flow or randf() < 0.4:
		main.vfx.impact(point, g.type, strength, g.contact)
		main.audio.impact(g.type, strength, point)
		main.shake_camera(0.08 + 0.12 * strength, point)
		if attacker is Fighter and attacker.has_method("rumble_pad"):
			attacker.rumble_pad(0.2 + 0.25 * strength, 0.35 + 0.3 * strength, 0.08 + 0.06 * strength)
	if g.on_strike.is_valid():
		g.on_strike.call(o, "hit")
	return "hit"


# ---------------------------------------------------------------- geometry

static func closest_on_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return a + ab * t


## Minimum distance between two segments (for capsules and sweeps).
static func dist_seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return p1.distance_to(p2)
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var den := a * e - bb * bb
			s = clampf((bb * f - c * e) / den, 0.0, 1.0) if den > 0.000001 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
