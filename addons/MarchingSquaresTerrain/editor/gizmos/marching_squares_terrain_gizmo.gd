extends EditorNode3DGizmo
class_name MarchingSquaresTerrainGizmo


const BrushPatternCalculator = preload("uid://bli1mnri3jwpa")

var lines : PackedVector3Array = PackedVector3Array()

var addchunk_material : Material
var removechunk_material : Material
var highlightchunk_material : Material
var brush_material : Material

var terrain_plugin : MarchingSquaresTerrainPlugin


func _redraw():
	lines.clear()
	clear()
	
	addchunk_material = get_plugin().get_material("addchunk", self)
	removechunk_material = get_plugin().get_material("removechunk", self)
	highlightchunk_material = get_plugin().get_material("highlightchunk", self)
	brush_material = get_plugin().get_material("brush", self)
	
	var terrain_system: MarchingSquaresTerrain = get_node_3d()
	terrain_plugin = MarchingSquaresTerrainPlugin.instance
	
	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) != 1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] != terrain_system:
		return
	
	# Selected chunk gizmo lines
	if terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT and terrain_plugin.selected_chunk:
		if terrain_plugin.current_terrain_node.find_child("Chunk " + str(terrain_plugin.selected_chunk.chunk_coords)):
			add_chunk_lines(terrain_system, terrain_plugin.selected_chunk.chunk_coords, highlightchunk_material)
		else:
			lines.clear()
	
	# Chunk management gizmo lines
	if terrain_system.chunks.is_empty():
		if terrain_plugin.is_chunk_plane_hovered:
			add_chunk_lines(terrain_system, terrain_plugin.current_hovered_chunk, addchunk_material)
	else:
		for chunk_coords: Vector2i in terrain_system.chunks:
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x-1, chunk_coords.y))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x+1, chunk_coords.y))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x, chunk_coords.y-1))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x, chunk_coords.y+1))
			try_add_chunk(terrain_system, chunk_coords)
	
	var pos : Vector3 = terrain_plugin.brush_position
	var cursor_chunk_coords : Vector2i
	var cursor_cell_coords : Vector2i
	
	if terrain_plugin.is_setting and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true
		
		if terrain_system.grid_type == MarchingSquaresTerrain.GridType.SQUARE:
			var chunk_x := floor(pos.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x))
			var chunk_z := floor(pos.z / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y))
			cursor_chunk_coords = Vector2i(chunk_x, chunk_z)
			
			var x := int(floor(((pos.x + terrain_system.cell_size.x/2) / terrain_system.cell_size.x) - chunk_x * (terrain_system.dimensions.x - 1)))
			var z := int(floor(((pos.z + terrain_system.cell_size.y/2) / terrain_system.cell_size.y) - chunk_z * (terrain_system.dimensions.z - 1)))
			cursor_cell_coords = Vector2i(x, z)
		else:
			var cursor_global := _world_to_global_cell(terrain_system, Vector2(pos.x, pos.z))
			cursor_chunk_coords = _chunk_of_global_cell(terrain_system, cursor_global)
			cursor_cell_coords = _local_of_global_cell(terrain_system, cursor_global)
		
		# When setting, if there is no pattern and alt not held, go to draw mode
		var has_pattern : bool = not terrain_plugin.current_draw_pattern.is_empty()
		if not has_pattern and not Input.is_key_pressed(KEY_ALT):
			terrain_plugin.current_draw_pattern.clear()
			terrain_plugin.is_setting = false
			terrain_plugin.is_drawing = true
			terrain_plugin.draw_height = pos.y
		
		# Otherwise, drag that pattern's height
		else:
			# If alt held, ONLY drag the cursor cell
			if Input.is_key_pressed(KEY_ALT) and terrain_system.chunks.has(cursor_chunk_coords):
				terrain_plugin.current_draw_pattern.clear()
				terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
				terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = terrain_system.chunks[cursor_chunk_coords].get_height(cursor_cell_coords)
				terrain_plugin.draw_height = pos.y
			terrain_plugin.base_position = pos
	
	if terrain_plugin.is_drawing and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true
		terrain_plugin.draw_height = terrain_plugin.brush_position.y
	
	var terrain_chunk_hovered : bool = terrain_plugin.terrain_hovered
	
	# Check if we're in wall painting mode
	var is_wall_painting : bool = terrain_plugin.paint_walls_mode and terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING
	
	# Set the BRUSH_VISUAL's size dynamically
	terrain_plugin.BRUSH_VISUAL.size = Vector2(1.0, 1.0) * (terrain_system.cell_size.x + terrain_system.cell_size.y) / 4.0
	
	if terrain_chunk_hovered:
		# Brush radius visualization
		var brush_transform : Transform3D
		brush_transform = Transform3D(Vector3.RIGHT * terrain_plugin.brush_size, Vector3.UP, Vector3.BACK * terrain_plugin.brush_size, pos)
		
		if is_wall_painting:
			var viewport := EditorInterface.get_editor_viewport_3d()
			var editor_camera := viewport.get_camera_3d()
			var mouse_pos := viewport.get_mouse_position()
			
			var ray_origin := editor_camera.project_ray_origin(mouse_pos)
			var ray_dir := editor_camera.project_ray_normal(mouse_pos)
			
			var space := terrain_system.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(
				ray_origin,
				ray_origin + ray_dir * 10000.0
			)
			
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit_result = space.intersect_ray(query)
			var wall_normal : Vector3 = Vector3.BACK
			if hit_result:
				wall_normal = hit_result.normal
			
			var basis := _create_brush_basis(wall_normal, terrain_plugin.brush_size)
			if wall_normal.y > 0.5:
				basis.z = Vector3.ZERO
			brush_transform = Transform3D(basis, pos)
		
		# Grid aligned selections get an outline that exactly encloses the
		# selected cells (lattice hexagon on triangle terrain).
		if terrain_plugin.grid_aligned and terrain_plugin.grid_align_gate_passes():
			brush_transform = _grid_aligned_brush_transform(terrain_system, pos)
		
		if terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING:
			if terrain_plugin.paint_walls_mode:
				add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, null, brush_transform)
		elif terrain_plugin.mode != terrain_plugin.TerrainToolMode.SMOOTH and terrain_plugin.mode != terrain_plugin.TerrainToolMode.GRASS_MASK and terrain_plugin.mode != terrain_plugin.TerrainToolMode.DEBUG_BRUSH:
			add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, null, brush_transform)
		
		pos = terrain_plugin.brush_position
		
		if terrain_system.grid_type != MarchingSquaresTerrain.GridType.SQUARE:
			_redraw_cell_brush(terrain_system, pos, is_wall_painting)
		else:
			var bounds = BrushPatternCalculator.calculate_bounds(pos, terrain_plugin.brush_size, terrain_system)
			var max_distance : float = BrushPatternCalculator.calculate_max_distance(terrain_plugin.brush_size, terrain_plugin.current_brush_index)
			var brush_pos : Vector2 = Vector2(pos.x, pos.z)
			
			for chunk_z in range(bounds.chunk_tl.y, bounds.chunk_br.y + 1):
				for chunk_x in range(bounds.chunk_tl.x, bounds.chunk_br.x + 1):
					cursor_chunk_coords = Vector2i(chunk_x, chunk_z)
					if not terrain_system.chunks.has(cursor_chunk_coords):
						continue
					var chunk : MarchingSquaresTerrainChunk = terrain_system.chunks[cursor_chunk_coords]
					
					var cell_range : Dictionary = BrushPatternCalculator.get_cell_range_for_chunk(cursor_chunk_coords, bounds, terrain_system)
					
					for z in range(cell_range.z_min, cell_range.z_max):
						for x in range(cell_range.x_min, cell_range.x_max):
							cursor_cell_coords = Vector2i(x, z)
							var world_pos : Vector2 = BrushPatternCalculator.cell_to_world_pos(cursor_chunk_coords, cursor_cell_coords, terrain_system)
							
							var sample : float = BrushPatternCalculator.calculate_falloff_sample(
								world_pos, brush_pos, terrain_plugin.brush_size, terrain_plugin.current_brush_index,
								max_distance, terrain_plugin.falloff, terrain_plugin.falloff_curve
							)
							
							if sample < 0:
								continue  # Outside brush
							
							var y : float
							if not terrain_plugin.current_draw_pattern.is_empty() and terrain_plugin.flatten:
								y = terrain_plugin.draw_height
							else:
								y = chunk.height_map[z][x]
							
							var draw_position := Vector3(world_pos.x, y, world_pos.y)
							var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
							# Only draw ground brush squares if NOT in wall paint mode
							if not is_wall_painting:
								add_mesh(terrain_plugin.BRUSH_VISUAL, brush_material, draw_transform)
							
							# Draw to current pattern
							if terrain_plugin.is_drawing:
								if not terrain_plugin.current_draw_pattern.has(cursor_chunk_coords):
									terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
								if terrain_plugin.current_draw_pattern[cursor_chunk_coords].has(cursor_cell_coords):
									var prev_sample = terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords]
									if sample > prev_sample:
										terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
								else:
									terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
	
	var height_diff : float
	if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
		height_diff = terrain_plugin.brush_position.y - terrain_plugin.draw_height
	
	if not terrain_plugin.current_draw_pattern.is_empty():
		for draw_chunk_coords : Vector2i in terrain_plugin.current_draw_pattern:
			var chunk = terrain_system.chunks[draw_chunk_coords]
			var draw_chunk_dict : Dictionary = terrain_plugin.current_draw_pattern[draw_chunk_coords]
			for draw_coords: Vector2i in draw_chunk_dict:
				var draw_world : Vector2
				var draw_y : float
				if terrain_system.grid_type == MarchingSquaresTerrain.GridType.SQUARE:
					draw_world = Vector2(
						(draw_chunk_coords.x * (terrain_system.dimensions.x - 1) + draw_coords.x) * terrain_system.cell_size.x,
						(draw_chunk_coords.y * (terrain_system.dimensions.z - 1) + draw_coords.y) * terrain_system.cell_size.y)
					draw_y = terrain_plugin.draw_height if terrain_plugin.flatten else chunk.height_map[draw_coords.y][draw_coords.x]
				else:
					var global := _global_of_local_cell(terrain_system, draw_chunk_coords, draw_coords)
					draw_world = BrushPatternCalculator.cell_center_for(terrain_system, global)
					draw_y = terrain_plugin.draw_height if terrain_plugin.flatten else chunk.get_height(draw_coords)
				
				var sample : float = draw_chunk_dict[draw_coords]
				
				# If setting, also show a square at the height to set to
				if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
					var draw_position := Vector3(draw_world.x, draw_y + height_diff * sample, draw_world.y)
					var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting:
						add_mesh(_marker_for(terrain_system), null, draw_transform)
				else:
					var draw_position := Vector3(draw_world.x, draw_y, draw_world.y)
					var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting:
						add_mesh(_marker_for(terrain_system), null, draw_transform)


