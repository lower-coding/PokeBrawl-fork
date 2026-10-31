"""Converts Cobblemon's Bedrock models and animations into a JSON that Godot reads.

Usage:  python tools/convert_cobblemon.py
Reads   sources/cobblemon/<pokemon>/   and writes   game/pokemon/<pokemon>/model.json.gz

- Axes: Bedrock has X flipped compared to Godot. X is flipped in positions and X/Y in
  rotations (the same thing Blockbench does when importing).
- Meshes come out already in each bone's local space (in pixels, 16 = 1 m).
- Animations are baked at 30 fps: catmull-rom, pre/post and Molang (math.sin, math.cos,
  math.clamp, q.anim_time) are all resolved here.
"""
import gzip
import json
import math
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources" / "cobblemon"
OUTPUT = ROOT / "game" / "pokemon"
FPS = 30

# Animations exported for each Pokémon (if they exist).
ANIMS = ["ground_idle", "ground_walk", "ground_run", "battle_idle", "faint", "air_idle", "air_fly", "air_glide",
         "physical", "physical_alt", "physical_kick", "physical_blunt", "special", "status", "recoil", "hurt",
         "air_physical", "air_special", "air_recoil", "blink", "cry", "battle_cry", "sleep", "sleep_intro",
         "watershuriken_3hit", "volttackle", "battle_idle_aura_left", "battle_idle_aura_right",
         "shadowball", "confusion", "disable"]


# ---------------------------------------------------------------- Molang

def _molang_to_python(expr):
    e = expr.strip().lower()
    e = e.replace("query.anim_time", "t").replace("q.anim_time", "t")
    e = e.replace("math.sin", "msin").replace("math.cos", "mcos")
    e = e.replace("math.clamp", "mclamp").replace("math.abs", "abs")
    e = e.replace("math.pi", "3.14159265").replace("&&", " and ").replace("||", " or ")
    e = re.sub(r"\bmath\.([a-z_]+)", r"m_\1", e)
    e = re.sub(r"(?<![\d.\w])0+(\d)", r"\1", e)   # "02" is valid in Molang, not in Python
    # Any other variable or query (v.something, q.something) is 0.
    e = re.sub(r"\b(?:v|variable|q|query|c|context|temp|t)\.[a-z_0-9.]+", "0", e)
    return e


_NS = {
    "msin": lambda d: math.sin(math.radians(d)),
    "mcos": lambda d: math.cos(math.radians(d)),
    "mclamp": lambda v, a, b: max(a, min(b, v)),
    "abs": abs,
    "m_sqrt": lambda v: math.sqrt(max(0.0, v)), "m_pow": lambda a, b: math.pow(a, b),
    "m_min": min, "m_max": max, "m_floor": math.floor, "m_ceil": math.ceil, "m_round": round,
    "m_trunc": math.trunc, "m_mod": lambda a, b: math.fmod(a, b) if b else 0.0, "m_exp": math.exp,
    "m_lerp": lambda a, b, k: a + (b - a) * k, "m_atan": lambda v: math.degrees(math.atan(v)),
    "m_atan2": lambda a, b: math.degrees(math.atan2(a, b)), "m_asin": lambda v: math.degrees(math.asin(v)),
    "m_acos": lambda v: math.degrees(math.acos(v)), "m_random": lambda a=0, b=1: (a + b) / 2,
    "m_random_integer": lambda a=0, b=1: (a + b) // 2, "m_die_roll": lambda n, a, b: n * (a + b) / 2,
    "m_hermite_blend": lambda v: 3 * v * v - 2 * v * v * v,
    "__builtins__": {},
}
MOLANG_FAILURES = []


def evaluate(value, t):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        if not value.strip():
            return 0.0
        try:
            return float(eval(_molang_to_python(value), _NS, {"t": t}))
        except Exception:
            # Molang we cannot read (odd ternaries, queries...): it is 0 and gets logged.
            MOLANG_FAILURES.append(value)
            return 0.0
    raise ValueError(value)


def uses_time(x):
    return "anim_time" in json.dumps(x)


def vec3(value, t):
    if isinstance(value, list):
        if len(value) == 1:
            v = evaluate(value[0], t)
            return [v, v, v]
        return [evaluate(v, t) for v in value]
    v = evaluate(value, t)
    return [v, v, v]


# ---------------------------------------------------------- Keyframes

def _key(k):
    """Returns (pre, post, mode) of a keyframe."""
    if isinstance(k, dict) and ("post" in k or "pre" in k):
        post = k.get("post", k.get("pre"))
        pre = k.get("pre", post)
        return pre, post, k.get("lerp_mode", "linear")
    if isinstance(k, dict) and "vector" in k:
        return k["vector"], k["vector"], k.get("lerp_mode", "linear")
    return k, k, "linear"


