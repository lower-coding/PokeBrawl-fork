class_name Damage
extends RefCounted
## How much a hit takes off, with the games' formula at level 50 so every move does to every
## Pokémon the same share of its health as in the games:
##   (22 × power × Attack / Defense) / 50 + 2
## times STAB (×1.5 if the move is of one of the user's types), type effectiveness (our
## softened table, Roster.affinity) and the average of the games' random roll (×0.925).
## Physical moves use Attack and Defense; special ones, Sp. Atk and Sp. Def, each with its
## stage (Fighter.stages: +1 is x1.5).
## Health is HP × Stats.HP_MULT, so damage is scaled the same way and then divided by
## BATTLE_LENGTH: battles take that many times more hits than in the games.
## A hit that is only part of a use (a stream tick, one of two swipes) deals its share
## (Moves.DATA "split", "power_at"). The weather changes it too (Weather: sun, rain, sand,
## snow; Solar Power).
## A move with "crit" is always a critical hit, as in the games: ×1.5, ignoring the user's
## lowered attack and the target's raised defense. One with "hits_def" is special but measured
## against the target's Defense, not its Sp. Def (Psyshock). Pixilate turns the user's Normal moves
## into Fairy ones (Moves.type_for), for STAB and the weather too, and they hit ×1.2 (PIXILATE).
## Light Screen halves the special damage its side takes (×2/3 in a 2 vs 2): a critical hit and
## Infiltrator go through it (SCREEN, screen_mult). Grass Knot's power goes by the target's weight.

const BATTLE_LENGTH := 4.2
const STAB := 1.5
const CRIT := 1.5
const ROLL := 0.925
const PIXILATE := 1.2
const SCREEN := 0.5
const SCREEN_DOUBLES := 2.0 / 3.0


## Damage of hit "g" from "attacker" to "target" ("affinity": type effectiveness). Without
## stats (--hand-stats) or power, the hit's own hand-tuned damage.
static func dealt(g: Hit, attacker: Fighter, target: Fighter, affinity: float) -> float:
	# A projectile sent back still hits with whoever threw it (its stats, its STAB).
	if g.source is Fighter and is_instance_valid(g.source):
		attacker = g.source
	var d: Dictionary = Moves.DATA.get(g.move_id, {})
	var power := power_of(d, attacker, target)
	var screen := screen_mult(g, d, attacker, target)
	if power <= 0.0 or attacker == null or not attacker.data.has("stats") or not target.data.has("stats"):
		return g.damage * affinity * g.bonus * screen
	var physical := g.cat == "physical"
	var crit: bool = d.get("crit", false)
	var atk_stage: float = attacker.stage_mult("atk" if physical else "spa")
	var vs_def: bool = physical or d.get("hits_def", false)
	var def_stage: float = target.stage_mult("def" if vs_def else "spd")
	if crit:
		atk_stage = maxf(atk_stage, 1.0)
		def_stage = minf(def_stage, 1.0)
	var atk: float = (attacker.data.stats.atk if physical else attacker.data.stats.spa) * atk_stage
	var def: float = (target.data.stats.def if vs_def else target.data.stats.spd) * def_stage
	# A burn halves physical moves (not Facade), as in the games.
	if physical and attacker.status == "brn" and d.get("power_by", "") != "status":
		atk *= 0.5
	var w: Weather = attacker.main.weather
	if w:
		def *= w.defense_mult(target.types, vs_def)
		if not physical and w.is_on("sun") and attacker.data.passive.id == "solarpower":
			atk *= 1.5
	var base := (22.0 * power * atk / def) / 50.0 + 2.0
	# Whoever threw it decides its type (a shot sent back keeps its thrower's).
	var type := Moves.type_for(g.move_id, attacker.data.passive.id)
	if type in attacker.types:
		base *= STAB
	if crit:
		base *= CRIT
	var share: float = g.damage / maxf(float(d.get("power_at", d.get("damage", g.damage))), 0.01)
	if w:
		base *= w.type_mult(type)
	return base * affinity * ROLL * Stats.HP_MULT / BATTLE_LENGTH / float(d.get("split", 1)) * share * g.bonus * screen


## Light Screen on the target's side. A critical hit and Infiltrator go through it.
static func screen_mult(g: Hit, d: Dictionary, attacker: Fighter, target: Fighter) -> float:
	if g.cat != "special" or d.get("crit", false) or not target.main.screen_on(target.team):
		return 1.0
	if attacker and attacker.data.passive.id == "infiltrator":
		return 1.0
	return SCREEN_DOUBLES if target.main.doubles else SCREEN


## The power it hits with: the games', and Pixilate's on the Normal moves of whoever has it.
static func power_of(d: Dictionary, attacker: Fighter, target: Fighter) -> float:
	var power := base_power(d, attacker, target)
	if attacker and d.get("type", "") == "normal" and attacker.data.passive.id == "pixilate":
		power *= PIXILATE
	return power


## The move's power in the games; Electro Ball's depends on how much faster the user is, and Grass Knot's on the target's weight.
static func base_power(d: Dictionary, attacker: Fighter, target: Fighter) -> float:
	if d.get("power_by", "") == "speed" and attacker and target and attacker.data.has("stats"):
		var ratio: float = float(attacker.data.stats.spe) / maxf(float(target.data.stats.spe), 1.0)
		if ratio >= 4.0:
			return 150.0
		if ratio >= 3.0:
			return 120.0
		if ratio >= 2.0:
			return 80.0
		if ratio >= 1.0:
			return 60.0
		return 40.0
	# Grass Knot: Showdown's thresholds, in kg.
	if d.get("power_by", "") == "weight" and target:
		var kg := float(target.data.get("weight_kg", 100.0))
		for step in [[200.0, 120.0], [100.0, 100.0], [50.0, 80.0], [25.0, 60.0], [10.0, 40.0]]:
			if kg >= step[0]:
				return step[1]
		return 20.0
	# Facade: twice the power while the user is burned, poisoned or paralyzed.
	if d.get("power_by", "") == "status" and attacker and attacker.has_status():
		return float(d.get("power", 0)) * 2.0
	# Lash Out: twice the power while a stat drop is fresh (Fighter.lowered_t).
	if d.get("power_by", "") == "lowered" and attacker and attacker.lowered_t > 0.0:
		return float(d.get("power", 0)) * 2.0
	return float(d.get("power", 0))
