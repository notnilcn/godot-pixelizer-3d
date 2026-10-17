extends SceneTree

## Unit check for B1's repaired branch (VERIFICATION.md item 4): a bind that
## SUCCEEDS and swapped a bridge shader must arm the applier's watchdog, so a
## material the owning system replaces afterwards is bridged too — without a
## rescan.
##
## The demo never reaches this branch (its MST chunks are mesh-less at first
## bind, so the older failed-bind path arms the watchdog instead). Here the
## bridged material exists at first bind, and the mesh is replaced afterwards
## with a fresh material on another approved source shader — the same thing
## MST's runtime texture baker does to every chunk.
##
## Runs headless against the production manifest (no renderer needed: a bridge
## swap is an in-place `material.shader` assignment).
##
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . --fixed-fps 60 \
##     --script res://tests/bridge_watchdog_check.gd
## Exit 0 = all pass.

const MANIFEST := "res://pixelizer_bridges/pixelizer_bridge_manifest.tres"
const FIRST_SOURCE := "res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain.gdshader"
const LATER_SOURCE := "res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain_baked.gdshader"
const BRIDGE_DIR := "res://pixelizer_bridges/"

var _failures := PackedStringArray()
var _checks := 0
var _applier: PixelizerApplier3D
var _mesh: MeshInstance3D
var _later: ShaderMaterial
## Negative control: the same flow with the watch entry removed after the first
## bind, so a pass cannot come from some other path re-binding the mesh.
var _control_applier: PixelizerApplier3D
var _control_mesh: MeshInstance3D
var _control_later: ShaderMaterial
var _frames := 0


func _initialize() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	var manager := PixelizerManager3D.new()
	manager.name = "PixelizerManager3D"
	manager.bridge_manifests = [load(MANIFEST)]
	manager.auto_bridge_custom_shaders = true
	scene_root.add_child(manager)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	scene_root.add_child(camera)
	scene_root.add_child(DirectionalLight3D.new())

	_applier = PixelizerApplier3D.new()
	scene_root.add_child(_applier)

	_mesh = MeshInstance3D.new()
	_mesh.name = "BridgedAtFirstBind"
	_mesh.mesh = _box_with(_shader_material(FIRST_SOURCE))
	_applier.add_child(_mesh)

	_control_applier = PixelizerApplier3D.new()
	scene_root.add_child(_control_applier)
	_control_mesh = MeshInstance3D.new()
	_control_mesh.name = "UnwatchedControl"
	_control_mesh.mesh = _box_with(_shader_material(FIRST_SOURCE))
	_control_applier.add_child(_control_mesh)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_assert_first_bind()
		# The owning system replaces the rendered material after the bind. No
		# rescan is requested: only the watchdog can pick this up.
		_later = _shader_material(LATER_SOURCE)
		_mesh.mesh = _box_with(_later)
		(_control_applier.get("_watch_ids") as Dictionary).erase(_control_mesh.get_instance_id())
		_control_later = _shader_material(LATER_SOURCE)
		_control_mesh.mesh = _box_with(_control_later)
	if _frames < 60:
		return false
	_assert_replacement()
	_report()
	quit(0 if _failures.is_empty() else 1)
	return true


func _assert_first_bind() -> void:
	var state: PixelizerGeometryState = (_applier.get("_states") as Dictionary).get(_mesh.get_instance_id())
	_check(state != null and state.is_applied(), "the first bind succeeded")
	_check(state != null and state.bridge_swapped(), "the first bind swapped a bridge shader")
	_check(_shader_path(_mesh.mesh.surface_get_material(0)).begins_with(BRIDGE_DIR),
		"the authored material runs the generated bridge (%s)" % _shader_path(_mesh.mesh.surface_get_material(0)))
	_check((_applier.get("_watch_ids") as Dictionary).has(_mesh.get_instance_id()),
		"a successful bind that swapped arms the watchdog (the B1 branch)")


func _assert_replacement() -> void:
	var path := _shader_path(_later)
	_check(path.begins_with(BRIDGE_DIR) and path.ends_with("mst_terrain_baked.gdshader"),
		"the replacement material was bridged by the watchdog, without a rescan (%s)" % path)
	_check(_shader_path(_control_later) == LATER_SOURCE,
		"control: with the watch entry removed the replacement stays unbridged (%s)" % _shader_path(_control_later))


func _shader_material(source: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(source)
	return material


func _box_with(material: Material) -> BoxMesh:
	var box := BoxMesh.new()
	box.surface_set_material(0, material)
	return box


func _shader_path(material: Material) -> String:
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		return (material as ShaderMaterial).shader.resource_path
	return ""


func _report() -> void:
	if _failures.is_empty():
		print("BRIDGE WATCHDOG CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("BRIDGE WATCHDOG CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
