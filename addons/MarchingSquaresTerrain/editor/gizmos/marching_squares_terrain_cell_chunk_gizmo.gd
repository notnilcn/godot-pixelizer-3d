# This gizmo has one handle per cell (triangle/hexagon chunk).
# Mostly for debugging, mirroring the square chunk gizmo.

extends EditorNode3DGizmo
class_name MarchingSquaresTerrainCellChunkGizmo


func _redraw():
	clear()
	
	var chunk : MarchingSquaresCellChunk = get_node_3d()
	
	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) != 1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] != chunk:
		return
	
	var cells := chunk.cells_per_chunk()
	var origin := chunk.get_chunk_origin_world()
	var corners := PackedVector3Array()
	var ids := PackedInt32Array()
	for r in range(cells.y):
		for c in range(cells.x):
			var global := chunk.chunk_coords * cells + Vector2i(c, r)
			var center := chunk.cell_center_world(global) - origin
			var y : float = chunk.get_height(Vector2i(c, r))
			corners.append(Vector3(center.x, y, center.y))
			ids.append(r * cells.x + c)
	add_handles(corners, get_plugin().get_material("handles", self), ids)


func _get_handle_name(handle_id: int, _secondary: bool) -> String:
	return str(handle_id)


func _get_handle_value(handle_id: int, _secondary: bool) -> Variant:
	var chunk : MarchingSquaresCellChunk = get_node_3d()
	return chunk.height_map[handle_id]


func _commit_handle(handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var chunk : MarchingSquaresCellChunk = get_node_3d()
	
	if cancel:
		chunk.height_map[handle_id] = restore
		chunk.mark_dirty()
		chunk.regenerate_mesh()
	else:
		var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
		var do_value = chunk.height_map[handle_id]
		undo_redo.create_action("move terrain cell")
		undo_redo.add_do_method(self, "move_cell_height", chunk, handle_id, do_value)
		undo_redo.add_undo_method(self, "move_cell_height", chunk, handle_id, restore)
		undo_redo.commit_action()
	
	chunk.update_gizmos()


func move_cell_height(chunk: MarchingSquaresCellChunk, handle_id: int, height: float) -> void:
	var cells := chunk.cells_per_chunk()
	chunk.draw_height(handle_id % cells.x, handle_id / cells.x, height)
	chunk.regenerate_mesh()
	chunk.update_gizmos()


func _set_handle(handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var chunk : MarchingSquaresCellChunk = get_node_3d()
	var cells := chunk.cells_per_chunk()
	var c := handle_id % cells.x
	var r := handle_id / cells.x
	var origin := chunk.get_chunk_origin_world()
	var global := chunk.chunk_coords * cells + Vector2i(c, r)
	var center := chunk.cell_center_world(global) - origin
	var y : float = chunk.height_map[handle_id]
	var handle_position = chunk.to_global(Vector3(center.x, y, center.y))
	
	# Convert mouse movement to 3D world coordinates using raycasting.
	# The movement is restricted to the Y axis via an XZ-aligned plane.
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var plane = Plane(Vector3(ray_dir.x, 0, ray_dir.z), handle_position)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection:
		intersection = chunk.to_local(intersection)
		chunk.height_map[handle_id] = intersection.y
		chunk.mark_dirty()
		chunk.update_gizmos()
