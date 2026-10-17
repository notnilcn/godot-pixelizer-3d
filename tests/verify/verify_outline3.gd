## TRUST: FULL for every asserted check as of 2026-10-16 (0 px noise floor).
## The D3 exposed-rect control inks (~2100 px) while the occluded rect stays at
## 0, so the occluded 0 is not vacuous. The earlier "exposed rect 0 px" result
## is not reproducible with this file.
extends SceneTree

## In-game verification of the three outline paths with no reproduction in the
## repo (PLAN.md D1b, D2, D3).
##
## Written after three separate measurement traps were hit while building it —
## all three are probe bugs that produce plausible-looking numbers, so they are
## worth stating:
##
##   1. `root.get_texture().get_image()` returns the LAST RENDERED frame. Two
##      grabs inside one `_process` call are the SAME image, so any diff between
##      them is trivially zero. Likewise, mutating state and grabbing in the same
##      call captures the pre-mutation frame. This probe therefore alternates
##      strictly: a phase either MUTATES or CAPTURES, never both.
##   2. The demo animates far more than it looks: the cloud wind scrolls the
##      shadow field, the god-ray pass reads the wall clock, the grass billboards
##      sway, the water waves and the fireflies move — all TIME-driven. Two
##      frames of "the same" scene can differ by ~24% of the image, which makes
##      every diff meaningless. `_setup()` hides the effects container and the
##      grass planters and freezes the cloud wind and god-ray phase, and a
##      noise-floor check (two frames, both unchanged) asserts the result.
##   3. A colour predicate for "ink" cannot work on this scene: the authored
##      outline is near-black, and so is much of the shaded terrain at close
##      range (an earlier version counted 201590 "ink" px in one half). Ink is
##      therefore always measured as the DIFFERENCE the outline toggle makes,
##      never as an absolute colour.
##
## Claims:
##   D3  a non-pixelized occluder in front of pixelized geometry gets no outline
##       ink (the revert gate): with the occluder covering the left half,
##       toggling outlines on must change ~nothing there, while the pixelized
##       right half changes a lot.
##   D2  with `multiply_colors` on, rows at 0.5 are a no-op (the shader does
##       `color *= rgb * 2` with the authored value as the factor) and rows at
##       0.25 darken.
##   D1b with a material that samples `hint_normal_roughness_texture` in frame
##       (which forces the engine's normal-roughness buffer; SSAO stays off),
##       raising `outline_normal_threshold` changes the render, and the same
##       toggle WITHOUT the forcing mesh renders identically: the manager
##       requests the buffer itself (`needs_normal_roughness`) while the term
##       is on.
##
## Run (needs a real renderer):
##   Godot-stable_mono_win64_console.exe --path . --fixed-fps 60 \
##     --script <abs path>/verify_outline3.gd

const SETTLE := 150
const STEP := 8

