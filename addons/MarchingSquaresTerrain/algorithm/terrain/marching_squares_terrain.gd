@tool
extends Node3D
class_name MarchingSquaresTerrain


signal chunk_dimensions_changed (value : Vector3i)

enum StorageMode {
	## Saves load time. Loads a pre-built visual mesh from disk.
	## The collision mesh, grass etc. are generated when the scene loads.
	## (faster load, slightly larger files).
	BAKED,
	## Saves disk space. Generates everything from heightmaps when the scene loads.
	## This is overkill for most games.
	## (slower load, smallest files).
	RUNTIME,
}

enum GridType {SQUARE, TRIANGLE, HEX}
signal grid_type_changed (value : GridType)

@export_category("Storage Options")
## The storage mode for terrain data. 
@export var storage_mode : StorageMode = StorageMode.BAKED:
	set(value):
		if storage_mode != value:
			storage_mode = value
			# Mark all chunks dirty to force re-save of data/meshes
			if chunks:
				for chunk in chunks.values():
					chunk.mark_dirty()
			print_verbose("[MST] Storage mode changed. All chunks marked for save.")
		notify_property_list_changed()

## If true, storage will include grass data, ignored if storage_mode = RUNTIME
@export var bake_grass : bool = true:
	set(value):
		bake_grass = value
		for chunk in chunks.values():
			chunk.mark_dirty()

## If true, storage will include collision data, ignored if storage_mode = RUNTIME
@export var bake_collision : bool = true:
	set(value):
		bake_collision = value
		for chunk in chunks.values():
			chunk.mark_dirty()

## The folder where this terrain's data is saved. 
## If left empty, it automatically fills with a folder name relative to your scene file.
## Note: Manually setting a path locks the save location even if you rename the terrain node later.
@export_dir var data_directory : String = "":
	get():
		if EngineWrapper.is_editor() and data_directory.is_empty():
			var auto_path := MSTDataHandler.generate_data_directory(self)
			if not auto_path.is_empty():
				data_directory = auto_path
		return data_directory

@export_category("Runtime Baking")
## If this option is true, the textures will be baked into a texture atlas
## at runtime. This will improve rendering performance, but increase cost of generation
## slightly.
@export var enable_runtime_texture_baking : bool = true

## The resolution used per polygon when baking the texture atlas. Increase this value
## when using high-res textures. Higher values increase the baking time and memory usage.
@export var polygon_texture_resolution : int = 32

## Used for overriding the material of the baked terrain texture.
@export var bake_material_override : Material

## True after external storage has been initialized.
## Used to detect when migration from embedded data is needed.
@export_storage var _storage_initialized : bool = false

## Tracks the mode used during the last successful save for reporting purposes.
@export_storage var _last_storage_mode : StorageMode = StorageMode.BAKED

#region global terrain settings
# Terrain Settings
## The cell grid used by this terrain. Square keeps the original
## marching-squares behavior; Triangle and Hexagon use per-cell columns.
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var grid_type : GridType = GridType.SQUARE:
	get:
		return _grid_type
	set(value):
		if _grid_type == value:
			return
		_switch_grid_type(value)
