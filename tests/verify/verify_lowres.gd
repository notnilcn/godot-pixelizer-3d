## Moved here from the 2026-10-16 verification session's scratchpad so it is not lost.
## TRUST: all 65 checks are valid and pass on the committed tree. Run windowed.
extends SceneTree

## In-game verification of the LOW_RES smooth-scroll compensation (PLAN.md C3).
##
## The claim under test: with `snap_camera` on, the snapped render plus the
## upscaler's `scroll_shift` must reproduce the *continuous* (unsnapped) camera
## for a fixed world point — i.e. the sub-texel part of camera motion is carried
## by the display shift instead of the lattice.
##
## Measured with the engine's own projection, per sample:
##   i_snapped = mirror.unproject_position(P)      (offsets applied: what renders)
##   i_cont    = mirror.unproject_position(P)      (offsets zeroed: continuous)
##   shift     = manager.get_subtexel_remainder()  (source texels, what the
##                                                  upscale shader subtracts)
## Requirement: i_snapped + shift == i_cont, on both axes.
##
## Non-vacuity: the residual must be non-trivial on some sample, and the
## pre-fix formula (`-residual` on x) must FAIL the same assertion — otherwise
## the test would pass on a broken sign.
##
## Needs a real renderer (LOW_RES renders through a SubViewport).
## Run:
##   Godot-stable_mono_win64_console.exe --path . --fixed-fps 60 \
##     --script <abs path>/verify_lowres.gd

const SETTLE := 120
const STEP_FRAMES := 4
## Camera offsets to visit, in fractions of one source texel, as
## (world X, world Z) — X drives the source x axis, Z the source y axis for this
## downward-looking rig. Both axes are swept so neither sign can hide.
const OFFSETS := [
	Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.31, 0.0), Vector2(0.5, 0.0),
	Vector2(0.67, 0.0), Vector2(0.82, 0.0), Vector2(1.0, 0.0), Vector2(1.37, 0.0),
	Vector2(2.63, 0.0), Vector2(3.41, 0.0),
	Vector2(0.0, 0.17), Vector2(0.0, 0.42), Vector2(0.0, 0.58), Vector2(0.0, 0.91),
	Vector2(0.0, 1.29), Vector2(0.0, 1.73), Vector2(0.0, 2.38),
	Vector2(0.23, 0.61), Vector2(0.44, 1.19), Vector2(0.71, 2.06),
]

var _frames := 0
var _phase := 0
var _index := 0
var _wait := 0
var _manager: PixelizerManager3D
var _camera: Camera3D
var _mirror: Camera3D
var _lowres: PixelizerLowResView
var _probe_point := Vector3.ZERO
var _base_x := 0.0
var _base_z := 0.0
var _texel := 0.0
var _results: Array = []
var _checks := 0
var _failures := PackedStringArray()


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE:
		return false
	match _phase:
		0:
			_setup()
			_phase = 1
			_wait = SETTLE + 20
		1:
			if _frames >= _wait:
				_measure()
				_index += 1
				if _index >= OFFSETS.size():
					_phase = 2
				else:
					_position_camera()
					_wait = _frames + STEP_FRAMES
		2:
			_report()
			quit(0 if _failures.is_empty() else 1)
			return true
	return false


func _setup() -> void:
	_manager = _find_manager()
	_lowres = _manager.get_lowres_view()
	# A probe-owned orthographic camera, pinned as the manager's target so
	# nothing else competes for it.
	var player := _find_named(root, "Player")
	if player != null:
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.current = false
	_camera = Camera3D.new()
	_camera.name = "LowResProbeCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 4000.0
	_camera.current = true
	root.add_child(_camera)
	_camera.global_position = Vector3(0.0, 12.0, 12.0)
	_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	_manager.set_target_camera(_camera)

	var look := _manager.get_settings()
	look.snap_camera = true
	look.lock_camera = false
	look.render_resolution = Vector2i(960, 540)
	look.texel_density = 0.5
	look.view_zoom = 1.0
	_manager.mode = PixelizerManager3D.Mode.LOW_RES
	# A fixed world point well inside the view (the character row).
	_probe_point = Vector3(8.0, 1.0, 0.0)
	_base_x = _camera.global_position.x
	_base_z = _camera.global_position.z
	_position_camera()


