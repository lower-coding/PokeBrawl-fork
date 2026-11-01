class_name Roster
extends RefCounted
## The playable Pokémon: how they move, how much they can take, their passive and their
## moves. Every mobility number is here so it can be tuned without touching code.
##   height      body height in game (m), what hits and effects go by; radius, the body radius
##               used for hits; model_height, the height the model is fitted to, if not that
##               (Goodra's raised antennae make its model far taller than its body)
##   tilt_max    how far moves can lean it forward (rad), for a head that would go through
##               the floor (lean turns around the feet; Goodra's long neck)
##   speed/accel top speed (m/s) and ground acceleration
##   turn        how fast it turns to face (rad/s)
##   jump        initial jump speed; gravity; air_control = control in the air (0 to 1)
##   jumps       jumps before landing, if not 2: the ones in the air cost energy
##               (BattleRules air_jump_cost). Flyers have just one: they take off instead
##   knockback   multiplies how far hits push it (lower is heavier)
##   poise       0 light, 1 heavy: added to the poise of the move it is winding up
##               (see Moves). Only hits with strength >= the total interrupt it
##   no_anims    Cobblemon animations not used for movement (Blastoise's run is
##               withdrawing into its shell)
##   dodge       dist (m), dur (s), iframes [from, to] (s), recovery (s), charges,
##               recharge (s per charge), delay (s from the start of a dodge until charges
##               start coming back; defaults to Fighter.DODGE_DELAY), teleport (vanishes)
##   flight      flyers (Charizard): stamina (s hovering), climb (m/s), ceiling (m),
##               recharge (s to refill on the ground), speed (multiplies air speed).
##               Jump, then jump again in the air to take off
##   item        what it holds, as in the games (Stats.ITEMS): Ash's Pikachu, a Light Ball
##   points      locators shared moves ask for -> this model's own bone, for a model without
##               them (Goodra has a mouth, no cannons): moves stay as they are
##   extra_abilities  abilities it can pick that it does not have in the games
##               (Species.DATA is generated, so they cannot go there). Only for deliberate
##               exceptions: Goodra's Overcoat, Urshifu's Inner Focus (it is Kubfu's)
##   echo_of     this entry is a form of that Pokémon: they share one cell on the selection
##               wall (Menu.form_pick) and a team only holds one of them. To everything else
##               it is one more Pokémon
##   form_name   the form's name; form_tab, the short one on the wall's tabs
## Player-facing text (style, passive name and text) is in English and is translated
## through game/i18n/translations.csv.

