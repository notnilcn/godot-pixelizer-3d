extends SceneTree

## Unit check for the unsupported-custom-material hint (VERIFICATION.md item 2).
##
## A node under an applier whose slot holds a custom ShaderMaterial the pipeline
## cannot convert (not registered, no approved bridge) must be left untouched AND
## produce exactly one actionable warning naming the node and the shader, even
## though `bind()` is retried by later rescans.
##
## A second node whose material opts in AFTER the first bind (the deferred
## registration every effect node uses) must be bound by the registration
## re-scan and must not be reported.
##
## Warnings are counted through an `OS.add_logger()` logger, so the test asserts
## on what the engine actually reports rather than on internal state.
##
## Runs headless: binding needs no renderer.
##
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script res://tests/unsupported_material_check.gd
## Exit 0 = all pass.

class WarningCounter:
	extends Logger
	var lines := PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			return
		var text := rationale if rationale != "" else code
		if text.contains("left unpixelized"):
			_mutex.lock()
			lines.append(text)
			_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SHADER_PATH := "res://tests/fixtures/unregistered_custom.gdshader"

var _failures := PackedStringArray()
var _checks := 0
var _counter := WarningCounter.new()
var _applier: PixelizerApplier3D
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _late_mesh: MeshInstance3D
var _late_material: ShaderMaterial
var _manager: PixelizerManager3D
var _frames := 0


func _initialize() -> void:
	OS.add_logger(_counter)
	var scene_root := Node3D.new()
	root.add_child(scene_root)

	_manager = PixelizerManager3D.new()
	_manager.name = "PixelizerManager3D"
	scene_root.add_child(_manager)
	# Orthographic so the manager's camera snap stays quiet.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	scene_root.add_child(camera)
	scene_root.add_child(DirectionalLight3D.new())

	_applier = PixelizerApplier3D.new()
	scene_root.add_child(_applier)

	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_mesh = MeshInstance3D.new()
	_mesh.name = "CustomShaded"
	var box := BoxMesh.new()
	box.surface_set_material(0, _material)
	_mesh.mesh = box
	_applier.add_child(_mesh)

	_late_material = ShaderMaterial.new()
	_late_material.shader = load(SHADER_PATH)
	_late_mesh = MeshInstance3D.new()
	_late_mesh.name = "LateOptIn"
	_late_mesh.mesh = BoxMesh.new()
	_late_mesh.material_override = _late_material
	_applier.add_child(_late_mesh)


func _process(_delta: float) -> bool:
	_frames += 1
	# The deferred opt-in, after the applier's first bind attempt.
	if _frames == 2:
		_manager.register_pixelized_material(_late_material)
	# Force retries: every rescan re-attempts the bind.
	if _frames == 5 or _frames == 10:
		_applier.rescan()
	if _frames < 20:
		return false
	_evaluate()
	OS.remove_logger(_counter)
	quit(0 if _failures.is_empty() else 1)
	return true


func _evaluate() -> void:
	_check(_counter.lines.size() == 1, "exactly one hint was logged (%d)" % _counter.lines.size())
	if not _counter.lines.is_empty():
		var line := _counter.lines[0]
		_check(line.contains("CustomShaded"), "the hint names the node")
		_check(line.contains(SHADER_PATH), "the hint names the shader")
		_check(line.contains("register_pixelized_material"), "the hint says how to opt in")
	_check(_mesh.mesh.surface_get_material(0) == _material and _material.shader.resource_path == SHADER_PATH,
		"the authored material and shader are untouched")
	_check(_mesh.get_surface_override_material(0) == null and _mesh.material_override == null,
		"no converted material was assigned")
	_check(not _mesh.get_layer_mask_value(_manager.metadata_layer), "the node did not join the metadata layer")
	_check(_late_mesh.get_layer_mask_value(_manager.metadata_layer),
		"a material registered after the first bind is bound by the re-scan")
	for line in _counter.lines:
		_check(not line.contains("LateOptIn"), "the late opt-in is not reported")
	if _failures.is_empty():
		print("UNSUPPORTED MATERIAL CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("UNSUPPORTED MATERIAL CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
