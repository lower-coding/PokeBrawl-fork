"""Sylveon's clips: every number of its walk, run and special, to adjust here.

Usage:  python tools/sylveon_walk.py
Then:   godot --path game -- --training --p1=sylveon

Cobblemon's file has no walk: its poser moves the legs in code (q.quadruped_walk(0.66, 1.4), in
QuadrupedWalkAnimation.kt: diagonal pairs swinging on a cosine). So the clips are written here into
sources/cobblemon/sylveon/moves.animation.json (edit them here, not there: each run replaces it),
which convert() merges, and only Sylveon is converted.

Angles are in degrees and distances in model pixels: one pixel is about 4 cm in the game. On x,
positive swings a leg back and tips the head down. On y, a neck ribbon's positive angle sweeps the
left one forward and the right one back. Every angle is added to the bone's rest pose; the walking
ones start from ground_idle's, so the ribbons keep their shape.
"""
import json

from convert_cobblemon import SOURCES, convert

# ---------------------------------------------------------------- the numbers

# One gait per clip. At full speed the game plays the walk up to 2.2 times faster.
WALK = {
    "cycle": 0.42,         # seconds per stride
    "swing": 27.0,         # how far each leg swings, front and back of its middle
    "lift": 26.0,          # how far the lower leg folds as it comes forward
    "bob": 0.35,           # up and down, twice per stride
    "tail": 5.0,           # side to side
    "sweep": 12.0,         # ribbons further back than in the idle
    "flutter": 7.0,        # ribbons waving; each segment further out adds more
}
RUN = {"cycle": 0.3, "swing": 42.0, "lift": 40.0, "bob": 0.7, "tail": 9.0, "sweep": 26.0, "flutter": 11.0}

RIBBON_LAG = 55.0          # delay from one ribbon segment to the next: higher makes the wave tighter
FLUTTER_GROW = 0.3         # how much more each segment waves than the one before

# Special: head up and forward, the neck ribbons sweeping ahead.
SPECIAL_LENGTH = 0.5
SPECIAL_RISE = 0.14        # when it is fully up
SPECIAL_HOLD = 0.34        # when it starts settling back
NECK_RAISE = -14.0
HEAD_RAISE = -10.0
BODY_FORWARD = -1.2
RIBBON_AHEAD = 42.0        # on the first neck ribbon segments
EAR_RIBBON_AHEAD = 20.0

# ---------------------------------------------------------------- the clips

FOLDER = SOURCES / "sylveon"
CLIPS = FOLDER / "moves.animation.json"
NECK_LEFT = [f"ribbon_neck_left{i}" if i > 1 else "ribbon_neck_left" for i in range(1, 7)]
NECK_RIGHT = [f"ribbon_neck_right{i}" if i > 1 else "ribbon_neck_right" for i in range(1, 7)]
EAR_LEFT = [f"ribbon_ear_left{i}" if i > 1 else "ribbon_ear_left" for i in range(1, 5)]
EAR_RIGHT = [f"ribbon_ear_right{i}" if i > 1 else "ribbon_ear_right" for i in range(1, 5)]
# Bone -> (which way "back" is on y, delay in its own wave).
RIBBONS = [(NECK_LEFT, -1.0, 0.0), (NECK_RIGHT, 1.0, 90.0), (EAR_LEFT, -1.0, 180.0), (EAR_RIGHT, 1.0, 270.0)]


def _idle():
    source = json.loads((FOLDER / "anim.animation.json").read_text(encoding="utf-8"))["animations"]
    return source["animation.sylveon.ground_idle"]["bones"]


def _sine(base, size, cycle, delay=0.0):
    """base plus a sine that closes on itself at the end of the clip."""
    return f"{round(base, 2)}+{round(size, 2)}*math.sin(q.anim_time*{360 / cycle:g}-{round(delay, 2)})"


def _fold(base, size, cycle, delay):
    """base plus only the rising half of a sine: a joint that bends once per stride."""
    return f"{round(base, 2)}+{round(size, 2)}*math.clamp(math.sin(q.anim_time*{360 / cycle:g}-{round(delay, 2)}),0,1)"


def _pose(idle, bone):
    return list(idle.get(bone, {}).get("rotation", [0, 0, 0]))


def gait(g):
    """Diagonal pairs, as in Cobblemon's quadruped_walk: the left front with the right hind leg."""
    idle = _idle()
    cycle = g["cycle"]
    bones = {"body": {"position": [0, _sine(idle["body"]["position"][1], g["bob"], cycle / 2), 0]}}
    # Each leg swings; 90° after it starts coming forward, its lower joint folds to clear the ground.
    for leg, lower, delay in (("front_leg_left", "elbow_left", 0.0), ("back_leg_right", "knee_right", 0.0),
                              ("front_leg_right", "elbow_right", 180.0), ("back_leg_left", "knee_left", 180.0)):
        x, y, z = _pose(idle, leg)
        bones[leg] = {"rotation": [_sine(x, g["swing"], cycle, delay), y, z]}
        x, y, z = _pose(idle, lower)
        bones[lower] = {"rotation": [_fold(x, g["lift"], cycle, delay + 90.0), y, z]}
    for i, name in enumerate(("tail", "tail2", "tail3")):
        x, y, z = _pose(idle, name)
        bones[name] = {"rotation": [x, _sine(y, g["tail"], cycle, i * 45.0), z]}
    for chain, back, delay in RIBBONS:
        for i, name in enumerate(chain):
            x, y, z = _pose(idle, name)
            sweep = g["sweep"] * back if i == 0 else 0.0
            wave = g["flutter"] * (1.0 + i * FLUTTER_GROW)
            bones[name] = {"rotation": [x, _sine(y + sweep, wave, cycle, delay + i * RIBBON_LAG), z]}
    return {"animation_length": cycle, "loop": True, "bones": bones}


def _keys(rest, peak):
    """From "rest" up to "peak", held for a moment and back."""
    return {"0.00": rest, f"{SPECIAL_RISE:.2f}": peak, f"{SPECIAL_HOLD:.2f}": peak, f"{SPECIAL_LENGTH:.2f}": rest}


def special():
    idle = _idle()
    bones = {
        "body": {"position": _keys([0, idle["body"]["position"][1], 0], [0, idle["body"]["position"][1], BODY_FORWARD])},
        "neck": {"rotation": _keys([0, 0, 0], [NECK_RAISE, 0, 0])},
        "head": {"rotation": _keys([0, 0, 0], [HEAD_RAISE, 0, 0])},
    }
    for chain, back, _delay in RIBBONS:
        ahead = RIBBON_AHEAD if chain in (NECK_LEFT, NECK_RIGHT) else EAR_RIBBON_AHEAD
        x, y, z = _pose(idle, chain[0])
        bones[chain[0]] = {"rotation": _keys([x, y, z], [x, y - ahead * back, z])}
    return {"animation_length": SPECIAL_LENGTH, "loop": False, "bones": bones}


if __name__ == "__main__":
    data = {"format_version": "1.8.0", "animations": {
        "animation.sylveon.ground_walk": gait(WALK),
        "animation.sylveon.ground_run": gait(RUN),
        "animation.sylveon.special": special(),
    }}
    CLIPS.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    convert("sylveon")
