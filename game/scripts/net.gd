class_name Net
extends Node
## Online play over IP (ENet over UDP): two players in a 1 vs 1 or 3 vs 3, two to four in a 2 vs 2.
##
## Authority: each player is in charge of their own Pokémon. Their presses run instantly
## on their screen; they reach the others with the ping and move a copy there (the
## "remote"), which is also corrected with the real state. Whoever takes a hit decides
## whether it landed (if they dodged on their screen, it did not) and tells the attacker.
## In a team battle "owned" and "remotes" are whoever is out: a switch is the owner's to decide and
## comes as reliable events (Party). Each state packet says which team member it is about, since
## it can overtake the event: one about somebody else is dropped.
##
## Seats: what travels says who by seat, the same on every copy. A copy's slots are worked out from
## its own seat (slot_of), so everyone is slot 0 on their own screen, with their ally at 2. The host
## also owns the AIs in a 2 vs 2's empty seats.
## ENet guests only reach the host, so the host relays what one says on to the others: guests hear
## each other at twice the path, and the ping shown is only to the host.
## Each battle has its number ("battle": every start and rematch, on both copies). What comes from
## another battle is dropped: a packet still on its way from the last one would knock out the
## new copy of a Pokémon that fainted there.
##
## Custom packets, no RPC, to keep them small:
##   channel 0, unreliable, every frame: input + state of each Pokémon this copy owns
##   channel 1, reliable: start, confirmed hits, effects, KO, rematch...
## Presses travel as per-action counters: even if a packet is lost, the next one carries
## them.
##
## Testing: --lag=ms (round trip), --jitter=ms and --loss=% simulate a bad network.

signal connected
signal disconnected(reason: String)
signal guest_joined(seat: int)   # the host, a 2 vs 2's room: one more, after the first
signal guest_left(seat: int)
signal event(data: Dictionary)

const PORT := 7777
const ACTIONS := ["jump", "dodge", "lock_on", "mov1", "mov2", "mov3", "mov4", "descend"]
const STATES := ["free", "action", "dodge", "stunned", "knocked_down", "lying", "get_up", "ko", "dive", "recall", "enter"]
const STATUSES := ["", "brn", "par", "psn", "tox", "slp", "frz"]
const TYPES := ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
const P_STATE := 1
const P_EVENT := 2
## Between one guest and the host alone: never passed on. "choice" comes back in the "room" the host
## sends each one, which keeps a team hidden from the other side.
const NOT_RELAYED := ["ping", "pong", "choice", "asks_rematch"]

var main: Node
var peer: ENetMultiplayerPeer
var host := false
var linked := false              # connected to the other player
## This copy's own id in shared decisions (votes): random per session, the same for the
## whole connection.
var me := ""
var in_battle := false
var battle := 0                 # this battle's number, the same on every copy
var seat := 0                   # this copy's seat: the host starts at 0, a guest at 1 until told
var guests := {}                 # the host: peer id -> seat
var humans := 2                 # how many players this battle has (the guests' count of votes)
var guest_seats: Array = []      # this battle's guests, by seat
var owned: Array = []            # the Pokémon this copy decides: its player and, on the host, the AIs
var remotes := {}                # slot -> the copy of someone else's
var local: Fighter:              # your own Pokémon
	get:
		return owned[0] if not owned.is_empty() else null
var remote: Fighter:             # the copy across from you, if that one is a copy
	get:
		return remotes.get(1)
var frame := 0
var rtt := 0.0                   # round trip, in seconds (measured)
var lag_sim := 0.0               # simulated round-trip delay (s)
var jitter_sim := 0.0
var loss_sim := 0.0
var upnp_ok := false
var public_ip := ""

var _seen_list := {}                # seat -> last counters received from it
var _last_frame_other := {}      # seat -> last frame received from it
var states_applied := 0       # rival states actually applied (tests and the session log)
var _exit_t: Array = []          # [time, channel, bytes, target] (simulated network)
var _reliable_leaves := 0.0      # when the last reliable packet leaves (simulated network)
var _ping_t := 0.0
var _pings := {}                 # id -> send time
var _ping_id := 0
var _last_packet := 0.0
var _t := 0.0
var _upnp: UPNP
var upnp_testing := false


func _ready() -> void:
	me = "%08x" % (randi() & 0x7fffffff)
	process_physics_priority = -15


# ---------------------------------------------------------------- connection

## "room": how many guests fit.
func create(port := PORT, room := 1) -> String:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, room, 2)
	if err != OK:
		return tr("Could not open port %d (is another program using it?)") % port
	host = true
	seat = 0
	_setup_peer()
	_open_router_port.call_deferred(port)
	return ""