func _position_camera() -> void:
	var offset: Vector2 = OFFSETS[_index]
	_camera.global_position = Vector3(_base_x + offset.x * _texel, _camera.global_position.y, _base_z + offset.y * _texel)
	_camera.look_at(Vector3(_camera.global_position.x, 0.0, _camera.global_position.z), Vector3.UP)


func _measure() -> void:
	_check(_lowres != null and _lowres.is_active(), "the LOW_RES view is active")
	if _lowres == null or not _lowres.is_active():
		return
	_mirror = _lowres.get("_mirror_camera")
	_check(_mirror != null and is_instance_valid(_mirror), "the mirror camera exists")
	if _mirror == null:
		return
	if _texel <= 0.0:
		_texel = _manager.get_texel_world_size()
		_check(_texel > 0.0, "the manager reports a positive LOW_RES texel size")
		_check(absf(_manager.get_texel_world_size() - _mirror.size / float(_lowres.get("_viewport").size.y)) < 1.0e-6,
			"the reported texel comes from the mirror camera and the display viewport")
	# What renders: offsets applied (copied from the probe camera each frame).
	var i_snapped: Vector2 = _mirror.unproject_position(_probe_point)
	# What a continuous camera would show: same pose, offsets zeroed.
	var saved_h := _mirror.h_offset
	var saved_v := _mirror.v_offset
	_mirror.h_offset = 0.0
	_mirror.v_offset = 0.0
	var i_cont: Vector2 = _mirror.unproject_position(_probe_point)
	_mirror.h_offset = saved_h
	_mirror.v_offset = saved_v
	var shift: Vector2 = _manager.get_subtexel_remainder()
	# The value must actually reach the upscaler, not just exist on the manager.
	var upscale_material: ShaderMaterial = _lowres.get("_material")
	if upscale_material != null:
		var pushed = upscale_material.get_shader_parameter("scroll_shift")
		_check(pushed is Vector2 and (pushed as Vector2).is_equal_approx(shift),
			"the upscale shader received scroll_shift %s (manager says %s)" % [str(pushed), str(shift)])
	var residual := Vector2(-shift.x, shift.y)  # residual = (shift.x, -shift.y)
	_results.append({
		"i_snapped": i_snapped, "i_cont": i_cont, "shift": shift, "residual": residual,
		"compensated": i_snapped + shift,
		"buggy": Vector2(i_snapped.x - shift.x, i_snapped.y + shift.y),
	})


func _report() -> void:
	var worst_ok := 0.0
	var worst_buggy := 0.0
	var max_residual := 0.0
	for r in _results:
		var err_ok: float = maxf(absf(r["compensated"].x - r["i_cont"].x), absf(r["compensated"].y - r["i_cont"].y))
		var err_buggy: float = maxf(absf(r["buggy"].x - r["i_cont"].x), absf(r["buggy"].y - r["i_cont"].y))
		worst_ok = maxf(worst_ok, err_ok)
		worst_buggy = maxf(worst_buggy, err_buggy)
		max_residual = maxf(max_residual, maxf(absf(r["residual"].x), absf(r["residual"].y)))
		print("SAMPLE snapped=(%.3f, %.3f) cont=(%.3f, %.3f) shift=(%.4f, %.4f) | err=%.4f texels" % [
			r["i_snapped"].x, r["i_snapped"].y, r["i_cont"].x, r["i_cont"].y,
			r["shift"].x, r["shift"].y, err_ok])
	print("TEXEL %.5f world units/texel; samples=%d; max |residual| = %.3f texels" % [
		_texel, _results.size(), max_residual])

	# The identity must hold on every sample, within a small tolerance (the
	# projection is float32 and the mirror's offsets are re-copied per frame).
	_check(worst_ok < 0.02, "snapped render + scroll_shift reproduces the continuous camera (worst %.4f texels)" % worst_ok)
	# Non-vacuity: the sweep must actually produce sub-texel residuals.
	_check(max_residual > 0.2, "the sweep produced a non-trivial sub-texel residual (max %.3f)" % max_residual)
	# The pre-fix formula (`-residual` on x) must be falsified by this test.
	_check(worst_buggy > 0.2, "the pre-fix x sign FAILS the same assertion (worst %.4f texels)" % worst_buggy)

	if _failures.is_empty():
		print("LOWRES SCROLL CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("LOWRES SCROLL CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _find_manager() -> PixelizerManager3D:
	var found := _find_named(root, "PixelizerManager3D")
	return found as PixelizerManager3D


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
