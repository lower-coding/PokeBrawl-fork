"""Brings Pokémon models from the Cobblemon repository and gets them ready for the game.

Usage:  python tools/import_cobblemon.py <path to common/src/main/resources> [generations]
        [--only=kecleon,other]                   (default: all of generation 1)

For each non-legendary species that walks or flies:
- copies into sources/cobblemon/<id>/ what its "resolver" points to (model, animations,
  texture, shiny texture, emissive layer, Alpha eyes and the model's license),
- converts it with convert_cobblemon.py into game/pokemon/<id>/.
Gameplay data (stats, learnset) comes from tools/import_species.py; the battle tuning of
each Pokémon lives in game/scripts/data/roster.gd.
"""
import json
import re
import shutil
import sys
from pathlib import Path

import convert_cobblemon as conv

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources" / "cobblemon"
EXCLUDED = {"legendary", "mythical", "restricted", "ultra_beast", "paradox"}
GEN_END = [0, 151, 251, 386, 493, 649, 721, 809, 905, 1025]


def _path(resources, ref):
    """"cobblemon:textures/pokemon/x.png" -> the file in the repository."""
    if isinstance(ref, dict):
        ref = ref["frames"][0]
    return resources / "assets" / "cobblemon" / ref.split(":", 1)[1]


def import_species(resources, species_file):
    j = json.loads(species_file.read_text(encoding="utf-8"))
    if not j.get("implemented") or EXCLUDED & set(j.get("labels", [])):
        return None
    mov = j.get("behaviour", {}).get("moving", {})
    walks = mov.get("walk", {}).get("canWalk", True) and not mov.get("walk", {}).get("avoidsLand", False)
    flies = mov.get("fly", {}).get("canFly", False)
    if not walks and not flies:
        return None   # swimmers only have no place on land
    dex = j["nationalPokedexNumber"]
    bedrock = resources / "assets" / "cobblemon" / "bedrock" / "pokemon"
    folders = list((bedrock / "resolvers").glob("%04d_*" % dex))
    if not folders:
        return None
    folder = folders[0].name
    ident = folder.split("_", 1)[1]
    base = sorted((bedrock / "resolvers" / folder).glob("0_*.json"))
    if not base:
        return None
    res = json.loads(base[0].read_text(encoding="utf-8"))
    var = next(v for v in res["variations"] if not v.get("aspects"))
    alpha = None
    shiny = None
    for v in res["variations"]:
        if v.get("aspects") == ["shiny"] and isinstance(v.get("texture"), str):
            shiny = _path(resources, v["texture"])
        for layer in v.get("layers", []):
            if layer.get("name") == "alpha_eyes" and not alpha:
                alpha = _path(resources, layer["texture"])
    # Animation group: the one its poser names with q.bedrock('group', ...)
    poser_id = var.get("poser", "cobblemon:" + ident).split(":", 1)[1]
    poser = bedrock / "posers" / folder / (poser_id + ".json")
    group = ident
    if poser.exists():
        groups = re.findall(r"q\.bedrock\('([^']+)'", poser.read_text(encoding="utf-8"))
        if groups and ident not in groups:
            group = max(set(groups), key=groups.count)
    model = bedrock / "models" / folder / (var["model"].split(":", 1)[1] + ".json")
    anims = bedrock / "animations" / folder / (group + ".animation.json")
    texture = _path(resources, var["texture"])
    if not (model.exists() and anims.exists() and texture.exists()):
        print(f"  {ident}: something is missing ({model.name}, {anims.name}, {texture.name})")
        return None

    dest = SOURCES / ident
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(model, dest / "model.geo.json")
    shutil.copy(anims, dest / "anim.animation.json")
    shutil.copy(texture, dest / "texture.png")
    for layer in var.get("layers", []):
        if layer.get("emissive"):
            shutil.copy(_path(resources, layer["texture"]), dest / "texture_emissive.png")
            break
    if shiny and shiny.exists():
        shutil.copy(shiny, dest / "texture_shiny.png")
    if alpha and alpha.exists():
        shutil.copy(alpha, dest / "texture_alpha.png")
    lic = bedrock / "models" / folder / "license"
    if lic.exists():
        shutil.copy(lic, dest / "LICENSE-model.txt")
    conv.convert(ident, group)
    return ident


def _of_gen(n, gens):
    return any(GEN_END[g - 1] < n <= GEN_END[g] for g in gens)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = []
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    if not args:
        sys.exit(__doc__)
    resources = Path(args[0])
    gens = [int(g) for g in args[1:]] or [1]
    done = []
    for g in gens:
        for f in sorted((resources / "data" / "cobblemon" / "species" / f"generation{g}").glob("*.json")):
            if only and f.stem not in only:
                continue
            ident = import_species(resources, f)
            if ident:
                done.append(ident)
    print(f"imported {len(done)} species")
    if conv.MOLANG_FAILURES:
        print(f"Unread Molang ({len(conv.MOLANG_FAILURES)} values), examples: {sorted(set(conv.MOLANG_FAILURES))[:6]}")


if __name__ == "__main__":
    main()