const POKEMON := {
	"pikachu": {
		"display_name": "Ash's Pikachu", "types": ["electric"], "cat": "special", "item": "lightball",
		"style": "Ash's Pikachu, with its Light Ball: double Attack and Sp. Atk. Agile and frail; it pressures, changes direction and never stands still.",
		"height": 0.95, "radius": 0.38, "poise": 0, "hp": 780.0, "knockback": 1.25,
		"speed": 8.6, "accel": 75.0, "turn": 18.0, "jump": 9.6, "gravity": 27.0, "air_control": 0.85,
		"dodge": {"dist": 6.2, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.14, "charges": 3, "recharge": 1.0},
		"moves": ["thundershock", "quickattack", "irontail", "electroball"],
		"passive": {"id": "static", "display_name": "Static",
			"text": "Whoever hits it with a contact move has a 30% chance of being paralyzed."},
	},
	"snorlax": {
		"display_name": "Snorlax", "types": ["normal"], "cat": "physical",
		"style": "Huge and slow. Soaks up damage, takes up space and punishes every mistake.",
		"height": 2.3, "radius": 0.95, "poise": 1, "hp": 1480.0, "knockback": 0.45,
		"speed": 5.2, "accel": 24.0, "turn": 6.5, "jump": 7.2, "gravity": 32.0, "air_control": 0.35,
		"dodge": {"dist": 3.2, "dur": 0.3, "iframes": [0.06, 0.22], "recovery": 0.3, "charges": 2, "recharge": 1.8},
		"moves": ["bodyslam", "icepunch", "earthquake", "rest"],
		"passive": {"id": "thickfat", "display_name": "Thick Fat",
			"text": "Takes half damage from Fire and Ice moves. A message shows when it happens."},
	},
	"charizard": {
		"display_name": "Charizard", "types": ["fire", "flying"], "cat": "special",
		"style": "Mid-range pressure. Flies while its stamina lasts; it can never stay up forever.",
		"height": 2.05, "radius": 0.72, "poise": 0, "hp": 1020.0, "knockback": 0.8,
		"speed": 7.0, "accel": 40.0, "turn": 10.0, "jump": 10.5, "gravity": 25.0, "air_control": 0.7,
		"dodge": {"dist": 5.0, "dur": 0.26, "iframes": [0.04, 0.2], "recovery": 0.2, "charges": 2, "recharge": 1.3},
		"flight": {"stamina": 6.0, "climb": 6.5, "ceiling": 8.5, "recharge": 3.0, "speed": 1.15},
		"moves": ["flamethrower", "airslash", "dragonclaw", "flareblitz"],
		"passive": {"id": "blaze", "display_name": "Blaze",
			"text": "At a third of its HP or less, its Fire moves hit 1.5 times as hard. Its tail flame burns brighter."},
	},
	"blastoise": {
		"display_name": "Blastoise", "types": ["water"], "cat": "special",
		"style": "Heavy. Controls lines with water and ice and punishes hard from range.",
		"height": 1.85, "radius": 0.85, "poise": 1, "hp": 1060.0, "knockback": 0.6,
		"speed": 6.0, "accel": 30.0, "turn": 8.0, "jump": 8.0, "gravity": 28.0, "air_control": 0.45,
		"dodge": {"dist": 3.8, "dur": 0.28, "iframes": [0.05, 0.21], "recovery": 0.26, "charges": 2, "recharge": 1.6},
		"no_anims": ["ground_run"],
		"moves": ["aquajet", "hydropump", "rapidspin", "icebeam"],
		"passive": {"id": "torrent", "display_name": "Torrent",
			"text": "At a third of its HP or less, its Water moves hit 1.5 times as hard."},
	},
	"venusaur": {
		"display_name": "Venusaur", "types": ["grass", "poison"], "cat": "special",
		"style": "Slow zoner. Long reach, fouls the ground and punishes anyone who gets careless.",
		"height": 1.75, "radius": 0.95, "poise": 1, "hp": 1180.0, "knockback": 0.55,
		"speed": 5.6, "accel": 26.0, "turn": 7.0, "jump": 7.0, "gravity": 30.0, "air_control": 0.4,
		"dodge": {"dist": 3.5, "dur": 0.3, "iframes": [0.06, 0.22], "recovery": 0.3, "charges": 2, "recharge": 1.8},
		"moves": ["vinewhip", "razorleaf", "sludgebomb", "solarbeam"],
		"passive": {"id": "overgrow", "display_name": "Overgrow",
			"text": "At a third of its HP or less, its Grass moves hit 1.5 times as hard."},
	},
	"lucario": {
		"display_name": "Lucario", "types": ["fighting", "steel"], "cat": "physical",
		"style": "Precise close-range fighter. Gets in fast, punishes and counters.",
		"height": 1.45, "radius": 0.5, "poise": 0, "hp": 920.0, "knockback": 1.0,
		"speed": 8.0, "accel": 60.0, "turn": 15.0, "jump": 10.0, "gravity": 28.0, "air_control": 0.8,
		"dodge": {"dist": 5.0, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.16, "charges": 3, "recharge": 1.1},
		"moves": ["aurasphere", "meteormash", "extremespeed", "detect"],
		"passive": {"id": "steadfast", "display_name": "Steadfast",
			"text": "Each time a hit cuts one of its moves short (it flinches), its Speed rises one stage (x1.5 for the battle)."},
	},
	"gengar": {
		"display_name": "Gengar", "types": ["ghost", "poison"], "cat": "special",
		"style": "Slippery. Harasses from range, tricks and shows up where you least expect it.",
		"height": 1.5, "radius": 0.65, "poise": 0, "hp": 880.0, "knockback": 0.9,
		"speed": 7.4, "accel": 40.0, "turn": 12.0, "jump": 9.0, "gravity": 18.0, "air_control": 0.9,
		"dodge": {"dist": 6.5, "dur": 0.3, "iframes": [0.02, 0.3], "recovery": 0.2, "charges": 2, "recharge": 1.5, "teleport": true},
		"levitates": true,
		# It levitates rather than flies on wings: lower and shorter than Charizard.
		"flight": {"stamina": 4.5, "climb": 5.0, "ceiling": 6.0, "recharge": 3.0, "speed": 1.0},
		"moves": ["shadowball", "sludgebomb", "hex", "substitute"],
		"passive": {"id": "levitate", "display_name": "Levitate",
			"text": "It floats: Earthquake, puddles and ice cannot reach it, and it can fly for a while (jump again in the air). Its dodge is to vanish and reappear."},
	},
	"garchomp": {
		"display_name": "Garchomp", "types": ["dragon", "ground"], "cat": "physical",
		"style": "Aggressive and fast on the ground. Strikes from below and gives no breathing room.",
		"height": 2.0, "radius": 0.75, "poise": 0, "hp": 1100.0, "knockback": 0.7,
		"speed": 8.8, "accel": 45.0, "turn": 11.0, "jump": 10.0, "gravity": 28.0, "air_control": 0.6,
		"dodge": {"dist": 5.0, "dur": 0.25, "iframes": [0.04, 0.2], "recovery": 0.2, "charges": 2, "recharge": 1.3},
		"moves": ["dig", "dragonclaw", "earthquake", "stoneedge"],
		"passive": {"id": "roughskin", "display_name": "Rough Skin",
			"text": "Whoever hits it with a contact move loses 1/8 of its max HP. Sparks fly."},
	},
	"greninja": {
		"display_name": "Greninja", "types": ["water", "dark"], "cat": "special",
		"style": "Ninja. Never stops moving, throws from range and comes in from the sides.",
		"height": 1.55, "radius": 0.5, "poise": 0, "hp": 940.0, "knockback": 1.05,
		"speed": 8.4, "accel": 65.0, "turn": 16.0, "jump": 10.5, "gravity": 27.0, "air_control": 0.85,
		"dodge": {"dist": 5.6, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.15, "charges": 3, "recharge": 1.1},
		"moves": ["watershuriken", "nightslash", "doubleteam", "hydropump"],
		"passive": {"id": "protean", "display_name": "Protean",
			"text": "Takes the type of the last move it used, which changes its weaknesses. Shown by the icons on its frame."},
	},
	"scizor": {
		"display_name": "Scizor", "types": ["bug", "steel"], "cat": "physical",
		"style": "Close-range pressure with short advances. Punishes every mistake with its pincers.",
		"height": 1.8, "radius": 0.6, "poise": 0, "hp": 1000.0, "knockback": 0.8,
		"speed": 7.0, "accel": 55.0, "turn": 13.0, "jump": 8.5, "gravity": 28.0, "air_control": 0.7,
		"dodge": {"dist": 3.6, "dur": 0.18, "iframes": [0.02, 0.15], "recovery": 0.12, "charges": 3, "recharge": 0.9},
		"moves": ["bulletpunch", "xscissor", "swordsdance", "wingattack"],
		"passive": {"id": "technician", "display_name": "Technician",
			"text": "Its moves of 60 power or less hit 1.5 times as hard: Bullet Punch hits above its weight."},
	},
	"goodra": {
		"display_name": "Goodra", "types": ["dragon"], "cat": "special",
		"style": "Heavy and slimy. Controls the mid range with water and ice, and whoever hits it up close gets slower and slower.",
		"height": 2.4, "model_height": 4.0, "radius": 0.7, "tilt_max": 0.9, "poise": 1, "hp": 1070.0, "knockback": 0.6,
		"speed": 7.2, "accel": 28.0, "turn": 8.0, "jump": 7.6, "gravity": 30.0, "air_control": 0.4,
		"dodge": {"dist": 5.0, "dur": 0.28, "iframes": [0.05, 0.21], "recovery": 0.26, "charges": 3, "recharge": 1.3},
		"points": {"locator_cannon_left": "mouth", "locator_cannon_right": "mouth", "locator_mouth": "mouth", "locator_head": "head",
			"locator_hand_primary": "hand_right", "locator_tail": "tail3", "locator_tail_tip": "tail5"},
		"extra_abilities": ["overcoat"],
		"moves": ["dragonpulse", "surf", "icebeam", "bodyslam"],
		"passive": {"id": "gooey", "display_name": "Gooey",
			"text": "Each contact move that hits it lowers the attacker's Speed one stage for the battle."},
	},
	"urshifu": {
		"display_name": "Urshifu", "form_name": "Single Strike", "form_tab": "Single", "types": ["fighting", "dark"], "cat": "physical",
		"style": "One perfect blow. It reads the rival's attack and answers with a hit no guard or stat can soften.",
		"height": 1.9, "model_height": 2.4, "radius": 0.6, "poise": 0, "hp": 1140.0, "knockback": 0.8,
		"speed": 7.7, "accel": 58.0, "turn": 14.0, "jump": 9.5, "gravity": 28.0, "air_control": 0.7,
		"dodge": {"dist": 5.4, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.16, "charges": 3, "recharge": 1.1},
		"points": {"locator_hand_primary": "hand_right", "locator_hand_secondary": "hand_left", "locator_head": "head", "locator_mouth": "mouth2"},
		"extra_abilities": ["innerfocus"],
		"moves": ["wickedblow", "suckerpunch", "closecombat", "bulkup"],
		"passive": {"id": "unseenfist", "display_name": "Unseen Fist",
			"text": "Its contact moves go through Protect and Detect."},
	},
	"urshifurapidstrike": {
		"echo_of": "urshifu",
		"display_name": "Urshifu", "form_name": "Rapid Strike", "form_tab": "Rapid", "types": ["fighting", "water"], "cat": "physical",
		"style": "Flowing water. Wears the rival down with flurries and chills its strength from afar.",
		"height": 1.9, "model_height": 2.4, "radius": 0.6, "poise": 0, "hp": 1140.0, "knockback": 0.8,
		"speed": 7.7, "accel": 58.0, "turn": 14.0, "jump": 9.5, "gravity": 28.0, "air_control": 0.7,
		"dodge": {"dist": 5.4, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.16, "charges": 3, "recharge": 1.1},
		"points": {"locator_hand_primary": "hand_right", "locator_hand_secondary": "hand_left", "locator_head": "head", "locator_mouth": "mouth2"},
		"extra_abilities": ["innerfocus"],
		"moves": ["surgingstrikes", "liquidation", "chillingwater", "closecombat"],
		"passive": {"id": "unseenfist", "display_name": "Unseen Fist",
			"text": "Its contact moves go through Protect and Detect."},
	},
	"mewtwo": {
		"display_name": "Mewtwo", "types": ["psychic"], "cat": "special",
		"style": "Overwhelming psychic power at any range. It takes away the rival's moves and its footing, and is gone before the answer comes.",
		"height": 2.0, "radius": 0.6, "poise": 0, "hp": 1180.0, "knockback": 0.85,
		"speed": 8.8, "accel": 62.0, "turn": 15.0, "jump": 9.6, "gravity": 26.0, "air_control": 0.8,
		"dodge": {"dist": 6.2, "dur": 0.22, "iframes": [0.03, 0.19], "recovery": 0.16, "charges": 3, "recharge": 0.9},
		"points": {"locator_cannon_left": "locator_hand_secondary", "locator_cannon_right": "locator_hand_primary"},
		# Teleport is a legacy move: being a default is what makes it available (Loadout.moves_for).
		"moves": ["psychic", "shadowball", "confusion", "teleport"],
		"passive": {"id": "pressure", "display_name": "Pressure",
			"text": "While it is in play, the rival's moves take 10% longer to come back."},
	},
	"sylveon": {
		"display_name": "Sylveon", "types": ["fairy"], "cat": "special",
		"style": "Slow and hard to wear down. Sweeps the field with wide waves, hunts with homing stars and steals health from whoever gets close.",
		"height": 1.35, "radius": 0.55, "poise": 0, "hp": 1100.0, "knockback": 1.05,
		"speed": 6.6, "accel": 44.0, "turn": 12.0, "jump": 8.6, "gravity": 28.0, "air_control": 0.6,
		"dodge": {"dist": 4.7, "dur": 0.24, "iframes": [0.04, 0.2], "recovery": 0.2, "charges": 2, "recharge": 1.5},
		"points": {"locator_hand_primary": "frontpaw_right", "locator_hand_secondary": "frontpaw_left"},
		"moves": ["moonblast", "swift", "drainingkiss", "hypervoice"],
		"passive": {"id": "pixilate", "display_name": "Pixilate",
			"text": "Its Normal moves become Fairy moves and hit 1.2 times as hard."},
	},
}

