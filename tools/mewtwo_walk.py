"""Mewtwo's floating walk: every number of its pose and motion, to adjust here.

Usage:  python tools/mewtwo_walk.py
Then:   godot --path game -- --training --p1=mewtwo

It starts from Cobblemon's walk pose, changes what the numbers below say, writes the clip into
sources/cobblemon/mewtwo/moves.animation.json (edit it here, not there: each run replaces it)
and converts only Mewtwo.

Angles are in degrees, written [x, y, z] as in Blockbench, and distances in model pixels: one
pixel is about 4 cm in the game. Every angle is added to the bone's rest pose, which is a T-pose
with the arms straight out to the sides.
"""
import json

from convert_cobblemon import SOURCES, convert

# ---------------------------------------------------------------- the numbers

# Whole body. It rotates at the hips, so the legs and the tail go with it.
LEAN = 12.0               # forward; Cobblemon's torso already adds 5, and running adds about 7 more
HEAD_LEVEL = 0.9          # how much of LEAN the head undoes: 1 keeps looking straight ahead, 0 looks down

# Right arm: crossed in front of the chest.
#   x    twists the arm along its length
#   y    negative swings it forward, positive back
#   z    negative lowers it, positive raises it
ARM_RIGHT = [0.0, -40.0, -18.0]
FOREARM_RIGHT = [0.0, -105.0, 0.0]    # y: negative bends the elbow, toward the other side of the chest
HAND_RIGHT = [5.0, 5.0, -10.0]

# Left arm: held back. The other side is a mirror: y positive swings it forward, negative back;
# z positive lowers it, negative raises it.
ARM_LEFT = [0.0, -48.0, 52.0]
FOREARM_LEFT = [0.0, 18.0, 0.0]       # y: positive bends the elbow
HAND_LEFT = [5.0, -5.0, 22.5]

# Float.
CYCLE = 3.0               # seconds of clip per bob. At full speed the game plays it 2.2 times faster
BOB = 1.5                 # how far up and down from the middle
BOB_HEIGHT = 2.75         # the middle. Keep BOB_HEIGHT - BOB above 0, or the feet can touch the floor

# Tail.
TAIL_CURL = 0.55          # 0 is Cobblemon's walk (stretched out), 1 its idle (coiled around the body)
TAIL_DROP = 10.0          # lowers the whole tail, to make up for LEAN lifting it
TAIL_SWAY = 2.4           # side to side, at the base. Each segment adds a quarter of it again
TAIL_LIFT = 1.4           # up and down, at the base. The same
TAIL_LAG = 38.0           # delay from one segment to the next: higher makes the wave tighter
TAIL_LIFT_LAG = 50.0      # delay of the up and down behind the side to side

# ---------------------------------------------------------------- the clip

FOLDER = SOURCES / "mewtwo"
CLIPS = FOLDER / "moves.animation.json"
TAIL = ["tail"] + [f"tail{i}" for i in range(2, 10)]


def _wave(base, size, delay):
    """base plus a sine that closes on itself at the end of the clip."""
    return f"{round(base, 2)}+{round(size, 2)}*math.sin(q.anim_time*{360 / CYCLE:g}-{round(delay, 2)})"


def clip():
    source = json.loads((FOLDER / "anim.animation.json").read_text(encoding="utf-8"))["animations"]
    bones = json.loads(json.dumps(source["animation.mewtwo.ground_walk"]["bones"]))
    idle = source["animation.mewtwo.ground_idle"]["bones"]
    del bones["locator_item"]     # invisible, and its 8 s bob would jump at the end of a shorter clip
    bones["body"] = {"rotation": [LEAN, 0, 0], "position": [0, _wave(BOB_HEIGHT, BOB, 0), 0]}
    bones["head"]["rotation"][0] -= LEAN * HEAD_LEVEL
    for name, pose in (("arm_right", ARM_RIGHT), ("arm_right2", FOREARM_RIGHT), ("hand_right", HAND_RIGHT),
                       ("arm_left", ARM_LEFT), ("arm_left2", FOREARM_LEFT), ("hand_left", HAND_LEFT)):
        bones[name] = {"rotation": pose}
    for i, name in enumerate(TAIL):
        walk, coil = bones[name]["rotation"], idle[name]["rotation"]
        x, y, z = (w + (c - w) * TAIL_CURL for w, c in zip(walk, coil))
        grow = 1.0 + i * 0.25
        if i == 0:
            x -= TAIL_DROP
        bones[name] = {"rotation": [_wave(x, TAIL_LIFT * grow, TAIL_LIFT_LAG + i * TAIL_LAG),
                                    _wave(y, TAIL_SWAY * grow, i * TAIL_LAG), round(z, 2)]}
    return {"animation_length": CYCLE, "loop": True, "bones": bones}


if __name__ == "__main__":
    data = json.loads(CLIPS.read_text(encoding="utf-8"))
    data["animations"]["animation.mewtwo.ground_walk"] = clip()
    CLIPS.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    convert("mewtwo")
