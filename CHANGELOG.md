# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [demo-goodra] - 2026-10-31

### Added
- Goodra, the 11th Pokémon: a heavy special wall that controls the mid range. Gooey (default) slows
  whoever hits it with a contact move, at most once a second.
- Three moves, for everyone who learns them: Water Pulse (a ring that widens as it flies and can
  confuse), Mud Shot (a straight shot that always lowers Speed) and Acid Spray (a lobbed glob that
  always lowers Sp. Def two stages).
- Three abilities: Sap Sipper, Hydration and Overcoat. Overcoat is not Goodra's in the games; it is a
  deliberate exception through the new roster field `extra_abilities`.
- Roster fields `points` (a model's own bones for the locators shared moves ask for) and
  `model_height` (the size a model is drawn at, when that is not its body's height).

### Changed
- Hydro Pump's and Ice Beam's text no longer mentions cannons: more than Blastoise uses them.
- The version is now `demo-goodra`: it cannot play online against `demo-3v3`.

## [demo-3v3] - 2026-10-31

### Added
- 3 vs 3 with switching (prototype, offline): a switch takes about a second, can be hit and cut,
  costs a scarce charge and refreshes nothing; the energy belongs to the team and the bench waits
  as it was. After a KO you pick the next one. The AI switches too. Shots left flying by a
  Pokémon that switched out spare its teammates. See the README. New tests: `--test=team`,
  `--test=menu_rules` and `--aivsai --test=team_battles`.
- Battle and Training ask for the format, 1 vs 1 or 3 vs 3, before anyone picks. In a 3 vs 3 each
  side picks three on the wall, with each one's model, types, ability and moves on its card.
- Online 3 vs 3: the host picks the format and the rules; each player's team stays hidden until both
  are ready; each one decides their own switches and the other's copy follows. The state packets
  changed, so the version is now `demo-3v3`: it cannot play against the released demo.
- Rules for each 3 vs 3: the selection's new Rules tab (or `--rules`) sets its times, switches and
  KO rules. Healing on the bench is there too, off by default. They are never saved.
- The 3 vs 3's HUD: both sides' bench and switches under their frames, chips for your teammates,
  a bar over a Pokémon going back to its ball and a card for picking the next one after a KO.

### Fixed
- Online, a packet still on its way from the last battle could knock out the rival's new copy
  right after a rematch, leaving it fainted on your screen for the whole battle. Each battle is
  numbered now and what comes from another one is dropped.

## [Demo] - 2026-10-29

The demo: the first version to play.

### Added
- Moves screen: Restore defaults (top right, X / R). From the list of Pokémon it restores
  all of them, from one Pokémon only that one, after asking.
- The mouse works in the Moves screen (Pokémon, slots, the ability and the options) and in
  yes/no questions, which before always took No on a click.
- Lock-on, souls style: locking on picks what the camera looks at, the rival or one of its
  decoys (Substitute's doll, Double Team's clones). While locked, a flick of the right stick
  or a sweep of the mouse switches to the next target on that side. When the decoy you are
  locked on disappears, the camera is free again.
- Free aim: with the camera free, moves go where the camera looks. Homing shots come out
  that way and still follow their target.
- The mouse wheel scrolls the menus like the arrows.
- Music: the menus, the selection and the battles each rotate their own tracks (Pokémon
  arrangements by The Noble Demon, credited). The audio is not in the repository; the
  release carries it inside the game's package. Without it, the game is silent.
- Confusion: a Pokémon's movement is turned around for a while, stars circling its head.
  Outrage leaves its user confused for 3.5 s (its recovery is shorter now).
- The mouse works in the menus (main, online, profile, selection, the IP keypad): pointing
  moves the cursor, left click accepts, right click goes back. Keyboard, mouse and pad work
  at the same time.
- An on-screen keyboard for the profile's name (pad and mouse); the real keyboard types
  straight into it.
- Super effective (x4) and barely effective (x1/4, and immunities) have their own texts
  and damage colors.
- Body Slam's landing raises an off-white cloud of dust, an upturned cone, that also hits
  whoever it catches outside the slam.
- After a battle, with nobody choosing, the game goes back to the selection by itself after
  15 s (online the host takes both, still connected).
- Trainers on the field: your trainer and the rival's stand in their trainer areas (on the
  floating stadium, on small platforms of their own off the deck, out of reach), with the
  games' sprites. They react to the battle (lean in on a move, hop on a hit, flinch on a
  heavy one, cheer or slump at the end), only for show.