var _frames := 0
var _phase := 0
var _wait := 0
var _manager: PixelizerManager3D
var _look: PixelizerSettings
var _camera: Camera3D
var _quad: MeshInstance3D
var _checks := 0
var _failures := PackedStringArray()
var _img_off_quad: Image
var _img_on_quad: Image
var _img_off_a: Image
var _img_off_b: Image
var _img_mult_half: Image
var _img_mult_quarter: Image
var _img_crease_off: Image
var _img_crease_on: Image
var _img_nobuf_off: Image
var _img_nobuf_on: Image
var _forcer: MeshInstance3D


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE:
		return false
	if _phase > 0 and _frames < _wait:
		return false
	match _phase:
		# 0-1: capture with outlines OFF and the occluder present
		0:
			_setup()
		# 1: capture OFF + quad
		1:
			_img_off_quad = _grab()
		# 2-3: outlines ON
		2:
			_look.default_outline_enabled = true
		# 3: capture ON + quad
		3:
			_img_on_quad = _grab()
		# 4-5: outlines OFF, occluder hidden
		4:
			_look.default_outline_enabled = false
			_quad.visible = false
		# 5: capture OFF, no quad
		5:
			_img_off_a = _grab()
		# 6: second OFF capture (noise floor)
		6:
			_img_off_b = _grab()
		# 7-8: multiply palette at 0.5, outlines ON
		7:
			_look.outline_palette = _multiply_palette(0.5)
			_look.default_outline_enabled = true
		# 8: capture
		8:
			_img_mult_half = _grab()
		# 9-10: rows at 0.25
		9:
			_look.outline_palette = _multiply_palette(0.25)
		# 10: capture
		10:
			_img_mult_quarter = _grab()
		# 11-14: the same toggle BEFORE the forcer is ever shown (no SSAO, no
		# material requesting the buffer). It must run first: once the engine
		# has allocated the buffer, the scene buffers keep it. Measured
		# Without the manager's request the buffer was allocated here anyway but
		# never written, which this order is what exposed.
		11:
			_look.outline_palette = null
			_look.outline_normal_threshold = 0.0
		12:
			_img_nobuf_off = _grab()
		13:
			_look.outline_normal_threshold = 0.6
		14:
			_img_nobuf_on = _grab()
		# 15-16: crease off with the forcing mesh (a material that samples
		# `hint_normal_roughness_texture`, which makes the engine create the
		# buffer; SSAO stays off).
		15:
			_look.outline_normal_threshold = 0.0
			_forcer.visible = true
		16:
			_img_crease_off = _grab()
		# 17-18: crease on (threshold 0.6); capture, evaluate, done
		17:
			_look.outline_normal_threshold = 0.6
		18:
			_img_crease_on = _grab()
			_evaluate()
			quit(0 if _failures.is_empty() else 1)
			return true
	_phase += 1
	if _phase > 0:
		_wait = _frames + STEP
	return false


func _setup() -> void:
	_manager = _find_named(root, "PixelizerManager3D") as PixelizerManager3D
	_look = _manager.get_settings()
	# Phase 1 captures the OFF state, so pin it here: the demo's settings
	# resource leaves the default at `true`, and an earlier version of this
	# probe never turned it off — both "off" and "on" captures were therefore
	# outlines-ON and every diff was trivially zero.
	_look.default_outline_enabled = false
	# Trap 2: everything that animates must go, or the diffs measure motion.
	var effects := _find_named(root, "PixelizerEffects")
	if effects != null:
		(effects as Node3D).visible = false
	# The god-ray PASS is not a scene node's visibility; pin its clock.
	var rays := _find_named(root, "PixelizerGodRays3D") as PixelizerGodRays3D
	if rays != null:
		rays.time_override = 0.0
	var sky := _find_named(root, "PixelizerSkyClouds3D") as PixelizerSkyClouds3D
	if sky != null:
		sky.cloud_wind = Vector2.ZERO
	var grass_hidden := 0
	for node in _find_all_with_prefix(root, "GrassPlanter"):
		(node as Node3D).visible = false
		grass_hidden += 1
	print("SETUP effects hidden=%s rays=%s sky=%s grass planters hidden=%d" % [
		str(effects != null), str(rays != null), str(sky != null), grass_hidden])
	_check(effects != null and rays != null and sky != null and grass_hidden > 0,
		"every animated source was found and neutralised")

	var player := _find_named(root, "Player")
	if player != null:
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.current = false
	_camera = Camera3D.new()
	_camera.name = "OutlineProbe3Camera"
	_camera.fov = 30.0
	_camera.current = true
	root.add_child(_camera)
	_camera.global_position = Vector3(8.0, 1.9, 7.0)
	_camera.look_at(Vector3(8.0, 1.1, 0.0), Vector3.UP)

	# The occluder: a flat magenta quad 2 units in front of the camera covering
	# the left half of the frame. A camera child, so it is outside every applier
	# and is never pixelized.
	_quad = MeshInstance3D.new()
	_quad.name = "GateProbeQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(1.05, 1.2)
	_quad.mesh = quad_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material_override = mat
	_quad.position = Vector3(-0.52, 0.0, -2.0)
	_camera.add_child(_quad)

	# Positive control for the crease term: a tiny non-pixelized quad whose
	# material samples the normal-roughness texture, in the top-right corner of
	# the frame (its own pixels are excluded from the measured rects). Its only
	# job is to make the renderer allocate the buffer; hidden by default.
	_forcer = MeshInstance3D.new()
	_forcer.name = "NormalRoughnessForcer"
	var forcer_mesh := QuadMesh.new()
	forcer_mesh.size = Vector2(0.02, 0.02)
	_forcer.mesh = forcer_mesh
	var forcer_shader := Shader.new()
	forcer_shader.code = "shader_type spatial;
