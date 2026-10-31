class_name Party
extends Node
## One side's team in a 3 vs 3 battle (--team): its Pokémon, who is out, and the rules of
## switching. One Pokémon per side fights at a time; main.fighters only ever holds the two out
## there, so everything else in the game sees a 1 vs 1 as usual.
##
## A switch is a committed move, paid from a scarce resource, that refreshes nothing:
##   - It costs a charge (START_CHARGES, up to MAX_CHARGES, one more every RECHARGE seconds;
##     each hit landed takes HIT_BONUS seconds off the wait). The charge is spent on starting,
##     so a switch that gets cut short still costs it.
##   - The Pokémon stands there for RECALL seconds and the ball's flight (FLIGHT, longer the
##     further it is from its trainer), and can be hit all along: a hit that beats its poise
##     cuts the switch. At that length it cannot answer a move it sees coming: nearly every
##     move's startup is shorter. It has to be a read.
##   - The one coming in lands where the other stood, LANDING seconds without acting and with
##     no invulnerability. The one that left cannot come back for LOCKOUT seconds.
##   - On the bench a Fighter does not run at all (Fighter.bench), so its HP, cooldowns and
##     status stay as they were. The energy goes with the team (Fighter.take_field). What it
##     does lose on leaving is its stat stages, confusion and decoys (Fighter.leave_field).
##
## After a KO the next one is free: its trainer picks within KO_CHOICE seconds (the healthiest
## by default), it lands on its side of the field with KO_INVULN seconds of invulnerability
## and the team gets KO_ENERGY energy. The stat stages of the Pokémon that made the KO go too,
## so a single boosted Pokémon does not sweep all three.
##
## Offline only: Net keeps one Pokémon per player.

const SIZE := 3
const START_CHARGES := 1
const MAX_CHARGES := 2
const RECHARGE := 25.0
const HIT_BONUS := 1.0
const LOCKOUT := 10.0
const RECALL := 0.5
const FLIGHT := Vector2(0.3, 0.6)        # seconds of the ball's flight, near and far
const FLIGHT_DIST := Vector2(6.0, 24.0)  # meters from the trainer that give them
const LANDING := 0.2
const KO_CHOICE := 3.0
const KO_MIN := 1.0                      # the faint plays out at least this long
const KO_FLIGHT := 0.6
const KO_INVULN := 1.0
const KO_ENERGY := 30.0
const AI_PICK := 1.2                     # how long the AI thinks over its next Pokémon

var main: Node
var side := 0                            # its index in main.fighters
var members: Array = []                  # in the order they were picked; the first one leads
var active: Fighter
var charges := START_CHARGES
var switches := 0                        # switches started this battle (tests)
var cut := 0                             # of those, how many a hit cut short
var pending: Fighter = null              # who a switch in progress is bringing in
var lockout := {}                        # Fighter -> seconds until it can come back
var replacing := false                   # its Pokémon fainted and the next one is on its way
var replace_t := 0.0                     # seconds left to pick it
var _recharge := RECHARGE
var _recall_total := 0.0
var _threw := false
var _ball_out := false
var _chosen: Fighter = null
var _faint_t := 0.0
var _flight_t := 0.0


func setup(m: Node, s: int, list: Array) -> void:
	main = m
	side = s
	members = list
	active = list[0]
	for f in list:
		f.party = self
		if f != active:
			f.bench()


# ---------------------------------------------------------------- what the others ask

## The Pokémon on bench slot "slot" (0 or 1): the other members, in their order.
func slot_member(slot: int) -> Fighter:
	var bench := members.filter(func(f): return f != active)
	return bench[slot] if slot < bench.size() else null


func alive_count() -> int:
	return members.filter(func(f): return f.state != "ko").size()


## Someone else can still come out after "who".
func has_more(who: Fighter) -> bool:
	return members.any(func(f): return f != who and f.state != "ko")


func locked_for(f: Fighter) -> float:
	return lockout.get(f, 0.0)


