class_name BattleRules
extends RefCounted
## What a 3 vs 3 can change from one battle to the next (Party reads them). They are picked for
## each battle, with the stage and the difficulty: in the selection's Rules screen (Menu) or
## with --rules=id:value,id:value. A battle keeps them for its rematches, and the menu for the
## next one until the game closes; they are never saved.
##   default          what a battle plays by unless someone changes it
##   min, max, step   what the Rules screen and --rules allow
##   unit             how the value reads: "s", "%", "%/s", "x" or nothing
##   zero             the word for 0, where 0 turns it off
## Player-facing text (group, label, help, zero) is in English and goes through tr() when drawn.

const DEFS := [
	{"id": "recall", "group": "Switching", "label": "Recall", "default": 0.5, "min": 0.1, "max": 1.5, "step": 0.05, "unit": "s",
		"help": "How long the Pokémon stands there, open to hits, before the ball leaves its trainer's hand."},
	{"id": "ball_near", "group": "Switching", "label": "Ball flight, near the trainer", "default": 0.3, "min": 0.0, "max": 1.5, "step": 0.05, "unit": "s",
		"help": "How long the ball flies when the Pokémon is close to its trainer. It can still be hit meanwhile."},
	{"id": "ball_far", "group": "Switching", "label": "Ball flight, far from the trainer", "default": 0.6, "min": 0.0, "max": 1.5, "step": 0.05, "unit": "s",
		"help": "How long the ball flies when the Pokémon is at the far end of the field. It can still be hit meanwhile."},
	{"id": "landing", "group": "Switching", "label": "Landing", "default": 0.2, "min": 0.0, "max": 1.0, "step": 0.05, "unit": "s",
		"help": "How long the one coming in cannot act. It has no invulnerability."},
	{"id": "lockout", "group": "Switching", "label": "Return lockout", "default": 10.0, "min": 0.0, "max": 30.0, "step": 1.0, "unit": "s", "zero": "None",
		"help": "How long the Pokémon that left has to wait before it can come back. It does not hold after a KO."},
	{"id": "start_charges", "group": "Switching", "label": "Switches at the start", "default": 1, "min": 0, "max": 5, "step": 1, "unit": "",
		"help": "How many switches each side starts with."},
	{"id": "max_charges", "group": "Switching", "label": "Switches held at most", "default": 2, "min": 1, "max": 5, "step": 1, "unit": "",
		"help": "How many switches a side can hold."},
	{"id": "recharge", "group": "Switching", "label": "Time for a new switch", "default": 25.0, "min": 5.0, "max": 60.0, "step": 1.0, "unit": "s",
		"help": "How long a new switch takes to come. A switch cut short by a hit still costs it."},
	{"id": "hit_bonus", "group": "Switching", "label": "Time off per hit landed", "default": 1.0, "min": 0.0, "max": 5.0, "step": 0.5, "unit": "s", "zero": "None",
		"help": "How much sooner the next switch comes for each hit you land."},
	{"id": "bench_heal", "group": "Bench", "label": "Healing on the bench", "default": 0.0, "min": 0.0, "max": 5.0, "step": 0.25, "unit": "%/s", "zero": "Off",
		"help": "How much of its max HP a Pokémon on the bench gets back each second. Fainted ones do not."},
	{"id": "ko_choice", "group": "After a KO", "label": "Time to pick the next one", "default": 3.0, "min": 1.0, "max": 10.0, "step": 0.5, "unit": "s",
		"help": "How long you have to pick. Out of time, the healthiest one comes out."},
	{"id": "ko_invuln", "group": "After a KO", "label": "Invulnerable on landing", "default": 1.0, "min": 0.0, "max": 3.0, "step": 0.25, "unit": "s", "zero": "None",
		"help": "How long the next one cannot be hit once it is out."},
	{"id": "ko_energy", "group": "After a KO", "label": "Energy for the team", "default": 30.0, "min": 0.0, "max": 100.0, "step": 5.0, "unit": "", "zero": "None",
		"help": "How much energy the team that lost a Pokémon gets."},
	{"id": "field_pace", "group": "Stadium", "label": "League's field closes slower", "default": 2.5, "min": 1.0, "max": 5.0, "step": 0.5, "unit": "x",
		"help": "How many times slower the League Stadium's field closes in. At 1 it closes as in a 1 vs 1."},
]


static func defaults() -> Dictionary:
	var out := {}
	for d in DEFS:
		out[d.id] = d.default
	return out


static func def(id: String) -> Dictionary:
	for d in DEFS:
		if d.id == id:
			return d
	return {}


## The rules from "id:value,id:value" (--rules), the defaults for the rest. What it does not
## know is reported and left out; values are kept within what the rule allows.
static func parsed(text: String) -> Dictionary:
	var out := defaults()
	for piece in text.split(",", false):
		var kv := piece.split(":")
		var d := def(kv[0])
		if d.is_empty() or kv.size() != 2 or not kv[1].is_valid_float():
			push_warning("--rules: ignored \"%s\"" % piece)
			continue
		out[d.id] = clampf(kv[1].to_float(), d.min, d.max)
	return out


## One step of rule "id" up (1) or down (-1), staying within what it allows.
static func stepped(id: String, value: float, step: int) -> float:
	var d := def(id)
	return clampf(snappedf(value + float(d.step) * step, float(d.step)), d.min, d.max)


## How a value reads on screen.
static func text(id: String, value: float) -> String:
	var d := def(id)
	if value == 0.0 and d.has("zero"):
		return TranslationServer.translate(d.zero)
	var number := ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
	match d.unit:
		"":
			return number
		"x":
			return "x" + number
		"s":
			return number + " s"
	return number + " " + d.unit


## Those that differ from the defaults (for the session log).
static func changed(rules: Dictionary) -> Dictionary:
	var out := {}
	for d in DEFS:
		if rules[d.id] != d.default:
			out[d.id] = rules[d.id]
	return out
