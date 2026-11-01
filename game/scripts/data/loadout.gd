class_name Loadout
extends RefCounted
## Each Pokémon's four moves and its ability, as the player sets them in the Moves menu or
## before a battle. Saved in user://loadouts.json, so they last between sessions; online, each
## side sends its own with its choice. What is set for the AI's picks is saved apart, one set for
## each AI's slot, so giving the AI's Charizard a set does not change yours, nor a 2 vs 2's other AI's. Only moves the Pokémon learns in the games (level, egg, TM or
## tutor) and whose script is done are allowed, and only abilities it has; anything else
## falls back to the roster's defaults.

## Where they are saved (tests use their own file).
static var path := "user://loadouts.json"
const LEARNED := ["level", "egg", "tm", "tutor"]
## A move more than this share of the roster can use is common.
const COMMON_SHARE := 0.5
const AI_KEY := "ai"

static var _saved := {}
static var _saved_ai := {}       # side 1's, under "ai" in the same file
static var _saved_more := {}     # slot -> a 2 vs 2's other AIs' (2 and 3), under "ai2" and "ai3"
static var _loaded := false
static var _learners := {}       # move -> how many Pokémon can use it
static var _groups := {}         # species and language -> its move_groups


## Moves it can use: its default four first, then the others it learns that are done.
static func moves_for(sp: String) -> Array:
	var out: Array = Roster.POKEMON[sp].moves.duplicate()
	var learns := {}
	if Species.DATA.has(sp):
		for e in Species.DATA[sp].learnset:
			if e.how in LEARNED:
				learns[e.move] = true
	for m in Moves.DATA:
		if learns.has(m) and not m in out and ResourceLoader.exists(Moves.DATA[m].script):
			out.append(m)
	return out


## Its moves in two groups, for the Moves screen: its own, and the common ones (its default four are
## always its own). Each by type, then by name as it reads in this language.
static func move_groups(sp: String) -> Array:
	var key := sp + TranslationServer.get_locale()
	if not _groups.has(key):
		var own: Array = []
		var common: Array = []
		for m in moves_for(sp):
			(common if is_common(m) and not m in Roster.POKEMON[sp].moves else own).append(m)
		own.sort_custom(_listed_before)
		common.sort_custom(_listed_before)
		_groups[key] = [own, common]
	return _groups[key]


static func is_common(move: String) -> bool:
	if _learners.is_empty():
		for sp in Roster.POKEMON:
			for m in moves_for(sp):
				_learners[m] = _learners.get(m, 0) + 1
	return _learners.get(move, 0) > Roster.POKEMON.size() * COMMON_SHARE


static func _listed_before(a: String, b: String) -> bool:
	var ta := UiKit.TYPE_ORDER.find(Moves.DATA[a].type)
	var tb := UiKit.TYPE_ORDER.find(Moves.DATA[b].type)
	if ta != tb:
		return ta < tb
	var na := TranslationServer.translate(Moves.DATA[a].display_name)
	var nb := TranslationServer.translate(Moves.DATA[b].display_name)
	return na.naturalnocasecmp_to(nb) < 0


## The moves that help an ally, by how much the AI wants them (ai_doubles).
const ALLY_MOVES := ["allyswitch", "tailwind", "helpinghand"]


## In a 2 vs 2, an AI Pokémon with nothing saved: half the time its least valued move gives way to
## an ally move it can learn.
static func ai_doubles(sp: String) -> Dictionary:
	var out := default_for(sp)
	if randf() >= 0.5:
		return out
	var can := moves_for(sp)
	for m in ALLY_MOVES:
		if m in can and not m in out.moves:
			var worst := 0
			for i in out.moves.size():
				if float(Moves.DATA[out.moves[i]].get("ai", {}).get("value", 0.0)) < float(Moves.DATA[out.moves[worst]].get("ai", {}).get("value", 0.0)):
					worst = i
			out.moves[worst] = m
			break
	return out