def sample_channel(channel, t):
    if not isinstance(channel, dict):
        return vec3(channel, t)
    key_names = sorted(((float(tt), _key(k)) for tt, k in channel.items()), key=lambda a: a[0])
    if t <= key_names[0][0]:
        return vec3(key_names[0][1][0], t)
    if t >= key_names[-1][0]:
        return vec3(key_names[-1][1][1], t)
    for i in range(len(key_names) - 1):
        t0, (pre0, post0, modo0) = key_names[i]
        t1, (pre1, post1, modo1) = key_names[i + 1]
        if t0 <= t < t1:
            a = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            p1 = vec3(post0, t)
            p2 = vec3(pre1, t)
            if modo0 == "step":
                return p1
            if modo0 == "catmullrom" or modo1 == "catmullrom":
                p0 = vec3(key_names[i - 1][1][1], t) if i > 0 else p1
                p3 = vec3(key_names[i + 2][1][0], t) if i + 2 < len(key_names) else p2
                return [_catmull(p0[j], p1[j], p2[j], p3[j], a) for j in range(3)]
            return [p1[j] + (p2[j] - p1[j]) * a for j in range(3)]
    return vec3(key_names[-1][1][1], t)


def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def bake_animation(anim, valid_bones):
    length = anim.get("animation_length")
    bones = anim.get("bones", {})
    if length is None:
        maximum = 0.0
        for channels in bones.values():
            for channel in channels.values():
                if isinstance(channel, dict):
                    for k in channel:
                        try:
                            maximum = max(maximum, float(k))
                        except ValueError:
                            pass
        length = maximum if maximum > 0 else (4.0 if uses_time(bones) else 0.0)
    length = float(length)
    n = max(1, int(round(length * FPS)) + 1) if length > 0 else 1
    output = {}
    for name_id, channels in bones.items():
        if name_id not in valid_bones:
            continue
        bone = {}
        for kind, key_name in (("rotation", "rot"), ("position", "pos"), ("scale", "scl")):
            if kind not in channels:
                continue
            channel = channels[kind]
            constant = not isinstance(channel, dict) and not uses_time(channel)
            samples = []
            for i in range(1 if constant else n):
                t = i / FPS
                v = sample_channel(channel, t)
                if kind == "rotation":
                    v = [-v[0], -v[1], v[2]]
                elif kind == "position":
                    v = [-v[0], v[1], v[2]]
                samples.extend(round(x, 3) for x in v)
            bone[key_name] = samples
        if bone:
            output[name_id] = bone
    return {"len": round(length, 4), "loop": bool(anim.get("loop", False)), "frames": n, "bones": output}


# ---------------------------------------------------------------- Meshes

def box_uv_faces(u, v, s, mirror):
    x, y, z = s
    faces = {
        "north": [z, z, z + x, z + y],
        "east": [0, z, z, z + y],
        "south": [2 * z + x, z, 2 * z + 2 * x, z + y],
        "west": [z + x, z, 2 * z + x, z + y],
        "up": [z + x, z, z, 0],
        "down": [z + 2 * x, 0, z + x, z],
    }
    faces = {k: [r[0] + u, r[1] + v, r[2] + u, r[3] + v] for k, r in faces.items()}
    if mirror:
        faces["east"], faces["west"] = faces["west"], faces["east"]
        for k, r in faces.items():
            faces[k] = [r[2], r[1], r[0], r[3]]
    return faces


def corners(face, a, b):
    """Corners (top-left, top-right, bottom-right, bottom-left) seen from outside."""
    x0, y0, z0 = a
    x1, y1, z1 = b
    return {
        "east": [(x1, y1, z1), (x1, y1, z0), (x1, y0, z0), (x1, y0, z1)],
        "west": [(x0, y1, z0), (x0, y1, z1), (x0, y0, z1), (x0, y0, z0)],
        "north": [(x1, y1, z0), (x0, y1, z0), (x0, y0, z0), (x1, y0, z0)],
        "south": [(x0, y1, z1), (x1, y1, z1), (x1, y0, z1), (x0, y0, z1)],
        "up": [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)],
        "down": [(x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0)],
    }[face]


NORMALS = {"east": (1, 0, 0), "west": (-1, 0, 0), "up": (0, 1, 0),
            "down": (0, -1, 0), "south": (0, 0, 1), "north": (0, 0, -1)}


def rotate(p, rot_deg, pivot):
    """Z·Y·X rotation (Blockbench order) around a pivot."""
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    x, y, z = p[0] - pivot[0], p[1] - pivot[1], p[2] - pivot[2]
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    return (x + pivot[0], y + pivot[1], z + pivot[2])


