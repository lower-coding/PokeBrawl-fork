# Roster plan

Goal: adding Pokémon has to scale, using the real data from the mainline games:
- **base stats** tied to our mechanics;
- **each Pokémon's abilities**, working as in the games and adapted only where their mechanic
  does not fit real time;
- **every move it learns**, so each player builds their own set.

**Decisions so far:**
- **Level 50** as the reference.
- **The games' damage formula, with HP multiplied**, so battles are not as short as in the games.
- **Moves one by one**, all 940 over time, each with its own identity. Shared pieces are there to
  avoid repeating work, not to make recolored copies.
- **Abilities one by one**, translating Showdown's code where possible. The player picks among
  the Pokémon's own (the two regular ones and the hidden one, if it has one).
- In the end, **each Pokémon will have everything it learns** and the player picks 4 moves and
  an ability.

**Built so others can help.** The detail work is huge, so there is a method to go step by step,
and anyone can pick a pending move or ability, follow the steps and contribute it:
- **Written recipes** for adding a move, an ability and a Pokémon, with a real example from
  start to finish ([CONTRIBUTING.md](../CONTRIBUTING.md)).
- **The tracking table as a public task list:** every pending item is something someone can
  pick up.
- **Each move and each ability in its own file,** so two people never touch the same thing.
- **An automated test per move and per ability,** so contributions can be accepted without
  reviewing everything by hand.

---

## 1. Where the data comes from

Everything is in a Cobblemon clone; it is copied into the project with its licenses.

| What | Where | License |
|---|---|---|
| Base stats, types, abilities (regular and hidden), height, weight, hitbox, learnset (level, egg, TM and tutor) | Cobblemon's `species/generationN/<pokemon>.json` (1025 species) | MPL-2.0 (Cobblemon) |
| How each ability works exactly (code), and each move's power, PP, accuracy, priority, effects and flags (contact, punch, bite, slicing, sound, pulse, bullet, wind) | `showdown.zip` inside Cobblemon: Pokémon Showdown (`data/abilities.js`, `moves.js`, `learnsets.js`) | MIT (Showdown) |
| Official names and descriptions of 314 abilities and 940 moves, per language | Cobblemon's `lang/*.json` | MPL-2.0 (Cobblemon) |
| Models and animations | Cobblemon (the converter already exists) | CC BY-NC 3.0, approved by the team |

Showdown's data is read as text, without running its code.

---

## 2. Base stats → mechanics

**Basis:** the real stats at level 50 (31 IVs, no EVs, neutral nature). The differences between
Pokémon are exactly the ones in the games.

| Stat | What it controls | First formula |
|---|---|---|
| **HP** | Health | health = HP at level 50 × 6.5 (roughly what we have now) |
| **Attack / Sp. Atk** | Damage of its physical / special moves | damage formula (below) |
| **Defense / Sp. Def** | Damage taken | damage formula |
| **Speed** | Movement speed, number of dodges, dodge distance and cooldown | speed = 4 + 0.032 × Spe50; dodges = 1 + Spe50 / 45 (max 3); cooldown = 2.2 − 0.009 × Spe50 s |
| **Real weight** | Knockback taken, poise (what does not interrupt it), dodge distance | dodge distance = 3.2 + 0.0225 × Spe50 − 0.085 × ln(kg); knockback and poise still hand-tuned |
| **Height and hitbox** | Size and hurtbox | Cobblemon's |

**Damage:** the games' formula at level 50, `(22 × Power × Attack / Defense) / 50 + 2`, times STAB
and type effectiveness, against the health above and divided by the **HP multiplier**.

**The multiplier, measured:** comparing the current damage of the 36 moves with what the real
formula would deal against an average rival in the roster, today battles need a median of
**about 6 times more hits than in the games**. With a multiplier of 6 battle length stays as it
is. It is a single constant: if battles get too long or too short, that is what gets tuned.

