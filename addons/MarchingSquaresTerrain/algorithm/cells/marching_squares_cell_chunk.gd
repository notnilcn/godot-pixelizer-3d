@tool
class_name MarchingSquaresCellChunk
extends MarchingSquaresTerrainChunkBase
## Shared chunk implementation for cell-centered modes (triangle, hexagon).
## Each cell renders as a flat regular polygon at its own height plus vertical
## wall quads where a neighbor is lower. Subclasses provide the coordinate and
## shape math by delegating to MarchingSquaresHexGrid / MarchingSquaresTriGrid.
## Merge modes turn walls below a height threshold into 45-degree ramps (the
## higher cell's edge connects to a lower line inside the neighbour cell).


# Same values/order as MarchingSquaresTerrainChunk: the threshold is the
# maximum height difference that is merged into a ramp instead of a wall.
enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}

const MERGE_MODE = {
	Mode.CUBIC: 0.6,
	Mode.POLYHEDRON: 1.3,
	Mode.ROUNDED_POLYHEDRON: 2.1,
	Mode.SEMI_ROUND: 5.0,
	Mode.SPHERICAL: 20.0,
}

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.CUBIC: # The max height distance between cells before a wall is created
	set(mode):
		merge_mode = mode
		merge_threshold = MERGE_MODE[mode]
		# Mesh generation reads every cell map, so do not rebuild while data
		# import has not populated them yet; initialize_terrain regenerates.
		if is_inside_tree() and terrain_system and _cell_maps_initialized():
			regenerate_mesh()

var merge_threshold : float = MERGE_MODE[Mode.CUBIC]


# Terrain-side state is fetched through terrain_system (see the base class).
var global_position_cached : Vector3 = Vector3.ZERO

# Cells painted by the bridge tool (1 = top surface blends with smooth
# neighbours so a bridge reads as a slanted plane instead of flat steps).
var smooth_map : PackedByteArray
var _has_smooth_cells : bool = false

# Caches used while regenerating a mesh (cleared on every regeneration).
var _corner_height_cache : Dictionary = {}
var _corner_key_cache : Dictionary = {}
const CORNER_KEY_SCALE : float = 1024.0

var bake_material : ShaderMaterial = preload("uid://cbbvkbnwmr2em")

#region temporary storage vars (mirrors the square chunk save hooks)
var _temp_mesh : ArrayMesh
var _temp_collision_shapes : Array[ConcavePolygonShape3D] = []
var _temp_height_map : Array = []
var _temp_grass_multimesh : MultiMesh
#endregion

# Grass-relevant cell changes since the last mesh regeneration (cell index keys).
var _grass_dirty_cells : Dictionary = {}


#region subclas responsibilities (virtuals)

## Number of cells along x and y in this chunk.
func cells_per_chunk() -> Vector2i:
	return Vector2i.ZERO


## World-space position of a global cell's center.
func cell_center_world(_cell: Vector2i) -> Vector2:
	return Vector2.ZERO


## World-space corner offsets of a global cell relative to its center.
func cell_corner_offsets(_cell: Vector2i) -> PackedVector2Array:
	return PackedVector2Array()


## Edge neighbors of a global cell, indexed by edge.
func edge_neighbors(_cell: Vector2i) -> Array[Vector2i]:
	return []


## Corner index pair carrying an edge.
func edge_corner_indices(_cell: Vector2i, _edge: int) -> Vector2i:
	return Vector2i.ZERO


## World-space position of the chunk's local cell (0, 0) reference point
## (the cell center for hex, the lattice origin for triangle).
func get_chunk_origin_world() -> Vector2:
	return cell_center_world(_chunk_global_cell(Vector2i.ZERO))

#endregion


#region helpers

## Global cell coordinate for a local cell coordinate.
func _chunk_global_cell(local: Vector2i) -> Vector2i:
	return global_cell(chunk_coords, local, cells_per_chunk())


