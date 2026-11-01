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
## With a team (Party) it also looks every so often at whether a teammate would do clearly
## better ("switch_margin", in Party.score's units) and sends it out when the rival is not on
## top of it.
## In a 2 vs 2 it chooses which foe to go after (_choose_rival), keeps its distance from its ally
## and uses the moves that help it (_help); with friendly fire on it holds a shot its ally is in
## the way of.

const DIFFICULTY := {
	"easy": {"reaction": 0.42, "aim_lead": 0.3, "aim_error": 1.6, "error": 0.32, "doubt": 0.5, "punish": 0.4, "defense": 0.45, "deflect": 0.05, "deflect_error": 0.12, "switch_every": 8.0, "switch_margin": 0.9},
	"normal": {"reaction": 0.28, "aim_lead": 0.6, "aim_error": 1.0, "error": 0.16, "doubt": 0.25, "punish": 0.7, "defense": 0.7, "deflect": 0.2, "deflect_error": 0.07, "switch_every": 5.0, "switch_margin": 0.6},
	"hard": {"reaction": 0.19, "aim_lead": 0.9, "aim_error": 0.6, "error": 0.06, "doubt": 0.1, "punish": 0.92, "defense": 0.9, "deflect": 0.4, "deflect_error": 0.04, "switch_every": 3.0, "switch_margin": 0.4},
}
const SWITCH_MIN_DIST := 4.0     # closer than this, the rival would just hit it out of the recall
const SWITCH_RETRY := 0.3        # seconds until it looks again when the moment was not safe
const SWITCH_CHARMED := 0.5      # how much worse staying looks while infatuated (a switch cures it)

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
	"goodra": {"dist": [4.0, 8.0], "aggression": 0.45, "circle_around": 0.35},
	"urshifu": {"dist": [1.5, 4.5], "aggression": 0.75, "circle_around": 0.5},
	"urshifurapidstrike": {"dist": [2.0, 6.0], "aggression": 0.65, "circle_around": 0.6},
	"mewtwo": {"dist": [4.0, 9.0], "aggression": 0.6, "circle_around": 0.7},
	"sylveon": {"dist": [4.0, 9.0], "aggression": 0.5, "circle_around": 0.5},
}

var main: Node
var me: Fighter
var rival: Fighter
var difficulty := "normal"
var mode := "active"           # active, still (training)
var state_text := ""         # for the debug view

var _history: Array = []     # snapshots of the rival: {t, pos, vel, state, action, phase, on_ground}
var _sight := {}             # foe -> what it saw of it (_watch): recorded all the time, so a change of rival has fresh sight
var _t := 0.0
var _decision_t := 0.0
var _circling := 1.0
var _circling_t := 0.0
var _hold := {}            # action -> seconds it stays held
var _cooldown_def := 0.0
var _rival_dodges: Array = []
var _rival_last_dodge := -10.0
var _plan := ""
const DODGE_REACH := 6.0      # about how far a dodge carries it, with some to spare (m)
const BELIEVES_DECOY := {"easy": 0.9, "normal": 0.65, "hard": 0.35}
const RANGED := ["projectile", "stream", "charge", "engage"]   # what reaches another height (dashes go diagonally)
var _flight_pending := -1.0              # pending second jump to take off
var _aim_phase := Vector2(randf() * TAU, randf() * TAU)   # so each AI wobbles its own way
var _switch_t := 3.0                     # seconds until it thinks about switching again
var _rival_t := 0.0                      # seconds until it looks again at which foe to go after
var _help_t := 0.0                       # seconds until it looks again at helping its ally
var _aid_t := 0.0                        # how long it has been turning to its ally for Ally Switch
const RIVAL_EVERY := 1.5
const RIVAL_NEAR := 5.0                  # a foe this close and attacking takes over at once
const RIVAL_STICKY := 0.35               # how much better another foe has to look (in _foe_score's units)
const ALLY_KEEP := 3.0                   # how far it keeps from its ally, so one area hit does not catch both
const AID_TURN := 0.5                    # it gives up on turning to its ally after this long
const HELP_EVERY := 0.25
const SHOT_SOON := 0.5                   # Ally Switch: a shot arriving on the ally within this long
const ALLY_LOW := 0.3                    # Ally Switch: the ally is this low on health with a foe on it
const WALK_TO_ALLY_FOE := 4.0            # Helping Hand: it walks to the ally only with no foe this close
const WIND_FOE := 6.0                    # Tailwind: no foe this close
const BIG_MOVE := 80                     # the power of a move worth helping


