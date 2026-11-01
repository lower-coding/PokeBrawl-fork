class_name Party
extends Node
## One trainer's team: its Pokémon, who is out, and the rules of switching. In a 3 vs 3 that is
## each side's three; in a 2 vs 2, each of the four trainers' one to three (Menu.team_size), so a
## 2 vs 2 always has four, even with one member each. One Pokémon per trainer fights at a time;
## main.fighters only ever holds those out there, so everything else in the game sees a 1 vs 1 or
## a plain 2 vs 2 as usual. The numbers are this battle's (BattleRules, "rules"); what follows
## names them.
##
## A switch is a committed move, paid from a scarce resource, that refreshes nothing:
##   - It costs a charge (start_charges, up to max_charges, one more every recharge seconds;
##     each hit landed takes hit_bonus seconds off the wait). The charge is spent on starting,
##     so a switch that gets cut short still costs it.
##   - The Pokémon stands there for recall seconds and the ball's flight (ball_near to ball_far,
##     longer the further it is from its trainer), and can be hit all along: a hit that beats
##     its poise cuts the switch. By default that is longer than nearly every move's startup, so
##     it cannot answer a move it sees coming: it has to be a read.
##   - The one coming in lands where the other stood, landing seconds without acting and with
##     no invulnerability. The one that left cannot come back for lockout seconds.
##   - On the bench a Fighter does not run at all (Fighter.bench), so its cooldowns and status
##     stay as they were, and so does its HP unless bench_heal gives some back. The energy goes
##     with the team (Fighter.take_field). What it does lose on leaving is its stat stages,
##     confusion and decoys (Fighter.leave_field).
##
## After a KO the next one is free: its trainer picks within ko_choice seconds (the healthiest
## by default), it lands on its side of the field with ko_invuln seconds of invulnerability and
## the team gets ko_energy energy. The stat stages of the Pokémon that made the KO go too
## (Main.ko_credit), so a single boosted Pokémon does not sweep all three.
##
## Online each player is in charge of their own team, as with their own Pokémon (Net). The owner
## decides every switch and pick and tells the other copies with reliable events (_tell); "remote",
## a copy only follows them (the net_* functions, called by main.gd) and gets the charges
## with each state packet.

const FLIGHT_DIST := Vector2(6.0, 24.0)  # meters from the trainer for ball_near and ball_far
const KO_MIN := 1.0                      # the faint plays out at least this long
const KO_FLIGHT := 0.6
const AI_PICK := 1.2                     # how long the AI thinks over its next Pokémon

var main: Node
var side := 0                            # its slot: its index in main.fighters
var members: Array = []                  # in the order they were picked; the first one leads
var active: Fighter
var rules := {}                          # this battle's (BattleRules)
var remote := false                      # online: the rival's team; this copy only follows it
var charges := 0
var switches := 0                        # switches started this battle (tests)
var cut := 0                             # of those, how many a hit cut short
var history: Array = []                  # who has come out this battle, in order (tests)
var pending: Fighter = null              # who a switch in progress is bringing in
var lockout := {}                        # Fighter -> seconds until it can come back
var replacing := false                   # its Pokémon fainted and the next one is on its way
var replace_t := 0.0                     # seconds left to pick it
var _recharge := 0.0
var _recall_total := 0.0
var _threw := false
var _ball_out := false
var _chosen: Fighter = null
var _faint_t := 0.0
var _flight_t := 0.0


func setup(m: Node, s: int, list: Array, battle_rules: Dictionary, follows := false) -> void:
	main = m
	side = s
	members = list
	active = list[0]
	rules = battle_rules
	remote = follows
	history = [active.species]
	_full_charges()
	for f in list:
		f.party = self
		if f != active:
			f.bench()


func _full_charges() -> void:
	charges = mini(int(rules.start_charges), max_charges())
	_recharge = rules.recharge


# ---------------------------------------------------------------- what the others ask

func max_charges() -> int:
	return int(rules.max_charges)


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
	return 1.0 if charges >= max_charges() else clampf(1.0 - _recharge / float(rules.recharge), 0.0, 1.0)