func cell_index(cc: Vector2i) -> int:
	return cc.y * cells_per_chunk().x + cc.x


## True once every per-cell map matches the chunk's cell count. Mesh
## generation reads all of them, so setters must not regenerate before data
## import / initialize_terrain has sized them.
func _cell_maps_initialized() -> bool:
	var count := cells_per_chunk().x * cells_per_chunk().y
	if count <= 0:
		return false
	return height_map.size() == count \
			and color_map_0.size() == count \
			and color_map_1.size() == count \
			and wall_color_map_0.size() == count \
			and wall_color_map_1.size() == count \
			and grass_mask_map.size() == count \
			and smooth_map.size() == count


func global_cell(chunk: Vector2i, local: Vector2i, cells: Vector2i) -> Vector2i:
	return chunk * cells + local


## Rounded world position of a global cell's center.
func _cell_center_rounded(cell: Vector2i) -> Vector2:
	return cell_center_world(cell)


#endregion


func initialize_terrain(should_regenerate_mesh: bool = true):
	var count := cells_per_chunk().x * cells_per_chunk().y
	var generated := false
	if not height_map or height_map.size() != count:
		generate_height_map()
		generated = true
	if not color_map_0 or color_map_0.size() != count:
		generate_color_maps()
	if not wall_color_map_0 or wall_color_map_0.size() != count:
		generate_wall_color_maps()
	if not grass_mask_map or grass_mask_map.size() != count:
		generate_grass_mask_map()
	if not smooth_map or smooth_map.size() != count:
		generate_smooth_map()
	refresh_smooth_flag()
	
	_initialize_grass_planter()
	
	if not mesh and should_regenerate_mesh:
		regenerate_mesh(false)
	elif mesh:
		if terrain_system:
			mesh.surface_set_material(0, terrain_system.terrain_material)
		if not _temp_collision_shapes.is_empty():
			_recreate_collision_body()
		else:
			for child in get_children():
				if child is StaticBody3D:
					child.free()
			create_trimesh_collision()
			_setup_collision_layers()
	
	if generated:
		mark_dirty()
	
	if not EngineWrapper.is_editor() and terrain_system.enable_runtime_texture_baking:
		var baker := MarchingSquaresGeometryBaker.new()
		baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
		baker.finished.connect(_on_bake_finished, CONNECT_ONE_SHOT)
		baker.bake_geometry_texture(self, get_tree())


## Applies the baked atlas to this chunk's mesh (runtime texture baking).
func _on_bake_finished(baked_mesh: Mesh, _original: MeshInstance3D, img: Image) -> void:
	mesh = baked_mesh
	var mat : Material
	if terrain_system.bake_material_override:
		mat = terrain_system.bake_material_override.duplicate()
	else:
		mat = bake_material.duplicate()
	
	if mat is StandardMaterial3D:
		mat.albedo_texture = ImageTexture.create_from_image(img)
	elif mat is ShaderMaterial:
		mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
	mesh.surface_set_material(0, mat)


## Create or rebind the per-cell grass planter (mirrors the square chunk).
func _initialize_grass_planter() -> void:
	grass_planter = get_node_or_null("GrassPlanter")
	if not grass_planter:
		grass_planter = MarchingSquaresCellGrassPlanter.new()
		add_child(grass_planter)
		EngineWrapper.set_owner_recursive(grass_planter)
	
	grass_planter.name = "GrassPlanter"
	grass_planter._chunk = self
	grass_planter.terrain_system = terrain_system
	
	if _temp_grass_multimesh:
		grass_planter.multimesh = _temp_grass_multimesh
		_temp_grass_multimesh = null
	if not grass_planter.multimesh:
		grass_planter.setup(self)
		grass_planter.regenerate_all_cells()
	if terrain_system:
		grass_planter.multimesh.mesh = terrain_system.grass_mesh