## Its Pokémon or the rival's changed: what it saw of the old one no longer counts.
func on_swap(out: Fighter, incoming: Fighter) -> void:
	if me == out:
		me = incoming
		_hold.clear()
	if rival == out:
		rival = incoming
	_sight.erase(out)


func _physics_process(delta: float) -> void:
	if me == null or rival == null or not is_instance_valid(rival):
		return
	me.ai_driven = true
	if main.intro_t > 0.0:
		me.ctrl.clear()
		return
	_t += delta
	_cooldown_def -= delta
	# The fighter's is the one that counts: a KO, a swap or a lock may have moved it.
	if me.rival and is_instance_valid(me.rival):
		rival = me.rival
	_record()
	var c := me.ctrl
	for k in _hold.keys():
		_hold[k] -= delta
		if _hold[k] <= 0.0:
			_hold.erase(k)
			c.release(k)
	if mode == "still":
		return   # still: does not touch the controls (training and tests use them)
	_choose_rival(delta)
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
	# Where it aims manual streams: the delayed sight plus a slow wobble of "aim_error" meters.
	var wobble := Vector3(sin(_t * 1.1 + _aim_phase.x), 0.0, sin(_t * 0.8 + _aim_phase.y))
	me.ai_aim = seen.pos + wobble * diff.aim_error
	me.aim_lead = diff.aim_lead
	if _recover():
		return
	# 1. Defense
	_fly(seen, dist, delta)
	if _defend(seen, dist, diff):
		_edge_guard()
		return
	if _consider_switch(seen, dist, diff, delta):
		return
	if _help(diff, delta):
		_edge_guard()
		return
	# 2 and 3. Decide every so often, not every step (with doubt depending on difficulty).
	_decision_t -= delta
	_move_ai(seen, dist, delta)
	if _decision_t <= 0.0:
		_decision_t = randf_range(0.08, 0.2) + (diff.doubt * randf() * 0.4)
		if not _punish(seen, dist, diff):
			_attack(seen, dist, diff)
	_edge_guard()


## On a stage with a void, a flyer that fell off flies back: it takes off, first moves out
## from under the platform (its underside is solid), climbs above the edge and then heads
## for the center. True while it is doing that.
func _recover() -> bool:
	var p := me.global_position
	if main.arena.void_y == -INF or not me.data.has("flight") or p.y > -0.3 or me.state != "free":
		return false
	if not me.flying:
		_press("jump")
	var out := Vector3(p.x, 0.0, p.z).normalized()
	if main.arena.inside(p, -1.2):
		me.ctrl.move_input = _to_local(out)          # under the platform: out first
	else:
		_hold_button("jump", 0.15)
		me.ctrl.move_input = _to_local(-out) * (1.0 if p.y > 0.6 else 0.0)
	state_text = "flies back to the platform"
	return true


## On a stage with a void: if its own momentum is carrying it off the edge, it runs back
## toward the center (it only falls if it is knocked off).
func _edge_guard() -> void:
	if main.arena.void_y == -INF or me.state not in ["free", "dodge"]:
		return
	var p := me.global_position
	var ahead := p + Vector3(me.velocity.x, 0.0, me.velocity.z) * 0.45
	if not main.arena.inside(ahead, 1.5) or not main.arena.inside(p, 2.0):
		me.ctrl.move_input = _to_local(-Vector3(p.x, 0.0, p.z).normalized())


# ---------------------------------------------------------------- switching

