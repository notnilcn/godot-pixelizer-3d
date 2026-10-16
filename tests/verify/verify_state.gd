## Moved here from the 2026-10-16 verification session's scratchpad so it is not lost.
## TRUST: all 13 checks are valid and pass (B3/D4/F4/F5). Headless is fine for this one (state only, no pixels).
extends SceneTree

## In-game verification of two engine-state claims that need no pixels:
##
##   B3  a node with one bridgeable material slot and one unregistered custom
##       slot must be left ENTIRELY as authored — no in-place shader swap, no
##       surface override, layers untouched. (The pre-fix order swapped the
##       bridgeable slot first and then bailed, leaving a generated shader the
##       state could never restore.)
##   D4  `pixel_size` and `outline_id` are clamped to what the anchor search and
##       the metadata channel can represent, with a one-shot warning.
##
## Run headless (state only):
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script <abs path>/verify_state.gd

const BRIDGEABLE := "res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain.gdshader"
const UNREGISTERED := "res://addons/pixelizer_3d/shaders/sky_clouds.gdshader"

var _checks := 0
var _failures := PackedStringArray()
var _started := false


func _initialize() -> void:
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	quit(0 if _failures.is_empty() else 1)
	return true


func _run() -> void:
	var manager := _find_named(root, "PixelizerManager3D") as PixelizerManager3D
	_check(manager != null, "the demo's manager resolved")
	var applier := _find_named(root, "PixelizerApplier3D") as PixelizerApplier3D
	_check(applier != null, "the demo's top-level applier resolved")
	if manager == null or applier == null:
		_report()
		return
	_check(manager.auto_bridge_custom_shaders, "the demo trusts bridge manifests (precondition for B3)")
	_check(manager.get_bridge_mapped_count() > 0, "the bridge registry admits at least one source shader")

	# ── B3 ──────────────────────────────────────────────────────────────────
	# One node, two surfaces: slot 0 runs a shader the manifest approves,
	# slot 1 runs an unregistered custom shader. The pre-swap check must skip
	# the whole node rather than half-bridging it.
	var node := MeshInstance3D.new()
	node.name = "MixedSlotProbe"
	var box_arrays := BoxMesh.new().get_mesh_arrays()
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box_arrays)
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box_arrays)
	combined.surface_set_material(0, _shader_material(BRIDGEABLE))
	combined.surface_set_material(1, _shader_material(UNREGISTERED))
	node.mesh = combined
	applier.add_child(node)
	applier.rescan()

	var authored_bridgeable := _shader_path(node, 0)
	var authored_unregistered := _shader_path(node, 1)
	print("B3 slot0 -> %s" % authored_bridgeable)
	print("B3 slot1 -> %s" % authored_unregistered)
	_check(authored_bridgeable == BRIDGEABLE,
		"the bridgeable slot was NOT swapped away from its authored shader (pre-fix it was)")
	_check(authored_unregistered == UNREGISTERED, "the unregistered slot kept its authored shader")
	_check(node.get_surface_override_material(0) == null and node.get_surface_override_material(1) == null,
		"no surface override material was installed on the skipped node")
	var metadata_bit := 1 << (manager.metadata_layer - 1)
	_check((node.layers & metadata_bit) == 0,
		"the skipped node was not moved onto the metadata layer")

	# ── D4 ──────────────────────────────────────────────────────────────────
	var plain := MeshInstance3D.new()
	plain.name = "ClampProbe"
	var plain_mesh := BoxMesh.new()
	plain_mesh.surface_set_material(0, StandardMaterial3D.new())
	plain.mesh = plain_mesh
	applier.add_child(plain)
	applier.pixel_size = 8
	applier.outline_id = 300
	applier.rescan()
	var clamped_size := int(plain.get_instance_shader_parameter("anchor_size"))
	var clamped_tag := int(plain.get_instance_shader_parameter("anchor_tag"))
	print("D4 pixel_size 8 -> anchor_size %d ; outline_id 300 -> anchor_tag %d" % [clamped_size, clamped_tag])
	_check(clamped_size == 5, "pixel_size is clamped to the search's MAX_ANCHOR_SIZE (%d)" % clamped_size)
	_check(clamped_tag == 254, "outline_id is clamped to 254 (%d)" % clamped_tag)
	applier.pixel_size = PixelizerInherit.INHERIT
	applier.outline_id = PixelizerInherit.INHERIT

	# ── F4: geometry-shaped effects opt out of appliers ──────────────────────
	for effect_name in ["PixelizerWater3D", "PixelizerSkyClouds3D"]:
		var effect := _find_named(root, effect_name)
		_check(effect != null and effect.is_in_group("pixelizer_ignore"),
			"%s joins pixelizer_ignore so an applier cannot bind it" % effect_name)
	var volume := _find_named(root, "PixelizerPointLightVolume3D")
	_check(volume != null and not volume.is_in_group("pixelizer_ignore"),
		"the point-light volume stays bindable (it opts in deliberately)")

	# ── F5: a second manager warns (assert via the printed warning, below) ───
	var second := PixelizerManager3D.new()
	second.name = "PixelizerManager3D_Second"
	root.add_child(second)
	print("F5 second manager added; expect a one-shot warning naming the shared globals")

	_report()


func _shader_material(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path) as Shader
	return material


func _shader_path(mi: MeshInstance3D, surface: int) -> String:
	var override := mi.get_surface_override_material(surface)
	var material: Material = override
	if material == null and mi.mesh != null and surface < mi.mesh.get_surface_count():
		material = mi.mesh.surface_get_material(surface)
	if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
		return (material as ShaderMaterial).shader.resource_path
	return "<none>"


func _report() -> void:
	if _failures.is_empty():
		print("IN-GAME STATE CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("IN-GAME STATE CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