## Soft type matchups: a disadvantage matters, but it does not decide the battle on its own.
## An immunity still lets a quarter through ("barely effective").
const EFFECTIVE := 1.25
const NOT_VERY := 0.8
const NOTHING := 0.25

const TABLE := {
	"normal": {"weak": ["rock", "steel"], "immune": ["ghost"]},
	"fire": {"super": ["grass", "ice", "bug", "steel"], "weak": ["fire", "water", "rock", "dragon"]},
	"water": {"super": ["fire", "ground", "rock"], "weak": ["water", "grass", "dragon"]},
	"electric": {"super": ["water", "flying"], "weak": ["electric", "grass", "dragon"], "immune": ["ground"]},
	"grass": {"super": ["water", "ground", "rock"], "weak": ["fire", "grass", "poison", "flying", "bug", "dragon", "steel"]},
	"ice": {"super": ["grass", "ground", "flying", "dragon"], "weak": ["fire", "water", "ice", "steel"]},
	"fighting": {"super": ["normal", "ice", "rock", "dark", "steel"], "weak": ["poison", "flying", "psychic", "bug", "fairy"], "immune": ["ghost"]},
	"poison": {"super": ["grass", "fairy"], "weak": ["poison", "ground", "rock", "ghost"], "immune": ["steel"]},
	"ground": {"super": ["fire", "electric", "poison", "rock", "steel"], "weak": ["grass", "bug"], "immune": ["flying"]},
	"flying": {"super": ["grass", "fighting", "bug"], "weak": ["electric", "rock", "steel"]},
	"psychic": {"super": ["fighting", "poison"], "weak": ["psychic", "steel"], "immune": ["dark"]},
	"bug": {"super": ["grass", "psychic", "dark"], "weak": ["fire", "fighting", "poison", "flying", "ghost", "steel", "fairy"]},
	"rock": {"super": ["fire", "ice", "flying", "bug"], "weak": ["fighting", "ground", "steel"]},
	"ghost": {"super": ["psychic", "ghost"], "weak": ["dark"], "immune": ["normal"]},
	"dragon": {"super": ["dragon"], "weak": ["steel"], "immune": ["fairy"]},
	"dark": {"super": ["psychic", "ghost"], "weak": ["fighting", "dark", "fairy"]},
	"steel": {"super": ["ice", "rock", "fairy"], "weak": ["fire", "water", "electric", "steel"]},
	"fairy": {"super": ["fighting", "dragon", "dark"], "weak": ["fire", "poison", "steel"]},
}