## Every so often: if a teammate would do clearly better than the one out, sends it out. It
## counts what leaving costs: stat stages won are lost, and lowered ones go away, as does being
## infatuated. It does not try with the rival close by or attacking, or with a shot on its way,
## which would cut the recall: it looks again in a moment.
func _consider_switch(seen: Dictionary, dist: float, diff: Dictionary, delta: float) -> bool:
	if me.party == null:
		return false
	_switch_t -= delta
	if _switch_t > 0.0:
		return false
	if dist < SWITCH_MIN_DIST or seen.state == "action" or main.combat.projectiles.any(func(p): return p.user != me and not main.combat.same_side(p.user, me)):
		_switch_t = SWITCH_RETRY
		return false
	_switch_t = float(diff.switch_every) * randf_range(0.8, 1.2)
	var stages := 0
	for k in me.stages:
		stages += int(me.stages[k])
	var here: float = _worst_score(me) + 0.15 * stages - (SWITCH_CHARMED if me.charmed_by != "" else 0.0)
	var best := -1
	var best_score: float = here + float(diff.switch_margin)
	for slot in 2:
		if me.party.can_switch(slot):
			var s: float = _worst_score(me.party.slot_member(slot))
			if s > best_score:
				best_score = s
				best = slot
	if best < 0:
		return false
	_press("switch%d" % (best + 1))
	state_text = "switches out"
	return true


## How good "f" looks against whichever foe suits it worst (one foe: that one).
func _worst_score(f: Fighter) -> float:
	var worst: float = Party.score(f, rival)
	if main.doubles:
		for o in me.foes():
			worst = minf(worst, Party.score(f, o))
	return worst


# ---------------------------------------------------------------- which foe

## In a 2 vs 2, every so often and with some stickiness: the foe closest, with the least health
## left and that it does best against. One within RIVAL_NEAR and attacking takes over at once.
func _choose_rival(delta: float) -> void:
	if not main.doubles or me.state == "ko":
		return
	_rival_t -= delta
	var foes := me.foes()
	if foes.is_empty():
		return
	var best: Fighter = null
	for f in foes:
		if f != rival and me.global_position.distance_to(f.global_position) < RIVAL_NEAR and f.is_attacking():
			best = f
	if best == null and (rival.state == "ko" or _rival_t <= 0.0):
		_rival_t = RIVAL_EVERY
		var top := -INF
		for f in foes:
			var s := _foe_score(f) + (RIVAL_STICKY if f == rival else 0.0)
			if s > top:
				top = s
				best = f
	if best != null and best != rival:
		rival = best
		me.rival = best
		_look_at_rival()


func _foe_score(f: Fighter) -> float:
	var dist: float = me.global_position.distance_to(f.global_position)
	return -dist * 0.1 + (1.0 - f.hp / f.hp_max) + Party.score(me, f) * 0.25


# ---------------------------------------------------------------- perception

## What it knows of a foe. "last_dodge" and the rest are this foe's alone.
func _watch(foe: Fighter) -> Dictionary:
	if not _sight.has(foe):
		_sight[foe] = {"history": [], "dodges": [], "last_dodge": -10.0, "decoy": null, "fooled": false}
	return _sight[foe]


func _record() -> void:
	var watched: Array = me.foes() if main.doubles else [rival]
	if not rival in watched:
		watched.append(rival)
	for foe in watched:
		_record_foe(foe)
	_look_at_rival()


## What it goes by is what it knows of its rival.
func _look_at_rival() -> void:
	var s := _watch(rival)
	_history = s.history
	_rival_dodges = s.dodges
	_rival_last_dodge = s.last_dodge
	me.fooled_by = s.decoy if s.fooled and is_instance_valid(s.decoy) else null


