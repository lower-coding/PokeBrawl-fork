class_name Hud
extends CanvasLayer
## Battle UI built from Cobblemon's battle GUI pieces, at the same pixel scale and with
## the same measurements (BattleOverlay.kt and BattleMoveSelection.kt):
##   top            each Pokémon's frame with its live portrait, HP and status
##   bottom left    the four moves on tiles tinted by type
##   above them     the player's dodges and energy
##   bottom right   the battle log
##   over the rival the lock-on arrow
## Everything is measured in GUI pixels (G) and multiplied by the integer scale _s.

const GUI := "res://gui/cobblemon/"
const TYPE_ORDER := ["normal", "fire", "water", "grass", "electric", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
const STATES := {
	"burned": ["brn", "BRN"], "poisoned": ["psn", "PSN"], "chilled": ["frz", "CHL"], "charged": ["par", "CHG"], "asleep": ["slp", "SLP"], "ko": ["fnt", "FNT"],
}
const INK := Color("f5f3ea")
const LOG_LINES := 5

var main: Node
var debug := false
var _c: Control
var _s := 3
var _tex := {}
var _font: FontFile
var _lag := [1.0, 1.0]
var _not_ready := [0.0, 0.0, 0.0, 0.0]
var _log: Array = []                 # [{text, t}]
var _log_t := 0.0
var _portraits: Array = []            # [{vp, model, cam, height, placed, t0}]
var _t := 0.0
var _dbg: MeshInstance3D
var _dbg_im := ImmediateMesh.new()


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://gui/font/pixel.fnt")
	_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	for n in ["battle/battle_info_base", "battle/battle_info_base_flipped", "battle/battle_info_underlay", "battle/battle_move",
			"battle/battle_move_overlay", "battle/battle_log", "battle/battle_log_expanded", "battle/arrow_pointer_down", "types", "types_small",
			"battle/battle_menu_fight", "summary/summary_base", "summary/summary_party_slot", "summary/portrait_background"]:
		_tex[n.get_file()] = load(GUI + n + ".png")
	for e in STATES.values():
		_tex[e[0]] = load(GUI + "battle/battle_status_%s.png" % e[0])
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_c.draw.connect(_draw_ui)
	add_child(_c)
	_dbg = MeshInstance3D.new()
	_dbg.mesh = _dbg_im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	_dbg.material_override = m
	_dbg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child.call_deferred(_dbg)


## Pause is handled by the UI, which stays alive while the game is paused.
func _unhandled_input(ev: InputEvent) -> void:
	if main.menu.is_open:
		return
	if main.paused and ev.is_action_pressed("menu_back"):
		main.back_to_menu()
		get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("pause"):
		main.toggle_pause()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- log

## Adds a line to the log. Long messages are wrapped by words.
func log_entry(text: String) -> void:
	if not _log.is_empty() and _log[-1].text == text and _t - _log[-1].t < 3.0:
		_log[-1].t = _t
		_log_t = _t
		return
	var width := 156.0 * _s
	var p := _p_log()
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if line != "" and _text_width(test, p) > width:
			_log.append({"text": line, "t": _t})
			line = word
		else:
			line = test
	_log.append({"text": line, "t": _t})
	while _log.size() > 12:
		_log.pop_front()
	_log_t = _t


func clear_log() -> void:
	_log.clear()


func warn_not_ready(i: int) -> void:
	_not_ready[i] = 0.4


# ---------------------------------------------------------------- portraits

## Each frame holds the Cobblemon model itself in a separate world, like in Cobblemon:
## a camera fixed on the face and the Pokémon in its idle animation.
func prepare_portraits(species_list: Array) -> void:
	for r in _portraits:
		r.vp.queue_free()
	_portraits.clear()
	for i in species_list.size():
		var sp: String = species_list[i]
		var data: Dictionary = Roster.POKEMON[sp]
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.size = Vector2i(28, 28) * _s
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var m := PokeModel.new()
		m.setup(sp)
		var box: AABB = m._res.mesh.get_aabb()
		var esc: float = data.height / maxf(box.size.y, 0.05)
		m.scale = Vector3.ONE * esc
		# Three-quarter view facing the center of the screen.
		m.rotation.y = PI + (0.55 if i == 0 else -0.55)
		vp.add_child(m)
		m.play("battle_idle" if m.has_anim("battle_idle") else "ground_idle", 0.0)
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.7, 0.5, 0.0)
		sun.light_energy = 1.25
		vp.add_child(sun)
		var amb := WorldEnvironment.new()
		amb.environment = Environment.new()
		amb.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		amb.environment.ambient_light_color = Color(0.85, 0.87, 0.95)
		amb.environment.ambient_light_energy = 0.75
		amb.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		vp.add_child(amb)
		_portraits.append({"vp": vp, "model": m, "cam": cam, "height": data.height, "placed": false, "t0": _t})


