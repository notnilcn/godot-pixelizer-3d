@tool
class_name BrushPatternCalculator

## Calculates which cells fall within a brush and their falloff samples.
## Used by both plugin (for editing) and gizmo (for visualization).

# Normalized hexagon SDF constants (2 / sqrt(3) and 1 / sqrt(3)).
const HEXAGON_SIDE_SCALE : float = 1.1547005383792517
const HEXAGON_EDGE_SCALE : float = 0.5773502691896258
const COS_30 : float = 0.8660254037844386
const SIN_30 : float = 0.5

# Normalized equilateral triangle SDF constant (sqrt(3)).
const TRIANGLE_SIDE_SCALE : float = 1.7320508075688772


class BrushBounds:
	var chunk_tl : Vector2i
	var chunk_br : Vector2i
	var cell_tl : Vector2i
	var cell_br : Vector2i


## True for the Hexagon and Hexagon30 brush shapes.
static func is_hexagon_brush(brush_index: int) -> bool:
	return brush_index == 2 or brush_index == 3


## True when the hexagon brush is rotated 30 degrees (flat-top).
static func is_rotated_hexagon(brush_index: int) -> bool:
	return brush_index == 3


## True for the Triangle and Triangle180 brush shapes.
static func is_triangle_brush(brush_index: int) -> bool:
	return brush_index == 4 or brush_index == 5


## True when the triangle brush is rotated 180 degrees (point-down).
static func is_rotated_triangle(brush_index: int) -> bool:
	return brush_index == 5


static func _rotate_30(v: Vector2) -> Vector2:
	return Vector2(v.x * COS_30 + v.y * SIN_30, -v.x * SIN_30 + v.y * COS_30)


## Pointy-top hexagon field in normalized space: <= 1 is inside, > 1 outside.
## Rotating the sample point by 30 degrees yields the flat-top (Hexagon30) shape.
static func hexagon_field(uv: Vector2, rotated_30: bool) -> float:
	if rotated_30:
		uv = _rotate_30(uv)
	return maxf(absf(uv.y), maxf(absf(uv.x) * HEXAGON_SIDE_SCALE,
		absf(uv.y) + absf(uv.x) * HEXAGON_EDGE_SCALE))


## Equilateral triangle field in normalized space: <= 1 is inside, > 1 outside.
## The base triangle has its apex on +Y and a flat bottom edge; rotating the
## sample point by 180 degrees yields the point-down (Triangle180) shape.
static func triangle_field(uv: Vector2, rotated_180: bool) -> float:
	if rotated_180:
		uv = -uv
	return maxf(TRIANGLE_SIDE_SCALE * absf(uv.x) + uv.y, -2.0 * uv.y)


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
		3: # Hexagon30 brush (flat-top)
			max_distance *= max_distance
		4: # Triangle brush (point-up)
			max_distance *= max_distance
		5: # Triangle180 brush (point-down)
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
	
	if is_hexagon_brush(brush_index):
		# Hexagon test in normalized brush space.
		var uv := (world_pos - brush_pos) / (brush_size * 0.5)
		var h := hexagon_field(uv, is_rotated_hexagon(brush_index))
		if h > 1.0:
			return -1.0  # Outside brush
		if not use_falloff:
			return 1.0
		var t_hex : float = 1.0 - clampf(h, 0.2, 1.0)
		return falloff_curve.sample(clamp(t_hex, 0.001, 0.999))
	
	if is_triangle_brush(brush_index):
		# Triangle test in normalized brush space.
		var uv := (world_pos - brush_pos) / (brush_size * 0.5)
		var h := triangle_field(uv, is_rotated_triangle(brush_index))
		if h > 1.0:
			return -1.0  # Outside brush
		if not use_falloff:
			return 1.0
		var t_tri : float = 1.0 - clampf(h, 0.2, 1.0)
		return falloff_curve.sample(clamp(t_tri, 0.001, 0.999))
	
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

## Sample for one hex-terrain cell. brush_pos and cell_pos are world XZ; center_pos is the
## world-space center of the cell under the brush (the same pointy-top lattice for the offset
## hex grid and the axial hex-rings grid).
static func hex_cell_sample(
	brush_pos : Vector2,
	cell_pos : Vector2,
	brush_size : float,
	brush_index : int,
	max_distance : float,
	use_falloff : bool,
	falloff_curve : Curve,
	center_pos : Vector2,
	spacing : Vector2
	) -> float:
	if is_hexagon_brush(brush_index):
		# Continuous hex distance in cell space around the cell under the
		# brush. Cell centers sit on a pointy-top lattice where world
		# X = spacing.x * (q + r / 2) and world Z = spacing.y * r, so the
		# axial delta is (dx / sx - 0.5 * dz / sz, dz / sz).
		var d_pos := cell_pos - center_pos
		if is_rotated_hexagon(brush_index):
			d_pos = _rotate_30(d_pos)
		var d_cell_f := Vector2(
			d_pos.x / spacing.x - 0.5 * d_pos.y / spacing.y,
			d_pos.y / spacing.y)
		var dist := maxf(absf(d_cell_f.x), maxf(absf(d_cell_f.y), absf(d_cell_f.x + d_cell_f.y)))
		var radius_cells : float = brush_size / spacing.x * 0.5 + 0.5
		if dist > radius_cells:
			return -1.0
		if not use_falloff:
			return 1.0
		var t : float = 1.0 - clampf(dist / maxf(radius_cells, 0.001), 0.2, 1.0)
		return falloff_curve.sample(clamp(t, 0.001, 0.999))
	return calculate_falloff_sample(cell_pos, brush_pos, brush_size, brush_index, max_distance, use_falloff, falloff_curve)