func _record_foe(foe: Fighter) -> void:
	var s := _watch(foe)
	# Substitute: if it falls for the decoy, what it sees is the still decoy.
	var decoy: Object = null
	for o in main.combat.targets:
		if o is Decoy and o.user == foe and is_instance_valid(o):
			decoy = o
	if decoy == null:
		s.decoy = null
		s.fooled = false
	elif decoy != s.decoy:
		s.decoy = decoy
		# Substitute's doll always fools it (Gengar is invisible); Double Team's clones,
		# depending on the difficulty.
		s.fooled = decoy.kind == "substitute" or randf() < BELIEVES_DECOY[difficulty]
	if decoy != null and s.fooled:
		s.history.append({"t": _t, "pos": decoy.global_position, "speed": Vector3.ZERO, "state": "free",
			"action": "", "phase": "", "charge": 0.0, "on_ground": true, "hp": foe.hp})
	else:
		s.history.append({"t": _t, "pos": foe.global_position, "speed": foe.velocity, "state": foe.state,
			"action": foe.action.id if foe.action else "", "phase": foe.action.phase if foe.action else "",
			"charge": foe.action.charge if foe.action else 0.0, "on_ground": foe.is_on_floor(), "hp": foe.hp})
	while s.history.size() > 90:
		s.history.pop_front()
	if foe.state == "dodge" and _t - s.last_dodge > 0.5:
		s.last_dodge = _t
		s.dodges.append(_t)
	while not s.dodges.is_empty() and _t - s.dodges[0] > 12.0:
		s.dodges.pop_front()


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


## Its usual button, even confused: it fires the wrong move, as a player who has not looked yet would.
func _button_for(move: String) -> String:
	var i: int = me.data.moves.find(move)
	return "mov%d" % (i + 1) if i >= 0 else ""


# ---------------------------------------------------------------- defense

func _defend(seen: Dictionary, dist: float, diff: Dictionary) -> bool:
	if me.state != "free" or _cooldown_def > 0.0:
		return false
	# Projectiles coming at me (seen with the same delay: age > reaction).
	for p in main.combat.projectiles:
		if main.combat.spares(p.user, me) or p.age_t < diff.reaction:
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
			# A move that deflects, ready and quick enough to be out when it arrives: swing
			# instead of dodging (sometimes; more often the harder it is).
			# Its sense of when the shot arrives is off by up to deflect_error: sometimes it
			# swings too early or too late and takes the hit anyway.
			var guess: float = t_near + randf_range(-diff.deflect_error, diff.deflect_error)
			var swing := _deflect_move(guess, int(Moves.DATA.get(p.hit.move_id, {}).get("deflectable", 2)))
			if swing != "" and randf() < diff.deflect:
				_use(swing)
				state_text = "swings at the projectile"
				_cooldown_def = 0.5
				return true
			if randf() < diff.defense:
				var side := v.cross(Vector3.UP).normalized()
				if not main.arena.inside(me.global_position + side * 4.0, 1.5):
					side = -side
				_dodge_toward(side, p.hit.move_id)
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
		# Reading a shot (fast ones arrive before they can be seen): when the swing would
		# meet it, swing as it fires.
		if ai.kind == "projectile" and seen.phase == "startup" and float(d.get("speed", 0.0)) > 0.0:
			var left := maxf(0.0, float(d.get("startup", 0.0)) - (_t - diff.reaction - _phase_start()))
			var guess: float = left + dist / float(d.speed) + randf_range(-diff.deflect_error, diff.deflect_error)
			var swing := _deflect_move(guess, int(d.get("deflectable", 2)))
			if swing != "" and randf() < diff.deflect:
				_use(swing)
				state_text = "swings at %s" % d.display_name
				_cooldown_def = 0.6
				return true
		var reach: float = ai.max + me.radius()
		if ai.kind in ["punish", "engage", "stream", "area"] and dist < reach + 1.0 and seen.phase == "startup":
			if randf() < diff.defense * 0.85:
				var outside: Vector3 = (me.global_position - seen.pos)
				outside.y = 0.0
				var side := outside.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
				var dir := (outside.normalized() * 0.4 + side).normalized() if ai.kind in ["engage", "stream"] else outside.normalized()
				_dodge_toward(dir, seen.action)
				state_text = "dodges %s" % d.display_name
			_cooldown_def = 0.5
			return true
	return false


## A ready move that deflects at least "level" (or breaks) whose hit is out at "arrival" s.
func _deflect_move(arrival: float, level: int) -> String:
	for move in me.data.moves:
		var d: Dictionary = Moves.DATA[move]
		if int(d.get("deflects", 0)) <= 0 or not me.ready(move) or level <= 0:
			continue
		var start: float = d.get("startup", 0.2)
		if absf(arrival - start - Combat.DEFLECT_WINDOW * 0.5) <= Combat.DEFLECT_WINDOW * 0.5:
			return move
	return ""


