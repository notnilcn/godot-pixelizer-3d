@tool
class_name MarchingSquaresHexGrid
extends RefCounted
## Static math for pointy-top, odd-r offset hexagonal cells.
## Pure math, no engine calls. All coordinates are cell coordinates unless
## noted otherwise; world coordinates are the terrain's local XZ plane.


const SQRT3 : float = 1.7320508075688772

# Edge k uses corners (k, (k + 1) % 6). Its outward normal angle is 60 * k
# degrees from +x towards +z.
const EDGE_NEIGHBORS_EVEN : Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1),
]
const EDGE_NEIGHBORS_ODD : Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]


## Spacing between hex centers for a given cell size.
## Hexes stay regular and are sized from cell_size.x only.
static func spacing_for(cell_size: Vector2) -> Vector2:
	return Vector2(cell_size.x, cell_size.x * 0.8660254037844386)


## Circumradius (center to corner distance).
static func radius_for(cell_size: Vector2) -> float:
	return cell_size.x / SQRT3


## 6 corner offsets, starting at -30 degrees and advancing by 60 degrees.
static func corner_offsets(radius: float) -> PackedVector2Array:
	var corners := PackedVector2Array()
	corners.resize(6)
	for i in range(6):
		var angle := deg_to_rad(-30.0 + 60.0 * float(i))
		corners[i] = Vector2(radius * cos(angle), radius * sin(angle))
	return corners


## Center of a cell in world space.
static func cell_center(cell: Vector2i, spacing: Vector2) -> Vector2:
	return Vector2(
		spacing.x * (float(cell.x) + 0.5 * float(cell.y & 1)),
		spacing.y * float(cell.y))


## Cell containing a world-space point.
static func world_to_cell(p: Vector2, spacing: Vector2) -> Vector2i:
	var row := roundi(p.y / spacing.y)
	var col := roundi(p.x / spacing.x - 0.5 * float(row & 1))
	return Vector2i(col, row)


## Edge neighbors around a cell, indexed by edge 0..5.
static func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var table := EDGE_NEIGHBORS_ODD if (cell.y & 1) == 1 else EDGE_NEIGHBORS_EVEN
	var result : Array[Vector2i] = []
	result.resize(6)
	for i in range(6):
		result[i] = cell + table[i]
	return result


## Convert offset coordinates to axial coordinates.
static func to_axial(c: Vector2i) -> Vector2i:
	return Vector2i(c.x - floori(float(c.y - (c.y & 1)) / 2.0), c.y)


## Convert axial coordinates to offset coordinates.
static func axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + floori(float(a.y - (a.y & 1)) / 2.0), a.y)


## Hex distance in cells between two offset coordinates.
static func hex_distance(at: Vector2i, bt: Vector2i) -> int:
	var d := to_axial(at) - to_axial(bt)
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## All cells within a hex radius (a hex disk) around a center cell.
static func cells_in_hex_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if radius < 0:
		return result
	var center_axial := to_axial(center)
	for dx in range(-radius, radius + 1):
		for dy in range(maxi(-radius, -dx - radius), mini(radius, -dx + radius) + 1):
			result.append(axial_to_offset(center_axial + Vector2i(dx, dy)))
	return result


## Chunk containing a global cell.
static func chunk_of_cell(c: Vector2i, cells: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / cells.x), floori(float(c.y) / cells.y))


## Cell coordinate local to its chunk.
static func local_cell(c: Vector2i, cells: Vector2i) -> Vector2i:
	return Vector2i(posmod(c.x, cells.x), posmod(c.y, cells.y))


## Global cell coordinate from chunk coordinate and local cell.
static func global_cell(chunk: Vector2i, local: Vector2i, cells: Vector2i) -> Vector2i:
	return chunk * cells + local