func _frame(r: Dictionary) -> void:
	var m: PokeModel = r.model
	# Between the face (at mouth height) and the crown: the whole head.
	var points: Array = []
	for bone in ["locator_face", "locator_head", "head"]:
		if m.skel.find_bone(bone) >= 0:
			points.append(m.bone_world(bone))
	var face := Vector3(0, r.height * 0.75, 0)
	if points.size() >= 2:
		face = (points[0] + points[1]) * 0.5
	elif points.size() == 1:
		face = points[0]
	# Head and some chest, like Cobblemon's portrait.
	var box_height: float = clampf(r.height * 0.6, 0.6, 1.4)
	var dist := box_height * 0.5 / tan(deg_to_rad(15.0))
	var looks := face - Vector3(0, box_height * 0.08, 0)
	r.cam.position = looks + Vector3(0, box_height * 0.1, dist)
	r.cam.look_at(looks)
	r.placed = true


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	_t += delta
	_s = maxi(1, int(_c.size.y / 300.0))
	for i in 4:
		_not_ready[i] = maxf(0.0, _not_ready[i] - delta)
	for i in 2:
		var l: Fighter = main.fighters[i] if i < main.fighters.size() else null
		if l:
			var f := l.hp / l.hp_max
			_lag[i] = f if f > _lag[i] else move_toward(_lag[i], f, delta * 0.35)
	for r in _portraits:
		if r.vp.size != Vector2i(28, 28) * _s:
			r.vp.size = Vector2i(28, 28) * _s
		# Framed once the animation has put the skeleton in its pose.
		if not r.placed and _t - r.t0 > 0.25:
			_frame(r)
	_c.queue_redraw()
	_debug()


# ---------------------------------------------------------------- drawing

func _p_log() -> int:
	return maxi(1, _s - 1)


func _text_width(s: String, p: int) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12 * p).x


## Text with the one-pixel shadow of Cobblemon's GUI. pos in screen pixels, top left;
## p = screen pixels per font pixel.
func _text(pos: Vector2, s: String, p: int, col := INK, align := -1) -> void:
	var x := pos.x
	if align == 0:
		x -= _text_width(s, p) * 0.5
	elif align == 1:
		x -= _text_width(s, p)
	var base := Vector2(roundf(x), roundf(pos.y) + 9 * p)
	_c.draw_string(_font, base + Vector2(p, p), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12 * p, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, col.a))
	_c.draw_string(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12 * p, col)


## A GUI piece in GUI pixels: origin, size and texture region.
func _piece(piece_id: String, g: Vector2, dims: Vector2, region := Rect2(), col := Color.WHITE) -> void:
	var t: Texture2D = _tex[piece_id]
	if region.size == Vector2.ZERO:
		region = Rect2(Vector2.ZERO, t.get_size())
	_c.draw_texture_rect_region(t, Rect2(g * _s, dims * _s), region, col)


func _rect(g: Vector2, dims: Vector2, col: Color) -> void:
	_c.draw_rect(Rect2((g * _s).round(), (dims * _s).round()), col)


func _type_icon(type: String, g: Vector2, side: float, a := 1.0) -> void:
	var i := TYPE_ORDER.find(type)
	if i < 0:
		return
	_piece("types", g, Vector2(side, side), Rect2(i * 36, 0, 36, 36), Color(1, 1, 1, a))


