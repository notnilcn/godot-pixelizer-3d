@tool
class_name BrushPatternCalculator

## Calculates which cells fall within a brush and their falloff samples.
## Used by both plugin (for editing) and gizmo (for visualization).
class BrushBounds:
	var chunk_tl : Vector2i
	var chunk_br : Vector2i
	var cell_tl : Vector2i
	var cell_br : Vector2i


static func calculate_bounds(pos: Vector3, brush_size: float, terrain: MarchingSquaresTerrain) -> BrushBounds:
	var bounds := BrushBounds.new()
	
	var pos_tl := Vector2(
		pos.x + terrain.cell_size.x - brush_size / 2,
		pos.z + terrain.cell_size.y - brush_size / 2
		)
	var pos_br := Vector2(
		pos.x + terrain.cell_size.x + brush_size / 2,
		pos.z + terrain.cell_size.y + brush_size / 2
		)
	
	var chunk_size_x : float = (terrain.dimensions.x - 1) * terrain.cell_size.x
	var chunk_size_z : float = (terrain.dimensions.z - 1) * terrain.cell_size.y
	
	bounds.chunk_tl = Vector2i(floori(pos_tl.x / chunk_size_x), floori(pos_tl.y / chunk_size_z))
	bounds.chunk_br = Vector2i(floori(pos_br.x / chunk_size_x), floori(pos_br.y / chunk_size_z))
	
	bounds.cell_tl = Vector2i(
		floori(pos_tl.x / terrain.cell_size.x - bounds.chunk_tl.x * (terrain.dimensions.x - 1)),
		floori(pos_tl.y / terrain.cell_size.y - bounds.chunk_tl.y * (terrain.dimensions.z - 1))
	)
	bounds.cell_br = Vector2i(
		floori(pos_br.x / terrain.cell_size.x - bounds.chunk_br.x * (terrain.dimensions.x - 1)),
		floori(pos_br.y / terrain.cell_size.y - bounds.chunk_br.y * (terrain.dimensions.z - 1))
	)
	
	return bounds


static func calculate_max_distance(brush_size: float, brush_index: int) -> float:
	var max_distance : float = brush_size / 2
	match brush_index:
		0: # Round brush
			max_distance *= max_distance
		1: # Square brush
			max_distance *= max_distance * 2
		2: # Hexagon brush (pointy-top)
			max_distance *= max_distance
	return max_distance


static func calculate_falloff_sample(
	world_pos: Vector2,
	brush_pos: Vector2,
	brush_size: float,
	brush_index: int,
	max_distance: float,
	use_falloff: bool,
	falloff_curve: Curve
	) -> float:
	
	if brush_index == 2:
		# Pointy-top hexagon test in normalized brush space.
		var uv := (world_pos - brush_pos) / (brush_size * 0.5)
		var h := maxf(absf(uv.y), maxf(absf(uv.x) * 1.1547005383792517,
										absf(uv.y) + absf(uv.x) * 0.5773502691896258))
		if h > 1.0:
			return -1.0  # Outside brush
		if not use_falloff:
			return 1.0
		var t_hex : float = 1.0 - clampf(h, 0.2, 1.0)
		return falloff_curve.sample(clamp(t_hex, 0.001, 0.999))
	
	var distance_squared := brush_pos.distance_squared_to(world_pos)
	if distance_squared > max_distance:
		return -1.0  # Outside brush
	
	if not use_falloff:
		return 1.0
	
	var t : float
	match brush_index:
		0: # Round brush
			var d : float = (max_distance - distance_squared) / max_distance
			t = clamp(d, 0.0, 1.0)
		1: # Square brush
			var local := world_pos - brush_pos
			var uv := local / (brush_size * 0.5)
			var d : float = max(abs(uv.x), abs(uv.y))
			t = 1.0 - clamp(d, 0.2, 1.0)
	
	return falloff_curve.sample(clamp(t, 0.001, 0.999))


## Calculate world position for a cell in a chunk
static func cell_to_world_pos(chunk_coords: Vector2i, cell_coords: Vector2i, terrain: MarchingSquaresTerrain) -> Vector2:
	var world_x : float = (chunk_coords.x * (terrain.dimensions.x - 1) + cell_coords.x) * terrain.cell_size.x
	var world_z : float = (chunk_coords.y * (terrain.dimensions.z - 1) + cell_coords.y) * terrain.cell_size.y
	return Vector2(world_x, world_z)


