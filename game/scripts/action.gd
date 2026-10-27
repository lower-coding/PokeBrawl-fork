class_name Action
extends RefCounted
## A move in progress. Common base: three phases with their timings (from
## Moves.DATA) and hooks that each move overrides:
##   startup   visible wind-up (this is where the opponent reads what is coming)
##   active    the hit volumes exist
##   recovery  vulnerable; depending on the move it can be cancelled or not
## "hold" moves extend the active phase while the button is held, up to "max";
## "chargeable" moves extend the startup and store how much was charged.

var l: Fighter
var id := ""
var d: Dictionary
var button := ""
var extra := {}
var t := 0.0              # time inside the current phase
var total := 0.0          # time since the move started
var phase := "startup"
var finished := false
var landed := false
var charge := 0.0         # 0 to 1 for chargeable moves

# What the action tells the fighter while it lasts.
var moves_freely := false
var move_mult := 0.3
var no_brake := false
var no_gravity := false
var faces_rival := true
var turn_mult := 1.0
var tint_col := Color.BLACK
var tint_k := 0.0

var _hits: Array = []
var _air_advance := false
var _live_pieces: Array = []   # [Fx emitter, locator]: they follow the body


func start() -> void:
	_pieces("fx_startup")
	on_start()


func step(delta: float) -> void:
	t += delta
	total += delta
	for p in _live_pieces:
		p[0].pos = _spot(p[1])
	match phase:
		"startup":
			var dur: float = d.get("startup", 0.1)
			if d.get("chargeable", false):
				# Charges while held, between "startup" and "startup_max".
				charge = clampf((t - dur) / maxf(d.get("startup_max", 1.0) - dur, 0.01), 0.0, 1.0) if t > dur else 0.0
				if (not l.ctrl.keeps(button) and t >= dur) or t >= d.get("startup_max", 1.0):
					_go_to("active")
			elif t >= dur:
				_go_to("active")
			in_startup(delta)
		"active":
			in_active(delta)
			var dur: float = d.get("active", 0.1)
			if d.get("hold", false):
				if (not l.ctrl.keeps(button) and t >= dur) or t >= d.get("max", 1.5):
					_go_to("recovery")
			elif t >= dur:
				_go_to("recovery")
		"recovery":
			in_recovery(delta)
			if t >= d.get("recovery", 0.2):
				finish(false)


func _go_to(new_phase: String) -> void:
	phase = new_phase
	t = 0.0
	match new_phase:
		"active":
			_pieces("fx_active")
			on_active()
		"recovery":
			if _air_advance:
				no_gravity = false
				# Whatever upward speed is left ends with the advance (otherwise
				# inertia keeps it rising and it shoots off into the sky).
				l.velocity.y = minf(l.velocity.y, 0.0)
			for h in _hits:
				l.main.combat.remove(h)
			_hits.clear()
			on_recovery()


func finish(interrupted: bool) -> void:
	if finished:
		return
	finished = true
	_live_pieces.clear()
	for h in _hits:
		l.main.combat.remove(h)
	_hits.clear()
	on_end(interrupted)


# ---------------------------------------------------------------- hooks

func on_start() -> void:
	pass


func in_startup(_delta: float) -> void:
	pass


func on_active() -> void:
	pass


func in_active(_delta: float) -> void:
	pass


func on_recovery() -> void:
	pass


func in_recovery(_delta: float) -> void:
	pass


func on_end(_interrupted: bool) -> void:
	pass


## Damage threshold below which the move is not interrupted (0: no armor).
func armor() -> float:
	return 0.0


func pose() -> Dictionary:
	return {}


# ---------------------------------------------------------------- cancels

## In recovery, and only if it landed when the move requires it.
func can_cancel() -> bool:
	if phase != "recovery":
		return false
	return landed or not d.get("cancel_only_on_hit", false)


func cancels_dodge() -> bool:
	return d.get("cancels_dodge", false)


func cancels_jump() -> bool:
	return d.get("cancels_jump", false)


## Cancel into another move (short combos): only if it landed and the data allows it.
func cancels_into(_move: String) -> bool:
	return landed and d.get("cancels_into_moves", false)


