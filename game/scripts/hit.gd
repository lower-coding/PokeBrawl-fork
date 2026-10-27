class_name Hit
extends RefCounted
## An active hit volume. It is the only thing that deals damage: if its shape does not
## touch the rival's body (a capsule), there is no hit, whatever the effects look like.
##   sphere   center, radius
##   capsule  a, b, radius (a segment with thickness: sweeps, streams)
##   cone     origin, dir, length, angle (Flamethrower)
##   ring     center, r_in, r_out, only hits whoever touches the ground (Earthquake: jump it)
## With "local", positions are in the user's space (x right, y up, z forward) and
## follow its body; otherwise they are in world space.

var user: Node            # Fighter
var shape := "sphere"
var local := true
var center := Vector3.ZERO
var a := Vector3.ZERO
var b := Vector3.ZERO
var radius := 0.5
var dir := Vector3.FORWARD
var length := 4.0
var angle := 0.4
var r_in := 0.0
var r_out := 1.0
var ground_only := false

var damage := 50.0
var type := "normal"
var cat := "physical"
var contact := true            # close-range hit (passives like Static)
var push := 4.0                # m/s away from the attacker (or along "push_dir")
var push_dir := Vector3.ZERO   # if not zero, in the user's space
var lift := 0.0                # upward speed: launches the target
var stun := 0.3                # time unable to act
var knocks_down := false       # falls to the ground and gets up (with invulnerability)
var hitstop := 0.06            # impact pause (hitstop) on both fighters
var strength := 1              # 0 light, 1 medium, 2 heavy: sound, rumble, effects
var effect := ""               # paralyze, freeze, burn...
var interval := 0.0            # repeated hits on the same target every so often (0: only one)
var lifetime := -1.0           # seconds it lasts (-1: until removed)
var active := true
var hit_list := {}             # target id -> time of the last hit
var on_strike := Callable()    # callback(target, result)
var move_id := ""


## Shape in world space, according to where the user is now.
func base() -> Transform3D:
	if not local or user == null:
		return Transform3D.IDENTITY
	return user.body_basis()