## Four different random moves it can use, at least one an attack of its own type (STAB), or just
## an attack if it has none of those: with none it could not fight. Outside a 2 vs 2, none of those
## that do nothing without an ally ("doubles").
static func random_moves(sp: String, doubles := false) -> Array:
	var pool := moves_for(sp)
	if not doubles:
		pool = pool.filter(func(m): return not Moves.DATA[m].get("needs_ally", false))
	pool.shuffle()
	var four := pool.slice(0, 4)
	var attacks := pool.filter(func(m): return Moves.DATA[m].get("power", 0) > 0)
	var wanted := attacks.filter(func(m): return Moves.DATA[m].type in Roster.POKEMON[sp].types)
	if wanted.is_empty():
		wanted = attacks
	if not four.any(func(m): return m in wanted):
		four[0] = wanted.pick_random()
	return four


## Abilities it can pick: its default one first, then those of its own in the games that
## are done (Abilities.DATA) and its deliberate exceptions (Roster "extra_abilities"). Each
## one with its id.
static func abilities_for(sp: String) -> Array:
	var own: Dictionary = Roster.POKEMON[sp].passive
	var out: Array = [own]
	if Species.DATA.has(sp):
		for a in Species.DATA[sp].abilities:
			# Once each (Gengar has Cursed Body both as its ability and its hidden one).
			if Abilities.DATA.has(a.id) and out.all(func(o): return o.id != a.id):
				var d: Dictionary = Abilities.DATA[a.id].duplicate()
				d.id = a.id
				out.append(d)
	for id in Roster.POKEMON[sp].get("extra_abilities", []):
		if Abilities.DATA.has(id) and out.all(func(o): return o.id != id):
			var d: Dictionary = Abilities.DATA[id].duplicate()
			d.id = id
			out.append(d)
	return out


static func ability(sp: String, id: String) -> Dictionary:
	for a in abilities_for(sp):
		if a.id == id:
			return a
	return Roster.POKEMON[sp].passive


static func default_for(sp: String) -> Dictionary:
	return {"moves": Roster.POKEMON[sp].moves.duplicate(), "ability": Roster.POKEMON[sp].passive.id}


## The loadout if it is allowed (four different moves it can use, an ability it has);
## otherwise the default. Also for what the online rival sends.
static func valid(sp: String, l: Variant) -> Dictionary:
	if not Roster.POKEMON.has(sp):
		return {}
	if not l is Dictionary or not l.get("moves") is Array or not l.get("ability") is String:
		return default_for(sp)
	var can := moves_for(sp)
	var moves: Array = l.moves
	if moves.size() != 4:
		return default_for(sp)
	var seen := {}
	for m in moves:
		if not m is String or not m in can or seen.has(m):
			return default_for(sp)
		seen[m] = true
	var ab: String = l.ability
	if abilities_for(sp).all(func(a): return a.id != ab):
		ab = Roster.POKEMON[sp].passive.id
	return {"moves": moves.duplicate(), "ability": ab}


## What the player saved for this Pokémon on that side (or its default).
static func saved(sp: String, side := 0) -> Dictionary:
	return valid(sp, _of_side(side).get(sp, {}))


static func store(sp: String, l: Dictionary, side := 0) -> void:
	_of_side(side)[sp] = valid(sp, l)
	_write()


## Back to the roster's four moves and ability: one Pokémon, or all of them (sp ""), on that side.
static func restore(sp := "", side := 0) -> void:
	if sp == "":
		_of_side(side).clear()
	else:
		_of_side(side).erase(sp)
	_write()


static func is_default(sp: String, side := 0) -> bool:
	return saved(sp, side) == default_for(sp)


## Whether anything is saved for it on that side, even its default set put back by hand.
static func has_set(sp: String, side := 0) -> bool:
	return _of_side(side).has(sp)


static func _of_side(side: int) -> Dictionary:
	_load()
	if side == 0:
		return _saved
	return _saved_ai if side == 1 else _saved_more.get_or_add(side, {})


static func _write() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		var all := _saved.duplicate()
		all[AI_KEY] = _saved_ai
		for slot in _saved_more:
			all[AI_KEY + str(slot)] = _saved_more[slot]
		f.store_string(JSON.stringify(all, "\t"))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_saved_more = {}
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			var ai: Variant = d.get(AI_KEY, {})
			_saved_ai = ai if ai is Dictionary else {}
			d.erase(AI_KEY)
			for slot in [2, 3]:
				var more: Variant = d.get(AI_KEY + str(slot), {})
				_saved_more[slot] = more if more is Dictionary else {}
				d.erase(AI_KEY + str(slot))
			_saved = d
