# Contributing to PokeBrawl

Thanks for helping. The long-term goal is every Pokémon with its real learnset and abilities
([docs/roster-plan.md](docs/roster-plan.md)), and that only works if moves and abilities can be
added one at a time by different people. These recipes are how.

Before starting something big, open an issue (or comment on an existing one) so two people do
not build the same move.

## Ground rules

- **English everywhere** in code, comments and data. Player-facing text is written in English and
  goes through `tr()` (or `TranslationServer.translate()` outside nodes); see
  [Translations](#translations).
- **One move, one file.** Each move's behavior lives in `game/scripts/moves/<id>.gd`, where `<id>`
  is its [Showdown](https://github.com/smogon/pokemon-showdown) id (lowercase, no spaces:
  `thundershock`, `aurasphere`).
- **Balance numbers live in data**, not in scripts: `game/scripts/data/moves.gd` for moves,
  `game/scripts/data/roster.gd` for Pokémon.
- **Readable first.** Every move needs a startup the opponent can read and a way to answer it
  (dodge, jump, step aside, punish). Write that answer in the move's `counterplay`.
- **Visual style:** Cobblemon's own particle pieces first; whatever is missing, pixel art at
  Cobblemon's density (16 px per meter) with flat color bands and stepped transparency. No smooth
  gradients or soft glows, and nothing that flashes faster than twice per second.
- **Assets:** only Cobblemon assets (respecting their licenses) or your own work. Never assets
  ripped from the official games.

## Recipe: add a move

Use an existing move as a model. `thundershock` (projectile), `quickattack` (dash, through the
shared `dash.gd`), `flamethrower` (held stream), `hyperbeam` (held beam, through the shared
`energystream.gd`), `aurasphere` (chargeable) and `earthquake` (ground wave) cover the common
shapes.

1. **Research.** Look the move up in Pokkén and Smash (button, does it charge, is it a counter,
   what punishes it) and how it looks in the anime. Add a short entry to
   [docs/move-references.md](docs/move-references.md).

2. **Find its Cobblemon pieces.** Its particle pieces and sequence, if Cobblemon has them, are in
   `game/fx/particles/<move>_*.json` and `game/fx/sequences/<move>.json`.

3. **Add its data** to `Moves.DATA` in `game/scripts/data/moves.gd`, under the Pokémon section it
   belongs to. The header of that file documents every field. The minimum:

   ```gdscript
   "thundershock": {
       "display_name": "Thunder Shock", "script": "res://scripts/moves/thundershock.gd",
       "type": "electric", "cat": "special",
       "cost": 12.0, "cd": 1.0, "startup": 0.16, "active": 0.1, "recovery": 0.22,
       "damage": 52.0, "push": 3.0, "stun": 0.35, "hitstop": 0.05,
       "desc": "A straight discharge from the cheeks. Fast and cheap.",
       "counterplay": "It flies straight: sidestep it or dodge through it.",
       "ai": {"min": 3.0, "max": 18.0, "kind": "projectile", "value": 1.0},
   },
   ```

   `fx_startup`, `fx_active` and `fx_hit` list the Cobblemon pieces to spawn in each phase. `ai`
   tells the AI when to use it (`kind` is one of `projectile`, `engage`, `punish`, `area`,
   `heal`, `stream`, `charge`, `guard`, `decoy`, `buff`).

4. **Write its behavior** in `game/scripts/moves/<id>.gd`. It extends `Action`, which runs the
   three phases (startup, active, recovery) from the data and calls these hooks:

   | Hook | When |
   |---|---|
   | `on_start()` / `in_startup(delta)` | the move begins / every frame of the wind-up |
   | `on_active()` / `in_active(delta)` | hit volumes exist |
   | `on_recovery()` / `in_recovery(delta)` | the punishable part |
   | `on_end(interrupted)` | always, at the end; clean up here |
   | `pose()` | procedural pose on top of the animation: `tilt`, `side`, `stretch`, `anim`… |
   | `armor()` | extra poise while it runs |

   Useful helpers: `hit({...})` creates a hit volume from the data, `aim()` gives the firing
   direction, `to_world()`, `mouth()` and `l.point("<locator>")` give body points,
   `play_sound()` plays a sound, and `l.main.vfx` / `l.main.fx` draw effects. If the move is a
   plain dash, punch or body slam, point `"script"` at the shared `dash.gd`, `punch.gd` or
   `bodyslam.gd` and only add data.

5. **Give it to a Pokémon.** Every Pokémon that learns it in the games (its learnset in
   `species.gd`) can pick it in the Moves screen as soon as its script exists. To make it one
   of a Pokémon's default four, put it in `"moves": [...]` in `game/scripts/data/roster.gd`.

6. **Test it:**

   ```bash
   godot --path game -- --test=moves --p1=<pokemon> --sequence   # capture strip of each move
   godot --headless --path game -- --test=mechanics               # must stay all OK
   godot --headless --path game -- --test=loadouts                # every Pokémon with every move it can pick
   godot --headless --path game -- --test=animations --p1=<pokemon>
   ```

   Then play it against the AI and in training mode (`training.bat`, **F3** shows the hit
   volumes).

7. **Update the translations** (below) and open a pull request with a capture strip or a short
   clip of the move.

## Recipe: add a Pokémon

1. **Model and animations:** with a Cobblemon clone,
   `python tools/import_cobblemon.py <clone>/common/src/main/resources --only=<species>`
   copies its files into `sources/cobblemon/<species>/` and converts them into
   `game/pokemon/<species>/`.
2. **Species data:** `python tools/import_species.py --cobblemon <clone> <species>` adds its real
   stats, abilities and learnset to `game/scripts/data/species.gd` (generated; never edit it by
   hand).
3. **Battle data:** add its entry to `Roster.POKEMON` in `game/scripts/data/roster.gd` (size,
   mobility, dodge, passive, moves) and its style to `PROFILE` in `game/scripts/ai.gd`.
4. **Test:** `--test=animations --p1=<species>` must report no failures, then
   `--aivsai --test=aivsai --p1=<species>` and play it.

## Translations

All text lives in `game/i18n/translations.csv`, one column per language (`keys,en,es`). The key
is the English text.

```bash
python tools/update_translations.py           # adds new keys, lists missing translations
python tools/update_translations.py --check   # only reports; fails if something is missing
```

New keys get empty cells, and an empty cell falls back to English in game. To add a language,
add a column with its code (for example `fr`) and register
`res://i18n/translations.fr.translation` in `game/project.godot` under `[internationalization]`.
Use the official Pokémon names of that language.

## Code style

- GDScript with tabs, typed variables where it helps, `snake_case` names in English.
- `##` doc comments say what a function is for and why, not how. Keep them short.
- Keep logic and visuals apart: effects never deal damage, hit volumes never draw.
- Python tools: standard library plus Pillow where images are involved.

## Pull requests

- One move, ability or fix per pull request when possible.
- Run the mechanics test and `python tools/update_translations.py --check` before opening it.
- Describe how the move plays and what counters it, with captures.

By contributing you agree that your code is released under the project's [MIT license](LICENSE).
