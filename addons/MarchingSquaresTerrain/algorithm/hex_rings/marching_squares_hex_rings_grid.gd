@tool
class_name MarchingSquaresHexRingsGrid
extends RefCounted
## Static math for hex-ring chunks: a low-res chunk hex owns a disk of micro-hexes,
## mirroring the server's hexmod chunk layout (server/spacetimedb/src/world/hex.rs).
## Pure math, no engine calls. All cell coordinates are axial (q, r); chunk coordinates
## are the low-res axial chunk indices, so a chunk's cells are the fine hexes whose
## [method to_lower_res] is that chunk. World coordinates are the terrain's local XZ plane.
##
## Lockstep siblings: client/Scripts/World/HexMath.cs (ToLowerRes/ChunkCenterHex/HexToLocal/
## WrapHex) and the server's chunk_center_hex / to_lower_res / wrap_hex_coords — all copies
## must change together.


const SQRT3 : float = 1.7320508075688772

## Axial deltas for the 6 neighbor directions, indexed 0-5, where direction D's world offset
## has angle 60*D degrees. Matches the server's HEX_NEIGHBOR_DELTAS and the corner order used
## by [method corner_offsets] (edge k carries corners k and k+1).
const NEIGHBOR_OFFSETS : Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]


## Spacing between hex centers for a given cell size. Hexes stay regular and are sized
## from cell_size.x (the center-to-center distance = sqrt(3) * outer radius).
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


## Center of a cell in world space (axial coordinates).
static func cell_center(cell: Vector2i, spacing: Vector2) -> Vector2:
	return Vector2(
		spacing.x * (float(cell.x) + 0.5 * float(cell.y)),
		spacing.y * float(cell.y))


## Cell containing a world-space point (axial cube rounding).
static func world_to_cell(p: Vector2, spacing: Vector2) -> Vector2i:
	var radius := spacing.x / SQRT3
	var q := (p.x * SQRT3 / 3.0 - p.y / 3.0) / radius
	var r := p.y * 2.0 / 3.0 / radius
	var s := -q - r
	var rq := roundi(q)
	var rr := roundi(r)
	var rs := roundi(s)
	if absf(rq - q) > absf(rr - r) and absf(rq - q) > absf(rs - s):
		rq = -rr - rs
	elif absf(rr - r) > absf(rs - s):
		rr = -rq - rs
	return Vector2i(rq, rr)


## Edge neighbors around a cell, indexed by edge 0..5.
static func edge_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	result.resize(6)
	for i in range(6):
		result[i] = cell + NEIGHBOR_OFFSETS[i]
	return result


## Hex distance in cells between two axial coordinates.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## All cells within a hex radius (a hex disk) around a center cell.
static func cells_in_hex_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if radius < 0:
		return result
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			result.append(center + Vector2i(dq, dr))
	return result


## The low-res chunk hex owning a fine hex (hexx to_lower_res; radius 2 -> 19 cells).
static func to_lower_res(q: int, r: int, radius: int) -> Vector2i:
	var s := -q - r
	var area := 3.0 * float(radius) * float(radius + 1) + 1.0
	var shift := 3 * radius + 2
	var a := floori((float(r) + float(shift) * float(q)) / area)
	var b := floori((float(s) + float(shift) * float(r)) / area)
	var c := floori((float(q) + float(shift) * float(s)) / area)
	return Vector2i(
		floori((1.0 + float(a) - float(b)) / 3.0),
		floori((1.0 + float(b) - float(c)) / 3.0))


## Center hex of a chunk in global axial coordinates (hexx to_higher_res).
static func chunk_center_hex(cq: int, cr: int, radius: int) -> Vector2i:
	var s := -cq - cr
	return Vector2i(cq * (radius + 1) - radius * s, cr * (radius + 1) - radius * cq)


## World-space center of a chunk.
static func chunk_center_world(chunk: Vector2i, radius: int, cell_size: Vector2) -> Vector2:
	var center := chunk_center_hex(chunk.x, chunk.y, radius)
	return cell_center(center, spacing_for(cell_size))


## Local axial offset of a hex inside its owning chunk (cell - chunk center).
static func hex_to_local(q: int, r: int, radius: int) -> Vector2i:
	var chunk := to_lower_res(q, r, radius)
	var center := chunk_center_hex(chunk.x, chunk.y, radius)
	return Vector2i(q - center.x, r - center.y)


## Chunk owning a fine hex.
static func chunk_of_cell(cell: Vector2i, radius: int) -> Vector2i:
	return to_lower_res(cell.x, cell.y, radius)


## Map an arbitrary fine hex back into the canonical lap: the hex's chunk coords wrap and its
## local offset inside the chunk is preserved. Mirror of the server's wrap_hex_coords.
static func wrap_cell(cell: Vector2i, radius: int, cols: int, rows: int) -> Vector2i:
	if cols <= 0 or rows <= 0:
		return cell
	var chunk := to_lower_res(cell.x, cell.y, radius)
	var wrapped := Vector2i(posmod(chunk.x, cols), posmod(chunk.y, rows))
	if chunk == wrapped:
		return cell
	var center := chunk_center_hex(chunk.x, chunk.y, radius)
	var wrapped_center := chunk_center_hex(wrapped.x, wrapped.y, radius)
	return Vector2i(
		wrapped_center.x + cell.x - center.x,
		wrapped_center.y + cell.y - center.y)


## Dense bounding-box size of a chunk: axial local offsets span -radius..radius.
static func cells_per_chunk(radius: int) -> Vector2i:
	return Vector2i(2 * radius + 1, 2 * radius + 1)


## Bounding-box local coordinate of a cell inside its owning chunk (offsets shifted to >= 0).
static func local_cell(cell: Vector2i, radius: int) -> Vector2i:
	var local := hex_to_local(cell.x, cell.y, radius)
	return Vector2i(local.x + radius, local.y + radius)


## Global cell coordinate from a chunk coordinate and a bounding-box local cell.
static func global_cell(chunk: Vector2i, local: Vector2i, radius: int) -> Vector2i:
	var center := chunk_center_hex(chunk.x, chunk.y, radius)
	return Vector2i(center.x + local.x - radius, center.y + local.y - radius)


## Whether a bounding-box local cell is inside the chunk's hex disk (the box corners are not).
static func has_local(local: Vector2i, radius: int) -> bool:
	var dq := local.x - radius
	var dr := local.y - radius
	return absi(dq) <= radius and absi(dr) <= radius and absi(dq + dr) <= radius