## How far along the switch in progress is (0 to 1).
func recall_share() -> float:
	return clampf(active._state_t / maxf(_recall_total, 0.01), 0.0, 1.0) if pending else 0.0


func can_switch(slot: int) -> bool:
	var f := slot_member(slot)
	if f == null or f.state == "ko" or charges < 1 or pending != null or replacing or locked_for(f) > 0.0 or main._end_t >= 0.0:
		return false
	# Falling off a stage with a void: too late, nobody can be sent out over the pit.
	return active.state == "free" and (main.arena.void_y == -INF or main.arena.inside(active.global_position, 0.0))


## A hit of this side's landed.
func on_landed_hit() -> void:
	if charges < max_charges():
		_recharge -= float(rules.hit_bonus)


# ---------------------------------------------------------------- switching

func begin_recall(slot: int) -> void:
	pending = slot_member(slot)
	charges -= 1
	switches += 1
	_threw = false
	_ball_out = false
	var t: Trainer = main.trainers[side]
	var far: float = t.hand().distance_to(active.global_position)
	_recall_total = float(rules.recall) + remap(clampf(far, FLIGHT_DIST.x, FLIGHT_DIST.y), FLIGHT_DIST.x, FLIGHT_DIST.y, rules.ball_near, rules.ball_far)
	active.start_recall()
	main.hud.log_entry(tr("%s, come back!") % tr(active.data.display_name))
	main.session.event("switch", {"team": side, "from": active.species, "to": pending.species, "charges": charges,
		"hp": snappedf(active.hp / active.hp_max, 0.01)})
	_tell({"t": "recall", "to": pending.species, "total": _recall_total})


## One step of the recall; true once it is over and "active" is someone else. It glows more
## and more, for the rival to see it coming.
func step_recall(t: float) -> bool:
	active.appear_glow = clampf(t / maxf(_recall_total, 0.01), 0.0, 1.0) * 0.5
	if not _threw and t >= float(rules.recall) - 0.25:
		_threw = true
		main.trainers[side].throw()
	if not _ball_out and t >= float(rules.recall):
		_ball_out = true
		main.switch_ball(side, active.global_position + Vector3.UP * 0.7, _recall_total - float(rules.recall))
	# Online, the rival's copy waits for its owner's word.
	if remote or t < _recall_total:
		return false
	var out := active
	var incoming := pending
	pending = null
	if float(rules.lockout) > 0.0:
		lockout[out] = rules.lockout
	var spot := _entry_spot(out.global_position)
	_tell_swap("swap", incoming, spot, out.face_yaw)
	_swap(incoming, spot, out.face_yaw)
	incoming.enter_field()
	return true


## The recall was cut short (a hit, a stun): the charge stays spent.
func on_recall_cut() -> void:
	pending = null
	cut += 1
	main.vfx.text(active.center() + Vector3.UP * 0.9, tr("Interrupted!"), Color(1.0, 0.6, 0.4))
	_tell({"t": "recall_cut"})


func _swap(incoming: Fighter, pos: Vector3, yaw: float) -> void:
	var out := active
	out.leave_field()
	active = incoming
	history.append(incoming.species)
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
		_tell({"t": "bench_ko", "sp": who.species})
		return
	pending = null
	replacing = true
	replace_t = rules.ko_choice
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
		var to := _entry_spot(active.start_pos) + Vector3.UP * 0.7
		main.trainers[side].throw()
		main.switch_ball(side, to, KO_FLIGHT)
		_tell({"t": "replace_ball", "to": to})
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
	var foe: Fighter = main.ko_credit(fainted)
	var spot := _entry_spot(fainted.start_pos)
	var to_foe: Vector3 = fainted.rival.global_position - spot
	var yaw := atan2(to_foe.x, to_foe.z)
	_tell_swap("replace", incoming, spot, yaw, {"foe": main.net.seat_of(foe.slot) if main.net and foe else -1})
	_swap(incoming, spot, yaw)
	incoming.energy = minf(Fighter.ENERGY_MAX, incoming.energy + float(rules.ko_energy))
	incoming.invulnerable = rules.ko_invuln
	incoming.enter_field()
	if foe:
		foe.clear_stages()
	main.session.event("replacement", {"team": side, "to": incoming.species, "left": alive_count()})