What changes is the distribution. The hand-tuned damage was uneven: Pikachu hit much harder than
it should (x2 against the x6 median) and Garchomp, Scizor or Lucario quite a bit less (x10-12).
With the formula, each one hits according to its Attack and the move's real power.

**How the other mechanics would come out for the current 10** (hand-tuned → formula):

| Pokémon | HP50 | Spe50 | kg | health | speed | dodges | distance | cooldown |
|---|---|---|---|---|---|---|---|---|
| Pikachu | 110 | 110 | 6 | 780 → 720 | 8.6 → 7.5 | 3 → 3 | 6.2 → 5.5 | 1.0 → 1.2 |
| Snorlax | 235 | 50 | 460 | 1480 → 1530 | 5.2 → 5.6 | 2 → 2 | 3.2 → 3.8 | 1.8 → 1.8 |
| Charizard | 153 | 120 | 90.5 | 1020 → 990 | 7.0 → 7.8 | 2 → 3 | 5.0 → 5.5 | 1.3 → 1.1 |
| Blastoise | 154 | 98 | 85.5 | 1060 → 1000 | 6.0 → 7.1 | 2 → 3 | 3.8 → 5.0 | 1.6 → 1.3 |
| Venusaur | 155 | 100 | 100 | 1180 → 1010 | 5.6 → 7.2 | 2 → 3 | 3.5 → 5.0 | 1.8 → 1.3 |
| Lucario | 145 | 110 | 54 | 920 → 940 | 8.0 → 7.5 | 3 → 3 | 5.0 → 5.3 | 1.1 → 1.2 |
| Gengar | 135 | 130 | 40.5 | 880 → 880 | 7.4 → 8.2 | 2 → 3 | 6.5 → 5.8 | 1.5 → 1.0 |
| Garchomp | 183 | 122 | 95 | 1100 → 1190 | 8.8 → 7.9 | 2 → 3 | 5.0 → 5.5 | 1.3 → 1.1 |
| Greninja | 147 | 142 | 40 | 940 → 960 | 8.4 → 8.5 | 3 → 3 | 5.6 → 6.1 | 1.1 → 0.9 |
| Scizor | 145 | 85 | 118 | 1000 → 940 | 7.0 → 6.7 | 3 → 2 | 3.6 → 4.7 | 0.9 → 1.4 |

With real stats, Blastoise and Venusaur have medium speed (78 and 80) rather than slow, and
Garchomp is faster than Pikachu. The formulas get tuned, never a single Pokémon. What does not
come from stats (how it jumps, whether it flies, its dodge style) comes from its type, weight
and a few per-species tags.

---

## 3. Moves: one by one

Each move has its own data and behavior, like the current 36. To make hundreds of them viable:

**1. The data fills itself in.** From Showdown and Cobblemon:
- power → damage;
- PP → cooldown;
- accuracy → homing or spread;
- priority → faster startup;
- secondary effects, with their chance;
- flags;
- name and description in each language.

What remains is the design: how it looks and how it plays.

**2. A library of pieces, not templates.** Moves are built by combining small pieces that already
exist spread across the current scripts, moved to a common place:
- **trajectories:** straight, arc, homing, boomerang, bounce, from the sky, underground;
- **hit volumes:** sphere, capsule, cone, ring, line;
- **user movement:** dash, jump, dive, teleport, spin;
- **lingering zones:** puddle, fire, ice, cracks;
- **status conditions and stat changes;**
- **charge and hold, and multi-hit;**
- **visual effects:** Cobblemon pieces, pixel sprites, trails, waves.

Two homing balls share the homing trajectory, but each has its own way of charging, its look and
its impact. Each move is still its own script; just a short one, because the pieces do the heavy
lifting.

**3. By families.** Moves that are similar in the games are designed together, so they stay
distinct and do not overlap:
- Fire Punch, Ice Punch and Thunder Punch;
- the bites;
- the special balls;
- the streams;
- the dances.

