@tool
class_name MarchingSquaresTriGrid
extends RefCounted
## Static math for equilateral triangle cells addressed through the triangular
## lattice's 60-degree rhombi. A rhombus (i, j) is split by its short diagonal
## into triangle A (i, j) and triangle B (i, j). Exposed cell coordinates are
## Vector2i(2 * i + orient, j) with orient 0 = A, 1 = B.
## Pure math, no engine calls.


# Corner index pairs carrying edge k for each orientation, chosen so that the
# edge_neighbors() offsets match the pair geometry exactly:
#   A: edge 0 = (1,2) (+1, 0), edge 1 = (0,2) (-1, 0), edge 2 = (0,1) (+1,-1)
#   B: edge 0 = (1,2) (-1, 0), edge 1 = (0,2) (-1,+1), edge 2 = (0,1) (+1, 0)
const EDGE_CORNER_INDICES_A : Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1),
]
const EDGE_CORNER_INDICES_B : Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1),
]


## Corner index pair carrying a cell's edge k.
static func edge_corner_indices(cell: Vector2i, edge: int) -> Vector2i:
	var table := EDGE_CORNER_INDICES_B if (cell.x & 1) == 1 else EDGE_CORNER_INDICES_A
	return table[edge]


## Triangle edge length (= cell_size.x).
static func side_for(cell_size: Vector2) -> float:
	return cell_size.x


## Distance between lattice rows (= sqrt(3) / 2 * side).
static func row_height(cell_size: Vector2) -> float:
	return sqrt(3.0) / 2.0 * cell_size.x


## World position of a lattice point.
static func lattice_point(i: int, j: int, cell_size: Vector2) -> Vector2:
	var s := cell_size.x
	var h := row_height(cell_size)
	return Vector2(float(i) * s + float(j) * s * 0.5, float(j) * h)


## Inverse of lattice_point for arbitrary points. (alpha, beta) are the
## continuous lattice coordinates.
static func lattice_floats(p: Vector2, cell_size: Vector2) -> Vector2:
	var h := row_height(cell_size)
	var beta := p.y / h
	var alpha := p.x / cell_size.x - beta * 0.5
	return Vector2(alpha, beta)


## Cell containing a world-space point.
static func world_to_cell(p: Vector2, cell_size: Vector2) -> Vector2i:
	var af := lattice_floats(p, cell_size)
	var i := floori(af.x)
	var j := floori(af.y)
	var a := af.x - float(i)
	var b := af.y - float(j)
	var orient := 0 if (a + b) < 1.0 else 1
	return Vector2i(2 * i + orient, j)


## Rhombus column owning a triangle cell coordinate. Rhombus m owns cell
## x values 2m (A) and 2m + 1 (B) for every integer m, so x = -1 belongs to
## rhombus -1 (not 0). Integer division truncates towards zero, so floor.
static func rhombus_i(cell_x: int) -> int:
	return floori(float(cell_x) / 2.0)


## B cell coordinate x for a rhombus column.
static func b_cell_x(i: int) -> int:
	return 2 * i + 1


## A cell coordinate x for a rhombus column.
static func a_cell_x(i: int) -> int:
	return 2 * i


## Corners of a cell in world space.
## A: [L(i, j), L(i+1, j), L(i, j+1)]
## B: [L(i+1, j+1), L(i+1, j), L(i, j+1)]
static func cell_corners(cell: Vector2i, cell_size: Vector2) -> PackedVector2Array:
	var corners := PackedVector2Array()
	corners.resize(3)
	var i := rhombus_i(cell.x)
	var j := cell.y
	if (cell.x & 1) == 0:
		corners[0] = lattice_point(i, j, cell_size)
		corners[1] = lattice_point(i + 1, j, cell_size)
		corners[2] = lattice_point(i, j + 1, cell_size)
	else:
		corners[0] = lattice_point(i + 1, j + 1, cell_size)
		corners[1] = lattice_point(i + 1, j, cell_size)
		corners[2] = lattice_point(i, j + 1, cell_size)
	return corners