func _phase_start() -> float:
	# Moment (in the history) when the rival entered the phase we see.
	var current_phase: String = _history.back().phase if not _history.is_empty() else ""
	for i in range(_history.size() - 1, -1, -1):
		if _history[i].phase != current_phase:
			return _history[i].t
	return _t


## "threat": the move it is getting away from.
func _dodge_toward(world_dir: Vector3, threat: String) -> void:
	# Never into the void (stages with an edge): the other way, or toward the center.
	if not _lands_inside(world_dir, DODGE_REACH):
		world_dir = -world_dir
		if not _lands_inside(world_dir, DODGE_REACH):
			world_dir = -Vector3(me.global_position.x, 0.0, me.global_position.z).normalized()
	for move in me.data.moves:
		if Moves.DATA[move].get("ai", {}).get("kind", "") == "guard" and me.ready(move) and _guard_fits(move, threat) and randf() < 0.45:
			# A guard that travels (Teleport) goes the way it last moved: make that the way out,
			# and not off the stage, which it could reach: it goes further than a dodge.
			if Moves.DATA[move].has("dist"):
				if not _lands_inside(world_dir, float(Moves.DATA[move].dist)):
					continue
				me.ctrl.move_input = _to_local(world_dir)
				me.last_move = world_dir.normalized()
			_use(move)
			state_text = "reads the hit"
			return
	if me.charges < 1.0:
		# No dodges left: at least run out of the way.
		me.ctrl.move_input = _to_local(world_dir)
		return
	me.ctrl.move_input = _to_local(world_dir)
	_press("dodge")


## Whether this guard does anything against "threat": Counter only pays back physical hits from
## close by, and Unseen Fist's contact moves go through Protect and Detect.
func _guard_fits(move: String, threat: String) -> bool:
	var g: Dictionary = Moves.DATA[move]
	var t: Dictionary = Moves.DATA.get(threat, {})
	if g.has("rival_stun") and g.has("range"):
		return t.get("cat", "") == "physical" and me.global_position.distance_to(rival.global_position) <= float(g.range)
	if g.get("protects", false) and rival.data.passive.id == "unseenfist" and t.get("contact", true):
		return false
	return true


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
		if ai.is_empty() or ai.kind in ["heal", "guard", "decoy", "ally"] or not _only_if(ai, seen):
			continue
		# A weather that is already on is not called again.
		if Moves.DATA[move].has("weather") and main.weather.is_on(Moves.DATA[move].weather):
			continue
		# A status the rival cannot get right now is not tried.
		if _status_useless(move):
			continue
		if _other_height(seen) and not ai.kind in RANGED:
			continue
		if _hits_ally(ai, seen):
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
	# Apart from its ally, so one area hit does not catch both.
	var mate := me.ally()
	if mate:
		var off := Vector3(p.x - mate.global_position.x, 0.0, p.z - mate.global_position.z)
		if off.length() < ALLY_KEEP and off.length() > 0.01:
			m += _to_local(off.normalized()) * (1.0 - off.length() / ALLY_KEEP) * 1.5
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
		if ai.is_empty() or ai.kind in ["heal", "guard", "decoy", "ally"] or not _only_if(ai, seen):
			continue
		# A weather that is already on is not called again.
		if Moves.DATA[move].has("weather") and main.weather.is_on(Moves.DATA[move].weather):
			continue
		# A status the rival cannot get right now is not tried.
		if _status_useless(move):
			continue
		if _other_height(seen) and not ai.kind in RANGED:
			continue
		if _hits_ally(ai, seen):
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