func _draw_ui() -> void:
	if main.menu and main.menu.is_open:
		_menu()
		return
	if main.fighters.size() < 2:
		return
	var gw: float = _c.size.x / _s
	var gh: float = _c.size.y / _s
	_frame_box(main.fighters[0], 0, Vector2(12, 10), false)
	_frame_box(main.fighters[1], 1, Vector2(gw - 12 - 140, 10), true)
	var j: Fighter = main.player
	if j:
		_moves(j, Vector2(20, gh - 62))
		_resources(j, Vector2(11, gh - 76))
	if j:
		_locked(j)
	_log_box(Vector2(gw - 169 - 12, gh - 55 - 10))
	if main.net and main.net.in_battle:
		var ms: int = main.net.ping_ms()
		var col := Color("7fd65b") if ms < 70 else (Color("ffc94a") if ms < 140 else Color("ff8a6a"))
		_text(Vector2(gw * 0.5, 8) * _s, "Ping %d ms" % ms, _p_log(), col, 0)
	if main.paused:
		_pause_menu(gw, gh)
	if debug and main.ai:
		var p := _p_log()
		var green := Color(0.6, 1.0, 0.7)
		_text(Vector2(_c.size.x - 12 * _s, 60 * _s), "AI: " + main.ai.state_text, p, green, 1)
		var r: Fighter = main.fighters[1]
		_text(Vector2(_c.size.x - 12 * _s, 60 * _s + 12 * p), "%s, %s" % [r.state, r.action.phase if r.action else "-"], p, green, 1)
		_text(Vector2(12 * _s, 60 * _s), "Player: %s, %s" % [j.state, j.action.phase if j and j.action else "-"], p, green)


## BattleOverlay frame: portrait, name, types, HP and status.
func _frame_box(l: Fighter, i: int, g: Vector2, turned: bool) -> void:
	var px := g.x + (140 - 28 - 5 if turned else 5)
	var portrait := Vector2(px, g.y + 8)
	_piece("battle_info_underlay", portrait, Vector2(28, 28))
	if i < _portraits.size():
		var vp: SubViewport = _portraits[i].vp
		_c.draw_texture_rect(vp.get_texture(), Rect2(portrait * _s, Vector2(28, 28) * _s), false)
	_piece("battle_info_base_flipped" if turned else "battle_info_base", g, Vector2(140, 40))
	var info_x := g.x + (7.0 if turned else 40.0)
	_text(Vector2(info_x, g.y + 7) * _s, tr(l.data.display_name), _s)
	# The types go where Cobblemon puts the level.
	var n: int = l.types.size()
	for k in n:
		_type_icon(l.types[n - 1 - k], Vector2(info_x + 95 - 10 * (k + 1), g.y + 6.5), 10)
	# HP: what was just lost in a light color, the current amount on top in Cobblemon's color.
	var f := clampf(l.hp / l.hp_max, 0.0, 1.0)
	var lag: float = clampf(_lag[i], 0.0, 1.0)
	var bx := info_x - 2
	var filled := 97.0
	if lag > f:
		var wl := filled * lag
		_rect(Vector2(bx + (filled - wl if turned else 0.0), g.y + 22), Vector2(wl, 4), Color(0.95, 0.93, 0.85, 0.75))
	var w := filled * f
	_rect(Vector2(bx + (filled - w if turned else 0.0), g.y + 22), Vector2(w, 4), _hp_color(f))
	_text(Vector2(info_x + (44.5 if turned else 39.5), g.y + 21.5) * _s, "%d/%d" % [ceilf(l.hp), l.hp_max], _p_log(), INK, 0)
	# Status on the tab below, only one: the one that matters most.
	var e := _state(l)
	if e != "":
		var d: Array = STATES[e]
		var ew := 37.0
		var ex := g.x + (65.0 if turned else 38.0)
		_piece(d[0], Vector2(ex, g.y + 28), Vector2(ew, 7), Rect2(0.0 if turned else 74.0 - ew, 0, ew, 7))
		_text(Vector2(g.x + (86.0 if turned else 41.0), g.y + 27.5) * _s, tr(d[1]), _p_log(), INK)


func _hp_color(f: float) -> Color:
	var r := clampf(2.0 * (1.0 - f), 0.0, 1.0)
	var v := clampf(2.0 * f, 0.0, 1.0)
	return Color(r * 0.8, v * 0.8, 0.27)


func _state(l: Fighter) -> String:
	if l.state == "ko":
		return "ko"
	if l.vulnerable > 1.0:
		return "asleep"
	if l.burned > 0.0:
		return "burned"
	if l.poisoned > 0.0:
		return "poisoned"
	if l.slow < 1.0:
		return "chilled"
	if l.static_mark > 0.0:
		return "charged"
	return ""


