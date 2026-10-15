@tool
extends RefCounted
class_name MSTGridSnap
## Shared grid snapping helper for MST terrains.
##
## Snaps points to the terrain's vertex or cell-center lattice in terrain-local
## space, optionally scaling the lattice by a cell-size multiplier. v1 supports
## square terrains only; triangle/hex terrains are reported as unsupported so
## callers can disable grid-align UI instead of snapping to a lattice that does
## not exist yet.

enum AlignKind { VERTEX_AND_CENTER, VERTEX_ONLY, CENTER_ONLY }

## Default options used by [method snap] and [method snap_point].
const DEFAULT_OPTIONS : Dictionary = {
	"cell_multiplier": 1,
	"align_kind": AlignKind.VERTEX_AND_CENTER,
	"y_snap": false,
	"y_snap_distance": 1.0,
}


## True when [param terrain] has a lattice this helper understands.
## v1 only implements square grids (triangle/hex snapping is deferred).
static func is_supported(terrain : MarchingSquaresTerrain) -> bool:
	return terrain != null and terrain.grid_type == MarchingSquaresTerrain.GridType.SQUARE


## Effective lattice size for [param terrain] and a cell-size multiplier.
static func lattice_size(terrain : MarchingSquaresTerrain, cell_multiplier : int) -> Vector2:
	return terrain.cell_size * maxi(cell_multiplier, 1)


## Snap a point in terrain-local XZ space to the nearest vertex and/or cell
## center. Returns the input unchanged when the terrain is unsupported.
static func snap_xz(local_point : Vector2, terrain : MarchingSquaresTerrain, cell_multiplier : int = 1,
		kind : AlignKind = AlignKind.VERTEX_AND_CENTER) -> Vector2:
	if not is_supported(terrain):
		return local_point
	
	var lattice := lattice_size(terrain, cell_multiplier)
	var vertex := (local_point / lattice + Vector2(0.5, 0.5)).floor() * lattice
	var center := (local_point / lattice).floor() * lattice + lattice * 0.5
	
	match kind:
		AlignKind.VERTEX_ONLY:
			return vertex
		AlignKind.CENTER_ONLY:
			return center
		_:
			var vertex_dist := local_point.distance_squared_to(vertex)
			var center_dist := local_point.distance_squared_to(center)
			return vertex if vertex_dist <= center_dist else center


## Snap a world-space point using the terrain's transform.
## [param opts] keys: cell_multiplier (int), align_kind ([enum AlignKind]),
## y_snap (bool), y_snap_distance (float). Y snapping is applied in terrain-local
## space so rotated/scaled terrains behave predictably.
## Returns a Dictionary with "point" (Vector3) and "unsupported" (bool).
static func snap(point : Vector3, terrain : MarchingSquaresTerrain, opts : Dictionary = {}) -> Dictionary:
	var result := {"point": point, "unsupported": false}
	if not is_supported(terrain):
		result["unsupported"] = true
		return result
	
	var multiplier : int = opts.get("cell_multiplier", DEFAULT_OPTIONS["cell_multiplier"])
	var kind := _coerce_kind(opts.get("align_kind", DEFAULT_OPTIONS["align_kind"]))
	var y_snap : bool = opts.get("y_snap", DEFAULT_OPTIONS["y_snap"])
	var y_distance : float = opts.get("y_snap_distance", DEFAULT_OPTIONS["y_snap_distance"])
	
	var local := terrain.to_local(point)
	var local_xz := snap_xz(Vector2(local.x, local.z), terrain, multiplier, kind)
	local.x = local_xz.x
	local.z = local_xz.y
	if y_snap and y_distance > 0.0:
		local.y = snappedf(local.y, y_distance)
	
	result["point"] = terrain.to_global(local)
	return result


## Convenience wrapper around [method snap] for callers that do not need the
## unsupported flag.
static func snap_point(point : Vector3, terrain : MarchingSquaresTerrain, opts : Dictionary = {}) -> Vector3:
	return snap(point, terrain, opts)["point"]


## Lattice candidates considered for [param local_point], in terrain-local XZ
## space. Used by debug overlays to draw both lattices while grid align is
## active.
static func candidate_points(local_point : Vector2, terrain : MarchingSquaresTerrain, cell_multiplier : int = 1,
		kind : AlignKind = AlignKind.VERTEX_AND_CENTER) -> Array[Vector2]:
	var result : Array[Vector2] = []
	if not is_supported(terrain):
		return result
	
	var lattice := lattice_size(terrain, cell_multiplier)
	var vertex := (local_point / lattice + Vector2(0.5, 0.5)).floor() * lattice
	var center := (local_point / lattice).floor() * lattice + lattice * 0.5
	match kind:
		AlignKind.VERTEX_ONLY:
			result.append(vertex)
		AlignKind.CENTER_ONLY:
			result.append(center)
		_:
			result.append(vertex)
			result.append(center)
	return result


## Which lattice the nearest match belongs to for [param local_point].
static func nearest_kind(local_point : Vector2, terrain : MarchingSquaresTerrain,
		cell_multiplier : int = 1) -> AlignKind:
	var candidates := candidate_points(local_point, terrain, cell_multiplier)
	if candidates.size() < 2:
		return AlignKind.VERTEX_AND_CENTER
	var vertex_dist := local_point.distance_squared_to(candidates[0])
	var center_dist := local_point.distance_squared_to(candidates[1])
	return AlignKind.VERTEX_ONLY if vertex_dist <= center_dist else AlignKind.CENTER_ONLY


static func _coerce_kind(value) -> AlignKind:
	match int(value):
		AlignKind.VERTEX_ONLY:
			return AlignKind.VERTEX_ONLY
		AlignKind.CENTER_ONLY:
			return AlignKind.CENTER_ONLY
		_:
			return AlignKind.VERTEX_AND_CENTER