const TYPE_NAME := {
	"normal": "Normal", "fire": "Fire", "water": "Water", "electric": "Electric", "grass": "Grass", "ice": "Ice",
	"fighting": "Fighting", "poison": "Poison", "ground": "Ground", "flying": "Flying", "psychic": "Psychic",
	"bug": "Bug", "rock": "Rock", "ghost": "Ghost", "dragon": "Dragon", "dark": "Dark", "steel": "Steel", "fairy": "Fairy",
}

const TYPE_COLOR := {
	"normal": Color("c9c6a5"), "fire": Color("ff8a3d"), "water": Color("5aa2ff"), "electric": Color("ffd93a"),
	"grass": Color("7fd65b"), "ice": Color("9ff0f5"), "fighting": Color("e0553e"), "poison": Color("b45cc8"),
	"ground": Color("e2bf65"), "flying": Color("b9a8ff"), "psychic": Color("ff6f9f"), "bug": Color("b5cc2c"),
	"rock": Color("c9b458"), "ghost": Color("8f6fc4"), "dragon": Color("7f5cff"), "dark": Color("8a7062"),
	"steel": Color("c8ccdf"), "fairy": Color("f2a3cf"),
}


## The Pokémon a form belongs to on the selection wall (itself if it is not an echo).
static func base_of(sp: String) -> String:
	return POKEMON.get(sp, {}).get("echo_of", sp)


