class_name AI
extends Node
## Computer-controlled rival. It fills in its fighter's Intent as if it were a gamepad:
## same rules for movement, resources, collisions and timings. It does not read inputs:
## it sees the rival with a delay (what it was doing "reaction" seconds ago), with a
## margin of error and deliberate mistakes depending on the difficulty.
##
## Priorities at every moment:
##   1. defend against concrete threats (incoming projectiles, attacks being prepared
##      nearby, the Earthquake wave: jump as it arrives)
##   2. punish long recoveries and whiffs
##   3. hold the distance that suits its Pokémon and attack with the right move
## It adapts: if the player dodges a lot, it waits out the dodge to punish it.

const DIFFICULTY := {
	"easy": {"reaction": 0.42, "error": 0.32, "doubt": 0.5, "punish": 0.4, "defense": 0.45},
	"normal": {"reaction": 0.28, "error": 0.16, "doubt": 0.25, "punish": 0.7, "defense": 0.7},
	"hard": {"reaction": 0.19, "error": 0.06, "doubt": 0.1, "punish": 0.92, "defense": 0.9},
}

## Each Pokémon's style: preferred distance and eagerness to attack.
const PROFILE := {
	"pikachu": {"dist": [4.0, 7.5], "aggression": 0.65, "circle_around": 0.8},
	"snorlax": {"dist": [1.8, 3.2], "aggression": 0.45, "circle_around": 0.2},
	"charizard": {"dist": [5.0, 8.5], "aggression": 0.55, "circle_around": 0.6},
	"blastoise": {"dist": [4.5, 9.0], "aggression": 0.5, "circle_around": 0.4},
	"venusaur": {"dist": [4.0, 7.5], "aggression": 0.45, "circle_around": 0.3},
	"lucario": {"dist": [2.5, 6.0], "aggression": 0.7, "circle_around": 0.7},
	"gengar": {"dist": [5.5, 10.0], "aggression": 0.5, "circle_around": 0.9},
	"garchomp": {"dist": [2.0, 5.5], "aggression": 0.8, "circle_around": 0.5},
	"greninja": {"dist": [4.0, 8.0], "aggression": 0.65, "circle_around": 1.0},
	"scizor": {"dist": [1.8, 4.5], "aggression": 0.8, "circle_around": 0.6},
}

var main: Node
var me: Fighter
var rival: Fighter
var difficulty := "normal"
var mode := "active"           # active, still (training)
var state_text := ""         # for the debug view

var _history: Array = []     # snapshots of the rival: {t, pos, vel, state, action, phase, on_ground}
var _t := 0.0
var _decision_t := 0.0
var _circling := 1.0
var _circling_t := 0.0
var _hold := {}            # action -> seconds it stays held
var _cooldown_def := 0.0
var _rival_dodges: Array = []
var _rival_last_dodge := -10.0
var _plan := ""
var _decoy_seen: Object = null    # the last rival decoy it has seen
var _fooled := false               # whether it fell for it
const BELIEVES_DECOY := {"easy": 0.9, "normal": 0.65, "hard": 0.35}
const RANGED := ["projectile", "stream", "charge", "engage"]   # what reaches another height (dashes go diagonally)
var _flight_pending := -1.0              # pending second jump to take off


func _physics_process(delta: float) -> void:
	if me == null or rival == null or not is_instance_valid(rival):
		return
	_t += delta
	_cooldown_def -= delta
	_record()
	var c := me.ctrl
	for k in _hold.keys():
		_hold[k] -= delta
		if _hold[k] <= 0.0:
			_hold.erase(k)
			c.release(k)
	if mode == "still":
		return   # still: does not touch the controls (training and tests use them)
	if me.state == "ko" or rival.state == "ko" or main.paused:
		c.move_input = Vector2.ZERO
		return
	var diff: Dictionary = DIFFICULTY[difficulty]
	var seen := _seen(diff.reaction)
	if seen.is_empty():
		return
	var toward: Vector3 = seen.pos - me.global_position
	toward.y = 0.0
	var dist := toward.length()
	c.yaw = atan2(-toward.x, -toward.z)
	me.locked = true
	# 1. Defensa
	_fly(seen, dist, delta)
	if _defend(seen, dist, diff):
		return
	# 2 and 3. Decide every so often, not every step (with doubt depending on difficulty).
	_decision_t -= delta
	_move_ai(seen, dist, delta)
	if _decision_t <= 0.0:
		_decision_t = randf_range(0.08, 0.2) + (diff.doubt * randf() * 0.4)
		if not _punish(seen, dist, diff):
			_attack(seen, dist, diff)


