@tool
class_name MarchingSquaresHexChunk
extends MarchingSquaresCellChunk
## Hexagon cell chunk. Geometry math comes from MarchingSquaresHexGrid.


func cells_per_chunk() -> Vector2i:
	return Vector2i(terrain_system.dimensions.x, terrain_system.dimensions.z)


func _spacing() -> Vector2:
	return MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size)


func cell_center_world(cell: Vector2i) -> Vector2:
	return MarchingSquaresHexGrid.cell_center(cell, _spacing())


func cell_corner_offsets(_cell: Vector2i) -> PackedVector2Array:
	return MarchingSquaresHexGrid.corner_offsets(MarchingSquaresHexGrid.radius_for(terrain_system.cell_size))


func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return MarchingSquaresHexGrid.edge_neighbors(cell)


func edge_corner_indices(_cell: Vector2i, edge: int) -> Vector2i:
	return Vector2i(edge, (edge + 1) % 6)
