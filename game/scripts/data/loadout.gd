class_name Loadout
extends RefCounted
## Each Pokémon's four moves and its ability, as the player sets them in the Moves menu.
## Saved in user://loadouts.json, so they last between sessions; online, each side sends
## its own with its choice. Only moves the Pokémon learns in the games (level, egg, TM or
## tutor) and whose script is done are allowed, and only abilities it has; anything else
## falls back to the roster's defaults.

## Where they are saved (tests use their own file).
static var path := "user://loadouts.json"
const LEARNED := ["level", "egg", "tm", "tutor"]
## A move more than this share of the roster can use is common.
const COMMON_SHARE := 0.5

static var _saved := {}
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


## Four different random moves it can use, at least one an attack: with none it could not fight.
static func random_moves(sp: String) -> Array:
	var pool := moves_for(sp)
	pool.shuffle()
	var four := pool.slice(0, 4)
	if four.all(func(m): return Moves.DATA[m].get("power", 0) <= 0):
		four[0] = pool.filter(func(m): return Moves.DATA[m].get("power", 0) > 0).pick_random()
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


## What the player saved for this Pokémon (or its default).
static func saved(sp: String) -> Dictionary:
	_load()
	return valid(sp, _saved.get(sp, {}))


static func store(sp: String, l: Dictionary) -> void:
	_load()
	_saved[sp] = valid(sp, l)
	_write()


## Back to the roster's four moves and ability: one Pokémon, or all of them (sp "").
static func restore(sp := "") -> void:
	_load()
	if sp == "":
		_saved.clear()
	else:
		_saved.erase(sp)
	_write()


static func is_default(sp: String) -> bool:
	return saved(sp) == default_for(sp)


static func _write() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_saved, "\t"))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			_saved = d