# ---------------------------------------------------------------- perception

func _record() -> void:
	# Substitute: if it falls for the decoy, what it sees is the still decoy.
	var decoy: Object = null
	for o in main.combat.targets:
		if o is Decoy and o.user == rival and is_instance_valid(o):
			decoy = o
	if decoy != _decoy_seen:
		_decoy_seen = decoy
		_fooled = decoy != null and randf() < BELIEVES_DECOY[difficulty]
	me.fooled_by = decoy if _fooled else null
	if decoy != null and _fooled:
		_history.append({"t": _t, "pos": decoy.global_position, "speed": Vector3.ZERO, "state": "free",
			"action": "", "phase": "", "charge": 0.0, "on_ground": true, "hp": rival.hp})
	else:
		_history.append({"t": _t, "pos": rival.global_position, "speed": rival.velocity, "state": rival.state,
			"action": rival.action.id if rival.action else "", "phase": rival.action.phase if rival.action else "",
			"charge": rival.action.charge if rival.action else 0.0, "on_ground": rival.is_on_floor(), "hp": rival.hp})
	while _history.size() > 90:
		_history.pop_front()
	if rival.state == "dodge" and _t - _rival_last_dodge > 0.5:
		_rival_last_dodge = _t
		_rival_dodges.append(_t)
	while not _rival_dodges.is_empty() and _t - _rival_dodges[0] > 12.0:
		_rival_dodges.pop_front()


## What it sees: the rival as it was "delay" seconds ago (plus a bit of noise).
func _seen(delay: float) -> Dictionary:
	var target := _t - delay * randf_range(0.85, 1.15)
	for i in range(_history.size() - 1, -1, -1):
		if _history[i].t <= target:
			return _history[i]
	return _history[0] if not _history.is_empty() else {}


func _press(a: String) -> void:
	me.ctrl.press(a)
	if not _hold.has(a):
		_hold[a] = 0.05


func _hold_button(a: String, dur: float) -> void:
	me.ctrl.press(a)
	_hold[a] = dur


func _button_for(move: String) -> String:
	var i: int = me.data.moves.find(move)
	return "mov%d" % (i + 1) if i >= 0 else ""


# ---------------------------------------------------------------- defense

func _defend(seen: Dictionary, dist: float, diff: Dictionary) -> bool:
	if me.state != "free" or _cooldown_def > 0.0:
		return false
	# Projectiles coming at me (seen with the same delay: age > reaction).
	for p in main.combat.projectiles:
		if p.user == me or p.age_t < diff.reaction:
			continue
		var rel: Vector3 = me.center() - p.pos
		var v: Vector3 = p.velocity
		var vv := v.length_squared()
		if vv < 1.0:
			continue
		var t_near := rel.dot(v) / vv
		if t_near < 0.0 or t_near > 0.55:
			continue
		var near: Vector3 = p.pos + v * t_near
		if near.distance_to(me.center()) < p.radius + me.radius() + 0.5:
			if randf() < diff.defense:
				var side := v.cross(Vector3.UP).normalized()
				if not main.arena.inside(me.global_position + side * 4.0, 1.5):
					side = -side
				_dodge_toward(side)
				state_text = "dodges projectile"
			_cooldown_def = 0.35
			return true
	# Attacks the rival is preparing that would reach me.
	if seen.state == "action" and seen.phase in ["startup", "active"] and seen.action != "":
		var d: Dictionary = Moves.DATA[seen.action]
		var ai: Dictionary = d.get("ai", {"min": 0.0, "max": 2.5, "kind": "punish"})
		# Earthquake: jump when the wave is about to arrive.
		if seen.action == "earthquake" and seen.phase == "active":
			var k: float = clampf((_t - diff.reaction - _phase_start()) / d.active, 0.0, 1.0)
			var r: float = d.r_max * (1.0 - pow(1.0 - k, 2.0))
			if dist - r < 2.6 and dist - r > -0.5 and me.is_on_floor():
				if randf() < diff.defense:
					_press("jump")
					state_text = "jumps the wave"
					if me.data.has("flight"):
						_flight_pending = 0.2
						state_text = "takes off over the wave"
				_cooldown_def = 0.6
				return true
		elif seen.action == "earthquake" and seen.phase == "startup" and dist < d.r_max:
			state_text = "waits for the wave"
			return false
		var reach: float = ai.max + me.radius()
		if ai.kind in ["punish", "engage", "stream", "area"] and dist < reach + 1.0 and seen.phase == "startup":
			if randf() < diff.defense * 0.85:
				var outside: Vector3 = (me.global_position - seen.pos)
				outside.y = 0.0
				var side := outside.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
				var dir := (outside.normalized() * 0.4 + side).normalized() if ai.kind in ["engage", "stream"] else outside.normalized()
				_dodge_toward(dir)
				state_text = "dodges %s" % d.display_name
			_cooldown_def = 0.5
			return true
	return false


