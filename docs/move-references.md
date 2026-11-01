# Move references

For each move: how it works and how it looks in the Pokémon fighting games (Pokkén Tournament
DX and Super Smash Bros. Ultimate) and in the anime or the mainline games. Then, what we have
now and what could be taken from the reference.

**Where each note comes from:**
- **[Pokkén]:** Serebii's move lists (button, hit type, notes), e.g.
  [Pikachu](https://www.serebii.net/pokkendx/characters/pikachu.shtml) or
  [Lucario](https://www.serebii.net/pokkendx/characters/lucario.shtml). Change the name in the
  address to get the others.
- **[Smash]:** SmashWiki, e.g.
  [Aura Sphere](https://www.ssbwiki.com/Lucario_(SSBU)/Neutral_special),
  [Lucario](https://www.ssbwiki.com/Lucario_(SSBU)),
  [Greninja](https://www.ssbwiki.com/Greninja_(SSBU)) or
  [Ivysaur](https://www.ssbwiki.com/Ivysaur_(SSBU)).
- **[Anime] and [Games]:** from memory, with no source at hand. Shape and color are the most
  reliable things to remember, but watch a video before redoing something based on them.

**Method for new moves:**
1. Check whether it is in Pokkén or Smash (button, whether it charges, whether it is a counter,
   what punishes it).
2. Check how it looks in the anime.
3. Look for its particle pieces in Cobblemon (`game/fx/sequences/` and `game/fx/particles/`).
4. Whatever is missing, draw it as our own pixel sprites (`tools/move_sprites.py`). Stepped
   transparency, no gradients.

---

## Pikachu

**Thunder Shock** · *Now:* a fast straight projectile from the cheek, with the bolt behind it.
- [Games] [Anime]: a short zigzag discharge from the cheek to the rival.
- [Smash]: Pikachu does not have it. Its neutral special is Thunder Jolt, an electric ball that
  bounces along the ground.
- [Pokkén]: its A is Thunderbolt, with a charged version.
- *Proposal:* use Cobblemon's `thundershock_*` pieces, already converted, for the bolt instead
  of our own zigzag.

**Quick Attack** · *Now:* a straight dash, no invulnerability.
- [Smash]: an instant dash in one direction and, if the stick is tilted, a second leg in another;
  leaves white streaks.
- [Anime]: a zigzag run with a white trail of speed lines.
- *Proposal:* allow a second leg in another direction (the zigzag turn) and use Cobblemon's
  `quickattack_dashlines` texture.

**Iron Tail** · *Now:* spins and strikes with the tail; launches; in the air, dives.
- [Pokkén]: down + A, "very high damage", an overhead strike.
- [Anime]: the tail shines metallic white; a flip and a tail strike.
- *Proposal:* a white metallic shine on the tail during the startup (so it can be seen coming).

**Electro Ball** · *Now:* gathered on the tail tip, then flung with a tail flip in an arc; bursts
in an area and paralyzes. Not chargeable.
- [Pokkén]: back + A, "good against airborne rivals".
- [Anime]: a yellow ball with a white core on the tail tip; Pikachu jumps, spins and throws it.
- [Games]: deals more damage the faster the user is compared to the target.
- *Proposal:* hit harder the faster Pikachu is than the rival (its identity in the games, and it
  rewards fast Pokémon).

## Snorlax

**Body Slam** · *Now:* jumps and lands with all its weight; only heavy hits interrupt it.
- [Anime]: a jump and a belly flop, the ground shakes.
- *Proposal:* fine as it is. Maybe Cobblemon's dust and cracks (`bodyslam_*`, `bulldoze_*`).

**Ice Punch** · *Now:* a wide punch that chills the rival (slower).
- [Anime] [Games]: the fist gets covered in ice crystals and bursts into shards.
- *Proposal:* fine; it already uses Cobblemon's `icepunch_*` pieces (icy fist and shards).

**Earthquake** · *Now:* a stomp and a wave along the ground; it only hits whoever is grounded.
- [Pokkén] (Garchomp): A in the air, drops down and deals high damage.
- [Anime]: the ground shakes and cracks.
- *Proposal:* cracks opening from the stomp and pebbles jumping along the wave.

**Rest** · *Now:* sleeps and heals (Cobblemon's Zs).
- [Anime]: Snorlax sleeps with its "Zzz".
- *Proposal:* fine as it is.

## Charizard

**Flamethrower** · *Now:* a cone stream while held; turns slowly.
- [Pokkén]: its basic A.
- [Smash]: a continuous stream that gets shorter if held for long and recovers on release.
- *Proposal:* make the stream shorten when held for long (like Smash) instead of a fixed time
  limit.

**Air Slash** · *Now:* a horizontal blade of air; also usable in the air.
- [Games]: crescents of air.
- *Proposal:* fine; it already uses Cobblemon's `gust_actor` and `aerialace_*` pieces.

**Dragon Claw** (also Garchomp) · *Now:* two quick advancing swipes; opens combos.
- [Pokkén] (Garchomp): its A; holding A enters a running stance.
- [Anime]: the claws glow with dragon energy (blue and violet, or green).
- *Proposal:* fine. Cobblemon's `dragonclaw_*` pieces are already used.

**Flare Blitz** · *Now:* wraps itself in flames, charges in a line, shrugs off light hits and
takes recoil when it lands.
- [Pokkén]: in the air, dives down or straight; takes recoil.
- [Smash]: a flaming dash that explodes on contact.
- *Proposal:* a fire explosion on contact, and a diving version when used in the air.

## Blastoise

**Aqua Jet** · *Now:* wraps itself in water and shoots off in a line.
- [Anime]: a water rocket around the body.
- *Proposal:* fine.

**Hydro Pump** (also Greninja) · *Now:* a held stream from the cannons; pushes hard.
- [Pokkén]: up + A, a charged version that beats counters.
- [Smash] (Greninja): used to move (two boosts) and pushes while dealing almost no damage.
- *Proposal:* fine on Blastoise. On Greninja, push more and deal less (like Smash).

**Rapid Spin** · *Now:* spins inside its shell; steered with the stick and clears slowness.
- [Pokkén]: forward + A, a counter that **cancels some ranged attacks**.
- *Proposal:* destroy projectiles that hit it while spinning (like Pokkén).

**Ice Beam** · *Now:* a straight beam that chills and leaves a strip of ice on the ground.
- [Anime] [Games]: a light blue beam with crystals forming along its path.
- *Proposal:* fine.

## Venusaur

**Vine Whip** · *Now:* two vines that lash and pull the rival.
- [Smash] (Ivysaur): a long and very fast whip; **the tip hits harder** than the rest.
- *Proposal:* a sweet spot at the tip: more damage and knockback when it lands with the end.

**Razor Leaf** · *Now:* three leaves in a fan; up close all three land.
- [Smash] (Ivysaur): a spinning leaf with a slightly random curve; tapped quickly it goes farther
  and faster.
- [Anime]: a rain of sharp leaves.
- *Proposal:* make the leaves spin and curve a little in flight.

**Sludge Bomb** (also Gengar) · *Now:* a lobbed bomb; leaves a poisoning puddle.
- [Pokkén] (Gengar): there it is a counter that lowers attack (not similar).
- [Games]: purple sludge balls.
- *Proposal:* fine as it is.

**Solar Beam** · *Now:* gathers light for over a second and fires a huge beam; very punishable.
- [Smash] (Ivysaur, Final Smash): a long beam that traps and hits many times.
- [Anime]: the flower shines, gathers light and fires.
- *Proposal:* trap and hit several times (like Smash) instead of a single hit.

## Lucario

**Aura Sphere** · *Now:* charges like in Smash. Uncharged it is slow and homes a lot; charged it
is big, fast, straight and hits hard. It looks like in Ultimate.
- [Smash]: Lucario brings its hands together and the ball grows with energy spinning around it;
  charging has an absorb effect. No smoke on release. Uncharged it is slow and a bit crooked;
  charged, straight and fast. The ball also hits while charging.
- [Pokkén]: A, with a charged version that **stops the rival**.
- *Open proposal:* the ball hits at close range while charging (like Smash).

**Meteor Mash** · *Now:* a strong advancing punch.
- [Games]: the fist shines and falls like a comet, with stars.
- *Proposal:* a comet trail with pixel stars on the fist.

**Extreme Speed** · *Now:* crosses the field almost instantly and ends behind the rival.
- [Pokkén]: up + A, a **counter**.
- [Smash]: propelled by aura jets from its feet; can curve in flight; ends with a gust of wind.
- *Proposal:* blue aura jets on the feet and the gust at the end.

**Detect** · *Now:* a brief window that cancels the hit and stuns; on a miss it is exposed.
- [Smash] (Lucario's Double Team): when hit, it leaves blue afterimages, slows the attacker,
  vanishes and reappears with a flying kick.
- *Proposal:* on success, blue afterimages and an automatic counter (kick) instead of just a
  stun.

## Gengar

**Shadow Ball** · *Now:* a pixel shadow ball that homes slightly on the rival.
- [Pokkén]: A, with a **charged version**; links into "Shadow Sneak" (hides) with R.
- [Games]: a black and purple ball with a ragged edge.
- *Proposal:* it could charge like in Pokkén. Open, since Aura Sphere already charges.

**Hex** · *Now:* marks the ground under the rival and bursts; double damage if the rival has a
status condition.
- *Proposal:* fine (its identity in the games).

**Substitute** · *Now:* an identical decoy that breaks on the first hit; Gengar turns translucent
and fast for a moment.
- [Smash] (Greninja): a counter; when hit, it leaves a log or a dummy and reappears behind
  attacking.
- *Proposal:* fine on Gengar. The Smash one is closer to Greninja's Double Team.

## Garchomp

**Dig** · *Now:* moves underground; on release it bursts out launching; only Earthquake reaches
it.
- [Pokkén]: invulnerable underground; attacks with two different buttons; can be cancelled or
  jumped out of.
- *Proposal:* allow cancelling it or jumping out.

**Stone Edge** · *Now:* cracks in a line and stakes coming out one after another.
- [Pokkén]: a **counter**: Garchomp waits and, if attacked, the rocks come out. Charged it hits
  harder.
- [Games]: rock pillars around the rival.
- *Proposal:* keep it as a line attack. If Garchomp needs a counter, this would be the
  candidate.

## Greninja

**Water Shuriken** · *Now:* three shuriken in a row, each one aimed.
- [Smash]: **chargeable**: bigger and multi-hit, but slower and with less range.
- *Proposal:* fine with three. Optional: a chargeable third one.

**Night Slash** · *Now:* vanishes and appears at the rival's side slashing.
- [Smash] (Shadow Sneak): Greninja moves its shadow along the ground and teleports to it; a swirl
  as it vanishes and **its eyes glow red just before** (a warning).
- *Proposal:* a shadow on the ground where it will appear and the red flash of the eyes.

**Double Team** · *Now:* two copies at the sides that break on the first hit.
- [Smash] (Greninja's Substitute): a swirl with leaves as it vanishes.
- *Proposal:* a swirl with pixel leaves when creating the copies.

## Scizor

**Bullet Punch** · *Now:* an almost instant advancing punch; chains.
- [Pokkén]: down + A; pressing X during the punch gives **X-Scissor**; with a grab, Bug Bite
  (heals).
- *Proposal:* chain Bullet Punch → X-Scissor with a timed press.

**X-Scissor** · *Now:* two slashes in an X; the second one is heavy.
- [Pokkén]: Bullet Punch's finisher with a timed press.
- *Proposal:* the one above.

**Swords Dance** · *Now:* dances (vulnerable) and its next two physical hits deal 50% more.
- [Pokkén]: a **counter**; stores up to two charges that boost the next attacks.
- *Proposal:* counterattack if hit during the dance (like Pokkén) instead of being vulnerable.

**Wing Attack** · *Now:* rises on its wings and charges in a short line.
- [Pokkén] (Aerial Ace, in the air): low damage but worth it.
- *Proposal:* fine.

---

## Goodra
Pokkén, Smash and the anime are **not researched yet** for these three: their designs come from the
games' rules and Cobblemon's pieces. Do that before tuning their look.

**Water Pulse** · *Now:* suds at its feet, then a ring of water that flies straight and widens as
it goes, with what it touches. 20% to confuse.
- [Games] The 20% confusion. Cobblemon: `waterpulse_actorsuds`, `_actorring`, `_target`, `_targetsplash`.

**Mud Shot** · *Now:* a quick lean back and a fast straight glob (our own `mudshot_ball`). Always -1
Speed, a small stain where it lands.
- [Games] The Speed drop. Cobblemon has no Mud Shot: pieces from Mud Bomb, whose `_actor` flies by
  itself on its own timing, so it is not used.

**Acid Spray** · *Now:* a short rear back and a lobbed glob (our own `acidspray_ball`) that does not
follow. Always -2 Sp. Def, a sizzling burst, no puddle.
- [Games] The Sp. Def drop. Cobblemon: `acidspray_actorfling`, `_actortrail`, `_target`, `_targetsizzle`,
  `_targetsmoke`; its `_actor` flies by itself too.

---

## Urshifu
Pokkén, Smash and the anime are **not researched yet** for these nine: their designs come from the
games' rules and Cobblemon's pieces, and only Protect and Sucker Punch have pieces of their own.
Do that before tuning their look.

**Wicked Blow** · *Now:* the fist darkens, then a long lunge with the punches' sonic boom. Always crit.
- [Games] The crit. Cobblemon: `shadowclaw_hand`, and `suckerpunch_` and `crunch_` pieces on the hit.

**Surging Strikes** · *Now:* suds at its feet, three blows with hands in turn, each with a splash.
Always crit, spread over three hits; in the games it is 25 power × 3.
- [Games] The crit, and each blow being a contact hit. Cobblemon: `waterpulse_` and `watergun_` pieces.

**Sucker Punch** · *Now:* a blink-fast dash that only connects against a rival in the startup or
active phase of a damaging move; otherwise "But it failed!" and a long recovery.
- [Games] Priority +1 and the failure. Cobblemon: `suckerpunch_target1`, `_targethit`, `_targetspark`.

**Lash Out** · *Now:* Facade's angry charge. Double for 3 s after any stat drop, its own or the
rival's, where in the games it is only that turn. Short recovery on a hit, a very long one on a miss.
- [Games] The doubling. Cobblemon: `crunch_` pieces on the hit, `superfang_actorrage` from Facade.

**Protect** · *Now:* a barrier that stays up through everything in its window and does not stun:
Detect is the counter, this is the wall. Contact moves with Unseen Fist go through.
- [Games] Stops status moves too. Cobblemon: `protect_actor1`, `_actorcolor1`, `_block`.

**Counter** · *Now:* a stance: a physical hit from within 5 m deals its damage, and the attacker takes
double and is stunned. Ghost types take a quarter (softened immunity).
- [Games] Double the damage, physical only. Cobblemon: `closecombat_` pieces.

**Bulk Up** · *Now:* a flex open to hits, +1 Attack and +1 Defense at its end, three times a battle
(no limit in the games: nothing resets stages in 1 vs 1). Close Combat's aura and `stars`.

**Liquidation** · *Now:* a slower, stronger dash than Aqua Jet, with suds first. 20% -1 Defense.
- [Games] The Defense drop. Cobblemon: `waterpulse_` and `watergun_` pieces.

**Chilling Water** · *Now:* a quick straight burst of cold water (our own `chillingwater_ball`). Always
-1 Attack. Rapid Strike's only ranged move.
- [Games] The Attack drop. Cobblemon: `watergun_` pieces and `icepunch_targetfrost`.

---

## Decided

- **27 Oct 2026:** Pokkén's counters and chains (Rapid Spin destroying projectiles, Swords Dance
  and Detect countering, Bullet Punch → X-Scissor) **are not added**: the current battle style
  stays, at least for now. The other visual proposals (metallic tail, comet trail, aura jets,
  shadow and red eyes, Cobblemon's bolt for Thunder Shock) remain open.

---

## Mewtwo
Smash comes from SmashWiki's [Mewtwo](https://www.ssbwiki.com/Mewtwo_(SSBU)),
[Disable](https://www.ssbwiki.com/Disable), [Confusion](https://www.ssbwiki.com/Confusion),
[Teleport](https://www.ssbwiki.com/Teleport) and [Shadow Ball](https://www.ssbwiki.com/Shadow_Ball). The
anime is **not researched yet** for these six, and Psyshock's crystal shard is from memory of the games.
Do that before tuning their look. In Pokkén ([Mewtwo](https://www.serebii.net/pokkendx/characters/mewtwo.shtml),
[Shadow Mewtwo](https://www.serebii.net/pokkendx/characters/shadowmewtwo.shtml)) only Confusion and Teleport
are on its lists; Disable, Psyshock, Calm Mind, Agility, Shadow Ball, Psychic and Ice Beam are not.

**Disable** · *Now:* the eyes flash and a tiny pink spark flies a very short way. Every move of the target
not already cooling down waits 3 s; no damage, no stun.
- [Smash] A stun that needs the target grounded and facing Mewtwo; not taken.
- [Games] Blocks only the last move used. Cobblemon: `confusion_actorglint`, `confusion_impactdots`.

**Confusion** · *Now:* a hand sweeps forward and a purple ripple spreads, close and wide. Always confuses,
with a 3 s lock after it wears off.
- [Pokkén] A counter out of Barrier (A during Barrier) that consumes the Synergy Gauge.
- [Smash] A command grab that also reflects projectiles; `"deflects": 2` would add the reflect.
- [Games] 10% chance. Cobblemon: `confusion_` pieces, and our `psy_ring`.

**Teleport** · *Now:* a dark-pink flash, gone for 0.12 s, a fixed 8 m the way it last moved. It cannot be
hit while gone, walls stop it and it can leave a stage's edge.
- [Pokkén] A damageless move aimed with the D-Pad. Mewtwo cancels Hyper Beam or Barrier into it and goes on to
  midair attacks; Shadow Mewtwo's costs it HP.
- [Smash] Aimed with the stick, its distance varies; the fixed distance is on purpose here.

**Psyshock** · *Now:* a palm thrust and one straight shard (our own `psyshock_shard`). No homing. Special,
measured against Defense.
- [Games] The Defense rule. Cobblemon: `psybeam_charge`, `psybeam_targetburst`, `psybeam_targetsparkle`.

**Calm Mind** · *Now:* arms lower, a slow pink ring closes in, +1 Sp. Atk and +1 Sp. Def at its end, twice a
battle (no limit in the games: nothing resets stages in 1 vs 1). `selfboost.gd`, as Bulk Up.

**Agility** · *Now:* short and sharp, dash lines and wind, +2 Speed once a battle. `selfboost.gd`.
- [Games] The +2. Cobblemon: `quickattack_dashlines`.

**Shadow Ball, on Mewtwo** · *Now:* the same move, with a clip named after it: both hands at the right hip by
0.2 s, a thrust at 0.28 s. Every other Pokémon keeps `special`.
- [Smash] Cupped hands at the hip; there it also charges and flies in a wavy path, not taken.

---

## Sylveon
A first pass, and **mostly still owed**. Searches found no Sylveon or these moves in Pokkén, and the
[Smash fan wiki](https://supersmashbros.fandom.com/wiki/Sylveon_(Pokemon)) only has it as a trophy, so neither
gives a reference yet: check Serebii's Pokkén lists and SmashWiki directly. In the anime,
[Serena's Sylveon](https://bulbapedia.bulbagarden.net/wiki/Serena%27s_Sylveon) uses Swift and Fairy Wind; how
Moonblast, Draining Kiss, Dazzling Gleam and Hyper Voice look there is not researched. Their looks below come
from the games' descriptions.

**Draining Kiss** · *Now:* a very short wind-up, a small hop into a kiss, hearts where it lands and a green
shine as it heals 75% of the damage dealt. Close range, contact and special at once.

**Moonblast** · *Now:* a purple glow gathers at the mouth and a slow ball of moonlight flies out, barely
turning. Purple, not the type's pink.

**Swift** · *Now:* five gold stars leave in a fan and curve in. Running does not lose them; a dodge does.
- [Anime] Serena's Sylveon fires it as a stream of stars, in battle and in performances.

**Dazzling Gleam** · *Now:* a curtain of pink light rolls across the field with Surf's height curve.

**Hyper Voice** · *Now:* three arches of sound roll across the field with the same curve, hitting harder from
a longer wind-up.
