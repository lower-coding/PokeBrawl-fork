# PokeBrawl

Real-time 3D Pokémon battles in the style of the anime, built in Godot with Cobblemon's models.
Ten Pokémon, against the AI or 1 vs 1 online with a friend.

![A battle between Charizard and Lucario](docs/images/battle.png)

PokeBrawl is a non-profit fan project. It is an early prototype: the battle system, the AI, online
play and ten Pokémon are in; the plan to grow the roster with real stats, abilities and learnsets
is in [docs/roster-plan.md](docs/roster-plan.md). The game is in English and Spanish and follows
your system language.

## Play

You need [Godot 4.7.2](https://godotengine.org/download) (the standard build, not .NET).

```bash
git clone https://github.com/xjoje6/PokeBrawl.git
godot --path PokeBrawl/game
```

On Windows, `play.bat` does the same if Godot is on your `PATH` or in the `GODOT` environment
variable. `training.bat` opens the menu with training mode already picked.

Arguments skip the menu and go straight into a battle:

```bash
godot --path game -- --p1=charizard --p2=pikachu --diff=hard --stage=glade
```

| Argument | Values |
|---|---|
| `--p1`, `--p2` | `pikachu`, `snorlax`, `charizard`, `blastoise`, `venusaur`, `lucario`, `gengar`, `garchomp`, `greninja`, `scizor` |
| `--diff` | `easy`, `normal`, `hard` |
| `--stage` | `stadium`, `glade` |
| `--training` | still or active rival: **R** resets, **T** stops or frees the rival, **F3** shows the hitboxes |
| `--lang` | `en`, `es` (forces a language) |

## Controls

| Action | Xbox | PlayStation | Keyboard and mouse |
|---|---|---|---|
| Move | Left stick | Left stick | WASD |
| Camera | Right stick | Right stick | Mouse |
| Jump | A | ✕ | Space |
| Dodge | B | ○ | Shift |
| Lock on / release | RS (click the right stick) | R3 | Tab or middle click |
| Move 1 | LB | L1 | Q |
| Move 2 | RB | R1 | E |
| Move 3 | LT | L2 | Right click |
| Move 4 | RT | R2 | F |
| Pause | Menu | Options | Esc |
| Fly (Charizard) | A in the air to take off; hold A to climb | ✕ the same | Space the same |
| Descend while flying | LS (click the left stick) | L3 | Ctrl |
| Debug view | Select | Share | F3 |

## How battles work

- **Four moves, no basic attack.** Each move costs energy and has its own cooldown. Strong moves
  recharge slowly, so it pays to carry something weak and fast too; or you can play around your
  big moves and wait for them.
- **Every move has a readable startup.** What the opponent sees coming is what they can answer:
  dodge it, jump it, step out of it or punish the recovery.
- **Dodge:** each Pokémon has a number of dodge charges. Outside its invulnerability window it
  does not protect you, and dodging back to back makes the recovery longer.
- **Poise:** every hit is light, medium or heavy. While a Pokémon winds up or performs a move,
  only a hit that reaches its poise interrupts it (the move's poise plus 1 for heavy Pokémon). The
  hit still deals its damage.
- **No infinite combos:** stun gets shorter with each hit of the same combo, and the fifth hit
  knocks the target down; it gets up with a moment of invulnerability.
- **Type matchups, softened:** super effective ×1.25, not very effective ×0.8, "immune" ×0.6.
- **Everything works in the air.** Moves that need the ground (Earthquake, Dig, Stone Edge, Rest)
  dive down and happen on landing.
- **Streams are aimed by hand** (Hydro Pump, Flamethrower): you turn the stream with the stick and
  the rival's height is aimed for you. Everything else aims itself.
- **Lock-on** turns your Pokémon and the camera toward the rival, but it does not guarantee hits.
  Backing away from a locked-on rival is 15% slower.

## The roster

| Pokémon | Mobility | Passive | Moves |
|---|---|---|---|
| **Pikachu** | Very fast and agile, high jump, 3 long dodges. Frail. | **Static:** whoever hits it up close is charged for 4 s; its next Electric move slows them and deals 25% more. | Thunder Shock · Quick Attack · Iron Tail · Electro Ball |
| **Snorlax** | Slow, turns slowly, low jump, 2 short dodges. Lots of HP, barely moved by hits. | **Thick Fat:** takes 30% less from Fire and Ice. | Body Slam · Ice Punch · Earthquake · Rest |
| **Charizard** | Medium speed, high jump and real **flight** while its stamina lasts. | **Blaze:** below a third of its HP, its Fire moves deal 25% more. | Flamethrower · Air Slash · Dragon Claw · Flare Blitz |
| **Blastoise** | Heavy, medium-low speed, 2 short dodges. | **Rain Dish:** each Water move leaves it wet for 4 s, slowly healing. | Aqua Jet · Hydro Pump · Rapid Spin · Ice Beam |
| **Venusaur** | Slow, low jump, 2 dodges. | **Chlorophyll:** after a Grass move it runs 30% faster for 4 s. | Vine Whip · Razor Leaf · Sludge Bomb · Solar Beam |
| **Lucario** | Fast and precise, 3 short dodges, high jump. | **Steadfast:** when interrupted or knocked down, it runs 20% faster for 3 s. | Aura Sphere · Meteor Mash · Extreme Speed · Detect |
| **Gengar** | Floats and glides; its dodge is vanishing and reappearing. | **Levitate:** Earthquake, puddles and ice cannot reach it. | Shadow Ball · Sludge Bomb · Hex · Substitute |
| **Garchomp** | Fastest on the ground after Pikachu, high jump. | **Rough Skin:** melee attackers take 12% of the damage they deal. | Dig · Dragon Claw · Earthquake · Stone Edge |
| **Greninja** | Very agile: double jump and 3 long dodges. | **Protean:** takes the type of its last move. | Water Shuriken · Night Slash · Double Team · Hydro Pump |
| **Scizor** | Short, very fast dodges (3). | **Technician:** its light hits deal 25% more. | Bullet Punch · X-Scissor · Swords Dance · Wing Attack |

The selection screen shows what each move does and how to counter it. References from Pokkén,
Smash and the anime for every move are in [docs/move-references.md](docs/move-references.md).

## Online (1 vs 1)

- Main menu → **Online**: one player picks **Host game**, the other **Join** and types the host's
  IP.
- The waiting screen shows the host's IPs: local, VPN if any, and public if the router opened the
  port by itself (UPnP). Otherwise, open port **7777 UDP** on the router or use a LAN VPN such as
  Radmin VPN or ZeroTier.
- Both pick and get ready; then VS and battle. The ping is shown at the top.
- After a KO, A asks for a rematch (the host decides) and B goes back to selection without
  disconnecting. There is no pause or KO slow motion online.

How it keeps latency low: ENet over UDP with small custom packets; every frame carries your input
and your own Pokémon's state unreliably, while events (hits, start, rematch) go on a reliable
channel. Each player is in charge of their own Pokémon, so your input is applied with no delay;
the rival's copy runs their presses fast-forwarded by the ping and is corrected with their real
state. Hits are confirmed by whoever takes them.

## Tests

```bash
godot --headless --path game -- --test=mechanics                     # 22 acceptance cases
godot --headless --path game -- --aivsai --test=aivsai --p1=pikachu --p2=snorlax   # 3 AI vs AI battles
godot --headless --path game -- --test=animations [--p1=species]      # T-poses, sinking, stuck animations
godot --path game -- --test=moves --p1=charizard [--sequence]         # every move, with captures
godot --path game -- --test=menu                                      # the menu with simulated input
godot --path game -- --aivsai --test=combat                           # an on-screen battle, captures and FPS
```

Online tests run two copies: `--host --bot --test=net` and `--join=127.0.0.1 --bot --test=net`
(add `--lag=ms --jitter=ms --loss=%` to simulate a bad connection), or `--test=menu_net
--role=host|guest --bot` to go through the menus. Captures go to `captures/`.

## Project layout

```
game/                 the Godot project
  scripts/            game code (fighter, combat, AI, menus, HUD, online, effects)
    data/             roster.gd (Pokémon), moves.gd (move data), species.gd (generated)
    moves/            one script per move, named by its Showdown id
  fx/                 Cobblemon particle pieces and move sequences, converted
  pokemon/            converted Cobblemon models, textures and cries
  i18n/               translations.csv (one column per language)
tools/                Python tools: converters, importers, sprite and font generators
sources/              original Cobblemon files the converted models come from
docs/                 design documents
```

## Contributing

Contributions are welcome, especially new moves and abilities: see
[CONTRIBUTING.md](CONTRIBUTING.md) for the recipes and the rules.

## Credits and licenses

- **Code:** MIT, see [LICENSE](LICENSE).
- **Pokémon models, animations and textures:** [Cobblemon](https://gitlab.com/cable-mc/cobblemon),
  **CC BY-NC 3.0** ([game/pokemon/LICENSE-models.txt](game/pokemon/LICENSE-models.txt)), adapted
  and used with the Cobblemon team's approval. Non-commercial use with attribution.
- **Particle textures, effect pieces, move sounds, cries and the battle GUI pieces**
  (`game/gui/cobblemon/`): from the same repository, under its general license (MPL 2.0).
- **Species data:** Cobblemon (MPL 2.0). Move and ability behavior references:
  [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) (MIT).
- **Pixel font** (`game/gui/font/`): our own, made with `tools/pixel_font.py`. It is not the
  Minecraft font.

More detail in [CREDITS.md](CREDITS.md).

Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc., GAME FREAK and
The Pokémon Company. This is a non-profit fan project, not affiliated with or endorsed by them.