## Cell-mode brush preview: draws one marker per candidate cell at its height.
func _redraw_cell_brush(terrain_system: MarchingSquaresTerrain, pos: Vector3, is_wall_painting: bool) -> void:
	var brush_pos := Vector2(pos.x, pos.z)
	var max_distance : float = BrushPatternCalculator.calculate_max_distance(terrain_plugin.brush_size, terrain_plugin.current_brush_index)
	var marker := _marker_for(terrain_system)
	
	# Grid aligned selection replaces the brush shape entirely (M4).
	var grid_aligned : bool = terrain_plugin.grid_aligned and terrain_plugin.grid_align_gate_passes()
	var selected : Array[Vector2i] = []
	if grid_aligned:
		selected = BrushPatternCalculator.grid_aligned_cells(terrain_system, brush_pos, terrain_plugin.grid_size)
	else:
		var cells := terrain_system.cells_per_chunk()
		var chunks := terrain_system.chunks.keys()
		for chunk_coords: Vector2i in chunks:
			var candidates := BrushPatternCalculator.cell_candidates_for_chunk(
				chunk_coords, terrain_system, brush_pos, terrain_plugin.brush_size, 2)
			for local: Vector2i in candidates:
				var global := _global_of_local_cell(terrain_system, chunk_coords, local)
				var center := BrushPatternCalculator.cell_center_for(terrain_system, global)
				var sample := _cell_sample(terrain_system, brush_pos, center, global, max_distance)
				if sample < 0:
					continue
				selected.append(global)
				_draw_cell_marker(terrain_system, marker, chunk_coords, local, global, center, sample, is_wall_painting)
				if terrain_plugin.is_drawing:
					_add_to_pattern(chunk_coords, local, sample)
		return
	
	for global in selected:
		var chunk_coords := _chunk_of_global_cell(terrain_system, global)
		if not terrain_system.chunks.has(chunk_coords):
			continue
		var local := _local_of_global_cell(terrain_system, global)
		var center := BrushPatternCalculator.cell_center_for(terrain_system, global)
		_draw_cell_marker(terrain_system, marker, chunk_coords, local, global, center, 1.0, is_wall_painting)
		if terrain_plugin.is_drawing:
			_add_to_pattern(chunk_coords, local, 1.0)


