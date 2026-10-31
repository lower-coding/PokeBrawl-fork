extends "res://scripts/moves/dash.gd"
## Sucker Punch: a blink-fast dash that only connects while the rival winds up or runs a move
## that deals damage (Fighter.receive, "needs_attacking"). Against anyone else: "But it failed!"
## and a long, exposed recovery. A hit recovers at once, as Detect does.


func in_recovery(_delta: float) -> void:
	if landed and t >= d.recovery_on_hit:
		finish(false)