func join(ip: String, port := PORT) -> String:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port, 2)
	if err != OK:
		return tr("Invalid address")
	host = false
	seat = 1
	_setup_peer()
	return ""


func _setup_peer() -> void:
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_t = 0.0
	frame = 0
	guests.clear()
	_seen_list.clear()
	_last_frame_other.clear()


func _on_peer_connected(id: int) -> void:
	if host and linked and (in_battle or not main.menu.in_room()):
		# A battle is on: there is no seat for it. Not one of ours, so it goes unnoticed.
		peer.disconnect_peer(id)
		return
	var first := not linked
	linked = true
	_last_packet = _t
	if host:
		guests[id] = _free_seat()
	# No compression and no waiting: small packets, sent as soon as they are made.
	if first:
		connected.emit()
	else:
		guest_joined.emit(guests[id])


func _on_peer_disconnected(id: int) -> void:
	if host and not guests.has(id):
		return
	# In a 2 vs 2's room the seat just goes back to the AI, while somebody else is there.
	if host and guests.size() > 1 and not in_battle and main.menu.in_room():
		var left: int = guests[id]
		guests.erase(id)
		guest_left.emit(left)
		return
	# Never close the connection inside its own callback (it hangs): do it afterwards.
	_lost.call_deferred(tr("The other player disconnected"))


## The first seat with no player. Guests fill 1, then 2, then 3, so two people are rivals by default.
func _free_seat() -> int:
	for s in [1, 2, 3]:
		if s != seat and not s in guests.values():
			return s
	return 0


## "incoming" came out for "out".
func swapped(out: Fighter, incoming: Fighter) -> void:
	var i := owned.find(out)
	if i >= 0:
		owned[i] = incoming
	if remotes.get(out.slot) == out:
		remotes[out.slot] = incoming


## This copy's slot for the Pokémon in seat "s", or the other way round: either way, everyone is
## slot 0 on their own screen, with the ally at 2 and whoever is across from them at 1.
func slot_of(s: int) -> int:
	return s ^ seat


func seat_of(slot: int) -> int:
	return slot ^ seat


func close() -> void:
	if peer:
		peer.close()
	peer = null
	linked = false
	in_battle = false
	owned.clear()
	remotes.clear()
	guests.clear()
	_exit_t.clear()
	if _upnp and upnp_ok:
		# Removing the port from the router takes a while: in the background, without stalling the game.
		var u := _upnp
		WorkerThreadPool.add_task(func(): u.delete_port_mapping(PORT, "UDP"))
	upnp_ok = false


func _lost(reason: String) -> void:
	if not linked and peer == null:
		return
	close()
	disconnected.emit(reason)


## Tries to open the port on the router (UPnP) so others can join from outside.
func _open_router_port(port: int) -> void:
	# On the thread pool: if the game is closed halfway, the task finishes on its own
	# without leaving a dangling thread.
	var u := UPNP.new()
	_upnp = u
	upnp_testing = true
	var r := [false, ""]
	var task := WorkerThreadPool.add_task(func():
		if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
			r[0] = u.add_port_mapping(port, port, "PokeBrawl", "UDP") == UPNP.UPNP_RESULT_SUCCESS
			r[1] = u.query_external_address())
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	WorkerThreadPool.wait_for_task_completion(task)
	upnp_testing = false
	if peer == null:
		# It was closed in the meantime: the open port is not needed.
		if r[0]:
			WorkerThreadPool.add_task(func(): u.delete_port_mapping(port, "UDP"))
		return
	upnp_ok = r[0]
	public_ip = r[1]


## This computer's local IPs (for LAN or VPNs like Radmin/ZeroTier).
static func local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


# ---------------------------------------------------------------- sending

## "target": a peer, minus one for all but that one, or 0 for everyone.
func _send(channel: int, data: PackedByteArray, target := 0) -> void:
	if peer == null:
		return
	if lag_sim > 0.0 or loss_sim > 0.0:
		if channel == 0 and randf() * 100.0 < loss_sim:
			return
		var outbound := lag_sim * 0.5 + randf_range(-jitter_sim, jitter_sim) * 0.5
		var leaves := _t + maxf(outbound, 0.0)
		# The reliable channel arrives in order, as ENet's does, whatever the jitter.
		if channel == 1:
			leaves = maxf(leaves, _reliable_leaves)
			_reliable_leaves = leaves
		_exit_t.append([leaves, channel, data, target])
		return
	_put_on(channel, data, target)