func _draw_cell_marker(terrain_system: MarchingSquaresTerrain, marker: Mesh, chunk_coords: Vector2i, local: Vector2i, global: Vector2i, center: Vector2, sample: float, is_wall_painting: bool) -> void:
	var y : float
	if not terrain_plugin.current_draw_pattern.is_empty() and terrain_plugin.flatten:
		y = terrain_plugin.draw_height
	else:
		var h = terrain_system.get_cell_height(global)
		y = float(h) if h != null else 0.0
	var draw_position := Vector3(center.x, y, center.y)
	var draw_transform := Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
	if not is_wall_painting:
		add_mesh(marker, null, draw_transform)


func _add_to_pattern(chunk_coords: Vector2i, local: Vector2i, sample: float) -> void:
	if not terrain_plugin.current_draw_pattern.has(chunk_coords):
		terrain_plugin.current_draw_pattern[chunk_coords] = {}
	if terrain_plugin.current_draw_pattern[chunk_coords].has(local):
		var prev_sample = terrain_plugin.current_draw_pattern[chunk_coords][local]
		if sample > prev_sample:
			terrain_plugin.current_draw_pattern[chunk_coords][local] = sample
	else:
		terrain_plugin.current_draw_pattern[chunk_coords][local] = sample


func _cell_sample(terrain_system: MarchingSquaresTerrain, brush_pos: Vector2, center: Vector2, global: Vector2i, max_distance: float) -> float:
	if terrain_system.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		return BrushPatternCalculator.tri_cell_sample(
			brush_pos, center, terrain_plugin.brush_size, terrain_plugin.current_brush_index,
			max_distance, terrain_plugin.falloff, terrain_plugin.falloff_curve, terrain_system.cell_size)
	return BrushPatternCalculator.hex_cell_sample(
		brush_pos, center, terrain_plugin.brush_size, terrain_plugin.current_brush_index,
		max_distance, terrain_plugin.falloff, terrain_plugin.falloff_curve,
		MarchingSquaresHexGrid.world_to_cell(brush_pos, MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size)),
		MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size))


