"""Converts Cobblemon's move particles (Bedrock / Snowstorm format) into JSON for the
Godot interpreter (game/scripts/fx/).

Usage:  python tools/convert_particles.py <the assets/cobblemon folder of the Cobblemon repo>
Writes:
  game/fx/particles/<id>.json    one per piece, with the Molang translated
  game/fx/tex/...png             the textures they use (pixel art)
  game/fx/sequences/<move>.json  each move's sequence (which piece, where, when)
and copies the untouched originals to sources/cobblemon_particles/ as reference material.

Molang is translated into a Godot expression (Expression class):
  v.thing / q.thing / variable.thing  ->  V("thing")
  math.sin(x)                         ->  msin(x)   (degrees, like Bedrock)
  a ? b : c                           ->  mif(a, b, c)
  &&  ||  !                           ->  and  or  not
License: these Cobblemon files carry no license of their own; the repository's applies
(MPL 2.0).
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "game" / "fx"

# ---------------------------------------------------------------- Molang

TOKEN = re.compile(r"\s*(?:(\d+\.\d*|\.\d+|\d+)f?|([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)|(&&|\|\||==|!=|<=|>=|\?\?|[-+*/()<>?:,!]))")
FUNCS = {"sin": "msin", "cos": "mcos", "random": "mrand", "random_integer": "mrandi", "clamp": "mclamp",
         "round": "mround", "floor": "mfloor", "ceil": "mceil", "abs": "mabs", "min": "mmin", "max": "mmax",
         "pow": "mpow", "sqrt": "msqrt", "mod": "mmod", "lerp": "mlerp", "exp": "mexp", "trunc": "mtrunc",
         "asin": "masin", "acos": "macos", "atan": "matan", "atan2": "matan2", "die_roll": "mdie",
         "hermite_blend": "mhermite", "lerprotate": "mlerp", "ln": "mln"}


def tokens(s):
    pos, out = 0, []
    s = s.strip()
    while pos < len(s):
        m = TOKEN.match(s, pos)
        if not m or m.end() == pos:
            raise ValueError("token at %r @%d" % (s, pos))
        num, ident, op = m.groups()
        out.append(("n", num) if num else ("i", ident) if ident else ("o", op))
        pos = m.end()
    return out


class Parser:
    PREC = {"?": 1, "??": 1, "||": 2, "&&": 3, "==": 4, "!=": 4, "<": 5, ">": 5, "<=": 5, ">=": 5,
            "+": 6, "-": 6, "*": 7, "/": 7}

    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expr(self, minp=0):
        left = self.unary()
        while True:
            k, v = self.peek()
            if k != "o" or v not in self.PREC or self.PREC[v] < minp:
                return left
            self.take()
            if v == "?":
                a = self.expr(0)
                k2, v2 = self.take()
                if v2 != ":":
                    # "c ? a" without ":" is 0 when false
                    self.i -= 1
                    left = "mif(%s, %s, 0.0)" % (left, a)
                    continue
                b = self.expr(1)
                left = "mif(%s, %s, %s)" % (left, a, b)
            elif v == "??":
                right = self.expr(self.PREC[v] + 1)
                left = "(%s)" % left
            else:
                right = self.expr(self.PREC[v] + 1)
                op = {"&&": "and", "||": "or"}.get(v, v)
                if op in ("<", ">", "<=", ">=", "==", "!=", "and", "or"):
                    left = "mb(%s %s %s)" % (left, op, right)
                else:
                    left = "(%s %s %s)" % (left, op, right)

    def unary(self):
        k, v = self.take()
        if k == "o" and v == "-":
            return "(-%s)" % self.unary()
        if k == "o" and v == "!":
            return "mb(not mt(%s))" % self.unary()
        if k == "o" and v == "(":
            e = self.expr(0)
            self.take()
            return "(%s)" % e
        if k == "n":
            return repr(float(v))
        if k == "i":
            low = v.lower()
            parts_list = low.split(".")
            if parts_list[0] == "math":
                if parts_list[1] == "pi":
                    return "3.14159265"
                args = []
                if self.peek() == ("o", "("):
                    self.take()
                    if self.peek() != ("o", ")"):
                        while True:
                            args.append(self.expr(0))
                            if self.peek() == ("o", ","):
                                self.take()
                                continue
                            break
                    self.take()
                return "%s(%s)" % (FUNCS.get(parts_list[1], "mzero"), ", ".join(args))
            if parts_list[0] in ("v", "variable", "q", "query", "c", "context", "t", "temp"):
                name_id = ".".join(parts_list[1:])
                # unsupported q.thing(...): read as a variable
                if self.peek() == ("o", "("):
                    depth = 0
                    while True:
                        kk, vv = self.take()
                        if vv == "(":
                            depth += 1
                        elif vv == ")":
                            depth -= 1
                            if depth == 0:
                                break
                return 'V("%s")' % name_id
            if low in ("true", "false"):
                return "1.0" if low == "true" else "0.0"
            return 'V("%s")' % low
        raise ValueError("inesperado %r" % (v,))


def molang(x):
    """Number -> number; text -> {"e": Godot code}; a number written as text -> number."""
    if isinstance(x, (int, float)):
        return float(x)
    if not isinstance(x, str):
        return x
    s = x.strip()
    if s == "":
        return 0.0
    try:
        return float(s)
    except ValueError:
        pass
    s = s.rstrip(";")
    if s.lower().startswith("return "):
        s = s[7:]
    return {"e": Parser(tokens(s)).expr(0)}


def statements(s):
    """'v.a = 1; v.b = math.random(0,1);' -> [[name, expr], ...]"""
    out = []
    for part in str(s).split(";"):
        part = part.strip()
        if not part or "=" not in part:
            continue
        lhs, rhs = part.split("=", 1)
        name_id = lhs.strip().lower().split(".", 1)[-1]
        out.append([name_id, molang(rhs)])
    return out


def vec(x):
    if isinstance(x, list):
        return [molang(c) for c in x]
    return x


# ------------------------------------------------------- components

def convert_components(c):
    out = {}
    for k, v in c.items():
        name_id = k.split(":")[1]
        if name_id == "emitter_initialization":
            out[name_id] = {kk: statements(vv) for kk, vv in v.items()}
            continue
        if name_id == "particle_appearance_billboard":
            b = {"facing": v.get("facing_camera_mode", "rotate_xyz"), "size": vec(v.get("size", [0.1, 0.1]))}
            uv = v.get("uv", {})
            b["tw"] = uv.get("texture_width", 1)
            b["th"] = uv.get("texture_height", 1)
            if "flipbook" in uv:
                fb = uv["flipbook"]
                b["flip"] = {"base": vec(fb.get("base_UV", [0, 0])), "size": fb.get("size_UV", [1, 1]),
                             "step": fb.get("step_UV", [0, 0]), "fps": fb.get("frames_per_second", 8),
                             "max": molang(fb.get("max_frame", 1)), "stretch": fb.get("stretch_to_lifetime", False),
                             "loop": fb.get("loop", False)}
            else:
                b["uv"] = vec(uv.get("uv", [0, 0]))
                b["uv_size"] = vec(uv.get("uv_size", [b["tw"], b["th"]]))
            if "direction" in v and isinstance(v["direction"], dict):
                d = v["direction"]
                b["dir_mode"] = d.get("mode", "derive_from_velocity")
                if "custom_direction" in d:
                    b["dir_custom"] = vec(d["custom_direction"])
            out[name_id] = b
            continue
        if name_id == "particle_appearance_tinting":
            col = v.get("color")
            if isinstance(col, dict):
                deg = col.get("gradient", {})
                if isinstance(deg, list):
                    n = max(1, len(deg) - 1)
                    deg = {str(i / n): g for i, g in enumerate(deg)}
                out[name_id] = {"interp": molang(col.get("interpolant", 0)),
                               "grad": sorted([[float(p), g] for p, g in deg.items()], key=lambda a: a[0])}
            elif isinstance(col, str):
                out[name_id] = {"hex": col}
            else:
                out[name_id] = {"rgba": vec(col)}
            continue
        if name_id in ("emitter_lifetime_events", "particle_lifetime_events"):
            out[name_id] = v
            continue
        if isinstance(v, dict):
            out[name_id] = {kk: (vec(vv) if isinstance(vv, list) else (molang(vv) if not (kk in ("surface_only", "expire_on_contact", "enabled", "plane_normal", "scaling") or (kk == "direction" and vv in ("inwards", "outwards"))) or not isinstance(vv, str) else vv)) for kk, vv in v.items()}
        elif isinstance(v, list):
            out[name_id] = vec(v)
        else:
            out[name_id] = molang(v)
    return out


def convert_curves(cv):
    out = {}
    for name_id, c in (cv or {}).items():
        nodes = c.get("nodes", [])
        if isinstance(nodes, dict):
            nodes = [v for _, v in sorted(((float(k), v) for k, v in nodes.items()))]
        out[name_id.lower().split(".", 1)[-1]] = {"type": c.get("type", "linear"), "input": molang(c.get("input", 0)),
                                                 "range": molang(c.get("horizontal_range", 1)), "nodes": nodes}
    return out


# ------------------------------------------------- custom textures
# Cobblemon ships copies of Minecraft particles (Mojang's) in particle/vanilla/.
# Those are not used: our own pixel art versions are drawn here with THE SAME SIZES,
# so the effects' animation strips still line up.

CUSTOM = {  # name: (width, height)
    "generic": (64, 8), "big_smoke": (16, 192), "big_smoke_white": (16, 192), "bubble": (8, 8),
    "bubble_pop": (16, 80), "cherry_petal": (12, 9), "critical_hit": (8, 8), "flame": (8, 8),
    "flash": (32, 32), "gust": (384, 32), "lava": (8, 8), "small_explosion": (16, 144),
    "small_gust": (56, 8), "spiral": (64, 8), "wool_white": (16, 16),
}


def _disc(px, cx, cy, r, col, rim=None, w=None, h=None):
    for y in range(h):
        for x in range(w):
            d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            if d <= r:
                px[x, y] = rim if (rim and d > r - 1.0) else col


def draw_custom(name_id, fpath):
    import math
    from PIL import Image
    w, h = CUSTOM[name_id]
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()

    def strip(fw, fh, n, f):
        for i in range(n):
            sub = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            f(sub.load(), i, n, fw, fh)
            if w >= fw * n and h == fh:
                im.paste(sub, (i * fw, 0))
            else:
                im.paste(sub, (0, i * fh))

    white, grey = (255, 255, 255, 255), (205, 208, 214, 255)
    if name_id == "generic":
        strip(8, 8, 8, lambda p, i, n, fw, fh: _disc(p, 4, 4, 3.6 - i * 0.42, white, grey, fw, fh))
    elif name_id in ("big_smoke", "big_smoke_white"):
        tone = white if name_id.endswith("white") else (150, 152, 158, 255)
        dark = (210, 212, 218, 255) if name_id.endswith("white") else (112, 114, 120, 255)

        def smoke(p, i, n, fw, fh):
            r = 3.0 + i * 0.35
            for (dx, dy) in ((-2, 1), (2, 1), (0, -1.5)):
                _disc(p, 8 + dx * (1 + i * 0.05), 8 + dy, r * (1 - i / (n * 1.6)), tone, dark, fw, fh)
        strip(16, 16, 12, smoke)
    elif name_id == "bubble":
        _disc(px, 4, 4, 3.6, (0, 0, 0, 0), (170, 220, 255, 255), w, h)
        px[2, 2] = white
    elif name_id == "bubble_pop":
        def pop(p, i, n, fw, fh):
            r = 3 + i * 1.3
            for a in range(0, 360, 30 if i < 2 else 45):
                if i >= 2 and (a // 45) % 2:
                    continue
                x = int(8 + math.cos(math.radians(a)) * r)
                y = int(8 + math.sin(math.radians(a)) * r)
                if 0 <= x < fw and 0 <= y < fh:
                    p[x, y] = (190, 230, 255, 255)
        strip(16, 16, 5, pop)
    elif name_id == "cherry_petal":
        for y in range(h):
            for x in range(w):
                if ((x - 6) / 5.5) ** 2 + ((y - 4.5) / 3.5) ** 2 <= 1:
                    px[x, y] = (255, 180, 210, 255) if x < 9 else (240, 140, 180, 255)
    elif name_id == "critical_hit":
        for i in range(8):
            px[i, 3] = px[i, 4] = white if 1 <= i <= 6 else (0, 0, 0, 0)
            px[3, i] = px[4, i] = white if 1 <= i <= 6 else (0, 0, 0, 0)
    elif name_id in ("flame", "lava"):
        for y in range(h):
            for x in range(w):
                d = abs(x - 3.5) / max(0.5, (y + 1) * 0.45)
                if d <= 1 and y >= 1:
                    px[x, y] = (255, 230, 120, 255) if d < 0.45 else (255, 130, 40, 255)
    elif name_id == "flash":
        for y in range(h):
            for x in range(w):
                d = ((x + 0.5 - 16) ** 2 + (y + 0.5 - 16) ** 2) ** 0.5 / 16
                if d < 1:
                    a = 255 if d < 0.5 else (170 if d < 0.75 else 80)
                    px[x, y] = (255, 255, 255, a)
    elif name_id in ("gust", "small_gust"):
        fw = 32 if name_id == "gust" else 8

        def swirl(p, i, n, fw2, fh):
            c = fw2 / 2
            for k in range(40):
                t = k / 40 * math.pi * 1.6 + i * 0.5
                r = c * (0.25 + 0.7 * k / 40)
                x, y = int(c + math.cos(t) * r), int(c + math.sin(t) * r * 0.6)
                if 0 <= x < fw2 and 0 <= y < fh and k > i * 3:
                    p[x, y] = (235, 240, 245, 220)
        strip(fw, h, w // fw, swirl)
    elif name_id == "small_explosion":
        def boom(p, i, n, fw, fh):
            _disc(p, 8, 8, 2 + i * 0.7, (255, 240, 200, 255) if i < 4 else (200, 200, 205, 255),
                   (255, 160, 60, 255) if i < 4 else (150, 150, 155, 255), fw, fh)
        strip(16, 16, 9, boom)
    elif name_id == "spiral":
        def spiral(p, i, n, fw, fh):
            for k in range(6):
                t = k * 1.1 + i * 0.8
                x, y = int(4 + math.cos(t) * k * 0.6), int(4 + math.sin(t) * k * 0.6)
                if 0 <= x < fw and 0 <= y < fh:
                    p[x, y] = (230, 200, 255, 255)
        strip(8, 8, 8, spiral)
    elif name_id == "wool_white":
        for y in range(h):
            for x in range(w):
                px[x, y] = (245, 245, 245, 255) if (x * 7 + y * 3) % 5 else (225, 225, 228, 255)
    fpath.parent.mkdir(parents=True, exist_ok=True)
    im.save(fpath)


SUBSTITUTES = {"impact-fire": "generic/impact/impact_fire", "charge_orb": "generic/orb/orb"}


def find_texture(assets, fpath):
    r = fpath.replace("\\", "/").split(":")[-1]
    name_id = r.rsplit("/", 1)[-1]
    if "vanilla/" in r or name_id in ("flash", "wool_colored_white"):
        key_name = "wool_white" if name_id == "wool_colored_white" else name_id
        if key_name in CUSTOM:
            rel = "custom/%s.png" % key_name
            dest = DEST / "tex" / rel
            if not dest.exists():
                draw_custom(key_name, dest)
            return dest, rel
    if name_id in SUBSTITUTES:
        r = "textures/particle/" + SUBSTITUTES[name_id]
    for pref in ("textures/particles/", "textures/particle/", "textures/textures/", "textures/"):
        if r.startswith(pref):
            r = r[len(pref):]
            break
    for base in ("textures/particle/", "textures/particle/moves/", "textures/"):
        p = assets / (base + r + ".png")
        if p.exists():
            return p, (base + r + ".png").replace("textures/particle/", "")
    return None, None


def main():
    assets = Path(sys.argv[1])
    origin = assets / "bedrock" / "particles"
    (DEST / "particles").mkdir(parents=True, exist_ok=True)
    (DEST / "tex").mkdir(parents=True, exist_ok=True)
    (DEST / "sequences").mkdir(parents=True, exist_ok=True)
    copy_of = ROOT / "sources" / "cobblemon_particles"
    n = failures = 0
    textures = set()
    for f in sorted(origin.rglob("*.particle.json")):
        rel = f.relative_to(origin)
        if rel.parts[0] not in ("moves", "generic"):
            continue
        (copy_of / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(f, copy_of / rel)
        d = json.loads(f.read_text(encoding="utf-8"))["particle_effect"]
        ident = d["description"]["identifier"].split(":")[-1]
        brp = d["description"].get("basic_render_parameters", {})
        tex, tex_rel = find_texture(assets, brp.get("texture", ""))
        try:
            effect = {
                "id": ident,
                "material": brp.get("material", "particles_alpha"),
                "tex": "res://fx/tex/" + tex_rel if tex else "",
                "curves": convert_curves(d.get("curves")),
                "events": d.get("events", {}),
                "comp": convert_components(d.get("components", {})),
            }
        except Exception as e:
            print("FAILED", rel, e)
            failures += 1
            continue
        if tex:
            dst = DEST / "tex" / tex_rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if Path(tex).resolve() != dst.resolve():
                shutil.copy(tex, dst)
            textures.add(tex_rel)
        (DEST / "particles" / (ident + ".json")).write_text(json.dumps(effect, separators=(",", ":")), encoding="utf-8")
        n += 1
    # Loose generic textures (orbs, flashes, slashes, per-type impacts): the game uses them
    # directly for projectiles and hits, even if no piece asks for them.
    gen = assets / "textures" / "particle" / "generic"
    for png in gen.rglob("*.png"):
        rel = "generic/" + png.relative_to(gen).as_posix()
        dst = DEST / "tex" / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            shutil.copy(png, dst)
            textures.add(rel)
    # Move sequences (data/cobblemon/action_effects/moves).
    actions = assets.parent.parent / "data" / "cobblemon" / "action_effects" / "moves"
    g = 0
    if actions.exists():
        for f in sorted(actions.glob("*.json")):
            d = json.loads(f.read_text(encoding="utf-8"))
            steps = []
            for step in d.get("timeline", []):
                t = step.get("type")
                if t == "pause":
                    steps.append({"pause": step.get("pause", 0)})
                elif t == "entity_particles":
                    cond = step.get("entityCondition", "")
                    who = "target" if "is_user == false" in cond else "actor"
                    steps.append({"fx": step["effect"].split(":")[-1], "who": who,
                                  "loc": (step.get("locators") or ["root"])[0]})
            (DEST / "sequences" / f.name).write_text(json.dumps(steps, separators=(",", ":")), encoding="utf-8")
            g += 1
    print("pieces: %d (failed %d) · textures: %d · sequences: %d" % (n, failures, len(textures), g))


if __name__ == "__main__":
    main()
