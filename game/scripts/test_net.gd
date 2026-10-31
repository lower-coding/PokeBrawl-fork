extends Node
## Netplay test (godot --headless --path game -- --host|--join=IP --bot --test=net
## [--duration=s] [--lag=ms --jitter=ms --loss=%]): the AI controls each copy's own
## Pokémon and this test measures whether both copies see the same thing:
##   deviation    distance between the rival's copy and its real position (the one its
##                owner sends), with the ping discounted: what looks "out of place"
##   jumps        times the copy had to snap to a new position
##   hp           both HP values as each copy sees them (compared afterwards)
##   ping         measured round trip
##   stuck_ko     seconds the rival's copy lay fainted while its owner said it was not
## At the end it prints a NET_FINAL line with a summary to compare both copies. In a 3 vs 3
## (both with --team) it has, for each battle, who came out on each side, in order, and everyone's
## HP as this copy saw them: the owner's record of a team must match the other copy's.

var main: Node
var _t := 0.0
var _report := 0.0
var _deviations: Array = []
var _jumps := 0
var _last_pos := Vector3.ZERO
var _battles: Array = []
var _hits_taken := 0
var _hp_before := -1.0
var _stuck_ko := 0.0
var _counted := false            # this battle's end has been written down


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	_t += delta
	var dur := float(main._args.get("duration", "60"))
	var net: Net = main.net
	if net and net.in_battle and net.local and net.remote and is_instance_valid(net.remote):
		var r: Fighter = net.remote
		var s: Dictionary = r.net_state
		if not s.is_empty():
			var age_t: float = s.outbound + (net._t - s.received)
			var real: Vector3 = s.pos + s.speed * clampf(age_t, 0.0, 0.3)
			_deviations.append(r.global_position.distance_to(real))
			if r.state == "ko" and s.state != "ko":
				_stuck_ko += delta
		if _last_pos != Vector3.ZERO and r.global_position.distance_to(_last_pos) > 2.0:
			_jumps += 1
		_last_pos = r.global_position
		var l: Fighter = net.local
		if _hp_before >= 0.0 and l.hp < _hp_before - 0.5:
			_hits_taken += 1
		_hp_before = l.hp
		if main._end_t < 0.0:
			_counted = false
		if main._end_t >= 0.0 and not _counted:
			_counted = true
			_battles.append({"t": _t, "winner": "me" if l.state != "ko" else "rival", "my_hp": l.hp, "rival_hp": r.hp})
			if not main.parties.is_empty():
				_battles.back().merge(_teams())
				print("TEAMS ", JSON.stringify(_teams()))
			print("BATTLE %d: winner %s · my HP %d · rival HP %d" % [_battles.size(), _battles.back().winner, l.hp, r.hp])
			# Rematch by votes: the guest asks first; nothing may start until the host asks
			# too (two seconds later).
			get_tree().create_timer(2.0 if not main.net.host else 4.0).timeout.connect(func():
				if main.net:
					main._vote_rematch(main.net.me))
			if not main.net.host:
				get_tree().create_timer(3.5).timeout.connect(func():
					print("%s  REMATCH waits for everyone: still on the result after only the guest asked" % ("OK   " if main._end_t >= 0.0 else "FAIL ")))
	_report -= delta
	if _report <= 0.0:
		_report = 5.0
		if net and net.local and net.remote and is_instance_valid(net.remote):
			print("t=%3ds  %s  ping %d ms  me %s %d  rival %s %d  mean deviation %.2f m  jumps %d" % [int(_t),
				"host" if net.host else "guest", net.ping_ms(), net.local.species, net.local.hp,
				net.remote.species, net.remote.hp, _mean(_deviations.slice(-300)), _jumps])
		else:
			print("t=%3ds  waiting for connection..." % int(_t))
	if _t > dur:
		_final()


func _teams() -> Dictionary:
	var out := {}
	for k in 2:
		var p: Party = main.parties[k]
		var who := "mine" if k == 0 else "rival"
		out[who] = p.history.duplicate()
		out[who + "_hp"] = p.members.map(func(f): return int(f.hp))
		out[who + "_switches"] = p.switches
		out[who + "_cut"] = p.cut
	return out


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


func _percentile(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(b.size() * p), 0, b.size() - 1)]


func _final() -> void:
	var net: Net = main.net
	var data := {
		"role": "host" if net and net.host else "guest",
		"ping_ms": net.ping_ms() if net else -1,
		"deviation_mean": snappedf(_mean(_deviations), 0.01),
		"deviation_p95": snappedf(_percentile(_deviations, 0.95), 0.01),
		"jumps": _jumps,
		"stuck_ko": snappedf(_stuck_ko, 0.1),
		"battles": _battles.size(),
		"won": _battles.filter(func(c): return c.winner == "me").size(),
		"hits_taken": _hits_taken,
		"my_hp": net.local.hp if net and net.local else -1,
		"rival_hp_seen": net.remote.hp if net and net.remote and is_instance_valid(net.remote) else -1,
		"records": _battles,
	}
	print("NET_FINAL ", JSON.stringify(data))
	get_tree().quit()
