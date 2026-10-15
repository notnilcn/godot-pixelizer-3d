@tool
extends MultiMeshInstance3D
class_name MarchingSquaresCellGrassPlanter
## Grass planter for cell-mode chunks (triangle/hexagon). Every cell is a flat
## polygon, so grass points are scattered uniformly across the cell's fan
## triangles and colored from the cell's ground maps and grass mask.
## Mirrors MarchingSquaresGrassPlanter's masking and color rules.


# Alpha values for grass sprites by texture ID (1-6)
const GRASS_ALPHA_VALUES := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

var _chunk : MarchingSquaresCellChunk
var terrain_system : MarchingSquaresTerrain

# Texture id -> Image, avoids decompressing the same texture for every point.
var _terrain_image_cache : Dictionary = {}


func setup(chunk: MarchingSquaresCellChunk, redo: bool = true) -> void:
	_chunk = chunk
	terrain_system = _chunk.terrain_system as MarchingSquaresTerrain
	_terrain_image_cache.clear()
	
	if not _chunk or not terrain_system:
		push_error("SETUP FAILED - no chunk or terrain system found for CellGrassPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var cells := _chunk.cells_per_chunk()
	multimesh.instance_count = cells.x * cells.y * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	if terrain_system.grass_mesh:
		multimesh.mesh = terrain_system.grass_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = terrain_system.grass_size * (terrain_system.cell_size.x + terrain_system.cell_size.y) / 4.0
	multimesh.mesh.center_offset.y = multimesh.mesh.size.y / 2.0
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF


func regenerate_all_cells() -> void:
	if not _chunk:
		push_error("_chunk not set while regenerating cells")
		return
	if not terrain_system:
		push_error("terrain_system not set while regenerating cells")
		return
	if not multimesh:
		setup(_chunk)
	
	var cells := _chunk.cells_per_chunk()
	for r in range(cells.y):
		for c in range(cells.x):
			generate_grass_on_cell(Vector2i(c, r))


func generate_grass_on_cell(local: Vector2i) -> void:
	if not _chunk or not terrain_system or not multimesh:
		return
	
	var subdivisions : int = terrain_system.grass_subdivisions
	var count : int = subdivisions * subdivisions
	var index : int = _chunk.cell_index(local) * count
	var end_index : int = index + count
	if end_index > multimesh.instance_count:
		# Instance buffer is stale (subdivisions changed): skip until setup runs.
		return
	
	if not _chunk.has_cell(local):
		# Bounding-box corners of a hex-ring chunk are not real cells.
		while index < end_index:
			_hide_grass_instance(index)
			index += 1
		return
	
	var texture_id := _get_texture_id(_chunk.get_color_0(local), _chunk.get_color_1(local))
	var mask := _chunk.get_grass_mask(local)
	var is_masked : bool = mask.r < 0.9999
	var force_grass_on : bool = mask.g >= 0.9999
	var on_grass_tex := _has_grass_for_texture(texture_id, force_grass_on)
	
	if not on_grass_tex or is_masked:
		while index < end_index:
			_hide_grass_instance(index)
			index += 1
		return
	
	var global := _chunk.global_cell(_chunk.chunk_coords, local, _chunk.cells_per_chunk())
	var origin := _chunk.get_chunk_origin_world()
	var center := _chunk.cell_center_world(global) - origin
	var offsets := _chunk.cell_corner_offsets(global)
	var corner_count := offsets.size()
	var h : float = _chunk.get_height(local)
	var world_xz := _chunk.position if not _chunk.is_inside_tree() else _chunk.global_position
	var sample_pos := Vector3(world_xz.x + center.x, h, world_xz.z + center.y)
	
	for i in range(count):
		var corner := randi() % corner_count
		var a := center
		var b := center + offsets[corner]
		var c := center + offsets[(corner + 1) % corner_count]
		var r1 := randf()
		var r2 := randf()
		if r1 + r2 > 1.0:
			r1 = 1.0 - r1
			r2 = 1.0 - r2
		var p := a + (b - a) * r1 + (c - a) * r2
		_create_grass_instance(index, Vector3(p.x, h, p.y), sample_pos, texture_id)
		index += 1
	
	while index < end_index:
		_hide_grass_instance(index)
		index += 1

#region grass property getters

func _get_terrain_image(texture_id: int) -> Image:
	if _terrain_image_cache.has(texture_id):
		return _terrain_image_cache[texture_id]
	
	var terrain_texture : Texture2D = null
	var material := terrain_system.terrain_material
	match texture_id:
		2:
			terrain_texture = material.get_shader_parameter("vc_tex_rg")
		3:
			terrain_texture = material.get_shader_parameter("vc_tex_rb")
		4:
			terrain_texture = material.get_shader_parameter("vc_tex_ra")
		5:
			terrain_texture = material.get_shader_parameter("vc_tex_gr")
		6:
			terrain_texture = material.get_shader_parameter("vc_tex_gg")
		_: # Base grass
			terrain_texture = material.get_shader_parameter("vc_tex_rr")
	if terrain_texture == null:
		return null
	
	var img : Image = terrain_texture.get_image()
	if img:
		img.decompress()
	_terrain_image_cache[texture_id] = img
	return img


func _get_texture_id(vc_col_0: Color, vc_col_1: Color) -> int:
	var id : int = 1;
	if vc_col_0.r > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 1;
		elif vc_col_1.g > 0.9999:
			id = 2;
		elif vc_col_1.b > 0.9999:
			id = 3;
		elif vc_col_1.a > 0.9999:
			id = 4;
	elif vc_col_0.g > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 5;
		elif vc_col_1.g > 0.9999:
			id = 6;
		elif vc_col_1.b > 0.9999:
			id = 7;
		elif vc_col_1.a > 0.9999:
			id = 8;
	elif vc_col_0.b > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 9;
		elif vc_col_1.g > 0.9999:
			id = 10;
		elif vc_col_1.b > 0.9999:
			id = 11;
		elif vc_col_1.a > 0.9999:
			id = 12;
	elif vc_col_0.a > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 13;
		elif vc_col_1.g > 0.9999:
			id = 14;
		elif vc_col_1.b > 0.9999:
			id = 15;
		elif vc_col_1.a > 0.9999:
			id = 16;
	return id;


## Checks if the given texture ID should have grass placed on it.
func _has_grass_for_texture(texture_id: int, force_grass_on: bool) -> bool:
	if force_grass_on:
		return true
	if texture_id == 1:
		return true  # Base grass always has grass
	if texture_id < 2 or texture_id > 6:
		return false
	
	var has_grass_flags := [
		terrain_system.tex2_has_grass,
		terrain_system.tex3_has_grass,
		terrain_system.tex4_has_grass,
		terrain_system.tex5_has_grass,
		terrain_system.tex6_has_grass
	]
	return has_grass_flags[texture_id - 2]


## Gets the texture scale for the given texture ID.
func _get_texture_scale(texture_id: int) -> float:
	var scales := [
		terrain_system.texture_scale_1,
		terrain_system.texture_scale_2,
		terrain_system.texture_scale_3,
		terrain_system.texture_scale_4,
		terrain_system.texture_scale_5,
		terrain_system.texture_scale_6
	]
	var idx := clampi(texture_id - 1, 0, 5)
	return scales[idx]


## Gets the grass sprite alpha value for the given texture ID.
func _get_grass_alpha(texture_id: int) -> float:
	var idx := clampi(texture_id - 1, 0, 5)
	return GRASS_ALPHA_VALUES[idx]


## Samples the terrain texture color at the given world position.
func _sample_terrain_texture_color(world_pos: Vector3, texture_id: int, tex_scale: float) -> Color:
	var terrain_image := _get_terrain_image(texture_id)
	if not terrain_image:
		return Color.WHITE
	
	var extent := _terrain_world_extent()
	var uv_x : float = clamp(world_pos.x / extent.x, 0.0, 1.0)
	var uv_y : float = clamp(world_pos.z / extent.y, 0.0, 1.0)
	
	uv_x = abs(fmod(uv_x * tex_scale, 1.0))
	uv_y = abs(fmod(uv_y * tex_scale, 1.0))
	
	var px := int(uv_x * (terrain_image.get_width() - 1))
	var py := int(uv_y * (terrain_image.get_height() - 1))
	var color := terrain_image.get_pixelv(Vector2(px, py))
	if _format_needs_conversion(terrain_image.get_format()):
		return color.srgb_to_linear()
	return color


## World-space XZ extent covered by the terrain (cell modes use cell counts).
func _terrain_world_extent() -> Vector2:
	if terrain_system.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		return Vector2(
			terrain_system.dimensions.x * terrain_system.cell_size.x,
			terrain_system.dimensions.z * MarchingSquaresTriGrid.row_height(terrain_system.cell_size))
	var spacing := MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size)
	if terrain_system.grid_type == MarchingSquaresTerrain.GridType.HEX_RINGS:
		var cells := terrain_system.cells_per_chunk()
		return Vector2(cells.x * spacing.x, cells.y * spacing.y)
	return Vector2(
		terrain_system.dimensions.x * spacing.x,
		terrain_system.dimensions.z * spacing.y)


