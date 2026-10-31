"""Keeps game/i18n/translations.csv in sync with the text the game shows.

Every player-facing string is written in English in the code and goes through tr()
(or TranslationServer.translate() outside nodes) when drawn. Data text (move names,
descriptions, counterplay, Pokémon styles and passives, type names, menu entries,
credits) is translated when displayed, so it is collected here too.

    python tools/update_translations.py           add new keys, report what is missing
    python tools/update_translations.py --check   only report; exit code 1 if anything is missing

New keys are appended with empty cells. An empty cell falls back to English in game,
so a missing translation never breaks anything. To add a language, add a column
(e.g. "fr") to the CSV header and register res://i18n/translations.fr.translation in
project.godot under [internationalization].
"""
import csv
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
SCRIPTS = os.path.join(ROOT, "scripts")
CSV_PATH = os.path.join(ROOT, "i18n", "translations.csv")
LIT = r'"((?:[^"\\]|\\.)*)"'


def read(*parts):
    return open(os.path.join(SCRIPTS, *parts), encoding="utf-8").read()


def collect():
    keys = []

    def add(k):
        k = k.replace('\\"', '"')
        if k and k not in keys:
            keys.append(k)

    for root, _, files in os.walk(SCRIPTS):
        for f in sorted(files):
            if f.endswith(".gd") and f != "species.gd":
                text = open(os.path.join(root, f), encoding="utf-8").read()
                for m in re.finditer(r"\btr\(" + LIT + r"\)|translate\(" + LIT + r"\)", text):
                    add(m.group(1) or m.group(2))

    data = read("data", "moves.gd") + read("data", "roster.gd") + read("data", "abilities.gd")
    for field in ("display_name", "desc", "counterplay", "style", "text", "form_name", "form_tab"):
        for m in re.finditer(r'"%s": ' % field + LIT, data):
            add(m.group(1))
    for m in re.finditer(r'"name": ' + LIT, read("data", "trainers.gd")):
        add(m.group(1))
    for m in re.finditer(r'": ' + LIT, re.search(r"const TYPE_NAME := \{(.*?)\}", data, re.S).group(1)):
        add(m.group(1))

    menu = read("menu.gd") + read("ui", "menu_draw.gd")
    for name in ("DIFFICULTY_NAME", "STAGE_NAME", "STAGE_TEXT"):
        for m in re.finditer(r'": ' + LIT, re.search(r"const %s := \{(.*?)\}" % name, menu, re.S).group(1)):
            add(m.group(1))
    for name in ("MAIN_MENU", "ONLINE", "CREDITS"):
        block = re.search(r"const %s := \[(.*?)\]\]?\n" % name, menu, re.S).group(1)
        for m in re.finditer(LIT, block):
            if name == "CREDITS" or not re.fullmatch(r"[a-z_]+", m.group(1)):
                add(m.group(1))

    for m in re.finditer(r'\["[a-z]{3}", "([A-Z]{3})"\]', read("hud.gd")):
        add(m.group(1))
    # Gamepad buttons with a name that is a word (not a letter or a symbol).
    pads = re.search(r"const PAD_NAME := \{(.*?)\n\}", read("controls.gd"), re.S).group(1)
    for v in re.finditer(r': ' + LIT, pads):
        if not re.fullmatch(r"[A-Z0-9△○□✕]{1,3}", v.group(1)):
            add(v.group(1))
    for m in re.finditer(r'"keyboard": \{(.*?)\}', read("controls.gd")):
        for v in re.finditer(r'": ' + LIT, m.group(1)):
            add(v.group(1))
    return keys


def main():
    check_only = "--check" in sys.argv
    with open(CSV_PATH, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header, body = rows[0], rows[1:]
    langs = header[1:]
    known = {r[0] for r in body}
    keys = collect()

    new = [k for k in keys if k not in known]
    unused = [r[0] for r in body if r[0] not in keys]
    if new and not check_only:
        body += [[k, k] + [""] * (len(langs) - 1) for k in new]
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, lineterminator="\n")
            w.writerow(header)
            w.writerows(body)

    missing = {lang: [r[0] for r in body if r[0] in keys and (len(r) <= i + 1 or r[i + 1] == "")]
               for i, lang in enumerate(langs) if lang != "en"}
    print("%d keys in use, %d new%s, %d unused" % (len(keys), len(new), "" if check_only else " (added)", len(unused)))
    for k in new if check_only else []:
        print("  NEW      %s" % k)
    for lang, ks in missing.items():
        for k in ks:
            print("  MISSING  [%s] %s" % (lang, k))
    for k in unused:
        print("  UNUSED   %s" % k)
    if check_only and (new or any(missing.values())):
        sys.exit(1)


if __name__ == "__main__":
    main()