func _notification(what: int) -> void:
	if not EngineWrapper.is_editor():
		return
	
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_skip_save_on_exit = _skip_save_on_exit # Surpress warning
			_temp_height_map = height_map
			height_map = []
			
			_temp_mesh = mesh
			mesh = null
			
			# Store grass multimesh and clear
			if grass_planter and grass_planter.multimesh:
				_temp_grass_multimesh = grass_planter.multimesh
				grass_planter.multimesh = null
			
			_temp_collision_shapes.clear()
			var bodies_to_free : Array[StaticBody3D] = []
			for child in get_children():
				if child is StaticBody3D:
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
							_temp_collision_shapes.append(shape_child.shape)
							shape_child.shape = null
						shape_child.owner = null
					child.owner = null
					bodies_to_free.append(child)
			for body in bodies_to_free:
				body.name += "_"
				body.queue_free()
		
		NOTIFICATION_EDITOR_POST_SAVE:
			if _temp_height_map:
				height_map = _temp_height_map
				_temp_height_map = []
			
			if _temp_mesh:
				mesh = _temp_mesh
				_temp_mesh = null
			
			# Restore grass multimesh
			if _temp_grass_multimesh and grass_planter:
				grass_planter.multimesh = _temp_grass_multimesh
				_temp_grass_multimesh = null
			
			if not _temp_collision_shapes.is_empty():
				_recreate_collision_body.call_deferred()
		
		NOTIFICATION_PREDELETE:
			for child in get_children():
				if child is StaticBody3D:
					child.owner = null
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D:
							shape_child.owner = null


func _enter_tree() -> void:
	if get_parent() != terrain_system:
		push_error("Chunk must remain within its parent!")
	if terrain_system:
		terrain_system.chunks[chunk_coords] = self


func _exit_tree() -> void:
	_temp_height_map = []
	_temp_mesh = null
	_temp_grass_multimesh = null
	_temp_collision_shapes.clear()
	
	if EngineWrapper.is_editor():
		for child in get_children():
			if child is StaticBody3D:
				child.owner = null
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.owner = null
	
	if terrain_system and terrain_system.chunks.get(chunk_coords) == self:
		terrain_system.chunks.erase(chunk_coords)


## Recreate collision body after scene save (deferred call for proper physics refresh).
func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	
	var shape : ConcavePolygonShape3D = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()
	
	var body := StaticBody3D.new()
	body.name = name + "_col"
	body.collision_layer = 17
	if terrain_system:
		body.set_collision_layer_value(terrain_system.extra_collision_layer, true)
	
	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	col_shape.shape = shape
	col_shape.visible = false
	body.add_child(col_shape)
	add_child(body)
	
	if EngineWrapper.is_editor():
		var scene_root = EngineWrapper.get_root_for_node(self)
		if scene_root:
			body.owner = scene_root
			col_shape.owner = scene_root
		for group in get_groups():
			if group.begins_with("navmesh_"):
				body.add_to_group(group)


func _setup_collision_layers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.collision_layer = 17
			if terrain_system:
				child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			for _child in child.get_children():
				if _child is CollisionShape3D:
					_child.set_visible(false)


#region cell_geometry generators (when empty)

func generate_height_map():
	var cells := cells_per_chunk()
	var count := cells.x * cells.y
	height_map = []
	height_map.resize(count)
	var noise = terrain_system.noise_hmap if terrain_system else null
	for r in range(cells.y):
		for c in range(cells.x):
			var global := _chunk_global_cell(Vector2i(c, r))
			var center := cell_center_world(global)
			if noise:
				height_map[cell_index(Vector2i(c, r))] = noise.get_noise_2d(center.x, center.y) * terrain_system.dimensions.y
			else:
				height_map[cell_index(Vector2i(c, r))] = 0.0


func generate_color_maps():
	var count := cells_per_chunk().x * cells_per_chunk().y
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	color_map_0.resize(count)
	color_map_1.resize(count)
	for i in count:
		color_map_0[i] = Color(0, 0, 0, 0)
		color_map_1[i] = Color(0, 0, 0, 0)