func _put_on(channel: int, data: PackedByteArray, target := 0) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.transfer_channel = channel
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel == 0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.set_target_peer(target if host else MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.put_packet(data)
	# Send it now, not on the next poll (that would add 16 ms each way).
	if peer.host:
		peer.host.flush()


## How many players share this session (themselves included): the votes (rematch) count against
## this.
func players() -> int:
	if not linked:
		return 1
	return guests.size() + 1 if host else humans


## Reliable event (start, confirmed hit, effect, KO, rematch, pick...), for everyone.
func send_event(data: Dictionary) -> void:
	send_event_to(0, data)


## "to": the peer to tell. A guest can only tell the host.
func send_event_to(to: int, data: Dictionary) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(P_EVENT)
	b.put_var(data)
	_send(1, b.data_array, to)


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_t += delta
	if peer == null:
		return
	peer.poll()
	# Simulated delayed output.
	var i := 0
	while i < _exit_t.size():
		if _exit_t[i][0] <= _t:
			_put_on(_exit_t[i][1], _exit_t[i][2], _exit_t[i][3])
			_exit_t.remove_at(i)
		else:
			i += 1
	while peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED and peer.get_available_packet_count() > 0:
		# Who sent it is about the next packet: read it first.
		var from := peer.get_packet_peer()
		var pkt := peer.get_packet()
		_last_packet = _t
		_receive(pkt, from)
	if peer == null:
		return
	if linked and _t - _last_packet > 5.0:
		_lost.call_deferred(tr("No response from the other player"))
		linked = false
		return
	# Own ping every half second (includes the simulated network).
	_ping_t -= delta
	if linked and _ping_t <= 0.0:
		_ping_t = 0.5
		_ping_id += 1
		_pings[_ping_id] = _t
		send_event({"t": "ping", "id": _ping_id})
	if in_battle and not owned.is_empty():
		frame += 1
		for f in owned:
			_send(0, _pack(f))


func _receive(pkt: PackedByteArray, from: int) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = pkt
	match b.get_u8():
		P_STATE:
			if host and guests.size() > 1:
				_send(0, pkt, -from)
			_read_state(b)
		P_EVENT:
			var d = b.get_var()
			if typeof(d) != TYPE_DICTIONARY:
				return
			if host and guests.size() > 1 and not d.get("t", "") in NOT_RELAYED:
				_send(1, pkt, -from)
			# Its seat, from the connection: nobody can speak for another.
			if host:
				d.from = guests.get(from, -1)
			match d.get("t", ""):
				"ping":
					send_event_to(from, {"t": "pong", "id": d.id})
				"pong":
					if _pings.has(d.id):
						var measured: float = _t - _pings[d.id]
						rtt = measured if rtt <= 0.0 else lerpf(rtt, measured, 0.3)
						_pings.erase(d.id)
				_:
					event.emit(d)


# ---------------------------------------------------------------- state

func _pack(l: Fighter) -> PackedByteArray:
	var c := l.ctrl
	var b := StreamPeerBuffer.new()
	b.put_u8(P_STATE)
	b.put_u8(seat_of(l.slot))
	b.put_u32(frame)
	b.put_u8(battle & 255)
	# Its team: which member this is about, its switches and how far along the next one is.
	var p: Party = l.party
	b.put_u8(p.members.find(l) if p else 0)
	b.put_u8(p.charges if p else 0)
	b.put_u8(roundi(p.recharge_share() * 255.0) if p else 0)
	# Input: what the copy needs to do the same.
	b.put_float(c.move_input.x)
	b.put_float(c.move_input.y)
	b.put_float(c.yaw)
	b.put_float(c.aim_at.x)
	b.put_float(c.aim_at.y)
	b.put_float(c.aim_at.z)
	var mask := 0
	for k in ACTIONS.size():
		if c.keeps(ACTIONS[k]):
			mask |= 1 << k
	b.put_u16(mask)
	for a in ACTIONS:
		b.put_u8(int(c.counter.get(a, 0)))
	# Confused, a press fires another move: it travels with them, so the copy fires the same one.
	b.put_u8(buttons_code(l.button_moves))
	# Real state, to correct the copy.
	for v in [l.global_position, l.velocity]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	b.put_float(l.face_yaw)
	b.put_u8(maxi(STATES.find(l.state), 0))
	b.put_float(l._stunned)
	var code := 0
	if l.action:
		code = l.data.moves.find(l.action.id) + 1
	b.put_u8(code)
	b.put_u8(["startup", "active", "recovery"].find(l.action.phase) if l.action else 0)
	b.put_float(l.action.t if l.action else 0.0)
	# The status: code, time left, toxic turns.
	for v in [l.hp, l.energy, l.charges, l.flight, l.slow, l._slow_t, float(STATUSES.find(l.status)), l.status_t, l._status_age,
			l.steadfast_t, l.translucent, l.invulnerable]:
		b.put_float(v)
	# The last two decide whether a press is refused, so a copy reaches the owner's answer.
	b.put_u8((1 if l.flying else 0) | (2 if l.model.visible else 0) | (4 if c.aim_ally else 0) | (8 if c.ally_near else 0))
	b.put_u8(l.boosted_hits)
	b.put_u8(maxi(TYPES.find(l.types[0]), 0))
	b.put_u8(TYPES.find(l.types[1]) + 1 if l.types.size() > 1 else 0)
	# Who it is after: with two foes a copy could not tell what its shots follow.
	b.put_u8(seat_of(l.rival.slot) if is_instance_valid(l.rival) else 255)
	return b.data_array


func _read_state(b: StreamPeerBuffer) -> void:
	var from := b.get_u8()
	var f := b.get_u32()
	var last: int = _last_frame_other.get(from, -1)
	if f <= last and last - f < 1000000:
		return   # old or repeated
	_last_frame_other[from] = f
	var r: Fighter = remotes.get(slot_of(from))
	if r == null or not is_instance_valid(r):
		return
	if b.get_u8() != battle & 255:
		return   # from the battle before, or from the next one if the rival got there first
	var member := b.get_u8()
	var team_charges := b.get_u8()
	var team_share := b.get_u8() / 255.0
	if r.party:
		if r.party.members.find(r) != member:
			return   # about another member: the event of its switch is on its way, or went by
		r.party.net_charges(team_charges, team_share)
	states_applied += 1
	var c := r.ctrl
	c.move_input = Vector2(b.get_float(), b.get_float())
	c.yaw = b.get_float()
	c.aim_at = Vector3(b.get_float(), b.get_float(), b.get_float())
	var mask := b.get_u16()
	# Estimated one-way delay, in frames: whatever starts is fast-forwarded by it.
	var outbound := _outbound_from(from)
	var lead := int(round(outbound * 60.0))
	var seen: Dictionary = _seen_list.get_or_add(from, {})
	for k in ACTIONS.size():
		var a: String = ACTIONS[k]
		var n := b.get_u8()
		var new_ones := (n - int(seen.get(a, 0)) + 256) % 256
		seen[a] = n
		if new_ones > 0 and new_ones < 30:
			c.press(a)
			r.net_lead = lead
		elif mask & (1 << k):
			c.held[a] = true
		else:
			c.release(a)
		# The owner's count, whatever got lost on the way: infatuation's roll goes by it.
		c.counter[a] = n
	r.button_moves = buttons_from(b.get_u8())
	var s := {}
	s.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
	s.speed = Vector3(b.get_float(), b.get_float(), b.get_float())
	s.yaw = b.get_float()
	s.state = STATES[clampi(b.get_u8(), 0, STATES.size() - 1)]
	s.stunned = b.get_float()
	s.action = b.get_u8()
	s.phase = b.get_u8()
	s.action_t = b.get_float()
	for k in ["hp", "energy", "charges", "flight", "slow", "slow_t", "burned", "poisoned", "static_mark",
			"steadfast_t", "translucent", "invulnerable"]:
		s[k] = b.get_float()
	var flags := b.get_u8()
	s.flying = flags & 1 != 0
	s.visible = flags & 2 != 0
	c.aim_ally = flags & 4 != 0
	c.ally_near = flags & 8 != 0
	s.boosted_hits = b.get_u8()
	var t1 := b.get_u8()
	var t2 := b.get_u8()
	s.types = [TYPES[clampi(t1, 0, TYPES.size() - 1)]] + ([TYPES[t2 - 1]] if t2 > 0 and t2 <= TYPES.size() else [])
	var after := b.get_u8()
	if slot_of(after) < main.fighters.size():
		var who: Fighter = main.fighters[slot_of(after)]
		if r.rival != who:
			r.rival = who
			r.fooled_by = null
	s.outbound = outbound
	s.received = _t
	r.net_state = s


## Fighter.button_moves in one byte: two bits per button.
static func buttons_code(order: Array) -> int:
	return order[0] | order[1] << 2 | order[2] << 4 | order[3] << 6


static func buttons_from(code: int) -> Array:
	return [code & 3, code >> 2 & 3, code >> 4 & 3, code >> 6 & 3]


## Estimated one-way delay (s).
func _outbound() -> float:
	return maxf(rtt, 0.0) * 0.5


## From seat "s": another guest's comes through the host, so it has twice the path. The AIs are the
## host's own.
func _outbound_from(s: int) -> float:
	return _outbound() * (2.0 if not host and s in guest_seats else 1.0)


func ping_ms() -> int:
	return int(round(rtt * 1000.0))