var _grid_type : GridType = GridType.SQUARE
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
		if EngineWrapper.is_editor():
			emit_signal("chunk_dimensions_changed", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2.0, 2.0): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
		grass_size = grass_size
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var blend_mode : int = 0:
	set(value):
		blend_mode = value
		if value == 1 or value == 2:
			terrain_material.set_shader_parameter("use_hard_textures", true)
		else:
			terrain_material.set_shader_parameter("use_hard_textures", false)
		terrain_material.set_shader_parameter("blend_mode", value)
		for chunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int = 9:
	set(value):
		extra_collision_layer = value
		for chunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold: float = 1.0:
	set(value):
		ridge_threshold = value
		terrain_material.set_shader_parameter("ridge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold: float = 1.0:
	set(value):
		ledge_threshold = value
		terrain_material.set_shader_parameter("ledge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture: bool = true:
	set(value):
		use_ridge_texture = value
		terrain_material.set_shader_parameter("use_ridge_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ledge_texture: bool = true:
	set(value):
		use_ledge_texture = value
		terrain_material.set_shader_parameter("use_ledge_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise # used to generate smooth initial heights for more natrual looking terrain. if null, initial terrain will be flat

# Grass settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var animation_fps : int = 0:
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("fps", clamp(value, 0, 30))
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_subdivisions : int = 3:
	set(value):
		grass_subdivisions = value
		_update_square_grass_subdivisions()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		var scale_factor := (cell_size.x + cell_size.y) / 4.0
		var scaled_value := value * scale_factor
		_apply_square_grass_scale(scaled_value)
#endregion

#region vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_1 : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		texture_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_1:
				grass_mat.set_shader_parameter("use_base_color_1", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_1", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		texture_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_2:
				grass_mat.set_shader_parameter("use_base_color_2", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_2", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		texture_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rb", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_3:
				grass_mat.set_shader_parameter("use_base_color_3", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_3", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		texture_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ra", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_4:
				grass_mat.set_shader_parameter("use_base_color_4", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_4", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		texture_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_5:
				grass_mat.set_shader_parameter("use_base_color_5", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_5", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = preload("uid://cv87twjgbqq0s"):
	set(value):
		texture_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_6:
				grass_mat.set_shader_parameter("use_base_color_6", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_6", true)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gb", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ga", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_br", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bg", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bb", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ba", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ar", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ag", value)
			_regenerate_square_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ab", value)
			_regenerate_square_grass()
#endregion

#region grass textures
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_1 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_1 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_6", value)
#endregion

#region has grass variables
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_6", value)
#endregion

#region texture albedos
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_1 : Color = Color("647851ff"):
	set(value):
		texture_albedo_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_1", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_2 : Color = Color("527b62ff"):
	set(value):
		texture_albedo_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_2", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_3 : Color = Color("5f6c4bff"):
	set(value):
		texture_albedo_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_3", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_4 : Color = Color("647941ff"):
	set(value):
		texture_albedo_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_4", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_5 : Color = Color("4a7e5dff"):
	set(value):
		texture_albedo_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_5", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_albedo_6 : Color = Color("71725dff"):
	set(value):
		texture_albedo_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_albedo_6", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_6", value)
#endregion

#region texture scales
# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_7", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_8", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_9", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_10", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_11", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_12", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_13", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_14", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_15", value)
#endregion

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int = 5

signal load_finished

var void_texture := preload("uid://csvthlqhb8g5j")
var placeholder_wind_texture := preload("uid://dk1t5hy2tiil7") # Change to your own texture
var placeholder_rl_noise_texture := preload("uid://85iqlmnoua0e") # Change to your own texture

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null 

var is_batch_updating : bool = false

var chunks : Dictionary = {}


func _validate_property(property: Dictionary) -> void:
	if property.name in ["bake_grass", "bake_collision"]:
		if storage_mode != StorageMode.BAKED:
			property.usage = PROPERTY_USAGE_NO_EDITOR


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("uid://bahbybbjwkhlg").duplicate(true)
	var base_grass_mesh := preload("uid://h41fuxldpf1u")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)
	print_verbose("Last storage mode: ", _last_storage_mode)


func _notification(what: int) -> void:
	# Save all dirty chunks to external storage before scene save
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if EngineWrapper.is_editor():
			MSTDataHandler.save_all_chunks(self)


func _enter_tree() -> void:
	_deferred_enter_tree.call_deferred()


func _initialize_data_directory() -> void:
	var copy_from_dir := ""
	if EngineWrapper.is_editor() and not data_directory.is_empty() and not MSTDataHandler.is_data_directory_unique(self):
		copy_from_dir = data_directory
		data_directory = ""
	
	if EngineWrapper.is_editor() and (data_directory.is_empty()):
		var auto_path := MSTDataHandler.generate_data_directory(self)
		if not auto_path.is_empty():
			data_directory = auto_path
	if copy_from_dir:
		MSTDataHandler.copy_recursive(copy_from_dir, data_directory)


func _deferred_enter_tree() -> void:
	_initialize_data_directory()
	
	print_verbose("Terrain data dir: ", data_directory)
	
	# Populate chunks dictionary from scene children
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunkBase:
			if chunk._data_dirty:
				return
	chunks.clear()
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunkBase:
			chunks[chunk.chunk_coords] = chunk
			chunk.terrain_system = self
			if chunk is MarchingSquaresTerrainChunk or chunk is MarchingSquaresCellChunk:
				chunk.grass_planter = null
	
	# Load external data if storage was previously initialized
	if _storage_initialized:
		MSTDataHandler.load_terrain_data(self)
	elif EngineWrapper.is_editor() and MSTDataHandler.needs_migration(self):
		# Auto-migrate embedded data to external storage (editor only)
		MSTDataHandler.migrate_to_external_storage(self)
	
	# Initialize all chunks (regenerate mesh/grass from loaded data)
	for chunk in chunks.values():
		chunk.initialize_terrain(true)
		
	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	force_batch_update()
	grass_size = grass_size
	
	load_finished.emit()


func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


## Create the chunk node matching the current grid type.
func make_chunk() -> MarchingSquaresTerrainChunkBase:
	match grid_type:
		GridType.TRIANGLE:
			return MarchingSquaresTriChunk.new()
		GridType.HEX:
			return MarchingSquaresHexChunk.new()
		_:
			return MarchingSquaresTerrainChunk.new()


## Cell counts per chunk for cell modes. Square mode returns Vector2i.ZERO.
func cells_per_chunk() -> Vector2i:
	if grid_type == GridType.TRIANGLE:
		return Vector2i(2 * dimensions.x, dimensions.z)
	if grid_type == GridType.HEX:
		return Vector2i(dimensions.x, dimensions.z)
	return Vector2i.ZERO


## Resolve the chunk owning a global cell for cell modes.
func chunk_for_cell(global_cell: Vector2i) -> MarchingSquaresTerrainChunkBase:
	var cells := cells_per_chunk()
	if cells == Vector2i.ZERO:
		return null
	var cc := MarchingSquaresHexGrid.chunk_of_cell(global_cell, cells)
	return chunks.get(cc)


## Height of a global cell for cell modes. Returns null when the cell's chunk
## does not exist (used to skip walls at terrain borders).
func get_cell_height(global_cell: Vector2i) -> Variant:
	var chunk = chunk_for_cell(global_cell)
	if chunk == null:
		return null
	return chunk.get_height(MarchingSquaresHexGrid.local_cell(global_cell, cells_per_chunk()))


## Whether a global cell is smoothed (bridge-sloped) for cell modes.
func get_cell_smooth(global_cell: Vector2i) -> bool:
	var chunk = chunk_for_cell(global_cell)
	if chunk == null:
		return false
	return chunk.get_smooth(MarchingSquaresHexGrid.local_cell(global_cell, cells_per_chunk()))


## World-space origin position of a cell chunk node.
func cell_chunk_position(coords: Vector2i) -> Vector3:
	var cells := cells_per_chunk()
	if grid_type == GridType.TRIANGLE:
		var p := MarchingSquaresTriGrid.lattice_point(
			coords.x * dimensions.x, coords.y * dimensions.z, cell_size)
		return Vector3(p.x, 0, p.y)
	elif grid_type == GridType.HEX:
		var p := MarchingSquaresHexGrid.cell_center(coords * cells, MarchingSquaresHexGrid.spacing_for(cell_size))
		return Vector3(p.x, 0, p.y)
	return Vector3.ZERO


## Switch grid modes: save, flush, reload. No undo support for mode switches.
func _switch_grid_type(value: GridType):
	if EngineWrapper.is_editor():
		MSTDataHandler.save_all_chunks(self)
	
	# Free all chunks without re-saving them. remove_child + free is immediate so
	# mode switches can save/load several modes within the same frame.
	for child in get_children():
		if child is MarchingSquaresTerrainChunkBase:
			child._skip_save_on_exit = true
			child.owner = null
			remove_child(child)
			child.free()
	chunks.clear()
	
	_grid_type = value
	force_batch_update()
	grid_type_changed.emit(value)
	
	# Mode switches clear undo history (scene-relative setup changed)
	var plugin := MarchingSquaresTerrainPlugin.instance
	if plugin:
		var undo_redo := plugin.get_undo_redo()
		if undo_redo:
			undo_redo.clear_history(false)
	
	if EngineWrapper.is_editor():
		MSTDataHandler.load_terrain_data(self)
		EditorInterface.mark_scene_as_unsaved()
		set_deferred("_deferred_rebuild_chunks", true)


func _deferred_rebuild_chunks(_unused: bool) -> void:
	for chunk in chunks.values():
		chunk.initialize_terrain(true)


func add_new_chunk(chunk_x: int, chunk_z: int, plugin):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := make_chunk()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.terrain_system = self
	new_chunk.mark_dirty()
	add_chunk(chunk_coords, new_chunk, plugin, false)
	
	if grid_type != GridType.SQUARE:
		# Cell modes: no border heights to copy. Regenerate neighbours so their
		# walls face the new chunk.
		for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var neighbor = chunks.get(chunk_coords + offset)
			if neighbor:
				neighbor.regenerate_mesh()
		new_chunk.regenerate_mesh()
		return
	
	var chunk_left : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left:
		for z in range(0, dimensions.z):
			new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right:
		for z in range(0, dimensions.z):
			chunk_right.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up:
		for x in range(0, dimensions.x):
			new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down:
		for x in range(0, dimensions.x):
			new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]
	
	new_chunk.regenerate_mesh()


func remove_chunk(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunkBase = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk.free()
	
	if grid_type != GridType.SQUARE:
		_regenerate_neighbor_chunks(chunk_coords)
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunkBase:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunkBase = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null
	
	if grid_type != GridType.SQUARE:
		_regenerate_neighbor_chunks(chunk_coords)
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunkBase:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


func _regenerate_neighbor_chunks(chunk_coords: Vector2i) -> void:
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var neighbor = chunks.get(chunk_coords + offset)
		if neighbor:
			neighbor.regenerate_mesh()


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunkBase, plugin, regenerate_mesh: bool = true):
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	add_child(chunk)
	chunks[coords] = chunk
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors
	# when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	if grid_type == GridType.SQUARE:
		chunk.position = Vector3(
			coords.x * ((dimensions.x - 1) * cell_size.x),
			0,
			coords.y * ((dimensions.z - 1) * cell_size.y)
		)
	else:
		chunk.position = cell_chunk_position(coords)
	
	EngineWrapper.set_owner_recursive(chunk)
	chunk.initialize_terrain(regenerate_mesh)
	print_verbose("[MST] Added new chunk to terrain system at ", chunk)
	if plugin:
		if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == Vector2i(99999, 99999):
			plugin.selected_chunk = chunk
		plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
		plugin.gizmo_plugin.trigger_redraw(self)

#region grass helpers (all grid types)

## Regenerate grass for every chunk in this terrain.
func _regenerate_square_grass() -> void:
	for chunk in chunks.values():
		if chunk is MarchingSquaresTerrainChunk:
			chunk.grass_planter.regenerate_all_cells()
		elif chunk is MarchingSquaresCellChunk:
			chunk.grass_planter.regenerate_all_cells()


## Update grass subdivision counts and regenerate grass for every chunk.
func _update_square_grass_subdivisions() -> void:
	for chunk in chunks.values():
		if chunk is MarchingSquaresTerrainChunk:
			chunk.grass_planter.multimesh.instance_count = (dimensions.x - 1) * (dimensions.z - 1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
		elif chunk is MarchingSquaresCellChunk:
			var cells : Vector2i = chunk.cells_per_chunk()
			chunk.grass_planter.multimesh.instance_count = cells.x * cells.y * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()


## Apply the scaled grass size to every chunk.
func _apply_square_grass_scale(scaled_value: Vector2) -> void:
	for chunk in chunks.values():
		if chunk is MarchingSquaresTerrainChunk:
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0
		elif chunk is MarchingSquaresCellChunk:
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0

#endregion grass helpers

#region texture (set) functions

# WARNING: this function is currently not being used anymore. [Q] YÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â«gen: was that intentional?
# This (legacy) function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	if not grass_mat.get_shader_parameter("use_base_color_1") and terrain_material.get_shader_parameter("vc_tex_rr") == null:
		terrain_material.set_shader_parameter("vc_tex_rr", texture_1)
	if not grass_mat.get_shader_parameter("use_base_color_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if not grass_mat.get_shader_parameter("use_base_color_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if not grass_mat.get_shader_parameter("use_base_color_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if not grass_mat.get_shader_parameter("use_base_color_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if not grass_mat.get_shader_parameter("use_base_color_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	
	if grass_mat.get_shader_parameter("use_grass_tex_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if grass_mat.get_shader_parameter("use_grass_tex_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if grass_mat.get_shader_parameter("use_grass_tex_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if grass_mat.get_shader_parameter("use_grass_tex_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if grass_mat.get_shader_parameter("use_grass_tex_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	
	if grass_sprite_tex_1 and grass_mat.get_shader_parameter("grass_texture_1") == null:
		grass_mat.set_shader_parameter("grass_texture_1", grass_sprite_tex_1)
	if grass_sprite_tex_2 and grass_mat.get_shader_parameter("grass_texture_2") == null:
		grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	if grass_sprite_tex_3 and grass_mat.get_shader_parameter("grass_texture_3") == null:
		grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	if grass_sprite_tex_4 and grass_mat.get_shader_parameter("grass_texture_4") == null:
		grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	if grass_sprite_tex_5 and grass_mat.get_shader_parameter("grass_texture_5") == null:
		grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	if grass_sprite_tex_6 and grass_mat.get_shader_parameter("grass_texture_6") == null:
		grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	if terrain_material.get_shader_parameter("vc_tex_aa") == null:
		terrain_material.set_shader_parameter("vc_tex_aa", void_texture)
	
	if grass_mat.get_shader_parameter("wind_texture") == null:
		grass_mat.set_shader_parameter("wind_texture", placeholder_wind_texture)
	if terrain_material.get_shader_parameter("rl_noise_texture") == null:
		terrain_material.set_shader_parameter("rl_noise_texture", placeholder_rl_noise_texture)


## Applies all shader parameters and regenerates grass once
## Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("chunk_size", dimensions)
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Ground Textures
	terrain_material.set_shader_parameter("vc_tex_rr", texture_1)
	terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	terrain_material.set_shader_parameter("vc_tex_gb", texture_7)
	terrain_material.set_shader_parameter("vc_tex_ga", texture_8)
	terrain_material.set_shader_parameter("vc_tex_br", texture_9)
	terrain_material.set_shader_parameter("vc_tex_bg", texture_10)
	terrain_material.set_shader_parameter("vc_tex_bb", texture_11)
	terrain_material.set_shader_parameter("vc_tex_ba", texture_12)
	terrain_material.set_shader_parameter("vc_tex_ar", texture_13)
	terrain_material.set_shader_parameter("vc_tex_ag", texture_14)
	terrain_material.set_shader_parameter("vc_tex_ab", texture_15)
	
	# TERRAIN MATERIAL - Ground Colors (used for both floor and wall in unified system)
	terrain_material.set_shader_parameter("tex_albedo_1", texture_albedo_1)
	terrain_material.set_shader_parameter("tex_albedo_2", texture_albedo_2)
	terrain_material.set_shader_parameter("tex_albedo_3", texture_albedo_3)
	terrain_material.set_shader_parameter("tex_albedo_4", texture_albedo_4)
	terrain_material.set_shader_parameter("tex_albedo_5", texture_albedo_5)
	terrain_material.set_shader_parameter("tex_albedo_6", texture_albedo_6)
	
	# TERRAIN MATERIAL - Per-Texture UV Scales
	terrain_material.set_shader_parameter("tex_scale_1", texture_scale_1)
	terrain_material.set_shader_parameter("tex_scale_2", texture_scale_2)
	terrain_material.set_shader_parameter("tex_scale_3", texture_scale_3)
	terrain_material.set_shader_parameter("tex_scale_4", texture_scale_4)
	terrain_material.set_shader_parameter("tex_scale_5", texture_scale_5)
	terrain_material.set_shader_parameter("tex_scale_6", texture_scale_6)
	terrain_material.set_shader_parameter("tex_scale_7", texture_scale_7)
	terrain_material.set_shader_parameter("tex_scale_8", texture_scale_8)
	terrain_material.set_shader_parameter("tex_scale_9", texture_scale_9)
	terrain_material.set_shader_parameter("tex_scale_10", texture_scale_10)
	terrain_material.set_shader_parameter("tex_scale_11", texture_scale_11)
	terrain_material.set_shader_parameter("tex_scale_12", texture_scale_12)
	terrain_material.set_shader_parameter("tex_scale_13", texture_scale_13)
	terrain_material.set_shader_parameter("tex_scale_14", texture_scale_14)
	terrain_material.set_shader_parameter("tex_scale_15", texture_scale_15)
	
	# GRASS MATERIAL - Grass Textures 
	grass_mat.set_shader_parameter("grass_texture_1", grass_sprite_tex_1)
	grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	# GRASS MATERIAL - Grass Colors 
	grass_mat.set_shader_parameter("grass_color_1", texture_albedo_1)
	grass_mat.set_shader_parameter("grass_color_2", texture_albedo_2)
	grass_mat.set_shader_parameter("grass_color_3", texture_albedo_3)
	grass_mat.set_shader_parameter("grass_color_4", texture_albedo_4)
	grass_mat.set_shader_parameter("grass_color_5", texture_albedo_5)
	grass_mat.set_shader_parameter("grass_color_6", texture_albedo_6)
	
	# GRASS MATERIAL - Use Base Color Flags 
	grass_mat.set_shader_parameter("use_base_color_1", texture_1 == null)
	grass_mat.set_shader_parameter("use_base_color_2", texture_2 == null)
	grass_mat.set_shader_parameter("use_base_color_3", texture_3 == null)
	grass_mat.set_shader_parameter("use_base_color_4", texture_4 == null)
	grass_mat.set_shader_parameter("use_base_color_5", texture_5 == null)
	grass_mat.set_shader_parameter("use_base_color_6", texture_6 == null)
	
	# GRASS MATERIAL - Has Grass Flags 
	grass_mat.set_shader_parameter("use_grass_tex_2", tex2_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_3", tex3_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_4", tex4_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_5", tex5_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_6", tex6_has_grass)


## Syncs and saves current UI texture values to the given preset resource
## Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null:
		# Don't print an error here as not having a preset just means the user is making a new one
		return
	
	# Terrain textures
	current_texture_preset.new_textures.terrain_textures[0] = texture_1
	current_texture_preset.new_textures.terrain_textures[1] = texture_2
	current_texture_preset.new_textures.terrain_textures[2] = texture_3
	current_texture_preset.new_textures.terrain_textures[3] = texture_4
	current_texture_preset.new_textures.terrain_textures[4] = texture_5
	current_texture_preset.new_textures.terrain_textures[5] = texture_6
	current_texture_preset.new_textures.terrain_textures[6] = texture_7
	current_texture_preset.new_textures.terrain_textures[7] = texture_8
	current_texture_preset.new_textures.terrain_textures[8] = texture_9
	current_texture_preset.new_textures.terrain_textures[9] = texture_10
	current_texture_preset.new_textures.terrain_textures[10] = texture_11
	current_texture_preset.new_textures.terrain_textures[11] = texture_12
	current_texture_preset.new_textures.terrain_textures[12] = texture_13
	current_texture_preset.new_textures.terrain_textures[13] = texture_14
	current_texture_preset.new_textures.terrain_textures[14] = texture_15
	
	# Texture scales
	current_texture_preset.new_textures.texture_scales[0] = texture_scale_1
	current_texture_preset.new_textures.texture_scales[1] = texture_scale_2
	current_texture_preset.new_textures.texture_scales[2] = texture_scale_3
	current_texture_preset.new_textures.texture_scales[3] = texture_scale_4
	current_texture_preset.new_textures.texture_scales[4] = texture_scale_5
	current_texture_preset.new_textures.texture_scales[5] = texture_scale_6
	current_texture_preset.new_textures.texture_scales[6] = texture_scale_7
	current_texture_preset.new_textures.texture_scales[7] = texture_scale_8
	current_texture_preset.new_textures.texture_scales[8] = texture_scale_9
	current_texture_preset.new_textures.texture_scales[9] = texture_scale_10
	current_texture_preset.new_textures.texture_scales[10] = texture_scale_11
	current_texture_preset.new_textures.texture_scales[11] = texture_scale_12
	current_texture_preset.new_textures.texture_scales[12] = texture_scale_13
	current_texture_preset.new_textures.texture_scales[13] = texture_scale_14
	current_texture_preset.new_textures.texture_scales[14] = texture_scale_15
	
	# Grass sprites
	current_texture_preset.new_textures.grass_sprites[0] = grass_sprite_tex_1
	current_texture_preset.new_textures.grass_sprites[1] = grass_sprite_tex_2
	current_texture_preset.new_textures.grass_sprites[2] = grass_sprite_tex_3
	current_texture_preset.new_textures.grass_sprites[3] = grass_sprite_tex_4
	current_texture_preset.new_textures.grass_sprites[4] = grass_sprite_tex_5
	current_texture_preset.new_textures.grass_sprites[5] = grass_sprite_tex_6
	
	# Grass colors
	current_texture_preset.new_textures.grass_colors[0] = texture_albedo_1
	current_texture_preset.new_textures.grass_colors[1] = texture_albedo_2
	current_texture_preset.new_textures.grass_colors[2] = texture_albedo_3
	current_texture_preset.new_textures.grass_colors[3] = texture_albedo_4
	current_texture_preset.new_textures.grass_colors[4] = texture_albedo_5
	current_texture_preset.new_textures.grass_colors[5] = texture_albedo_6
	
	# Has grass flags
	current_texture_preset.new_textures.has_grass[0] = tex2_has_grass
	current_texture_preset.new_textures.has_grass[1] = tex3_has_grass
	current_texture_preset.new_textures.has_grass[2] = tex4_has_grass
	current_texture_preset.new_textures.has_grass[3] = tex5_has_grass
	current_texture_preset.new_textures.has_grass[4] = tex6_has_grass

#endregion