func _format_needs_conversion(fmt: Image.Format) -> bool:
	match(fmt):
		Image.FORMAT_RGB8, \
		Image.FORMAT_RGBA8, \
		Image.FORMAT_DXT1, \
		Image.FORMAT_DXT3, \
		Image.FORMAT_DXT5, \
		Image.FORMAT_BPTC_RGBA, \
		Image.FORMAT_ETC2_RGB8 , \
		Image.FORMAT_ETC2_RGBA8 , \
		Image.FORMAT_ETC2_RGB8A1 : return true
	return false

#endregion

#region grass placement helpers

## Creates a grass instance at the given position with proper transform and color.
## The basis matches the square planter's flat-floor basis exactly (the square
## planter derives a downward normal from its floor winding, which is what the
## grass shader's normal test expects).
func _create_grass_instance(index: int, local_pos: Vector3, sample_pos: Vector3, texture_id: int) -> void:
	var normal := Vector3.DOWN
	var right := Vector3.FORWARD.cross(normal).normalized()
	var forward := normal.cross(Vector3.RIGHT).normalized()
	var instance_basis := Basis(right, forward, -normal)
	
	multimesh.set_instance_transform(index, Transform3D(instance_basis, local_pos))
	
	var tex_scale := _get_texture_scale(texture_id)
	var instance_color := _sample_terrain_texture_color(sample_pos, texture_id, tex_scale)
	instance_color.a = _get_grass_alpha(texture_id)
	
	multimesh.set_instance_custom_data(index, instance_color)


## Hides a grass instance by scaling it to zero.
func _hide_grass_instance(index: int) -> void:
	if index >= multimesh.instance_count:
		return
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

#endregion