func generate_wall_color_maps():
	var count := cells_per_chunk().x * cells_per_chunk().y
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	wall_color_map_0.resize(count)
	wall_color_map_1.resize(count)
	for i in count:
		wall_color_map_0[i] = Color(1, 0, 0, 0) # Default to texture slot 0
		wall_color_map_1[i] = Color(1, 0, 0, 0)


func generate_grass_mask_map():
	var count := cells_per_chunk().x * cells_per_chunk().y
	grass_mask_map = PackedColorArray()
	grass_mask_map.resize(count)
	for i in count:
		grass_mask_map[i] = Color(1.0, 1.0, 1.0, 1.0)


func generate_smooth_map():
	var count := cells_per_chunk().x * cells_per_chunk().y
	smooth_map = PackedByteArray()
	smooth_map.resize(count)
	_has_smooth_cells = false


## Recomputes the fast-path flag from the current smooth map.
func refresh_smooth_flag() -> void:
	_has_smooth_cells = false
	for value in smooth_map:
		if value != 0:
			_has_smooth_cells = true
			return

#endregion


#region cell_geometry getters

func get_height(cc: Vector2i) -> float:
	return height_map[cell_index(cc)]


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cell_index(cc)]


func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cell_index(cc)]


func get_wall_color_0(cc: Vector2i) -> Color:
	return wall_color_map_0[cell_index(cc)]


func get_wall_color_1(cc: Vector2i) -> Color:
	return wall_color_map_1[cell_index(cc)]


func get_grass_mask(cc: Vector2i) -> Color:
	return grass_mask_map[cell_index(cc)]


func get_smooth(cc: Vector2i) -> bool:
	if not _has_smooth_cells:
		return false
	if cc.x < 0 or cc.y < 0 or cc.x >= cells_per_chunk().x or cc.y >= cells_per_chunk().y:
		return false
	var idx := cell_index(cc)
	return idx < smooth_map.size() and smooth_map[idx] != 0


func has_smooth_cells() -> bool:
	return _has_smooth_cells

#endregion


#region cell_geometry setters

func draw_height(x: int, z: int, y: float):
	height_map[cell_index(Vector2i(x, z))] = y
	_grass_dirty_cells[cell_index(Vector2i(x, z))] = true
	mark_dirty()


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[cell_index(Vector2i(x, z))] = color
	_grass_dirty_cells[cell_index(Vector2i(x, z))] = true
	mark_dirty()


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[cell_index(Vector2i(x, z))] = color
	_grass_dirty_cells[cell_index(Vector2i(x, z))] = true
	mark_dirty()


func draw_wall_color_0(x: int, z: int, color: Color):
	wall_color_map_0[cell_index(Vector2i(x, z))] = color
	mark_dirty()


func draw_wall_color_1(x: int, z: int, color: Color):
	wall_color_map_1[cell_index(Vector2i(x, z))] = color
	mark_dirty()


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[cell_index(Vector2i(x, z))] = masked
	_grass_dirty_cells[cell_index(Vector2i(x, z))] = true
	mark_dirty()


func draw_smooth(x: int, z: int, smooth: bool):
	if smooth_map.size() != cells_per_chunk().x * cells_per_chunk().y:
		generate_smooth_map()
	smooth_map[cell_index(Vector2i(x, z))] = 1 if smooth else 0
	if smooth:
		_has_smooth_cells = true
	mark_dirty()

#endregion


func mark_dirty() -> void:
	_data_dirty = true


#region mesh generation