def cube_mesh(cube, bone_pivot, tex_w, tex_h):
    o, s = cube["origin"], cube["size"]
    inf = cube.get("inflate", 0.0)
    a = [-(o[0] + s[0]) - inf, o[1] - inf, o[2] - inf]
    b = [-o[0] + inf, o[1] + s[1] + inf, o[2] + s[2] + inf]
    rot = cube.get("rotation")
    piv = cube.get("pivot", [0, 0, 0])
    piv = [-piv[0], piv[1], piv[2]]
    rot = [-rot[0], -rot[1], rot[2]] if rot else None
    uvs = box_uv_faces(cube["uv"][0], cube["uv"][1], s, cube.get("mirror", False))
    verts, normals, coords = [], [], []
    for face, r in uvs.items():
        # A flat cube (size 0 on one axis) only needs its two large faces.
        if (face in ("east", "west") and s[1] * s[2] == 0) or \
           (face in ("up", "down") and s[0] * s[2] == 0) or \
           (face in ("north", "south") and s[0] * s[1] == 0):
            continue
        quad = corners(face, a, b)
        n = NORMALS[face]
        if rot:
            quad = [rotate(p, rot, piv) for p in quad]
            n = rotate(n, rot, (0, 0, 0))
        u0, v0, u1, v1 = r
        uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        for i in (0, 1, 2, 0, 2, 3):
            p = quad[i]
            verts.extend(round(p[j] - bone_pivot[j], 4) for j in range(3))
            normals.extend(round(c, 4) for c in n)
            coords.extend((round(uv[i][0] / tex_w, 5), round(uv[i][1] / tex_h, 5)))
    return verts, normals, coords


def convert(name_id, group=None):
    folder = SOURCES / name_id
    geo = json.loads((folder / "model.geo.json").read_text(encoding="utf-8"))["minecraft:geometry"][0]
    width_px = geo["description"]["texture_width"]
    height_px = geo["description"]["texture_height"]
    bones = []
    pivots = {}
    for h in geo["bones"]:
        piv = h.get("pivot", [0, 0, 0])
        pivots[h["name"]] = [-piv[0], piv[1], piv[2]]
    for h in geo["bones"]:
        p = pivots[h["name"]]
        parent_bone = h.get("parent")
        pp = pivots.get(parent_bone, [0, 0, 0]) if parent_bone else [0, 0, 0]
        rot = h.get("rotation", [0, 0, 0])
        verts, normals, coords = [], [], []
        for cube in h.get("cubes", []):
            v, n, c = cube_mesh(cube, p, width_px, height_px)
            verts += v
            normals += n
            coords += c
        locs = {}
        for loc, pos in (h.get("locators") or {}).items():
            if isinstance(pos, dict):
                pos = pos.get("offset", [0, 0, 0])
            locs[loc] = [round(-pos[0] - p[0], 4), round(pos[1] - p[1], 4), round(pos[2] - p[2], 4)]
        bones.append({
            "name": h["name"],
            "parent": parent_bone or "",
            "pos": [round(p[i] - pp[i], 4) for i in range(3)],
            "rot": [-rot[0], -rot[1], rot[2]],
            "verts": verts, "normals": normals, "uvs": coords,
            "locators": locs,
        })
    bone_names = {h["name"] for h in bones}
    raw_anims = json.loads((folder / "anim.animation.json").read_text(encoding="utf-8"))["animations"]
    # Clips of our own, kept apart so the source's file stays untouched (Mewtwo's attacks).
    # One named like a source clip replaces it (Mewtwo's walk).
    extra = folder / "moves.animation.json"
    if extra.exists():
        raw_anims.update(json.loads(extra.read_text(encoding="utf-8"))["animations"])
    anims = {}
    for short in ANIMS:
        key_name = f"animation.{group or name_id}.{short}"
        if key_name in raw_anims:
            anims[short] = bake_animation(raw_anims[key_name], bone_names)
    dest = OUTPUT / name_id
    dest.mkdir(parents=True, exist_ok=True)
    # Compressed: the animation numbers take 8 times less space (it matters in the browser).
    (dest / "model.json").unlink(missing_ok=True)
    (dest / "model.json.gz").write_bytes(gzip.compress(json.dumps({
        "fps": FPS, "tex_w": width_px, "tex_h": height_px, "bones": bones, "anims": anims,
    }, separators=(",", ":")).encode("utf-8"), 9, mtime=0))
    # texture_flame.png: an animated layer's frames side by side (Charizard's tail flame).
    for f in ("texture.png", "texture_shiny.png", "texture_emissive.png", "texture_alpha.png", "texture_flame.png", "cry.ogg"):
        if (folder / f).exists():
            shutil.copy(folder / f, dest / f)
    print(f"{name_id}: {len(bones)} bones, animations {sorted(anims)}")


if __name__ == "__main__":
    for folder in sorted(SOURCES.iterdir()):
        if folder.is_dir():
            convert(folder.name)