- The battle opens with each trainer throwing their Poké Ball and their Pokémon coming out.
- League Stadium, a coliseum of grey bricks with moss and ivy and a field of pale stone
  slabs, on a cool, dim day with drifting clouds. The field closes in by phases (at 30, 55,
  80 and 105 s, each ring marked a few seconds before, a low aurora at its edge); outside it
  a Pokémon loses 5% of its max HP a second.
- During the opening, each trainer's card instead of the battle's HUD, and a short START
  when you can move.
- Profile in the main menu (top right): pick your trainer among nine and type your name.
  Online, your rival sees both.
- New moves, each with its own look taken from the DS games and the anime: Thunderbolt,
  Fire Punch, Thunder Punch, Bite, Crunch, Fire Blast (the flying kanji of fire), Close Combat
  (fists popping on the target), Shadow Claw, Rock Slide (marked boulders falling), Surf (a
  wave that rises, crashes and rolls on low), Psychic, Dark Pulse (a dome of
  darkness swelling out all round), Energy Ball, Dragon Pulse (a ball of dragon energy
  poured out as a beam), Thunder (a bolt from a storm cloud onto a ring that follows the
  rival), Volt Tackle (a charge inside a ball of electricity), Focus Blast, Flash Cannon and
  Outrage (three lunges, then dizzy).
- Psychic lifts the target with a glowing outline round its body and slams it into the ground.
- Clashes: two projectiles that meet compare power by type. The clearly stronger one goes on,
  weaker; even ones burst. Streams put out weaker shots and cut each other where they meet
  (Hydro Pump cuts Flamethrower, with steam); the winner goes on weaker while they touch.
- Deflecting projectiles: some physical moves stop a projectile if their hit comes out right
  as it arrives (the first 0.15 s) and it comes from the front. Iron Tail, Night Slash,
  X-Scissor and Mega Kick send it back faster and stronger; Dragon Claw, Brick Break, Rapid
  Spin, Meteor Mash and Bullet Punch break it. Lobbed or bursting shots only break. The AI
  tries it now and then, and misses its timing sometimes.
- New menus in Smash Ultimate's dark look: a wall of tiles for the main and online menus,
  the selection with a row of portraits over two big player cards (each Pokémon in 3D,
  its ability and moves with their type symbol), the battle's options once both are picked
  (stage with its picture, difficulty, edit moves, fight) and a new end-of-battle screen.
  The stage is only built when the battle starts.
- Moves screen: each Pokémon's base stats, and each move's details (power, tracking,
  cooldown, energy, wind-up, recovery, knockback, poise...) as bars with the exact figure.
  It can also be opened from the selection for last-minute changes.
- Options: every battle control can be changed (keyboard and gamepad), music and effects
  volume, full screen, vertical sync, frame limit, camera shake, rumble and language.
- Music for the menus, the selection and each stage (game/music/, quiet on purpose).
- Leaving an online room asks first.
- Ash's Pikachu replaces Pikachu: Cobblemon's model with the original cap, holding a Light
  Ball (double Attack and Sp. Atk, as in the games).
- Night stadium: the big screens show both Pokémon's portrait, name and HP; the LED strip
  shows who is winning and, after the final blow, WINNER all round in the winner's color.
- Toxic reworked: a stain runs under the ground and erupts in bubbles (jump to avoid it).
- Status moves say why they fail (no effect, already has a status, temporary immunity),
  and the immunity after a status shows on the HUD.
- Major status conditions as in the games, with a fixed time instead of the whole battle (in
  real time a lasting poison rewards running away): burn (chip damage, physical moves at half),
  paralysis (half speed, sometimes fully paralyzed), poison (long and slow), Toxic (short and
  fast, growing), sleep and freeze (a Fire hit thaws). Same immunities as in the games; after
  one wears off, none for 5 s. The HUD tab shows the time left.
- Secondary effects of the existing moves: Thunder Shock, Body Slam, Flamethrower, Flare Blitz,
  Ice Punch, Ice Beam, Sludge Bomb, Shadow Ball, Iron Tail, Meteor Mash, Rapid Spin, Air Slash.
- Eight status moves for those who learn them, each with its own look: Toxic (a dripping glob,
  hard to escape from Poison types), Will-O-Wisp (three blue flames in a fan), Thunder Wave (a
  fast ring of sparks), Hypnosis (slow widening rings), Yawn (a slow bubble: drowsy, then
  asleep), Sleep Powder and Poison Powder (a short cloud in front) and Nuzzle (always paralyzes).
- Twelve common moves with their own look: Take Down, Double-Edge and Giga Impact (charges, with
  recoil or recharge), Headbutt (flinch), Strength, Mega Kick, Brick Break and Facade (each with its
  own body motion), Mega Punch, Rock Smash (lowers Defense) and Focus Punch (a hit ruins it), and
  Hyper Beam. Shared pieces: recoil, flinch, lowering the target's stats, recharge.