## Centroid of a cell in world space.
static func cell_center(cell: Vector2i, cell_size: Vector2) -> Vector2:
	var corners := cell_corners(cell, cell_size)
	return (corners[0] + corners[1] + corners[2]) / 3.0


## Edge neighbors around a cell, indexed by edge 0..2. Edge k carries corner
## pair EDGE_CORNER_INDICES_*[k]. Formula table verified against corner
## geometry for positive and negative coordinates:
##   A(2m, j):   edge 0 -> (x + 1, y),     edge 1 -> (x - 1, y),      edge 2 -> (x + 1, y - 1)
##   B(2m+1, j): edge 0 -> (x - 1, y),     edge 1 -> (x - 1, y + 1),  edge 2 -> (x + 1, y)
static func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var x := cell.x
	var y := cell.y
	var result : Array[Vector2i] = []
	result.resize(3)
	if (x & 1) == 0: # A triangle
		result[0] = Vector2i(x + 1, y)
		result[1] = Vector2i(x - 1, y)
		result[2] = Vector2i(x + 1, y - 1)
	else: # B triangle
		result[0] = Vector2i(x - 1, y)
		result[1] = Vector2i(x - 1, y + 1)
		result[2] = Vector2i(x + 1, y)
	return result


## Hex distance between two lattice points.
static func point_hex_distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Nearest lattice point to a world-space position.
static func nearest_lattice_point(p: Vector2, cell_size: Vector2) -> Vector2i:
	var af := lattice_floats(p, cell_size)
	var i0 := floori(af.x)
	var j0 := floori(af.y)
	var best := Vector2i(i0, j0)
	var best_dist := INF
	for di in range(2):
		for dj in range(2):
			var candidate := Vector2i(i0 + di, j0 + dj)
			var dist := p.distance_squared_to(lattice_point(candidate.x, candidate.y, cell_size))
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best


## All triangles whose three corners lie within lattice-point hex distance n
## of center_point. Forms a regular hexagon of side n (6 * n^2 triangles).
static func cells_in_hexagon(center_point: Vector2i, n: int, cell_size: Vector2) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if n < 1:
		return result
	var i_min := center_point.x - n
	var i_max := center_point.x + n
	var j_min := center_point.y - n
	var j_max := center_point.y + n
	for i in range(i_min - 1, i_max + 2):
		for j in range(j_min - 1, j_max + 2):
			# Triangle A of rhombus (i, j)
			if _triangle_in_hexagon(Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), center_point, n, cell_size):
				result.append(Vector2i(2 * i, j))
			# Triangle B of rhombus (i, j)
			if _triangle_in_hexagon(Vector2i(i + 1, j + 1), Vector2i(i + 1, j), Vector2i(i, j + 1), center_point, n, cell_size):
				result.append(Vector2i(2 * i + 1, j))
	return result


static func _triangle_in_hexagon(
	a: Vector2i, b: Vector2i, c: Vector2i,
	center_point: Vector2i, n: int, _cell_size: Vector2
	) -> bool:
	return (
		point_hex_distance(a, center_point) <= n and
		point_hex_distance(b, center_point) <= n and
		point_hex_distance(c, center_point) <= n
	)


## Chunk containing a global cell.
static func chunk_of_cell(c: Vector2i, cells: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / cells.x), floori(float(c.y) / cells.y))


## Cell coordinate local to its chunk.
static func local_cell(c: Vector2i, cells: Vector2i) -> Vector2i:
	return Vector2i(posmod(c.x, cells.x), posmod(c.y, cells.y))


## Global cell coordinate from chunk coordinate and local cell.
static func global_cell(chunk: Vector2i, local: Vector2i, cells: Vector2i) -> Vector2i:
	return chunk * cells + local