func regenerate_mesh(_use_threads: bool = false):
	_corner_height_cache.clear()
	_corner_key_cache.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)
	
	global_position_cached = global_position if is_inside_tree() else position
	
	var cells := cells_per_chunk()
	var origin := get_chunk_origin_world()
	var grass_dirty : Array = _grass_dirty_cells.keys()
	_grass_dirty_cells.clear()
	for r in range(cells.y):
		for c in range(cells.x):
			_emit_cell(st, Vector2i(c, r), origin)
	
	# Regenerate grass only for cells whose height/colors/mask changed.
	if grass_planter:
		for idx in grass_dirty:
			var local := Vector2i(int(idx) % cells.x, int(idx) / cells.x)
			grass_planter.generate_grass_on_cell(local)
	
	st.generate_normals()
	st.index()
	mesh = st.commit()
	
	if mesh and terrain_system:
		mesh.surface_set_material(0, terrain_system.terrain_material)
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	create_trimesh_collision()
	_setup_collision_layers()


#region smooth-corner interpolation

## Corner heights for a smooth cell's top surface. Each corner averages the
## heights of the smooth cells around it, so neighbouring smooth cells share
## identical corner heights and a bridge renders as one continuous slope.
func cell_corner_heights(global: Vector2i) -> PackedFloat32Array:
	if _corner_height_cache.has(global):
		return _corner_height_cache[global]
	var offsets := cell_corner_offsets(global)
	var count := offsets.size()
	var heights := PackedFloat32Array()
	heights.resize(count)
	var h_variant = terrain_system.get_cell_height(global) if terrain_system else null
	var h : float = float(h_variant) if h_variant != null else 0.0
	for i in range(count):
		heights[i] = h
	if terrain_system and terrain_system.get_cell_smooth(global):
		var keys := _corner_keys(global)
		for i in range(count):
			var sum := 0.0
			var n := 0
			for cell in cells_around_corner(global, keys[i]):
				if not terrain_system.get_cell_smooth(cell):
					continue
				var cell_h = terrain_system.get_cell_height(cell)
				if cell_h == null:
					continue
				sum += float(cell_h)
				n += 1
			if n > 0:
				heights[i] = sum / float(n)
	_corner_height_cache[global] = heights
	return heights


## All existing cells sharing a lattice corner with `global` (which owns
## `key`), walked through the edges that carry that corner.
func cells_around_corner(global: Vector2i, key: Vector2i) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	var visited : Dictionary = {global: true}
	var queue : Array[Vector2i] = [global]
	while not queue.is_empty():
		var cell : Vector2i = queue.pop_front()
		var local_corner := _corner_index_for_key(cell, key)
		if local_corner == -1:
			continue
		result.append(cell)
		var neighbors := edge_neighbors(cell)
		for edge in range(neighbors.size()):
			var pair := edge_corner_indices(cell, edge)
			if pair.x != local_corner and pair.y != local_corner:
				continue
			var nb : Vector2i = neighbors[edge]
			if visited.has(nb):
				continue
			visited[nb] = true
			if terrain_system and terrain_system.get_cell_height(nb) != null:
				queue.append(nb)
	return result


## Snapped world-position keys for a cell's corners so the same lattice point
## hashes equally from every incident cell.
func _corner_keys(global: Vector2i) -> Array:
	if _corner_key_cache.has(global):
		return _corner_key_cache[global]
	var offsets := cell_corner_offsets(global)
	var center := cell_center_world(global)
	var keys : Array = []
	for offset in offsets:
		var p := center + offset
		keys.append(Vector2i(roundi(p.x * CORNER_KEY_SCALE), roundi(p.y * CORNER_KEY_SCALE)))
	_corner_key_cache[global] = keys
	return keys


func _corner_index_for_key(cell: Vector2i, key: Vector2i) -> int:
	return _index_of_key(_corner_keys(cell), key)


## The neighbour's corner indices matching this cell's edge corner pair.
func _shared_corner_indices(global: Vector2i, nb: Vector2i, pair: Vector2i) -> Vector2i:
	var own_keys := _corner_keys(global)
	var nb_keys := _corner_keys(nb)
	return Vector2i(
		_index_of_key(nb_keys, own_keys[pair.x]),
		_index_of_key(nb_keys, own_keys[pair.y]))


func _index_of_key(keys: Array, key: Vector2i) -> int:
	for i in range(keys.size()):
		if keys[i] == key:
			return i
	return -1

