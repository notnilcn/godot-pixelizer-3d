@tool
class_name PixelizerWater3D
extends MeshInstance3D

## Opaque water tile for the Pixelizer3D demo. Builds a subdivided PlaneMesh
## with `water.gdshader`, drives the instance uniforms `coast` / `wave_phase`,
## and registers the material with the manager so the cloud-shadow uniforms
## follow the rest of the scene.
##
## Tiles can share one ShaderMaterial (`shared_material`), which is how a demo
## grid gets a coastline: every tile varies only its instance-uniform `coast`.
##
## Water must stay OPAQUE (see water.gdshader) — never add transparency here.

const SHADER_PATH := "res://addons/pixelizer_3d/shaders/water.gdshader"

## Manager whose cloud parameters drive the shadow receiver. Looked up from the
## "pixelizer_manager" group when unset.
@export var manager: PixelizerManager3D
## Optional material shared by many tiles. When null, a private material is
## created from water.gdshader (noise generated if unset).
@export var shared_material: ShaderMaterial
## Tile edge length in world units.
@export var size := 4.0
## Plane subdivisions (vertex waves need a few).
@export_range(1, 64) var subdivisions := 16
## 1.0 = shallow / coast, 0.0 = deep water.
@export_range(0.0, 1.0) var coast := 1.0
## Per-tile animation offset (vertex waves + normal scroll).
@export var wave_phase := 0.0
## Noise texture for foam/whitecaps. Generated (Perlin, seed 3) when unset.
@export var noise: Texture2D

var _material: ShaderMaterial
## One generated noise shared by every non-`shared_material` tile (a 256²
## seamless Perlin per tile would be wasteful).
static var _shared_noise: Texture2D


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane

	if shared_material != null:
		_material = shared_material
	else:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	material_override = _material
	if _material.get_shader_parameter("water_noise") == null:
		_material.set_shader_parameter("water_noise", noise if noise != null else _make_noise())

	set_instance_shader_parameter("coast", coast)
	set_instance_shader_parameter("wave_phase", wave_phase)

	# Deferred: an owning PixelizerApplier3D may create the manager in its own
	# `_ready`, which runs after this node's.
	call_deferred("_register_material")


func _register_material() -> void:
	if Engine.is_editor_hint() and not _editor_preview():
		return
	if _material == null:
		return
	if manager == null:
		manager = PixelizerManager3D.resolve_manager_explicit(self)
	if manager != null:
		manager.register_cloud_material(_material)
	else:
		push_error("Pixelizer3D: PixelizerWater3D at '%s' found no PixelizerManager3D; the water is not a cloud receiver." % get_path())


func _editor_preview() -> bool:
	return manager != null and is_instance_valid(manager) and manager.editor_preview


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if PixelizerManager3D.resolve_manager_explicit(self) == null:
		warnings.append("No PixelizerManager3D resolved; water is not registered as a cloud receiver.")
	return warnings


func _exit_tree() -> void:
	if manager != null and is_instance_valid(manager) and _material != null:
		manager.unregister_cloud_material(_material)


func _make_noise() -> Texture2D:
	if _shared_noise != null:
		return _shared_noise
	var fast_noise := FastNoiseLite.new()
	fast_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	fast_noise.frequency = 0.05
	fast_noise.seed = 3
	_shared_noise = ImageTexture.create_from_image(fast_noise.get_seamless_image(256, 256))
	return _shared_noise