- Weather, as in the games, for 5 turns (15 s): Sunny Day, Rain Dance, Sandstorm and Snowscape
  for those who learn them. Sun and rain change Fire and Water damage, sand wears down all but
  Rock, Ground and Steel types, Rock types resist special moves in sand and Ice types physical
  ones in snow; Solar Beam barely charges in the sun. Tint, rain, sand or snow on screen and the
  turns left on the HUD.
- Weather abilities: Rain Dish, Chlorophyll, Solar Power and Sand Veil. Blastoise and Venusaur
  start with Torrent and Overgrow (their regular abilities); the hidden ones are in the Moves menu.
- Real-time 3D battles with ten Pokémon: Pikachu, Snorlax, Charizard, Blastoise, Venusaur,
  Lucario, Gengar, Garchomp, Greninja and Scizor, each with four moves and a passive ability.
- Battle rules: energy and per-move cooldowns, dodges with invulnerability windows, poise,
  softened type matchups, combo limit with knockdown, flight for Charizard, every move usable in
  the air.
- AI opponent with three difficulties that reads the rival with a delay, dodges, jumps
  Earthquake waves and punishes recoveries.
- 1 vs 1 online play over UDP (ENet) with UPnP, rematches and pick changes without
  disconnecting.
- Three stages drawn by script: a night stadium with a crowd that reacts to the battle
  (the default), a day gym stadium and a forest glade.
- Real level 50 stats drive health, speed and dodges.
- Menus and battle UI built from Cobblemon's GUI pieces, with live portraits.
- Cobblemon models, animations, particle effects and sounds, converted by the tools in `tools/`.
- English and Spanish, following the system language (`--lang` forces one).
- Automated tests: mechanics, AI vs AI, animations, menus and online.

### Changed
- Hyper Beam, Dragon Pulse and Solar Beam are held streams like Flamethrower and Hydro Pump:
  aimed while firing, several hits, longer while the button is held, draining energy. Solar
  Beam keeps its long charge and its line on the ground, now golden and lumpy too.
- More moves deflect projectiles. Strong, committed swings send them back: Iron Tail, Night
  Slash, X-Scissor, Mega Kick, Dragon Claw, Meteor Mash, Close Combat, Mega Punch, Focus
  Punch, Strength and Crunch. Weak, quick or chainable ones only break them, and so do the
  charges, which plow through: Shadow Claw, Bullet Punch, Rapid Spin, Brick Break, the
  elemental punches, Bite, Headbutt, Rock Smash, Facade, Wing Attack, Vine Whip, Quick
  Attack, Aqua Jet, Extreme Speed, Body Slam, Volt Tackle, Flare Blitz, Giga Impact,
  Double-Edge, Take Down and Outrage.
- Profile: moving over the trainers only points at them; A (or a click) picks one.
- Hyper Beam: a big lumpy beam with a flare at the mouth, shock rings and an explosion at the
  end, not a plain tube; afterwards it is very slow for 2.5 s instead of rooted.
- Fire, Thunder and Ice Punch lunge much further and break the sound barrier: shock rings
  in their element's color.
- League Stadium: the closing field is a wall (it pushes you in, no damage), drawn as thin
  rays of light; its clock stops after the final blow and in the menus.
- Deflecting projectiles is fairer: the end of the wind-up already deflects, the whole first
  0.3 s of the hit count and it reaches a little past the hit.
- The stage stops running behind the menus.
- Immunities let only a quarter of the damage through (they let 60% through) and say
  "Barely effective".
- Energy Ball looks like energy too, see-through like Electro Ball.
- The Day Stadium and the Forest Glade are gone; the night and floating stadiums stay.
- The camera no longer goes into the night stadium's stands; the floating deck no longer
  looks speckled under the floodlights.
- Electro Ball and Solar Beam's sun look like energy, with stepped transparency.
- Softer menu sounds.
- Playtest rework: Ice Beam and Solar Beam travel instead of hitting the whole line at once
  (Solar Beam locks its line, which turns white, before firing); Hex's mark follows the target
  until it locks; Sludge Bomb flies faster with a bigger blast; Iron Tail leaps and slams; Body
  Slam is faster; Flamethrower is narrower and longer; Shadow Ball is bigger; Stone Edge is
  faster with clusters of spikes (same damage).
- Streams reach one use of the games with about half their ticks (Flamethrower 8, Hydro Pump 6).
- Double Team's copies run around on their own and break the rival's lock; Substitute's doll
  takes the rival's lock and Gengar turns invisible until it attacks.