# ---------------------------------------------------------------- online

## To the other copy of this team, if there is one and this is the owner's.
func _tell(d: Dictionary) -> void:
	if main.net and not remote:
		d.b = main.net.battle
		d.slot = main.net.seat_of(side)
		main.net.send_event(d)


## From this team's owner, to the copy that follows it.
func net_event(d: Dictionary) -> void:
	match d.t:
		"recall":
			net_recall(str(d.get("to", "")), float(d.get("total", 1.0)))
		"recall_cut":
			net_recall_cut()
		"swap":
			net_swap(d)
		"replace_ball":
			net_replace_ball(d.to)
		"replace":
			net_replace(d)
		"bench_ko":
			net_bench_ko(str(d.get("sp", "")))


## Who comes out and where, with what the copy cannot know exactly: the health and status of the
## one leaving and of the one coming in, which the bench has kept.
func _tell_swap(kind: String, incoming: Fighter, pos: Vector3, yaw: float, more := {}) -> void:
	var d := {"t": kind, "to": incoming.species, "pos": pos, "yaw": yaw, "hp": incoming.hp,
		"out_hp": active.hp, "out_status": active.status, "out_status_t": active.status_t}
	d.merge(more)
	_tell(d)


func _member(sp: String) -> Fighter:
	for f in members:
		if f.species == sp:
			return f
	return null


## With each state packet: how many switches its owner has and how far along the next one is.
func net_charges(n: int, share: float) -> void:
	charges = n
	_recharge = (1.0 - share) * float(rules.recharge)


func net_recall(sp: String, total: float) -> void:
	var f := _member(sp)
	if f == null or f == active or active.state == "ko":
		return
	if active.action:
		active.action.finish(true)
		active.action = null
	pending = f
	switches += 1
	_recall_total = total
	_threw = false
	_ball_out = false
	active.start_recall()
	main.hud.log_entry(tr("%s, come back!") % tr(active.data.display_name))


## Its recall was cut on its owner's side (Fighter._switch_state does the rest).
func net_recall_cut() -> void:
	if active.state == "recall":
		active._to_free()


func net_swap(d: Dictionary) -> void:
	var incoming := _member(str(d.get("to", "")))
	if incoming == null or incoming == active:
		return
	var out := active
	pending = null
	out.hp = d.out_hp
	out.status = d.out_status
	out.status_t = d.out_status_t
	if float(rules.lockout) > 0.0:
		lockout[out] = rules.lockout
	_swap(incoming, d.pos, d.yaw)
	incoming.hp = d.hp
	incoming.enter_field()


func net_replace_ball(to: Vector3) -> void:
	main.trainers[side].throw()
	main.switch_ball(side, to, KO_FLIGHT)


func net_replace(d: Dictionary) -> void:
	var incoming := _member(str(d.get("to", "")))
	if incoming == null or incoming == active:
		return
	# Its faint came with a state packet, which may not have arrived yet.
	if active.state != "ko":
		active._die({})
	replacing = false
	pending = null
	# Who made the KO, as its owner saw it: the same one's stages go on every copy.
	var foe: Fighter = main._on_field_at(int(d.foe)) if d.has("foe") else active.rival
	_swap(incoming, d.pos, d.yaw)
	incoming.hp = d.hp
	incoming.invulnerable = rules.ko_invuln
	incoming.enter_field()
	if foe:
		foe.clear_stages()


func net_bench_ko(sp: String) -> void:
	var f := _member(sp)
	if f and f != active and f.state != "ko":
		f._die({})


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
			var type := Moves.type_for(m, f.data.passive.id)
			deals = maxf(deals, power * (Damage.STAB if type in f.data.types else 1.0) * Roster.affinity(type, foe.data.types))
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
	if float(rules.bench_heal) > 0.0:
		for f in members:
			if f != active and f.state != "ko":
				f.heal(f.hp_max * float(rules.bench_heal) / 100.0 * delta)
	if remote:
		return
	if charges < max_charges():
		_recharge -= delta
		if _recharge <= 0.0:
			charges += 1
			_recharge += float(rules.recharge)
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
	_full_charges()
	lockout.clear()
	switches = 0
	cut = 0
	history = [lead.species]