func _marker_for(terrain_system: MarchingSquaresTerrain) -> Mesh:
	if terrain_system.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		return terrain_plugin.CELL_TRI_VISUAL
	return terrain_plugin.CELL_HEX_VISUAL


func _global_of_local_cell(terrain_system: MarchingSquaresTerrain, chunk_coords: Vector2i, local: Vector2i) -> Vector2i:
	return chunk_coords * terrain_system.cells_per_chunk() + local


func _chunk_of_global_cell(terrain_system: MarchingSquaresTerrain, global: Vector2i) -> Vector2i:
	return MarchingSquaresHexGrid.chunk_of_cell(global, terrain_system.cells_per_chunk())


func _local_of_global_cell(terrain_system: MarchingSquaresTerrain, global: Vector2i) -> Vector2i:
	return MarchingSquaresHexGrid.local_cell(global, terrain_system.cells_per_chunk())


func _world_to_global_cell(terrain_system: MarchingSquaresTerrain, p: Vector2) -> Vector2i:
	if terrain_system.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		return MarchingSquaresTriGrid.world_to_cell(p, terrain_system.cell_size)
	return MarchingSquaresHexGrid.world_to_cell(p, MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size))


## Outline transform that exactly encloses a grid-aligned selection (M6).
func _grid_aligned_brush_transform(terrain_system: MarchingSquaresTerrain, pos: Vector3) -> Transform3D:
	var outline := BrushPatternCalculator.grid_aligned_outline(
		terrain_system, Vector2(pos.x, pos.z), terrain_plugin.grid_size)
	var radius : float = outline["radius"]
	var rotation : float = outline["rotation"]
	var center : Vector2 = outline["center"]
	# The outline mesh is a 1x1 plane whose SDF boundary sits at half its
	# scale (same convention as the round/square brush outlines).
	var basis := Basis(Vector3.UP, rotation) * Basis(
		Vector3.RIGHT * radius * 2.0, Vector3.UP, Vector3.BACK * radius * 2.0)
	return Transform3D(basis, Vector3(center.x, pos.y, center.y))


