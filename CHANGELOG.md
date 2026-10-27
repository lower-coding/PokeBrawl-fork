# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Real-time 3D battles with ten Pokémon: Pikachu, Snorlax, Charizard, Blastoise, Venusaur,
  Lucario, Gengar, Garchomp, Greninja and Scizor, each with four moves and a passive ability.
- Battle rules: energy and per-move cooldowns, dodges with invulnerability windows, poise,
  softened type matchups, combo limit with knockdown, flight for Charizard, every move usable in
  the air.
- AI opponent with three difficulties that reads the rival with a delay, dodges, jumps
  Earthquake waves and punishes recoveries.
- 1 vs 1 online play over UDP (ENet) with UPnP, rematches and pick changes without
  disconnecting.
- Two stages drawn by script: a gym stadium and a forest glade.
- Menus and battle UI built from Cobblemon's GUI pieces, with live portraits.
- Cobblemon models, animations, particle effects and sounds, converted by the tools in `tools/`.
- English and Spanish, following the system language (`--lang` forces one).
- Automated tests: mechanics, AI vs AI, animations, menus and online.
