"""Imports real species data from a Cobblemon clone.

Reads, from a clone of the Cobblemon repository (https://gitlab.com/cable-mc/cobblemon):
  - common/src/main/resources/data/cobblemon/species/**/<species>.json
    (base stats, types, abilities, weight, height and learnset);
  - common/src/main/resources/assets/cobblemon/lang/en_us.json (official names).
It also works with a partial (sparse) clone: whatever is not on disk is read with
"git show".

Writes game/scripts/data/species.gd with every species imported so far (the ones already
there are kept). That file is generated: do not edit it by hand.

    python tools/import_species.py --cobblemon PATH_TO_CLONE pikachu snorlax ...
    python tools/import_species.py --cobblemon PATH_TO_CLONE --roster

The path can also come from the POKEBRAWL_COBBLEMON environment variable.

Data: Cobblemon, MPL-2.0 (the mod's code and data). Pokémon stats, moves and abilities
belong to Nintendo, Game Freak and The Pokémon Company.
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT = os.path.join(ROOT, "game", "scripts", "data", "species.gd")
ROSTER = os.path.join(ROOT, "game", "scripts", "data", "roster.gd")
SPECIES_DIR = "common/src/main/resources/data/cobblemon/species"
LANG = "common/src/main/resources/assets/cobblemon/lang/en_us.json"

# Cobblemon stat names -> ours (Showdown's).
STATS = {"hp": "hp", "attack": "atk", "defence": "def", "special_attack": "spa",
         "special_defence": "spd", "speed": "spe"}
# Forms with an entry of their own in the roster: id -> (species file, name of the form in it).
FORMS = {"urshifurapidstrike": ("urshifu", "Rapid-Strike")}


def read(clone, path):
    """A file from the clone: from disk if it is there, otherwise with git show."""
    on_disk = os.path.join(clone, path)
    if os.path.isfile(on_disk):
        with open(on_disk, encoding="utf-8") as f:
            return f.read()
    r = subprocess.run(["git", "-C", clone, "show", "HEAD:" + path], capture_output=True, text=True,
                       encoding="utf-8")
    if r.returncode != 0:
        raise FileNotFoundError(path)
    return r.stdout


def species_paths(clone):
    r = subprocess.run(["git", "-C", clone, "ls-tree", "-r", "--name-only", "HEAD", SPECIES_DIR],
                       capture_output=True, text=True, encoding="utf-8")
    paths = {os.path.splitext(os.path.basename(p))[0]: p for p in r.stdout.split() if p.endswith(".json")}
    for form, (base, _) in FORMS.items():
        if base in paths:
            paths[form] = paths[base]
    return paths


def species(clone, paths, lang, sp):
    d = json.loads(read(clone, paths[sp]))
    # A form: its own entry over the base's, which fills in what it leaves null (its abilities
    # and stats).
    if sp in FORMS:
        name = FORMS[sp][1]
        entry = next(f for f in d.get("forms", []) if f["name"] == name)
        d = {**d, **{k: v for k, v in entry.items() if v is not None}}
    types = [d["primaryType"]] + ([d["secondaryType"]] if d.get("secondaryType") else [])
    abilities = []
    for a in d.get("abilities", []):
        hidden = a.startswith("h:")
        abilities.append({"id": a[2:] if hidden else a, "hidden": hidden})
    learnset = []
    for m in d.get("moves", []):
        how, _, move = m.partition(":")
        entry = {"move": move, "how": "level" if how.isdigit() else how}
        if how.isdigit():
            entry["level"] = int(how)
        learnset.append(entry)
    return {
        "dex": d["nationalPokedexNumber"],
        "name": lang.get("cobblemon.species.%s.name" % sp, d["name"]),
        "types": types,
        "stats": {STATS[k]: v for k, v in d["baseStats"].items() if k in STATS},
        "weight_kg": d["weight"] / 10.0,
        "height_m": d["height"] / 10.0,
        "abilities": abilities,
        "learnset": learnset,
    }


def to_gd(value, indent=1):
    """A Python value as a GDScript literal (dictionaries indented with tabs)."""
    t = "\t" * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        parts = ["%s%s: %s" % (t, json.dumps(k, ensure_ascii=False), to_gd(v, indent + 1)) for k, v in value.items()]
        return "{\n" + ",\n".join(parts) + ",\n" + "\t" * (indent - 1) + "}"
    if isinstance(value, list):
        if value and all(isinstance(x, dict) for x in value):
            return "[" + ", ".join(json.dumps(x, ensure_ascii=False) for x in value) + "]"
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, float):
        return repr(value)
    return json.dumps(value, ensure_ascii=False)


def existing():
    """Species already in species.gd (so they are kept when adding others)."""
    if not os.path.isfile(OUTPUT):
        return {}
    with open(OUTPUT, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"# DATA_JSON (.*)$", text, re.M)
    return json.loads(m.group(1)) if m else {}


def write(data):
    data = dict(sorted(data.items(), key=lambda kv: kv[1]["dex"]))
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("class_name Species\n")
        f.write("extends RefCounted\n")
        f.write("## GENERATED by tools/import_species.py: do not edit by hand.\n")
        f.write("## Real data for each species (base stats, types, abilities, weight, height and\n")
        f.write("## learnset), taken from Cobblemon (MPL-2.0). Pokémon stats and moves belong to\n")
        f.write("## Nintendo, Game Freak and The Pokémon Company.\n\n")
        f.write("const DATA := %s\n\n" % to_gd(data))
        f.write("# DATA_JSON %s\n" % json.dumps(data, ensure_ascii=False))
    print("wrote", os.path.relpath(OUTPUT, ROOT), "with", len(data), "species")


def roster_species():
    with open(ROSTER, encoding="utf-8") as f:
        block = re.search(r"^const POKEMON := \{(.*?)^\}", f.read(), re.M | re.S).group(1)
    return re.findall(r'^\t"([a-z0-9_]+)": \{', block, re.M)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("species", nargs="*")
    ap.add_argument("--cobblemon", default=os.environ.get("POKEBRAWL_COBBLEMON", ""))
    ap.add_argument("--roster", action="store_true", help="import every species in the roster")
    a = ap.parse_args()
    if not a.cobblemon:
        sys.exit("Missing the path to the Cobblemon clone (--cobblemon or POKEBRAWL_COBBLEMON).")
    wanted = list(a.species) + (roster_species() if a.roster else [])
    if not wanted:
        sys.exit("Say which species to import.")
    paths = species_paths(a.cobblemon)
    lang = json.loads(read(a.cobblemon, LANG))
    data = existing()
    for sp in wanted:
        if sp not in paths:
            print("not in Cobblemon:", sp)
            continue
        data[sp] = species(a.cobblemon, paths, lang, sp)
        e = data[sp]
        print("%-10s %s  %s  %d abilities, %d moves" % (sp, e["types"], e["stats"], len(e["abilities"]), len(e["learnset"])))
    write(data)


if __name__ == "__main__":
    main()