## A move for one moment only ("only_if"): Sucker Punch while the rival is seen attacking, Lash
## Out while its power is doubled, Disable while the rival has at least two moves to lose.
func _only_if(ai: Dictionary, seen: Dictionary) -> bool:
	match ai.get("only_if", ""):
		"rival_attacking":
			return seen.state == "action" and seen.phase in ["startup", "active"] and Moves.DATA.get(seen.action, {}).get("cat", "status") != "status"
		"lowered":
			return me.lowered_t > 0.0
		"rival_ready":
			return rival.data.moves.filter(func(m): return rival.cd(m) <= 0.0).size() >= 2
	return true


## With friendly fire on: this move would catch its ally, who stands in its line to the rival or
## within reach of an area move.
func _hits_ally(ai: Dictionary, seen: Dictionary) -> bool:
	if not main.friendly_fire:
		return false
	var mate := me.ally()
	if mate == null:
		return false
	var to_mate := Vector3(mate.global_position.x - me.global_position.x, 0.0, mate.global_position.z - me.global_position.z)
	if ai.kind == "area":
		return to_mate.length() <= float(ai.max) + mate.radius()
	var to_rival := Vector3(seen.pos.x - me.global_position.x, 0.0, seen.pos.z - me.global_position.z)
	if to_rival.length() < 0.1 or to_mate.length() > to_rival.length():
		return false
	var along := to_mate.dot(to_rival.normalized())
	return along > 0.0 and (to_mate - to_rival.normalized() * along).length() < mate.radius() + 0.6


## The rival (or me) at another height: flying or on top of something. Melee hits and
## ground waves do not reach.
func _other_height(seen: Dictionary) -> bool:
	return absf(seen.pos.y - me.global_position.y) > 2.0


# ---------------------------------------------------------------- its ally

## Between defending and attacking: a move that helps its ally, when it is worth it. True while it
## is busy with that, so nothing else takes the button or the stick. "aiding" points it at the ally
## just for Ally Switch's startup; a player never has one.
func _help(diff: Dictionary, delta: float) -> bool:
	if me.aiding and not _turning_to_ally(delta):
		me.aiding = null
		me.ctrl.aim_ally = false
	if me.aiding:
		return true
	_help_t -= delta
	if me.state != "free" or _help_t > 0.0:
		return false
	_help_t = HELP_EVERY
	var mate := me.ally()
	if _wants_ally_switch(mate, diff):
		me.aiding = mate
		_aid_t = 0.0
		state_text = "turns to its ally"
		return true
	if _wants_helping_hand(mate, diff):
		if me.ctrl.ally_near:
			_use("helpinghand")
			state_text = "helps its ally"
			return true
		# Far off, with a big move on its ally's side and nobody on it: over there first.
		if me.global_position.distance_to(rival.global_position) >= WALK_TO_ALLY_FOE and _ally_has_big_move(mate):
			me.ctrl.move_input = _to_local(mate.global_position - me.global_position)
			state_text = "walks to its ally"
			_help_t = 0.0
			return true
	if _wants_tailwind(mate):
		_use("tailwind")
		state_text = "calls the wind"
		return true
	return false


## Faces its ally; once it does, it says so and presses. False once it is over.
func _turning_to_ally(delta: float) -> bool:
	if me.action and me.action.id == "allyswitch" and me.action.phase == "startup":
		return true
	_aid_t += delta
	var mate := me.ally()
	if mate == null or me.state != "free" or _aid_t > AID_TURN or not me.ready("allyswitch"):
		return false
	me.ctrl.move_input = Vector2.ZERO
	var to: Vector3 = mate.global_position - me.global_position
	to.y = 0.0
	if me.forward().dot(to.normalized()) > 0.85:
		me.ctrl.aim_ally = true
		_use("allyswitch")
	return true


func _wants_ally_switch(mate: Fighter, diff: Dictionary) -> bool:
	if mate == null or not "allyswitch" in me.data.moves or not me.ready("allyswitch") or not _clear_line(mate.global_position):
		return false
	if not _swap_is_worth_it(mate):
		return false
	return randf() < diff.defense


