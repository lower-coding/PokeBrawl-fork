"""Brings Urshifu's model from the Pokemans Pack and gets it ready for the game.

Usage:  python tools/import_pokemans.py <pokemans zip> --cobblemon=<path to the Cobblemon clone>

Cobblemon has no Urshifu model, so it comes from https://modrinth.com/datapack/cobblemon-pokemans
(version V15, CC BY-NC 4.0), a datapack in Cobblemon's own Bedrock format. For each form:
- copies the untouched originals into sources/pokemans/<id>/,
- writes model.geo.json, texture.png and anim.animation.json next to them, with the fixes in FORMS
  (the attack cut so the fist lands with the hit, a run built from the walk, no faint: it never
  falls, so a KO uses the sleep animation, with the back cloth lying on the ground; Rapid Strike's
  gold recolored),
- copies Cobblemon's cry (the pack's differ and do not say where they come from),
- converts it with convert_cobblemon.py into game/pokemon/<id>/.
Species data does not come from the pack: see tools/import_species.py.
"""
import colorsys
import json
import shutil
import sys
import zipfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import convert_cobblemon as conv

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources" / "pokemans"
PACK = "assets/pokemans/"
CRY = "common/src/main/resources/assets/cobblemon/sounds/pokemon/urshifu/urshifu_cry.ogg"

# Id in the roster -> the form's files in the pack, its stance, and the stretch of its attack (s).
FORMS = {
    "urshifu": {"pack": "urshifu", "stance": "singlestrike", "attack": "ssphysical_attack", "cut": (1.0, 2.0), "recolor": False},
    "urshifurapidstrike": {"pack": "urshifurs", "stance": "rapidstrike", "attack": "rsphysical_attack", "cut": (0.4, 1.2), "recolor": True},
}
# The run: the walk's first stride (2 s) in about what Lucario's takes.
RUN_STRIDE = 2.0
RUN_LEN = 0.5
# Rapid Strike's accents: the gold's hue goes to the Water type's blue. Same lightness and
# bands, so the pixel art stays as it is.
GOLD_HUE = (0.1, 0.2)
GOLD_MIN_SAT = 0.25
WATER_HUE = 0.59


def _shift(value, scale, start):
    """A keyframe value with q.anim_time as it was in the original animation."""
    if isinstance(value, str):
        return value.replace("query.anim_time", "q.anim_time").replace("q.anim_time", f"(q.anim_time*{scale}+{start})")
    if isinstance(value, list):
        return [_shift(v, scale, start) for v in value]
    if isinstance(value, dict):
        return {k: _shift(v, scale, start) if k != "lerp_mode" else v for k, v in value.items()}
    return value


def cut(anim, start, end, length=None, loop=False):
    """The stretch of an animation from start to end, played in "length" seconds."""
    length = length if length is not None else end - start
    scale = (end - start) / length
    bones = {}
    for bone, channels in anim.get("bones", {}).items():
        out = {}
        for kind, channel in channels.items():
            if not isinstance(channel, dict):
                out[kind] = _shift(channel, scale, start)
                continue
            keys = {"0.0": conv.sample_channel(channel, start)}
            for t, k in channel.items():
                if start < float(t) < end:
                    keys[str(round((float(t) - start) / scale, 4))] = _shift(k, scale, start)
            keys[str(round(length, 4))] = conv.sample_channel(channel, end)
            out[kind] = keys
        bones[bone] = out
    return {"animation_length": round(length, 4), "loop": loop, "bones": bones}


def animations(raw, ident, form):
    """The animations by the names the game asks for (convert_cobblemon.ANIMS)."""
    p = f"animation.pokemans_{form['pack']}."
    a = raw["animations"]
    start, end = form["cut"]
    attack = cut(a[p + form["attack"]], start, end)
    out = {
        "battle_idle": a[p + form["stance"]],
        "ground_idle": a[p + "ground_idle"],
        "ground_walk": a[p + "ground_walk"],
        "ground_run": cut(a[p + "ground_walk"], 0.0, RUN_STRIDE, RUN_LEN, True),
        "physical": attack,
        "special": attack,
        "blink": a[p + "blink"],
        # One go, like everyone else's (in the pack it loops).
        "cry": dict(a[p + "cry"], loop=False),
        # Lying down, the back cloth hangs through the floor and Fighter would lift the whole body
        # off the ground to clear it: it lies along the ground instead.
        "sleep": {**a[p + "sleep"], "bones": {**a[p + "sleep"]["bones"], "back": {"rotation": [-22, 0, 0]}}},
    }
    return {"animations": {f"animation.{ident}.{k}": v for k, v in out.items()}}


def recolored(png, dest):
    """Writes the texture with its gold turned to the Water type's blue."""
    img = Image.open(png).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, alpha = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if alpha > 0 and GOLD_HUE[0] <= h <= GOLD_HUE[1] and s >= GOLD_MIN_SAT:
                nr, ng, nb = colorsys.hsv_to_rgb(WATER_HUE, s, v)
                px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), alpha)
    img.save(dest)


def import_form(z, clone, ident, form):
    dest = SOURCES / ident
    dest.mkdir(parents=True, exist_ok=True)
    pack = form["pack"]
    geo_name = f"bedrock/pokemon/models/{pack}.geo.json"
    anim_name = f"bedrock/pokemon/animations/pokemans_{pack}.animation.json"
    tex = f"textures/pokemon/{pack}/{pack}.png"
    shiny = f"textures/pokemon/{pack}/{pack}_shiny.png"
    # The originals, untouched.
    for name in (geo_name, anim_name, tex, shiny):
        (dest / Path(name).name).write_bytes(z.read(PACK + name))
    # The body's root bone goes by the species id (Fighter._find_feet leaves it out by that name).
    geo = json.loads(z.read(PACK + geo_name))
    for bone in geo["minecraft:geometry"][0]["bones"]:
        if bone["name"] == "urshifu":
            bone["name"] = ident
        if bone.get("parent") == "urshifu":
            bone["parent"] = ident
    (dest / "model.geo.json").write_text(json.dumps(geo), encoding="utf-8")
    anims = animations(json.loads(z.read(PACK + anim_name)), ident, form)
    (dest / "anim.animation.json").write_text(json.dumps(anims), encoding="utf-8")
    for name, out in ((tex, "texture.png"), (shiny, "texture_shiny.png")):
        if form["recolor"]:
            recolored(dest / Path(name).name, dest / out)
        else:
            shutil.copy(dest / Path(name).name, dest / out)
    shutil.copy(Path(clone) / CRY, dest / "cry.ogg")
    conv.convert(ident)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    clone = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--cobblemon=")), "")
    if not args or not clone:
        sys.exit(__doc__)
    # What is converted here is not Cobblemon's, and must not be described as if it were.
    conv.SOURCES = SOURCES
    with zipfile.ZipFile(args[0]) as z:
        for ident, form in FORMS.items():
            import_form(z, clone, ident, form)
    if conv.MOLANG_FAILURES:
        print(f"Unread Molang ({len(conv.MOLANG_FAILURES)} values), examples: {sorted(set(conv.MOLANG_FAILURES))[:6]}")


if __name__ == "__main__":
    main()