## BattleMoveSelection tiles: 92 × 24, tinted by type, icon straddling the left edge,
## name on top and button and cost below.
func _moves(l: Fighter, g0: Vector2) -> void:
	for i in 4:
		var move: String = l.data.moves[i]
		var d: Dictionary = Moves.DATA[move]
		var g := g0 + Vector2(0.0 if i % 2 == 0 else 92.0 + 13.0, 0.0 if i < 2 else 24.0 + 5.0)
		var ready := l.ready(move)
		var using: bool = l.action != null and l.action.id == move
		var a := 1.0 if ready or using else 0.5
		var col: Color = Roster.TYPE_COLOR.get(d.type, Color.WHITE)
		if _not_ready[i] > 0.0:
			col = col.lerp(Color(0.95, 0.3, 0.25), _not_ready[i] / 0.4)
		col.a = a
		_piece("battle_move", g, Vector2(92, 24), Rect2(0, 24 if using else 0, 92, 24), col)
		_piece("battle_move_overlay", g, Vector2(92, 24), Rect2(), Color(1, 1, 1, a))
		_type_icon(d.type, g + Vector2(-9, 2), 18, a)
		var p := _s
		if _text_width(tr(d.display_name), p) > 73 * _s:
			p = _p_log()
		_text((g + Vector2(17, 2.5 if p == _s else 4)) * _s, tr(d.display_name), p, Color(INK, a))
		var pl := _p_log()
		_text((g + Vector2(17, 14)) * _s, Controls.glyph("mov%d" % (i + 1)), pl, Color(1, 1, 1, 0.8 * a))
		var missing := l.cd(move)
		var datum := ""
		var dcol := Color("ffc94a")
		if missing > 0.0:
			datum = "%.1f" % missing
			dcol = INK
		elif d.has("uses"):
			datum = "x%d" % l.uses.get(move, d.uses)
		elif d.get("cost", 0.0) > 0.0:
			datum = "%d" % d.cost
		if datum != "":
			_text((g + Vector2(75, 14)) * _s, datum, pl, Color(dcol, a), 0)
		# Cooldown and charge: a line at the bottom of the tile.
		if missing > 0.0:
			_rect(g + Vector2(2, 21), Vector2(87 * (1.0 - missing / maxf(d.get("cd", 1.0), 0.01)), 1), Color(1, 1, 1, 0.55))
		if using and d.get("chargeable", false) and l.action.phase == "startup":
			_rect(g + Vector2(2, 21), Vector2(87 * l.action.charge, 1), INK)


## The player's dodges (diamonds) and energy, above the moves.
func _resources(l: Fighter, g: Vector2) -> void:
	var x := g.x
	var charges: int = l.data.dodge.charges
	for k in charges:
		var filled := clampf(l.charges - k, 0.0, 1.0)
		_diamond(Vector2(x + 3.5, g.y + 3.5), filled)
		x += 9
	x += 3
	_rect(Vector2(x, g.y + 1), Vector2(62, 5), Color(0.05, 0.06, 0.09, 0.85))
	_rect(Vector2(x + 1, g.y + 2), Vector2(60 * l.energy / Fighter.ENERGY_MAX, 3), Color(0.35, 0.7, 1.0))
	if l.data.has("flight"):
		x += 66
		_rect(Vector2(x, g.y + 1), Vector2(30, 5), Color(0.05, 0.06, 0.09, 0.85))
		_rect(Vector2(x + 1, g.y + 2), Vector2(28 * l.flight / float(l.data.flight.stamina), 3),
			Color(1.0, 0.62, 0.3) if l.flight > float(l.data.flight.stamina) * 0.25 else Color(0.95, 0.35, 0.25))


func _diamond(c: Vector2, filled: float) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(0, -3.5), Vector2(3.5, 0), Vector2(0, 3.5), Vector2(-3.5, 0)]:
		pts.append((c + v) * _s)
	_c.draw_colored_polygon(pts, Color(0.05, 0.06, 0.09, 0.85))
	var inside := PackedVector2Array()
	for v in [Vector2(0, -2.5), Vector2(2.5, 0), Vector2(0, 2.5), Vector2(-2.5, 0)]:
		inside.append((c + v * (1.0 if filled >= 1.0 else filled)) * _s)
	if filled > 0.0:
		_c.draw_colored_polygon(inside, INK if filled >= 1.0 else Color(INK, 0.45))


func _log_box(g: Vector2) -> void:
	var age_t := _t - _log_t
	var a := clampf(1.0 - (age_t - 7.0) / 1.0, 0.0, 1.0)
	if _log.is_empty() or a <= 0.0:
		return
	_piece("battle_log", g, Vector2(169, 55), Rect2(), Color(1, 1, 1, a))
	var p := _p_log()
	var from_pos := maxi(0, _log.size() - LOG_LINES)
	var y := g.y + 6.5
	for k in range(from_pos, _log.size()):
		_text(Vector2(g.x + 7, y) * _s, _log[k].text, p, Color(INK, a))
		y += 12.0 * p / _s - 0.5