render_mode unshaded;
uniform sampler2D nr : hint_normal_roughness_texture, filter_nearest;
void fragment() { ALBEDO = texture(nr, SCREEN_UV).rgb; }
"
	var forcer_mat := ShaderMaterial.new()
	forcer_mat.shader = forcer_shader
	_forcer.material_override = forcer_mat
	_forcer.position = Vector3(0.4, 0.2, -1.0)
	_forcer.visible = false
	_camera.add_child(_forcer)


func _multiply_palette(row: float) -> PixelizerOutlinePalette:
	var palette := PixelizerOutlinePalette.new()
	palette.multiply_colors = true
	for i in PixelizerOutlinePalette.ROW_COUNT:
		palette.set_entry(i, Color(row, row, row), Color(row, row, row), 1.0, 1.0)
	return palette


func _evaluate() -> void:
	if _img_off_quad == null or _img_on_quad == null or _img_off_a == null or _img_off_b == null \
			or _img_mult_half == null or _img_mult_quarter == null \
			or _img_crease_off == null or _img_crease_on == null 			or _img_nobuf_off == null or _img_nobuf_on == null:
		_check(false, "all captures succeeded")
		return
	var size := _img_off_quad.get_size()
	# The rects must sit ON the pixelized subject, not in the margin beside it:
	# an earlier version inset them from the frame edges and both fell outside
	# the character, so the "control" measured bare flat terrain (which by D1a
	# produces no ink) and reported 0 for everything. Derive them from the
	# subject's projected origin and require the occluder's edge to fall between
	# them, so the test is self-validating.
	var subject := _find_named(root, "demo").get_node_or_null("PixelizerApplier3D/Node3D/Knight") as Node3D
	_check(subject != null, "the framed subject resolved")
	if subject == null:
		return
	var subject_px: Vector2 = _camera.unproject_position(subject.global_position)
	var edge_x := float(size.x) * 0.5
	var left := Rect2i(int(subject_px.x) - 112, int(subject_px.y) - 300, 96, 260)
	var right := Rect2i(int(subject_px.x) + 16, int(subject_px.y) - 300, 96, 260)
	print("RECTS subject at %s; occluder edge at x=%.0f; left %s; right %s" % [
		str(Vector2i(subject_px)), edge_x, str(left), str(right)])
	_check(left.position.x >= 0 and right.end.x <= size.x and left.position.y >= 0 and right.end.y <= size.y,
		"both measuring rects are on screen")
	_check(float(left.end.x) <= edge_x and float(right.position.x) >= edge_x,
		"the occluder's edge falls between the two rects (left occluded, right exposed)")

	# Trap 2 validation: two frames, nothing changed, must be identical.
	var noise := _count_changed(_img_off_a, _img_off_b, Rect2i(Vector2i.ZERO, size))
	print("NOISE FLOOR (two frames, outline off, whole frame): %d px" % noise)
	_check(noise < 200, "the scene is static between compared frames (%d px)" % noise)

	# ── D3: the revert gate ─────────────────────────────────────────────────
	var occluded := _count_changed(_img_off_quad, _img_on_quad, left)
	var exposed := _count_changed(_img_off_quad, _img_on_quad, right)
	print("D3 toggle-off-vs-on: occluded rect %d px changed; exposed rect %d px changed" % [occluded, exposed])
	print("D3 whole-frame change: %d px" % _count_changed(_img_off_quad, _img_on_quad, Rect2i(Vector2i.ZERO, size)))
	_grid_report("D3", _img_off_quad, _img_on_quad)
	_check(exposed > 100, "the exposed rect inks under the toggle, so the diff is sensitive (%d px)" % exposed)
	_check(occluded < 20, "the occluding quad receives no outline ink (%d px)" % occluded)

	# ── D2: multiply compositing ────────────────────────────────────────────
	var half_same := _images_match(_img_off_a, _img_mult_half, 2)
	print("D2 rows=0.5 vs outlines-off: %s (mean luma %.4f vs %.4f)" % [
		"IDENTICAL" if half_same else "DIFFERENT", _mean_luma(_img_off_a), _mean_luma(_img_mult_half)])
	_check(half_same, "multiply rows of 0.5 are a no-op (identical to outlines off)")
	var darker := _mean_luma(_img_mult_quarter) < _mean_luma(_img_off_a) - 1.0e-5
	print("D2 rows=0.25: mean luma %.4f (off: %.4f) -> %s" % [
		_mean_luma(_img_mult_quarter), _mean_luma(_img_off_a), "darker" if darker else "not darker"])
	_check(darker, "multiply rows of 0.25 darken the inked blocks")

	# ── D1b: the crease term ────────────────────────────────────────────────
	var whole := Rect2i(Vector2i.ZERO, size)
	var crease_px := _count_changed(_img_crease_off, _img_crease_on, whole)
	print("D1b crease, forcing mesh present (SSAO off): threshold 0 vs 0.6 -> %d px changed (noise floor %d)" % [crease_px, noise])
	_check(crease_px > noise + 100, "with the normal-roughness buffer forced, raising outline_normal_threshold changes the render beyond the noise floor (%d px)" % crease_px)
	var nobuf_px := _count_changed(_img_nobuf_off, _img_nobuf_on, whole)
	print("D1b unforced (no SSAO, no requesting material): threshold 0 vs 0.6 -> %d px changed" % nobuf_px)
	# The forcer's own pixels differ between the two pairs; everything else
	# must not, i.e. the unforced buffer holds the same live normals.
	var forcer_px := _count_changed(_img_nobuf_off, _img_crease_off, whole)
	var forced_vs_unforced := _count_changed(_img_nobuf_on, _img_crease_on, whole)
	print("D1b forced vs unforced: %d px with the term on, %d px with it off (forcer quad only)" % [forced_vs_unforced, forcer_px])
	_check(forcer_px > 0, "the forcing quad is on screen (%d px)" % forcer_px)
	# Before the manager set `needs_normal_roughness`, the unforced buffer was
	# allocated but never written (uninitialised contents, ~20k px off).
	_check(forced_vs_unforced == forcer_px,
		"the crease term renders identically with and without a material forcing the buffer (%d vs %d px)" % [forced_vs_unforced, forcer_px])

	if _failures.is_empty():
		print("IN-GAME OUTLINE CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("IN-GAME OUTLINE CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


# ── helpers ─────────────────────────────────────────────────────────────────

func _grab() -> Image:
	return root.get_texture().get_image()


func _environment() -> Environment:
	var we := _find_named(root, "WorldEnvironment") as WorldEnvironment
	return we.environment if we != null else null


## Coarse 8x4 grid of changed-pixel counts, so a diff can be localised rather
## than guessed at.
func _grid_report(label: String, a: Image, b: Image) -> void:
	var size := a.get_size()
	var cols := 8
	var rows := 4
	var line := ""
	for gy in rows:
		var row := ""
		for gx in cols:
			var rect := Rect2i(
				int(float(gx) / cols * size.x), int(float(gy) / rows * size.y),
				int(float(size.x) / cols), int(float(size.y) / rows))
			row += "%7d" % _count_changed(a, b, rect)
		line += "
  " + row
	print("%s grid (8x4, changed px per cell):%s" % [label, line])


func _count_changed(a: Image, b: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, mini(a.get_height(), b.get_height()))):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, mini(a.get_width(), b.get_width()))):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > 0.02 or absf(ca.g - cb.g) > 0.02 or absf(ca.b - cb.b) > 0.02:
				count += 1
	return count


func _mean_luma(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			n += 1
	return total / maxf(float(n), 1.0)


## Tolerance is in 8-bit steps per channel: 0 = byte-identical.
func _images_match(a: Image, b: Image, tolerance: int) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var limit := float(tolerance) / 255.0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > limit or absf(ca.g - cb.g) > limit or absf(ca.b - cb.b) > limit:
				return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _find_all_with_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	if node.name.begins_with(prefix):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all_with_prefix(child, prefix))
	return out


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
