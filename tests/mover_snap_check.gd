extends SceneTree

## Unit check for mover-snap registration (PLAN.md D4 coverage gap).
##
## Mover snap is a vertex-stage offset, so there is no CPU transform to inspect:
## the whole observable contract is the `anchor_mover_snap` instance uniform on
## the bound geometry (declared by `anchor_macros.gdshaderinc`, read by
## `ANCHOR_VERTEX`) plus the applier's effective setting. Nothing asserted this
## before, so a regression in the registration wiring would only show up as a
## silently-unpinned mover in a scene that happens to use one.
##
## Runs headless: binding needs no renderer (the manager warns once and disables
## only the compositor passes).
##
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script res://tests/mover_snap_check.gd
## Exit 0 = all pass.

var _failures := PackedStringArray()
var _checks := 0
var _manager: PixelizerManager3D
var _applier: PixelizerApplier3D
var _mesh: MeshInstance3D
var _started := false


func _initialize() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	_manager = PixelizerManager3D.new()
	_manager.name = "PixelizerManager3D"
	scene_root.add_child(_manager)

	# Mover snap is orthographic-only; the applier reports a mismatch otherwise.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	scene_root.add_child(camera)

	# The manager resolves a sibling DirectionalLight3D in _ready and reports an
	# error when there is none; give it one so the test output stays clean.
	scene_root.add_child(DirectionalLight3D.new())

	_applier = PixelizerApplier3D.new()
	# PER_OBJECT is the default; mover snap is a silent no-op under UNIFIED.
	_applier.mover_snap = 1
	scene_root.add_child(_applier)

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.surface_set_material(0, StandardMaterial3D.new())
	_mesh.mesh = box
	_applier.add_child(_mesh)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		quit(0 if _failures.is_empty() else 1)
		return true
	return true


func _run() -> void:
	_check(_applier.manager == _manager, "the applier resolved the sibling PixelizerManager3D")
	_check(_applier.get_bound_state_count() == 1, "the applier bound the test mesh")

	# The applier's effective `mover_snap = 1` must reach the instance uniform.
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 1,
		"a mesh under an applier with mover_snap = 1 carries anchor_mover_snap = 1")

	# Turning it off re-registers as a non-mover.
	_applier.mover_snap = 0
	_applier.rescan()
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 0,
		"mover_snap = 0 clears anchor_mover_snap")

	# The manager API is the same contract, independent of the applier.
	_manager.register_mover(_mesh)
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 1,
		"manager.register_mover sets anchor_mover_snap = 1")
	_manager.unregister_mover(_mesh)
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 0,
		"manager.unregister_mover clears anchor_mover_snap")

	# A fresh scan must not resurrect the value once the setting is off.
	_applier.rescan()
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 0,
		"a rescan keeps a non-mover unregistered")

	# Unbinding restores authored state; the mover uniform is the applier's, so a
	# rescan with the setting back on must restore it.
	_applier.mover_snap = 1
	_applier.rescan()
	_check(_mesh.get_instance_shader_parameter("anchor_mover_snap") == 1,
		"re-enabling mover_snap re-registers on the next scan")

	if _failures.is_empty():
		print("MOVER SNAP CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("MOVER SNAP CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