Each family is designed once and then tuned move by move.

**4. By priority.** First the moves of the Pokémon in the game; then those of the next ones to
come in. Whatever is not done does not show up in the menu.

**5. Every move goes through the same process:**
1. automatic data;
2. its entry in [move-references.md](move-references.md) (Pokkén, Smash, anime);
3. design;
4. Cobblemon pieces;
5. a capture strip (`--test=moves --sequence`).

**6. Tracking:** a table with the status of all 940 (pending, data, done, reviewed), so we always
know where we are.

**Cooldown and balance:** they come from real PP and power. Weak moves have 30-40 PP and strong
ones 5. Strong moves get long cooldowns so they cannot be spammed; that pushes players to carry
some weak, fast-recharging move as well, while whoever prefers to wait for their strong moves can
also play that way. Variety and freedom.

---

## 4. Abilities: one by one

- **Each ability is a small file** (`scripts/abilities/`) that mirrors its Showdown code. Showdown
  organizes them by events ("on taking a contact hit", "on computing attack", "at the end of each
  turn"…). The fighter emits those same events, so the translation is almost line by line.
- **Whatever does not fit real time** is adapted as closely as possible:
  - "each turn" → every few seconds;
  - "on switch-in" → at the start of the battle;
  - "on switching out" → the closest adaptation in 1 vs 1.
- **The 314, by how they work** (to estimate):

| How many | How they work | Translation |
|---|---|---|
| 74 | Multiply stats or damage, or change the move (Blaze, Technician, Adaptability…) | As is |
| 31 | Immunities or absorption (Volt Absorb, Immunity, Inner Focus…) | As is |
| 29 | On taking a hit (Static, Rough Skin, Cursed Body…) | As is |
| 45 | On entry or after an event (Intimidate, Steadfast…) | Almost as is |
| 46 | Weather or terrain (Drought, Chlorophyll, Sand Veil…) | Needs weather in the arena |
| 13 | Per turn (Shed Skin, Moody…) | Every few seconds |
| 5 | On switching out (Natural Cure, Regenerator…) | Adapt |
| 68 | Special (items, double battles, forms…) | Case by case |

- **Choice:** the ability is picked in the selection screen among the Pokémon's own.
- **The current 10:** their passives are already real, adapted abilities: Static, Thick Fat,
  Chlorophyll, Rain Dish, Steadfast, Rough Skin, Protean and Technician. Missing:
  - Pikachu: Lightning Rod.
  - Snorlax: Immunity and Gluttony (with items).
  - Charizard: Blaze and Solar Power.
  - Blastoise: Torrent.
  - Venusaur: Overgrow.
  - Lucario: Inner Focus and Justified.
  - Gengar: Cursed Body.
  - Garchomp: Sand Veil (with weather).
  - Greninja: Torrent.
  - Scizor: Swarm and Light Metal.

---

## 5. Adding a Pokémon, once this is in place

1. Convert the Cobblemon model and animations (`tools/import_cobblemon.py`).
2. `tools/import_species.py <pokemon>` generates its data: stats, mechanics, abilities, learnset
   and AI profile.
3. Animation test.
4. Its new moves and abilities join the queue in section 3.

---

## 6. Phases

1. **Importer and stats** (done, `game/scripts/data/stats.gd`): generated data for the 10 and real
   stats applied to health, speed and dodges. `--hand-stats` plays with the old numbers to compare.
2. **The games' damage:** level 50 formula with the HP multiplier, STAB and types; the 36 moves
   with their real power and PP.
3. **Events and abilities:** the system and every ability of the 10, picked in the selection
   screen.
4. **Piece library:** extract the shared pieces from the 36 scripts, without changing how they
   play.
5. **Learnsets:** pick 4 in the selection screen; the missing ones get done family by family.
6. **Grow the roster:** in batches.

**Out for now:** items, natures, EVs and Terastallization.
