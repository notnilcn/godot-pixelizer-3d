class_name PixelizerCloudField
extends RefCounted

## The manager's cloud-shadow field: one provider builds the uniform dictionary
## (`PixelizerSkyClouds3D.build_cloud_params`), which is then pushed to every
## registered cloud consumer (MST terrain, water, the sky deck, custom shaders).
## With no provider the field is neutral (`clouds_enabled = false`) so consumers
## never read stale uniforms.

var manager: PixelizerManager3D
## Duck-typed provider: any Object with `build_cloud_params(sun) -> Dictionary`.
var _provider: Object = null
var _params: Dictionary = {}
var _signature := 0
var _dirty := true
## Materials that receive the cloud field, keyed by instance id. Pruned when a
## material is freed.
var _materials: Dictionary = {}


## Register a cloud field provider. `provider` is any Object with a
## `build_cloud_params(sun: DirectionalLight3D) -> Dictionary` method. Passing a
## provider replaces any previous one.
func register_provider(provider: Object) -> void:
	if provider == null or not provider.has_method("build_cloud_params"):
		return
	_provider = provider
	_dirty = true
	_push_all()


func unregister_provider(provider: Object) -> void:
	if provider == null or _provider != provider:
		return
	_provider = null
	_dirty = true


## Register a ShaderMaterial that includes `cloud_fbm.gdshaderinc` (MST terrain,
## water, the deck). Safe to call repeatedly.
func register_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	_materials[material.get_instance_id()] = material
	if _params.is_empty():
		_params = _build()
	_push_to(material)


func unregister_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	# A pixelized material keeps receiving the cloud field even if its explicit
	# cloud registration is dropped (the macros include the toolkit).
	if material.has_meta(&"pixelizer_opt_in"):
		return
	_materials.erase(material.get_instance_id())


## The current cloud-field uniform dictionary, built from the provider (neutral
## defaults when none). Non-material consumers (the god-ray pass) pull this.
func get_params() -> Dictionary:
	if _params.is_empty():
		_params = _build()
	return _params


## Per-frame rebuild/push. Pushes only when the provider dictionary changed (or
## a provider change marked the field dirty).
func update() -> void:
	var params := _build()
	var signature := params.hash()
	if not _dirty and signature == _signature:
		return
	_dirty = false
	_signature = signature
	_params = params
	_push_all()


func _build() -> Dictionary:
	if _provider != null and is_instance_valid(_provider) and _provider.has_method("build_cloud_params"):
		var result = _provider.call("build_cloud_params", manager.sun)
		if result is Dictionary:
			return result
	return _neutral()


## Neutral param set: clouds off, but every shader-contract key present so no
## consumer reads a stale value.
func _neutral() -> Dictionary:
	var sun_dir := Vector3(0.0, -1.0, 0.0)
	if manager.sun != null and is_instance_valid(manager.sun):
		sun_dir = -manager.sun.global_transform.basis.z.normalized()
	return {
		"clouds_enabled": false,
		"cloud_noise": null,
		"cloud_sun_dir": sun_dir,
		"cloud_height": 400.0,
		"cloud_noise_scale": 0.0015,
		"cloud_threshold": 0.6,
		"cloud_bands": 3.0,
		"cloud_tightness": 1.0,
		"cloud_octave_drop": 0.5,
		"cloud_gap_erosion": 0.0,
		"cloud_detail_strength": 0.0,
		"cloud_wind": Vector2(0.01, 0.004),
		"cloud_shadow_strength": 0.0,
		"cloud_shadow_banding_enabled": true,
		"cloud_shadow_levels": 3.0,
		"cloud_shadow_softness": 0.35,
	}


func _push_all() -> void:
	if _params.is_empty():
		_params = _build()
	manager.get_material_factory().set_cloud_params(_params)
	_prune()
	for material in _materials.values():
		_push_to(material)


func _push_to(material) -> void:
	if not (material is ShaderMaterial):
		return
	for key in _params:
		(material as ShaderMaterial).set_shader_parameter(key, _params[key])


## Drop entries whose material has been freed, so the list cannot grow without
## bound across runtime material swaps.
func _prune() -> void:
	var dead: Array = []
	for id in _materials:
		if not is_instance_valid(_materials[id]):
			dead.append(id)
	for id in dead:
		_materials.erase(id)