func _phase_start() -> float:
	# Moment (in the history) when the rival entered the phase we see.
	var current_phase: String = _history.back().phase if not _history.is_empty() else ""
	for i in range(_history.size() - 1, -1, -1):
		if _history[i].phase != current_phase:
			return _history[i].t
	return _t


func _dodge_toward(world_dir: Vector3) -> void:
	for move in me.data.moves:
		if Moves.DATA[move].get("ai", {}).get("kind", "") == "guard" and me.ready(move) and randf() < 0.45:
			_use(move)
			state_text = "reads the hit"
			return
	if me.charges < 1.0:
		# No dodges left: at least run out of the way.
		me.ctrl.move_input = _to_local(world_dir)
		return
	me.ctrl.move_input = _to_local(world_dir)
	_press("dodge")


func _to_local(world_dir: Vector3) -> Vector2:
	var yaw := me.ctrl.yaw
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	return Vector2(world_dir.dot(right), world_dir.dot(fwd)).limit_length(1.0)


# ---------------------------------------------------------------- punish

func _punish(seen: Dictionary, dist: float, diff: Dictionary) -> bool:
	var open := false
	if seen.state == "action" and seen.phase == "recovery":
		var d: Dictionary = Moves.DATA[seen.action]
		open = d.get("recovery", 0.0) >= 0.3
	if seen.state == "dodge" and _t - _rival_last_dodge > 0.18:
		open = true
	if seen.action == "rest" and seen.phase == "active":
		open = true
	if not open or randf() > diff.punish:
		return false
	var best := ""
	var value := 0.0
	for move in me.data.moves:
		if not me.ready(move):
			continue
		var ai: Dictionary = Moves.DATA[move].get("ai", {})
		if ai.is_empty() or ai.kind in ["heal", "guard", "decoy"]:
			continue
		if _other_height(seen) and not ai.kind in RANGED:
			continue
		if dist >= ai.min and dist <= ai.max + me.radius():
			var v: float = ai.value * (1.4 if ai.kind in ["punish", "engage"] else 1.0)
			if v > value:
				value = v
				best = move
	if best != "":
		_use(best)
		state_text = "punishes with %s" % Moves.DATA[best].display_name
		return true
	return false


# ---------------------------------------------------------------- neutral

func _move_ai(seen: Dictionary, dist: float, delta: float) -> void:
	if me.state != "free" and not (me.action and me.action.moves_freely):
		return
	var profile: Dictionary = PROFILE.get(me.species, PROFILE.pikachu)
	_circling_t -= delta
	if _circling_t <= 0.0:
		_circling_t = randf_range(1.0, 2.6)
		_circling = -_circling if randf() < 0.6 else _circling
	var m := Vector2.ZERO
	var near: float = profile.dist[0]
	var far: float = profile.dist[1]
	if dist > far:
		m.y = 1.0
	elif dist < near:
		m.y = -0.8
	m.x = _circling * profile.circle_around
	# Away from walls and corners: if it gets close, it pulls toward the center.
	var p := me.global_position
	if not main.arena.inside(p, 3.5):
		var to_center := _to_local(-Vector3(p.x, 0, p.z).normalized())
		m = (m * 0.4 + to_center * 1.2).limit_length(1.0)
		_circling = -_circling if randf() < 0.02 else _circling
	me.ctrl.move_input = m.limit_length(1.0)


