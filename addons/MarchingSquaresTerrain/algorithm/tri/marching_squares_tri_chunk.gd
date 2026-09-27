@tool
class_name MarchingSquaresTriChunk
extends MarchingSquaresCellChunk
## Equilateral triangle cell chunk. Geometry math comes from
## MarchingSquaresTriGrid. Cells_per_chunk.x counts triangles (2 per rhombus
## column), so terrain.dimensions.x rhombus columns yield 2 * dimensions.x
## triangle columns.


func cells_per_chunk() -> Vector2i:
	return Vector2i(2 * terrain_system.dimensions.x, terrain_system.dimensions.z)


func _size() -> Vector2:
	return terrain_system.cell_size


func cell_center_world(cell: Vector2i) -> Vector2:
	return MarchingSquaresTriGrid.cell_center(cell, _size())


func cell_corner_offsets(cell: Vector2i) -> PackedVector2Array:
	var corners := MarchingSquaresTriGrid.cell_corners(cell, _size())
	var center := MarchingSquaresTriGrid.cell_center(cell, _size())
	var offsets := PackedVector2Array()
	offsets.resize(corners.size())
	for i in range(corners.size()):
		offsets[i] = corners[i] - center
	return offsets


func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return MarchingSquaresTriGrid.edge_neighbors(cell)


func edge_corner_indices(cell: Vector2i, edge: int) -> Vector2i:
	return MarchingSquaresTriGrid.edge_corner_indices(cell, edge)


func get_chunk_origin_world() -> Vector2:
	return MarchingSquaresTriGrid.lattice_point(
		chunk_coords.x * terrain_system.dimensions.x,
		chunk_coords.y * terrain_system.dimensions.z,
		terrain_system.cell_size)