## Sample for one triangle-terrain cell. Brush shapes are measured in world
## space so the selected cells match the drawn brush outline on every terrain.
static func tri_cell_sample(
	brush_pos : Vector2,
	cell_pos : Vector2,
	brush_size : float,
	brush_index : int,
	max_distance : float,
	use_falloff : bool,
	falloff_curve : Curve,
	_cell_size : Vector2
	) -> float:
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
	# Ring chunks are small and not rectangular-indexed: return every real cell and let the
	# brush sample filter them.
	if terrain.grid_type == MarchingSquaresTerrain.GridType.HEX_RINGS:
		var ring_chunk = terrain.chunks.get(chunk_coords)
		if ring_chunk == null:
			return result
		for r in range(cells.y):
			for c in range(cells.x):
				if ring_chunk.has_cell(Vector2i(c, r)):
					result.append(Vector2i(c, r))
		return result
	# Convert the brush bounds into global cell space and intersect with chunk.
	var half := brush_size * 0.5
	var lo := terrain.world_to_cell(brush_pos - Vector2(half, half))
	var hi := terrain.world_to_cell(brush_pos + Vector2(half, half))
	var global_min := Vector2i(mini(lo.x, hi.x) - margin, mini(lo.y, hi.y) - margin)
	var global_max := Vector2i(maxi(lo.x, hi.x) + margin, maxi(lo.y, hi.y) + margin)
	
	var chunk_min := chunk_coords * cells
	var local_min := Vector2i(maxi(global_min.x, chunk_min.x), maxi(global_min.y, chunk_min.y)) - chunk_min
	var local_max := Vector2i(mini(global_max.x, chunk_min.x + cells.x - 1), mini(global_max.y, chunk_min.y + cells.y - 1)) - chunk_min
	for r in range(local_min.y, local_max.y + 1):
		for c in range(local_min.x, local_max.x + 1):
			result.append(Vector2i(c, r))
	return result


## World-space XZ center of a global cell.
static func cell_center_for(terrain: MarchingSquaresTerrain, global_cell: Vector2i) -> Vector2:
	return terrain.cell_center_of(global_cell)


## Cells selected by a grid-aligned brush. size_mode: false = hex, true = tri.
static func grid_aligned_cells(terrain: MarchingSquaresTerrain, brush_pos: Vector2, grid_size: int) -> Array[Vector2i]:
	if terrain.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
		var center := MarchingSquaresTriGrid.nearest_lattice_point(brush_pos, terrain.cell_size)
		return MarchingSquaresTriGrid.cells_in_hexagon(center, maxi(grid_size, 1), terrain.cell_size)
	if terrain.grid_type == MarchingSquaresTerrain.GridType.HEX_RINGS:
		return MarchingSquaresHexRingsGrid.cells_in_hex_radius(terrain.world_to_cell(brush_pos), maxi(grid_size, 0))
	var spacing := MarchingSquaresHexGrid.spacing_for(terrain.cell_size)
	var center := MarchingSquaresHexGrid.world_to_cell(brush_pos, spacing)
	return MarchingSquaresHexGrid.cells_in_hex_radius(center, maxi(grid_size, 0))


## Outline that exactly encloses a grid-aligned selection:
## { "center": Vector2, "radius": float, "rotation": float (radians around Y) }.
## The hexagon outline visual is pointy-top in UV space. Hex disks (N >= 1)
## have their corners on the X axis, so a 30 degree rotation aligns the outline
## with the selected cells; a single-cell selection (N = 0) is one pointy-top
## hex cell and keeps the outline as-is. Triangle selections are flat-top.
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
	var cell := terrain.world_to_cell(brush_pos)
	var center := terrain.cell_center_of(cell)
	var radius_cells := maxi(grid_size, 0)
	return {
		"center": center,
		"radius": float(radius_cells) * spacing.x + MarchingSquaresHexGrid.radius_for(terrain.cell_size),
		"rotation": 0.0 if radius_cells == 0 else deg_to_rad(30.0),
	}

#endregion