func _attack(seen: Dictionary, dist: float, diff: Dictionary) -> void:
	if me.state != "free":
		# If it landed, cancel into a punishing move (if the move data allows it).
		if me.action and me.action.landed and randf() < 0.7 - diff.error:
			for move in me.data.moves:
				var ai: Dictionary = Moves.DATA[move].get("ai", {})
				if me.ready(move) and ai.get("kind", "") == "punish" and dist <= ai.max + me.radius() and me.action.cancels_into(move):
					_use(move)
					break
		return
	var profile: Dictionary = PROFILE.get(me.species, PROFILE.pikachu)
	# Against someone who dodges a lot: it stays close waiting to punish the dodge.
	if _rival_dodges.size() >= 4 and randf() < 0.5:
		state_text = "waits out the dodge"
		return
	if randf() > profile.aggression + 0.2:
		state_text = "pokes"
		return
	# Decoy (Substitute): when the rival rushes in.
	for move in me.data.moves:
		if Moves.DATA[move].get("ai", {}).get("kind", "") == "decoy" and me.ready(move):
			if (dist < 4.0 and randf() < 0.35) or (dist < 9.0 and randf() < 0.04):
				_use(move)
				state_text = "leaves a decoy"
				return
	# Rest when things go badly and the rival is far away.
	if me.hp < me.hp_max * 0.4 and dist > 9.0 and "rest" in me.data.moves and me.ready("rest") and randf() < 0.5:
		_use("rest")
		return
	var options := []
	for move in me.data.moves:
		if not me.ready(move):
			continue
		var ai: Dictionary = Moves.DATA[move].get("ai", {})
		if ai.is_empty() or ai.kind in ["heal", "guard", "decoy"]:
			continue
		if _other_height(seen) and not ai.kind in RANGED:
			continue
		if dist < ai.min or dist > ai.max + me.radius():
			continue
		# Do not fire if the rival is mid-dodge (invulnerable) or there is a wall in between.
		if ai.kind in ["projectile", "charge"] and (seen.state == "dodge" or not _clear_line(seen.pos)):
			continue
		options.append([move, ai.value * randf_range(0.7, 1.3)])
	if randf() < diff.error and not options.is_empty():
		options.shuffle()
	else:
		options.sort_custom(func(a, b): return a[1] > b[1])
	if not options.is_empty() and randf() < 0.75:
		_use(options[0][0])
		state_text = "uses %s" % Moves.DATA[options[0][0]].display_name


## The rival (or me) at another height: flying or on top of something. Melee hits and
## ground waves do not reach.
func _other_height(seen: Dictionary) -> bool:
	return absf(seen.pos.y - me.global_position.y) > 2.0


# ---------------------------------------------------------------- flight

## Flyers (Charizard): sometimes take off to attack from above, stay at mid height and
## land before running out of stamina.
func _fly(_seen: Dictionary, dist: float, delta: float) -> void:
	if not me.data.has("flight"):
		return
	if _flight_pending >= 0.0:
		_flight_pending -= delta
		if _flight_pending < 0.0 and not me.is_on_floor():
			_press("jump")
	var maximum: float = me._flight_max()
	if not me.flying:
		if me.is_on_floor() and me.state == "free" and me.flight > maximum * 0.85 and dist > 3.5 and randf() < 0.01:
			_press("jump")
			_flight_pending = 0.22
			state_text = "takes off"
		return
	var altitude: float = me.global_position.y - main.ground_y
	if me.flight < maximum * 0.3:
		_hold_button("descend", 0.15)
	elif altitude < 3.5:
		_hold_button("jump", 0.12)
	elif altitude > 6.0:
		_hold_button("descend", 0.1)


func _use(move: String) -> void:
	var b := _button_for(move)
	if b == "":
		return
	var d: Dictionary = Moves.DATA[move]
	if d.get("chargeable", false):
		_hold_button(b, randf_range(d.startup, d.startup_max))
	elif d.get("hold", false):
		_hold_button(b, randf_range(d.active + d.startup, d.max))
	else:
		_press(b)


func _clear_line(target_point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(me.center(), target_point + Vector3.UP * 0.5, 1)
	return main.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