func _locked(j: Fighter) -> void:
	var r := j.rival
	if r == null or not j.locked or r.state == "ko":
		return
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	var up: Vector3 = r.global_position + Vector3.UP * (r.data.height + 0.35)
	if cam == null or cam.is_position_behind(up):
		return
	var p := cam.unproject_position(up) / _s
	var bounce := sin(_t * TAU * 1.2) * 1.5
	_piece("arrow_pointer_down", Vector2(p.x - 8.5, p.y - 10 + bounce), Vector2(17, 10))


func _pause_menu(gw: float, gh: float) -> void:
	_c.draw_rect(Rect2(Vector2.ZERO, _c.size), Color(0.02, 0.03, 0.05, 0.55))
	var g := Vector2(floorf((gw - 169) * 0.5), floorf((gh - 101) * 0.5))
	_piece("battle_log_expanded", g, Vector2(169, 101))
	var p := _p_log()
	var lines := [
		[tr("Paused"), INK],
		[tr("%s to resume") % ("Menu" if Controls.last_device == "xbox" else ("Options" if Controls.last_device == "playstation" else "Esc")), Color(INK, 0.7)],
		["", INK],
		[tr("%s jump") % Controls.glyph("jump"), INK],
		[tr("%s dodge   %s lock on") % [Controls.glyph("dodge"), Controls.glyph("lock_on")], INK],
		[tr("%s %s %s %s moves") % [Controls.glyph("mov1"), Controls.glyph("mov2"), Controls.glyph("mov3"), Controls.glyph("mov4")], INK],
		["", INK],
		[tr("%s back to menu") % Controls.glyph("menu_back"), Color("ffc94a")],
	]
	var y := g.y + 7
	for k in lines.size():
		var ln: Array = lines[k]
		_text(Vector2(g.x + 8, y) * _s, ln[0], _s if k == 0 else p, ln[1])
		y += 12.0 * (_s if k == 0 else p) / _s


# ---------------------------------------------------------------- menu

func _wrap(text: String, width: float, p: int) -> Array:
	var lines: Array = []
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if line != "" and _text_width(test, p) > width:
			lines.append(line)
			line = word
		else:
			line = test
	lines.append(line)
	return lines


func _menu() -> void:
	main.menu.draw_ui(self)


# ---------------------------------------------------------------- debug

## Debug view (F3 / Select): hit volumes, bodies and AI state.
func _debug() -> void:
	_dbg_im.clear_surfaces()
	if not debug:
		return
	_dbg_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in main.combat.targets:
		var seg: Array = l.body()
		_circle(seg[0], l.radius(), Color(0.4, 1.0, 0.5))
		_circle(seg[1], l.radius(), Color(0.4, 1.0, 0.5))
		_line(seg[0], seg[1], Color(0.4, 1.0, 0.5))
	for g in main.combat.hits:
		if not g.active:
			continue
		var m: Transform3D = g.base()
		var col := Color(1.0, 0.3, 0.25)
		match g.shape:
			"sphere":
				_circle(m * g.center, g.radius, col)
			"capsule":
				_line(m * g.a, m * g.b, col)
				_circle(m * g.a, g.radius, col)
				_circle(m * g.b, g.radius, col)
			"cone":
				var o: Vector3 = m * g.center
				var dir: Vector3 = (m.basis * g.dir).normalized()
				_line(o, o + dir.rotated(Vector3.UP, g.angle) * g.length, col)
				_line(o, o + dir.rotated(Vector3.UP, -g.angle) * g.length, col)
				_line(o, o + dir * g.length, col)
				_line(o + dir.rotated(Vector3.UP, g.angle) * g.length, o + dir.rotated(Vector3.UP, -g.angle) * g.length, col)
			"ring":
				_circle(m * g.center, g.r_out, col, true)
				_circle(m * g.center, g.r_in, col, true)
	for p in main.combat.projectiles:
		_circle(p.pos, p.radius, Color(1.0, 0.6, 0.2))
	_dbg_im.surface_end()


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_dbg_im.surface_set_color(col)
	_dbg_im.surface_add_vertex(a)
	_dbg_im.surface_set_color(col)
	_dbg_im.surface_add_vertex(b)


func _circle(c: Vector3, r: float, col: Color, plane := false) -> void:
	var n := 20
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_line(c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r, col)
		if not plane:
			_line(c + Vector3(cos(a0), sin(a0), 0) * r, c + Vector3(cos(a1), sin(a1), 0) * r, col)