## How far along the next charge is (0 to 1).
func recharge_share() -> float:
	return 1.0 if charges >= MAX_CHARGES else clampf(1.0 - _recharge / RECHARGE, 0.0, 1.0)


func can_switch(slot: int) -> bool:
	var f := slot_member(slot)
	if f == null or f.state == "ko" or charges < 1 or pending != null or replacing or locked_for(f) > 0.0:
		return false
	# Falling off a stage with a void: too late, nobody can be sent out over the pit.
	return active.state == "free" and (main.arena.void_y == -INF or main.arena.inside(active.global_position, 0.0))


## A hit of this side's landed.
func on_landed_hit() -> void:
	if charges < MAX_CHARGES:
		_recharge -= HIT_BONUS


# ---------------------------------------------------------------- switching

func begin_recall(slot: int) -> void:
	pending = slot_member(slot)
	charges -= 1
	switches += 1
	_threw = false
	_ball_out = false
	var t: Trainer = main.trainers[side]
	var far: float = t.hand().distance_to(active.global_position)
	_recall_total = RECALL + remap(clampf(far, FLIGHT_DIST.x, FLIGHT_DIST.y), FLIGHT_DIST.x, FLIGHT_DIST.y, FLIGHT.x, FLIGHT.y)
	active.start_recall()
	main.hud.log_entry(tr("%s, come back!") % tr(active.data.display_name))
	main.session.event("switch", {"team": side, "from": active.species, "to": pending.species, "charges": charges,
		"hp": snappedf(active.hp / active.hp_max, 0.01)})


## One step of the recall; true once it is over and "active" is someone else. It glows more
## and more, for the rival to see it coming.
func step_recall(t: float) -> bool:
	active.appear_glow = clampf(t / _recall_total, 0.0, 1.0) * 0.5
	if not _threw and t >= RECALL - 0.25:
		_threw = true
		main.trainers[side].throw()
	if not _ball_out and t >= RECALL:
		_ball_out = true
		main.switch_ball(side, active.global_position + Vector3.UP * 0.7, _recall_total - RECALL)
	if t < _recall_total:
		return false
	var out := active
	var incoming := pending
	pending = null
	lockout[out] = LOCKOUT
	_swap(incoming, _entry_spot(out.global_position), out.face_yaw)
	incoming.enter_field()
	return true


## The recall was cut short (a hit, a stun): the charge stays spent.
func on_recall_cut() -> void:
	pending = null
	cut += 1
	main.vfx.text(active.center() + Vector3.UP * 0.9, tr("Interrupted!"), Color(1.0, 0.6, 0.4))


func _swap(incoming: Fighter, pos: Vector3, yaw: float) -> void:
	var out := active
	out.leave_field()
	active = incoming
	incoming.take_field(pos, yaw, out)
	main.on_party_swap(side, out, incoming)
	main.reveal_from_ball(incoming)
	main.hud.log_entry(tr("Go, %s!") % tr(incoming.data.display_name))


## Where it lands: on the ground under "p", and over solid floor if that is off the stage.
func _entry_spot(p: Vector3) -> Vector3:
	var spot := Vector3(p.x, main.ground_y, p.z)
	for k in 30:
		if main.arena.inside(spot, 1.0):
			break
		spot *= Vector3(0.9, 1.0, 0.9)
	return spot


# ---------------------------------------------------------------- after a KO

func on_fainted(who: Fighter) -> void:
	# Fainted on the bench (the recoil of a shot it left flying): nobody has to come out.
	if who != active:
		return
	pending = null
	replacing = true
	replace_t = KO_CHOICE
	_chosen = null
	_faint_t = 0.0
	_flight_t = 0.0
	_ball_out = false


