@tool
class_name MarchingSquaresHexRingsChunk
extends MarchingSquaresCellChunk
## Hex-ring chunk: one low-res chunk hex owning a disk of micro-hexes, matching the
## server's hexmod chunk layout. Geometry math comes from MarchingSquaresHexRingsGrid;
## chunk coords are low-res axial indices and cell coords are global axial indices.
## The chunk's dense maps cover the disk's bounding box (2R+1 squared); the box corners
## outside the disk are skipped by [method has_cell].


func _radius() -> int:
	return terrain_system.chunk_hex_radius


func _spacing() -> Vector2:
	return MarchingSquaresHexRingsGrid.spacing_for(terrain_system.cell_size)


func cells_per_chunk() -> Vector2i:
	return MarchingSquaresHexRingsGrid.cells_per_chunk(_radius())


## Box corners of the disk's bounding box are not real cells.
func has_cell(local: Vector2i) -> bool:
	return MarchingSquaresHexRingsGrid.has_local(local, _radius())


func global_cell(chunk: Vector2i, local: Vector2i, _cells: Vector2i) -> Vector2i:
	return MarchingSquaresHexRingsGrid.global_cell(chunk, local, _radius())


func local_cell(global: Vector2i) -> Vector2i:
	return MarchingSquaresHexRingsGrid.local_cell(global, _radius())


func cell_center_world(cell: Vector2i) -> Vector2:
	return MarchingSquaresHexRingsGrid.cell_center(cell, _spacing())


func cell_corner_offsets(_cell: Vector2i) -> PackedVector2Array:
	return MarchingSquaresHexRingsGrid.corner_offsets(MarchingSquaresHexRingsGrid.radius_for(terrain_system.cell_size))


func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return MarchingSquaresHexRingsGrid.edge_neighbors(cell)


func edge_corner_indices(_cell: Vector2i, edge: int) -> Vector2i:
	return Vector2i(edge, (edge + 1) % 6)


## The chunk node is placed at its chunk hex's center, so cell emission is relative to that.
func get_chunk_origin_world() -> Vector2:
	return MarchingSquaresHexRingsGrid.chunk_center_world(chunk_coords, _radius(), _spacing())