# ---------------------------------------------------------------- Cobblemon pieces

## Spawns the move's Cobblemon particle pieces from its data: [[id, site], ...].
## site: a model locator, "center" or "foot".
func _pieces(key: String) -> void:
	for p in d.get(key, []):
		var look_at = l.rival.center() if l.rival else null
		var em: Dictionary = l.main.vfx.cobble(p[0], _spot(p[1]), look_at, l.data.height)
		if not em.is_empty():
			_live_pieces.append([em, p[1]])


func _spot(site: String) -> Vector3:
	match site:
		"center":
			return l.center()
		"foot":
			return l.global_position
	return l.point(site)


# ---------------------------------------------------------------- hits

## Creates a hit volume from the move data plus the given values.
func hit(values: Dictionary) -> Hit:
	var h := Hit.new()
	h.user = l
	h.move_id = id
	h.type = d.get("type", "normal")
	h.cat = d.get("cat", "physical")
	h.damage = d.get("damage", 50.0)
	h.push = d.get("push", 4.0)
	h.lift = d.get("lift", 0.0)
	h.stun = d.get("stun", 0.3)
	h.knocks_down = d.get("knocks_down", false)
	h.hitstop = d.get("hitstop", 0.06)
	h.strength = d.get("strength", 1)
	h.effect = d.get("effect", "")
	h.contact = d.get("contact", true)
	for k in values:
		h.set(k, values[k])
	l.main.combat.add_hit(h)
	_hits.append(h)
	return h


func remove_hits() -> void:
	for h in _hits:
		l.main.combat.remove(h)
	_hits.clear()


## A point on the body in world space, from a position in its own frame (z forward).
func to_world(local: Vector3) -> Vector3:
	return l.body_basis() * local


func mouth() -> Vector3:
	return to_world(Vector3(0, l.data.height * d.get("mouth_height", 0.7), l.data.radius * 0.9))


## Firing direction: toward the rival if locked on and in front; otherwise straight ahead.
## "limit" caps the aim: it does not chase a rival that is too far to the side.
func aim(limit := 0.6) -> Vector3:
	var fwd := l.forward()
	if l.rival and is_instance_valid(l.rival) and l.rival.state != "ko":
		var toward := (l.target_center() - mouth())
		var flat := Vector3(toward.x, 0, toward.z).normalized()
		if flat.angle_to(fwd) < limit:
			return toward.normalized()
	return fwd


## Streams and beams: horizontally, where the fighter faces (the player turns it with
## the stick); vertically, at the target's height, automatically (to hit flyers).
func aim_stream(from_pos: Vector3) -> Vector3:
	var fwd := l.forward()
	var target := l.aim_target()
	if target == null or not is_instance_valid(target) or (target is Fighter and target.state == "ko"):
		return fwd
	var toward: Vector3 = l.target_center() - from_pos
	var flat_len := Vector2(toward.x, toward.z).length()
	if Vector3(toward.x, 0, toward.z).dot(fwd) <= 0.0 or flat_len < 0.5:
		return fwd
	var pitch := atan2(toward.y, flat_len)
	return (fwd * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Moves the fighter along with the strike (attack_dir: including the target's height).
## If it goes up or down, or is airborne, it does not fall during the active phase.
func advance_by(speed: float) -> void:
	var dir := l.attack_dir()
	# Never rises above the target (if it dodges, the attacker does not fly off), nor
	# higher than its jump allows unless it flies (Fighter.attack_ceiling).
	if dir.y > 0.0 and (l.global_position.y + l.data.height * 0.5 >= l.target_center().y or l.global_position.y >= l.attack_ceiling()):
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
	l.velocity.x = dir.x * speed
	l.velocity.z = dir.z * speed
	if not l.is_on_floor() or absf(dir.y) > 0.2:
		l.velocity.y = dir.y * speed
		no_gravity = true
		_air_advance = true


func play_sound(key: String, vol := 0.0) -> void:
	l.main.audio.play_sound(key, l.global_position, vol)