## A shot about to land on the ally that it would rather take itself, or the ally low on health
## with a foe on it.
func _swap_is_worth_it(mate: Fighter) -> bool:
	if mate.hp / mate.hp_max < ALLY_LOW:
		for f in mate.foes():
			if f.rival == mate and f.global_position.distance_to(mate.global_position) < RIVAL_NEAR:
				return true
	for p in main.combat.projectiles:
		if main.combat.same_side(p.user, me) or p.target != mate:
			continue
		var v: Vector3 = p.velocity
		if v.length_squared() < 1.0:
			continue
		var soon: float = (mate.center() - p.pos).dot(v) / v.length_squared()
		if soon < 0.0 or soon > SHOT_SOON:
			continue
		if me.hp / me.hp_max > mate.hp / mate.hp_max or Roster.affinity(p.hit.type, me.types) < Roster.affinity(p.hit.type, mate.types):
			return true
	return false


func _wants_helping_hand(mate: Fighter, diff: Dictionary) -> bool:
	if mate == null or not "helpinghand" in me.data.moves or not me.ready("helpinghand") or mate.help_t > 0.0:
		return false
	# A player's next press cannot be known: only a windup it can see.
	var winding_up: bool = mate.action != null and mate.action.phase == "startup" and mate.action.d.get("cat", "status") != "status"
	var about_to: bool = not mate.is_player and mate.state == "free" and _ally_has_big_move(mate)
	return (winding_up or about_to) and randf() < diff.punish


func _ally_has_big_move(mate: Fighter) -> bool:
	for m in mate.data.moves:
		if float(Moves.DATA[m].get("power", 0)) >= BIG_MOVE and mate.ready(m):
			return true
	return false


## Nobody has it, nobody is close, and the ally is in reach or out of the battle.
func _wants_tailwind(mate: Fighter) -> bool:
	if not "tailwind" in me.data.moves or not me.ready("tailwind") or _decision_t > 0.0 or me.tailwind_t > 0.0:
		return false
	for f in me.foes():
		if f.global_position.distance_to(me.global_position) < WIND_FOE:
			return false
	if mate == null:
		return true
	return mate.tailwind_t <= 0.0 and mate.global_position.distance_to(me.global_position) <= float(Moves.DATA.tailwind.pulse_radius)


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
	if me.flight < maximum * 0.3 and _lands_inside(Vector3.ZERO, 0.0):
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
	# Dashes and lunges carry it toward the rival: not if they would end off the edge
	# (if the rival dodges, the dash goes all the way).
	var travel: float = d.get("dist", d.get("advance", 0.0))
	if travel > 0.0 and not d.get("off_edge", false):
		var to_rival := rival.global_position - me.global_position
		if not _lands_inside(Vector3(-sin(me.ctrl.yaw), 0.0, -cos(me.ctrl.yaw)), travel + 1.5) 				or not _lands_inside(Vector3(to_rival.x, 0.0, to_rival.z), travel + 1.5):
			return
	if d.get("chargeable", false):
		_hold_button(b, randf_range(d.startup, d.startup_max))
	elif d.get("hold", false):
		_hold_button(b, randf_range(d.active + d.startup, d.max))
	else:
		_press(b)


## Moving "meters" along world_dir keeps it on the stage (always true without a void).
func _lands_inside(world_dir: Vector3, meters: float) -> bool:
	if main.arena.void_y == -INF:
		return true
	return main.arena.inside(me.global_position + world_dir.normalized() * meters, 1.0)


func _clear_line(target_point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(me.center(), target_point + Vector3.UP * 0.5, 1)
	return main.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## A status move whose status the rival cannot get now (it has one, was just cured, is
## drowsy, or is immune by type or ability).
func _status_useless(move: String) -> bool:
	var d: Dictionary = Moves.DATA[move]
	if not d.has("inflicts"):
		return false
	var o = me.rival
	if not (o is Fighter) or not is_instance_valid(o):
		return true
	if o.status != "" or o.status_lock > 0.0 or o.drowsy > 0.0:
		return true
	if d.get("respects_types", false) and Roster.immune(Moves.type_for(move, me.data.passive.id), o.types):
		return true
	if d.get("powder", false) and "grass" in o.types:
		return true
	return not Status.can_get("slp" if d.inflicts == "drowsy" else d.inflicts, o.types, o.data.passive.id)