#endregion


func _emit_cell(st: SurfaceTool, local: Vector2i, origin: Vector2) -> void:
	var global := _chunk_global_cell(local)
	var idx := cell_index(local)
	var h : float = height_map[idx]
	var center := cell_center_world(global) - origin
	var offsets := cell_corner_offsets(global)
	var corner_count := offsets.size()
	
	var own_smooth : bool = _has_smooth_cells and get_smooth(local)
	var own_heights := PackedFloat32Array()
	if own_smooth:
		own_heights = cell_corner_heights(global)
	
	# Top fan around the centroid as explicit triangles (center, i, i+1). The
	# corner order can differ per cell orientation (triangle B is wound opposite
	# of A), so flip the fan when the polygon is clockwise to keep normals up.
	var area := 0.0
	for i in range(corner_count):
		var a := offsets[i]
		var b := offsets[(i + 1) % corner_count]
		area += a.x * b.y - b.x * a.y
	var flip_fan := area < 0.0
	var center_3d := Vector3(center.x, h, center.y)
	if own_smooth:
		for i in range(corner_count):
			var next := (i + 1) % corner_count
			var p0 := center + offsets[i]
			var p1 := center + offsets[next]
			var h0 := own_heights[i]
			var h1 := own_heights[next]
			if flip_fan:
				var swap := p0
				p0 = p1
				p1 = swap
				var swap_h := h0
				h0 = h1
				h1 = swap_h
			_emit_top_vertex(st, center_3d, idx)
			_emit_top_vertex(st, Vector3(p0.x, h0, p0.y), idx)
			_emit_top_vertex(st, Vector3(p1.x, h1, p1.y), idx)
	else:
		for i in range(corner_count):
			var p0 := center + offsets[i]
			var p1 := center + offsets[(i + 1) % corner_count]
			if flip_fan:
				var swap := p0
				p0 = p1
				p1 = swap
			_emit_top_vertex(st, center_3d, idx)
			_emit_top_vertex(st, Vector3(p0.x, h, p0.y), idx)
			_emit_top_vertex(st, Vector3(p1.x, h, p1.y), idx)
	
	# Walls on edges whose neighbor is lower.
	var neighbors := edge_neighbors(global)
	var terrain := terrain_system
	for edge in range(corner_count):
		var nb : Vector2i = neighbors[edge]
		var nb_chunk = terrain.chunk_for_cell(nb) if terrain else null
		if nb_chunk == null:
			continue
		var nb_local := MarchingSquaresHexGrid.local_cell(nb, cells_per_chunk())
		var h_nb : float = nb_chunk.get_height(nb_local)
		var pair := edge_corner_indices(global, edge)
		var qa := center + offsets[pair.x]
		var qb := center + offsets[pair.y]
		var nb_smooth : bool = nb_chunk.has_smooth_cells() and nb_chunk.get_smooth(nb_local)
		
		if own_smooth or nb_smooth:
			# Both surfaces are planar; close the exact gap (if any) between
			# the two tilted edge lines instead of stepping.
			var own_a : float = own_heights[pair.x] if own_smooth else h
			var own_b : float = own_heights[pair.y] if own_smooth else h
			_emit_smooth_edge(st, idx, global, center, qa, qb, pair, own_a, own_b, nb, h_nb, origin)
			continue
		
		if h - h_nb <= 0.0001:
			continue
		# Order the pair so the wall's geometric normal faces away from this
		# (higher) cell on every edge orientation.
		var edge_dir := qb - qa
		var mid := (qa + qb) * 0.5
		var outward := mid - center
		if Vector2(edge_dir.y, -edge_dir.x).dot(outward) < 0.0:
			var swap := qa
			qa = qb
			qb = swap
			edge_dir = -edge_dir
		var step : float = h - h_nb
		var edge_distance := outward.length()
		if step <= merge_threshold:
			# Merged step: 45-degree ramp into the neighbour, capped so the
			# ramp never reaches the neighbour's centre.
			var run := minf(step, edge_distance)
			var outward_dir := outward / edge_distance
			var qa_low := qa + outward_dir * run
			var qb_low := qb + outward_dir * run
			_emit_ramp(st, idx, qa, qb, qa_low, qb_low, h, h_nb, origin)
		else:
			_emit_wall(st, idx, qa, qb, h, h_nb, origin)