func _create_brush_basis(normal: Vector3, brush_size: float) -> Basis:
	var n := normal.normalized()
	
	var tangent := Vector3.UP.cross(n)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT.cross(n)
	
	tangent = tangent.normalized()
	var bitangent := n.cross(tangent)
	
	tangent *= brush_size
	bitangent *= brush_size
	
	return Basis(tangent, n, bitangent)


func try_add_chunk(terrain_system: MarchingSquaresTerrain, coords: Vector2i):
	var terrain_plugin := MarchingSquaresTerrainPlugin.instance
	
	if Input.is_key_pressed(KEY_CTRL):
		return
	
	# Add chunk
	if (terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT or Input.is_key_pressed(KEY_SHIFT)) and not terrain_system.chunks.has(coords) and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, coords, addchunk_material)
	
	# Remove chunk (Manage Chunk tool only)
	elif terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, coords, removechunk_material) 


# Draw chunk ui lines inside and around a chunk
func add_chunk_lines(terrain_system: MarchingSquaresTerrain, coords: Vector2i, material: Material):
	var dx := (terrain_system.dimensions.x - 1) * terrain_system.cell_size.x
	var dz := (terrain_system.dimensions.z - 1) * terrain_system.cell_size.y
	var x := coords.x * dx
	var z := coords.y * dz
	dx += x
	dz += z
	
	lines.clear()
	if not terrain_system.chunks.has(Vector2i(coords.x, coords.y-1)):
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,z))
	if not terrain_system.chunks.has(Vector2i(coords.x+1, coords.y)):
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(dx,0,dz))
	if not terrain_system.chunks.has(Vector2i(coords.x, coords.y+1)):
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(x,0,dz))
	if not terrain_system.chunks.has(Vector2i(coords.x-1, coords.y)):
		lines.append(Vector3(x,0,dz))
		lines.append(Vector3(x,0,z))
	
	if material == removechunk_material:
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(x,0,dz))
	
	if material == addchunk_material:
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.75)))
	
	if material == highlightchunk_material:
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.75)))
		
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.75)))
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.75)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.75)))
	
	add_lines(lines, material, false)