## Get cell range for a specific chunk within the brush bounds
static func get_cell_range_for_chunk(chunk_coords: Vector2i, bounds: BrushBounds, terrain: MarchingSquaresTerrain) -> Dictionary:
	var x_min : int = bounds.cell_tl.x if chunk_coords.x == bounds.chunk_tl.x else 0
	var x_max : int = bounds.cell_br.x if chunk_coords.x == bounds.chunk_br.x else terrain.dimensions.x
	var z_min : int = bounds.cell_tl.y if chunk_coords.y == bounds.chunk_tl.y else 0
	var z_max : int = bounds.cell_br.y if chunk_coords.y == bounds.chunk_br.y else terrain.dimensions.z
	return {"x_min": x_min, "x_max": x_max, "z_min": z_min, "z_max": z_max}


#region cell-mode sampling

## Sample for one hex-terrain cell. brush_pos and cell_pos are world XZ.
static func hex_cell_sample(
	brush_pos : Vector2,
	cell_pos : Vector2,
	brush_size : float,
	brush_index : int,
	max_distance : float,
	use_falloff : bool,
	falloff_curve : Curve,
	center_cell : Vector2i,
	spacing : Vector2
	) -> float:
	if brush_index == 2:
		# Continuous hex distance in cell space.
		var center_pos := MarchingSquaresHexGrid.cell_center(center_cell, spacing)
		var d_pos := cell_pos - center_pos
		var d_cell_f := Vector2(
			d_pos.x / spacing.x,
			d_pos.y / spacing.y - 0.5 * absf(d_pos.x) / spacing.x)
		var dist := maxf(absf(d_cell_f.x), maxf(absf(d_cell_f.y), absf(d_cell_f.x + d_cell_f.y)))
		var radius_cells : float = brush_size / spacing.x * 0.5 + 0.5
		if dist > radius_cells:
			return -1.0
		if not use_falloff:
			return 1.0
		var t : float = 1.0 - clampf(dist / maxf(radius_cells, 0.001), 0.2, 1.0)
		return falloff_curve.sample(clamp(t, 0.001, 0.999))
	return calculate_falloff_sample(cell_pos, brush_pos, brush_size, brush_index, max_distance, use_falloff, falloff_curve)


## Sample for one triangle-terrain cell. The hexagon brush is measured in
## lattice space so its shape aligns with the lattice rows.
static func tri_cell_sample(
	brush_pos : Vector2,
	cell_pos : Vector2,
	brush_size : float,
	brush_index : int,
	max_distance : float,
	use_falloff : bool,
	falloff_curve : Curve,
	cell_size : Vector2
	) -> float:
	if brush_index == 2:
		var af := MarchingSquaresTriGrid.lattice_floats(cell_pos - brush_pos, cell_size)
		var h := maxf(absf(af.y), maxf(absf(af.x) * 1.1547005383792517,
										absf(af.y) + absf(af.x) * 0.5773502691896258))
		var radius_lattice : float = brush_size / cell_size.x * 0.5
		if h > radius_lattice:
			return -1.0
		if not use_falloff:
			return 1.0
		var t : float = 1.0 - clampf(h / maxf(radius_lattice, 0.001), 0.2, 1.0)
		return falloff_curve.sample(clamp(t, 0.001, 0.999))
	return calculate_falloff_sample(cell_pos, brush_pos, brush_size, brush_index, max_distance, use_falloff, falloff_curve)