## Closes the gap between two planar cell tops along one edge, using the
## corner heights of each side. Only the higher side emits, so each edge is
## covered once.
func _emit_smooth_edge(st: SurfaceTool, idx: int, global: Vector2i, own_center: Vector2, qa: Vector2, qb: Vector2, pair: Vector2i, top_a: float, top_b: float, nb: Vector2i, h_nb: float, origin: Vector2) -> void:
	var bot_a := h_nb
	var bot_b := h_nb
	if terrain_system.get_cell_smooth(nb):
		var nb_heights := cell_corner_heights(nb)
		var nb_pair := _shared_corner_indices(global, nb, pair)
		if nb_pair.x == -1 or nb_pair.y == -1:
			return
		bot_a = nb_heights[nb_pair.x]
		bot_b = nb_heights[nb_pair.y]
	if is_equal_approx(top_a, bot_a) and is_equal_approx(top_b, bot_b):
		return
	
	# Emit from the higher side only.
	var ref_center := own_center
	if top_a + top_b < bot_a + bot_b:
		# The neighbour is higher: swap roles and orient away from it.
		var swap := top_a
		top_a = bot_a
		bot_a = swap
		swap = top_b
		top_b = bot_b
		bot_b = swap
		ref_center = cell_center_world(nb) - origin
	
	var edge_dir := qb - qa
	var mid := (qa + qb) * 0.5
	var outward := mid - ref_center
	if Vector2(edge_dir.y, -edge_dir.x).dot(outward) < 0.0:
		var swap_pos := qa
		qa = qb
		qb = swap_pos
		var swap_h := top_a
		top_a = top_b
		top_b = swap_h
		swap_h = bot_a
		bot_a = bot_b
		bot_b = swap_h
	_emit_gap_quad(st, idx, qa, qb, top_a, top_b, bot_a, bot_b, origin)


func _emit_top_vertex(st: SurfaceTool, vert: Vector3, idx: int) -> void:
	st.set_smooth_group(0)
	st.set_uv(Vector2(0, 0))
	var uv2 : Vector2 = Vector2(vert.x, vert.z) / terrain_system.cell_size
	st.set_uv2(uv2)
	st.set_color(color_map_0[idx])
	st.set_custom(0, color_map_1[idx])
	st.set_custom(1, _custom1_for(idx, false))
	st.set_custom(2, _custom2_for(idx, false))
	st.add_vertex(vert)


func _emit_wall(st: SurfaceTool, idx: int, qa: Vector2, qb: Vector2, h_own: float, h_nb: float, origin: Vector2) -> void:
	_emit_gap_quad(st, idx, qa, qb, h_own, h_own, h_nb, h_nb, origin)


## Wall quad connecting two (possibly tilted) cell edge lines. The caller has
## already ordered qa/qb so the winding faces away from the higher cell.
func _emit_gap_quad(st: SurfaceTool, idx: int, qa: Vector2, qb: Vector2, a_top: float, b_top: float, a_bot: float, b_bot: float, origin: Vector2) -> void:
	var a_low := Vector3(qa.x, a_bot, qa.y)
	var b_low := Vector3(qb.x, b_bot, qb.y)
	var a_high := Vector3(qa.x, a_top, qa.y)
	var b_high := Vector3(qb.x, b_top, qb.y)
	
	# Quad (a_low, a_high, b_high, b_low) as two triangles. Winding faces away
	# from the higher cell.
	_emit_wall_vertex(st, idx, a_low, origin)
	_emit_wall_vertex(st, idx, a_high, origin)
	_emit_wall_vertex(st, idx, b_high, origin)
	_emit_wall_vertex(st, idx, a_low, origin)
	_emit_wall_vertex(st, idx, b_high, origin)
	_emit_wall_vertex(st, idx, b_low, origin)