## Its forms: the base first, then its echoes.
static func forms(sp: String) -> Array:
	var base := base_of(sp)
	var out: Array = [base]
	for id in POKEMON:
		if POKEMON[id].get("echo_of", "") == base:
			out.append(id)
	return out


## Whether one of these types is immune to the move's type in the games. Damage only
## softens immunities (NOTHING); status effects follow them to the letter.
static func immune(type: String, defense: Array) -> bool:
	var row: Dictionary = TABLE.get(type, {})
	return defense.any(func(t): return t in row.get("immune", []))


## How a multiplier reads, like the games' tiers: "super" (weak twice, x4 there),
## "effective" (x2), "" (neutral), "not_very" (x1/2), "barely" (resisted twice, x1/4 there,
## or immune).
static func tier(mult: float) -> String:
	if mult > EFFECTIVE * 1.15:
		return "super"
	if mult > 1.05:
		return "effective"
	if mult < NOT_VERY * 0.88:
		return "barely"
	if mult < 0.95:
		return "not_very"
	return ""


static func affinity(type: String, defense: Array) -> float:
	var row: Dictionary = TABLE.get(type, {})
	var m := 1.0
	for t in defense:
		if t in row.get("super", []):
			m *= EFFECTIVE
		elif t in row.get("immune", []):
			m *= NOTHING
		elif t in row.get("weak", []):
			m *= NOT_VERY
	return clampf(m, NOTHING, EFFECTIVE * EFFECTIVE)