func _step_replacement(delta: float) -> void:
	_faint_t += delta
	replace_t -= delta
	if _chosen == null:
		_chosen = _pick_next()
	if _chosen == null or _faint_t < KO_MIN:
		return
	if not _ball_out:
		_ball_out = true
		_flight_t = KO_FLIGHT
		main.trainers[side].throw()
		main.switch_ball(side, _entry_spot(active.start_pos) + Vector3.UP * 0.7, KO_FLIGHT)
	_flight_t -= delta
	if _flight_t > 0.0:
		return
	_send_replacement()


## The next one, once it is decided: the only one left, the AI's pick, what the player
## pressed or, out of time, the healthiest.
func _pick_next() -> Fighter:
	var left := members.filter(func(f): return f.state != "ko")
	if left.size() == 1:
		return left[0]
	if not active.is_player:
		return best_against(active.rival, left) if _faint_t >= AI_PICK else null
	for slot in 2:
		if active.ctrl.pressed.has("switch%d" % (slot + 1)):
			var f := slot_member(slot)
			if f and f.state != "ko":
				return f
	if replace_t > 0.0:
		return null
	left.sort_custom(func(a, b): return a.hp / a.hp_max > b.hp / b.hp_max)
	return left[0]


func _send_replacement() -> void:
	replacing = false
	var fainted := active
	var incoming := _chosen
	_chosen = null
	var foe: Fighter = fainted.rival
	var spot := _entry_spot(fainted.start_pos)
	var to_foe: Vector3 = foe.global_position - spot
	_swap(incoming, spot, atan2(to_foe.x, to_foe.z))
	incoming.energy = minf(Fighter.ENERGY_MAX, incoming.energy + KO_ENERGY)
	incoming.invulnerable = KO_INVULN
	incoming.enter_field()
	foe.clear_stages()
	main.session.event("replacement", {"team": side, "to": incoming.species, "left": alive_count()})


# ---------------------------------------------------------------- reading the matchup

## How good "f" looks against "foe", roughly and in the same units for everyone: the best it
## can hit with, what the foe's own types can do to it, and how much health it has left. The
## AI uses it to pick and to decide whether a switch is worth a charge.
static func score(f: Fighter, foe: Fighter) -> float:
	var deals := 0.0
	for m in f.data.moves:
		var d: Dictionary = Moves.DATA[m]
		var power: float = 80.0 if d.get("power_by", "") != "" else float(d.get("power", 0))
		if power > 0.0:
			deals = maxf(deals, power * (Damage.STAB if d.type in f.data.types else 1.0) * Roster.affinity(d.type, foe.data.types))
	var takes := 0.0
	for t in foe.data.types:
		takes = maxf(takes, Damage.STAB * 100.0 * Roster.affinity(t, f.data.types))
	return (deals - takes) / 100.0 + 0.8 * f.hp / f.hp_max


static func best_against(foe: Fighter, list: Array) -> Fighter:
	var best: Fighter = null
	var best_score := -INF
	for f in list:
		var s := score(f, foe)
		if s > best_score:
			best_score = s
			best = f
	return best


# ---------------------------------------------------------------- step

func _physics_process(delta: float) -> void:
	if main.intro_t > 0.0 or main._end_t >= 0.0:
		return
	for f in lockout.keys():
		lockout[f] -= delta
		if lockout[f] <= 0.0:
			lockout.erase(f)
	if charges < MAX_CHARGES:
		_recharge -= delta
		if _recharge <= 0.0:
			charges += 1
			_recharge += RECHARGE
	if replacing:
		_step_replacement(delta)


## The lead back out, everyone as new (a rematch).
func restart() -> void:
	var lead: Fighter = members[0]
	replacing = false
	pending = null
	_chosen = null
	if active != lead:
		var out := active
		out.leave_field()
		active = lead
		lead.take_field(lead.start_pos, lead.start_yaw, out)
		main.on_party_swap(side, out, lead)
	for f in members:
		if f != lead:
			f.reset(f.start_pos, f.start_yaw)
			f.bench()
	charges = START_CHARGES
	_recharge = RECHARGE
	lockout.clear()
	switches = 0
	cut = 0