## Merged step: connects the higher cell's edge to a line inside the lower
## neighbour at the lower height. Uses the higher cell's wall maps.
func _emit_ramp(st: SurfaceTool, idx: int, qa_top: Vector2, qb_top: Vector2, qa_low: Vector2, qb_low: Vector2, h_own: float, h_nb: float, origin: Vector2) -> void:
	var a_top := Vector3(qa_top.x, h_own, qa_top.y)
	var b_top := Vector3(qb_top.x, h_own, qb_top.y)
	var a_low := Vector3(qa_low.x, h_nb, qa_low.y)
	var b_low := Vector3(qb_low.x, h_nb, qb_low.y)
	
	_emit_wall_vertex(st, idx, a_low, origin)
	_emit_wall_vertex(st, idx, a_top, origin)
	_emit_wall_vertex(st, idx, b_top, origin)
	_emit_wall_vertex(st, idx, a_low, origin)
	_emit_wall_vertex(st, idx, b_top, origin)
	_emit_wall_vertex(st, idx, b_low, origin)


func _emit_wall_vertex(st: SurfaceTool, idx: int, vert: Vector3, origin: Vector2) -> void:
	st.set_smooth_group(-1)
	st.set_uv(Vector2(1, 1))
	var gp := Vector2(vert.x + origin.x, vert.z + origin.y)
	st.set_uv2(Vector2(gp.x + gp.y, gp.x + gp.y))
	st.set_color(wall_color_map_0[idx])
	st.set_custom(0, wall_color_map_1[idx])
	st.set_custom(1, _custom1_for(idx, true))
	st.set_custom(2, _custom2_for(idx, true))
	st.add_vertex(vert)


## CUSTOM1 = Color(grass_mask.r, 0, 0, rl_idx / 15) where rl_idx is the wall
## texture index of the cell (mirrors the helper's non-ridge floor output).
func _custom1_for(idx: int, wall: bool) -> Color:
	var map := wall_color_map_0 if wall else color_map_0
	var map_1 := wall_color_map_1 if wall else color_map_1
	var rl_idx := _texture_index_from_colors(map[idx], map_1[idx])
	var c := grass_mask_map[idx]
	return Color(c.r, 0.0, 0.0, float(rl_idx) / 15.0)


## CUSTOM2 = Color((m + m*16)/255, m/15, 1, 2) with m = floor texture index.
## A = 2.0 signals the shader's vertex-color path, matching the square helper.
func _custom2_for(idx: int, wall: bool) -> Color:
	var map := wall_color_map_0 if wall else color_map_0
	var map_1 := wall_color_map_1 if wall else color_map_1
	var m := _texture_index_from_colors(map[idx], map_1[idx])
	return Color((float(m) + float(m) * 16.0) / 255.0, float(m) / 15.0, 1.0, 2.0)


static func _texture_index_from_colors(c0: Color, c1: Color) -> int:
	var c0_idx := 0
	var c0_max := c0.r
	if c0.g > c0_max: c0_max = c0.g; c0_idx = 1
	if c0.b > c0_max: c0_max = c0.b; c0_idx = 2
	if c0.a > c0_max: c0_idx = 3
	
	var c1_idx := 0
	var c1_max := c1.r
	if c1.g > c1_max: c1_max = c1.g; c1_idx = 1
	if c1.b > c1_max: c1_max = c1.b; c1_idx = 2
	if c1.a > c1_max: c1_idx = 3
	
	return c0_idx * 4 + c1_idx

#endregion


func regenerate_all_cells(_use_threads: bool = false) -> void:
	regenerate_mesh(false)
	if grass_planter:
		grass_planter.regenerate_all_cells()