- Earthquake lifts slabs and opens cracks, Air Slash has a double crescent and a wind trail,
  Swords Dance shows a gold bar with the time left.
- Damage numbers and battle texts use the pixel font with the one-pixel shadow, on the pixel
  grid, popping in and fading in steps.
- Abilities work as in the games: Blaze 1.5x at a third of HP, Thick Fat half, Rough Skin 1/8 of
  the attacker's HP, Technician 1.5x for 60 power or less, Static 30% paralysis on contact,
  Steadfast +1 Speed when it flinches. Stat stages (+1 = x1.5) last the whole battle.
- New selectable abilities in the Moves menu: Lightning Rod, Immunity, Gluttony (a Sitrus Berry
  until there are items), Torrent, Overgrow, Swarm, Inner Focus, Justified, Cursed Body and
  Light Metal.
- Projectiles follow their target, turning as fast as the move's accuracy in the games allows:
  stepping aside at mid range no longer shakes them off. A dodge breaks the lock for good (like a
  step in Gundam Versus) and they never turn back once past the target.
- Floating Stadium: the kill plane is far below the platform, so flyers can fly back; a fighter
  knocked off regains control in the air, and the AI flies back from under the platform.
- Gengar can fly for a while with Levitate (lower and shorter than Charizard).
- Damage comes from the games' formula at level 50: power, Attack or Sp. Atk against Defense or
  Sp. Def, STAB and type effectiveness, scaled so battles last as before (Damage). A full stream
  or both swipes of a two-hit move deal one use's worth; Electro Ball's power depends on speed.
- Cooldowns come from PP and power (Moves.cooldown); status moves keep theirs.
- Flare Blitz's recoil is a third of the damage dealt, as in the games.
- Hits push the target back while it is stunned, by power: light 0.3 m, medium 1 m, heavy 2.5 m;
  push moves (Body Slam, Flare Blitz, Hydro Pump, Solar Beam) 4 to 5 m. Light Pokémon fly
  further than heavy ones. One rule for every move (`Knockback`).
- Stages can have a void: falling below it is a KO (ring-out).
- A move never carries its user off the edge (Extreme Speed, Quick Attack... stop at it): you
  only fall if you are knocked off, dodge out or walk out.
- Floating Stadium: a platform over a deep pit, lit only by its floodlights, with a giant
  screen that shows the battle and fireworks when the crowd gets loud. No walls: off the edge is
  a KO. The AI does not dash, dodge or land off the edge.
- Online, the host picks the stage in the selection (mov2) and the rival gets it.
- Moves menu: pick each Pokémon's four moves (among the ones it learns in the games that are
  done: 7 to 16 each today) and its ability. Saved between sessions and sent online with the
  choice, so the rival plays against your set.
- Hydro Pump looks like water, not a tube: lumpy and uneven, wider and frothier toward the end,
  with foam blobs, drops flying off its sides and a broken edge.
- Projectiles lead a moving rival (the AI leads less by difficulty); Shadow Ball and Air Slash are faster.
- IP entry with an on-screen keypad for gamepads; the keyboard types it directly.
- The pause menu opens online too (the battle goes on) and lets you leave.
- A clear end-of-battle screen says who won and what A and B do.
- A session log (no IP addresses) in the user folder; F9 opens it to report bugs.
- Credits: the full list in CREDITS.md and the release's CREDITS.txt (Cobblemon, The Noble
  Demon, the trainer sprites via Pokémon Showdown, Godot Engine and its components, whose
  notices ship as GODOT-LICENSES.txt), and a line more in the main menu.

### Fixed
- Online, a rematch asked by the guest started at once for both, with the host's Pokémon
  standing still; now everyone votes and it starts when all have asked ("waiting for the
  rival (1/2)"). The votes count every player, ready for more than two.
- Cries and every other sound now follow the effects volume, and the music the music volume
  (two audio buses); the cries in the menus are quieter.
- A broken projectile still burst (a broken Sludge Bomb hurt the one who broke it).
- Close Combat showed its fists only on a hit; now on a miss too.
- Flash Cannon showed fists on impact.
- Charizard's tail flame was missing: it is back, animated as in Cobblemon (four frames,
  glowing).
- Electro Ball only did 40% of its damage on a direct hit.
- A move cut short by a hit after it had gone off got no cooldown; now it does (cut while
  winding up it still does not).
- A move that cancels into other moves (Night Slash, Quick Attack, Bullet Punch...) could chain
  into itself without cooldown; cancelled moves now go on cooldown too.
- Online battles froze after picking other Pokémon (packets of the new battle were dropped as old).
- Body Slam almost never hit.
- Gengar's ability list showed Cursed Body twice.