## Enumerate candidate cells for a chunk in a chunk/non-grid-aligned paint.
## Returns local cell coordinates (may include out-of-range margin cells).
static func cell_candidates_for_chunk(
	chunk_coords : Vector2i,
	terrain : MarchingSquaresTerrain,
	brush_pos : Vector2,
	brush_size : float,
	margin : int = 2
	) -> Array[Vector2i]:
	var cells := terrain.cells_per_chunk()
	var result : Array[Vector2i] = []
	if cells == Vector2i.ZERO:
		return result
	# Convert the brush bounds into global cell space and intersect with chunk.
	var half := brush_size * 0.5
	var global_min := Vector2i.ZERO
	var global_max := Vector2i.ZERO
	if terrain.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		var lo := MarchingSquaresTriGrid.world_to_cell(brush_pos - Vector2(half, half), terrain.cell_size)
		var hi := MarchingSquaresTriGrid.world_to_cell(brush_pos + Vector2(half, half), terrain.cell_size)
		global_min = Vector2i(mini(lo.x, hi.x) - margin, mini(lo.y, hi.y) - margin)
		global_max = Vector2i(maxi(lo.x, hi.x) + margin, maxi(lo.y, hi.y) + margin)
	else:
		var spacing := MarchingSquaresHexGrid.spacing_for(terrain.cell_size)
		var lo := MarchingSquaresHexGrid.world_to_cell(brush_pos - Vector2(half, half), spacing)
		var hi := MarchingSquaresHexGrid.world_to_cell(brush_pos + Vector2(half, half), spacing)
		global_min = Vector2i(mini(lo.x, hi.x) - margin, mini(lo.y, hi.y) - margin)
		global_max = Vector2i(maxi(lo.x, hi.x) + margin, maxi(lo.y, hi.y) + margin)
	
	var chunk_min := chunk_coords * cells
	var local_min := Vector2i(maxi(global_min.x, chunk_min.x), maxi(global_min.y, chunk_min.y)) - chunk_min
	var local_max := Vector2i(mini(global_max.x, chunk_min.x + cells.x - 1), mini(global_max.y, chunk_min.y + cells.y - 1)) - chunk_min
	for r in range(local_min.y, local_max.y + 1):
		for c in range(local_min.x, local_max.x + 1):
			result.append(Vector2i(c, r))
	return result


## World-space XZ center of a global cell.
static func cell_center_for(terrain: MarchingSquaresTerrain, global_cell: Vector2i) -> Vector2:
	if terrain.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		return MarchingSquaresTriGrid.cell_center(global_cell, terrain.cell_size)
	return MarchingSquaresHexGrid.cell_center(global_cell, MarchingSquaresHexGrid.spacing_for(terrain.cell_size))


## Cells selected by a grid-aligned brush. size_mode: false = hex, true = tri.
static func grid_aligned_cells(terrain: MarchingSquaresTerrain, brush_pos: Vector2, grid_size: int) -> Array[Vector2i]:
	if terrain.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		var center := MarchingSquaresTriGrid.nearest_lattice_point(brush_pos, terrain.cell_size)
		return MarchingSquaresTriGrid.cells_in_hexagon(center, maxi(grid_size, 1), terrain.cell_size)
	var spacing := MarchingSquaresHexGrid.spacing_for(terrain.cell_size)
	var center := MarchingSquaresHexGrid.world_to_cell(brush_pos, spacing)
	return MarchingSquaresHexGrid.cells_in_hex_radius(center, maxi(grid_size, 0))


## Outline that exactly encloses a grid-aligned selection:
## { "center": Vector2, "radius": float, "rotation": float (radians around Y) }.
## The hexagon outline visual is pointy-top in UV space; on triangle terrain the
## lattice hexagons are flat-top (corners on the X axis) so a 30 degree rotation
## aligns the outline with the selected triangles.
static func grid_aligned_outline(terrain: MarchingSquaresTerrain, brush_pos: Vector2, grid_size: int) -> Dictionary:
	if terrain.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		var lattice := MarchingSquaresTriGrid.nearest_lattice_point(brush_pos, terrain.cell_size)
		var center := MarchingSquaresTriGrid.lattice_point(lattice.x, lattice.y, terrain.cell_size)
		return {
			"center": center,
			"radius": float(maxi(grid_size, 1)) * terrain.cell_size.x,
			"rotation": deg_to_rad(30.0),
		}
	var spacing := MarchingSquaresHexGrid.spacing_for(terrain.cell_size)
	var cell := MarchingSquaresHexGrid.world_to_cell(brush_pos, spacing)
	var center := MarchingSquaresHexGrid.cell_center(cell, spacing)
	return {
		"center": center,
		"radius": float(maxi(grid_size, 0)) * spacing.x + MarchingSquaresHexGrid.radius_for(terrain.cell_size),
		"rotation": 0.0,
	}

#endregion
