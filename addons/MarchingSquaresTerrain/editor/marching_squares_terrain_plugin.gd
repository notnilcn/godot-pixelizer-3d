@tool
extends EditorPlugin
class_name MarchingSquaresTerrainPlugin


static var instance : MarchingSquaresTerrainPlugin

const EMPTY_TEXTURE_PRESET : MarchingSquaresTexturePreset = preload("res://addons/MarchingSquaresTerrain/resources/empty_project.tres")
const BrushPatternCalculator = preload("res://addons/MarchingSquaresTerrain/editor/utils/brush_pattern_calculator.gd")

var vp_texture_names = preload("res://addons/MarchingSquaresTerrain/resources/texture_names.tres")

var gizmo_plugin := MarchingSquaresTerrainGizmoPlugin.new()
var toolbar := MarchingSquaresToolbar.new()
var tool_attributes := MarchingSquaresToolAttributes.new()
var active_tool : int = 0

var UI : Script = preload("res://addons/MarchingSquaresTerrain/editor/marching_squares_ui.gd")
var ui : MarchingSquaresUI

var is_initialized : bool = false
var initialization_error : String = ""

var current_terrain_node : MarchingSquaresTerrain

var selected_chunk : MarchingSquaresTerrainChunkBase

# Flag to prevent _set_new_textures() when syncing preset from terrain node
var _syncing_from_terrain : bool = false

#region brush variables
# Hexagon30 (index 3) reuses the pointy-top hexagon visual; the gizmo rotates
# its transform by 30 degrees so it renders flat-top.
var BrushMode : Dictionary = {
	"0" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/round_brush_radius_visual.tres"),
	"1" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/square_brush_radius_visual.tres"),
	"2" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/hex_brush_radius_visual.tres"),
	"3" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/hex_brush_radius_visual.tres"),
	"4" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/triangle_brush_radius_visual.tres"),
	"5" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/triangle180_brush_radius_visual.tres"),
}

var BrushMat : Dictionary = {
	"0" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/round_brush_radius_material.tres"),
	"1" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/square_brush_radius_material.tres"),
	"2" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/hex_brush_radius_material.tres"),
	"3" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/hex_brush_radius_material.tres"),
	"4" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/triangle_brush_radius_material.tres"),
	"5" = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/triangle180_brush_radius_material.tres"),
}

var current_brush_index : int = 0

var brush_position : Vector3

var BRUSH_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/brush_visual.tres")
var BRUSH_RADIUS_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/round_brush_radius_visual.tres")
var BRUSH_RADIUS_MATERIAL : ShaderMaterial = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/round_brush_radius_material.tres")
var CELL_HEX_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/hex_cell_visual.tres")
var CELL_TRI_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/tri_cell_visual.tres")
@onready var falloff_curve : Curve = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/curve_falloff.tres")
#endregion

#region tool_mode vars
enum TerrainToolMode {
	BRUSH = 0,
	LEVEL = 1,
	SMOOTH = 2,
	BRIDGE = 3,
	GRASS_MASK = 4,
	VERTEX_PAINTING = 5,
	DEBUG_BRUSH = 6,
	CHUNK_MANAGEMENT = 7,
	TERRAIN_SETTINGS = 8,
}

var mode : TerrainToolMode = TerrainToolMode.BRUSH:
	set(value):
		mode = value
		current_draw_pattern.clear()
		if mode == TerrainToolMode.VERTEX_PAINTING:
			falloff = false
			BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", false)
#endregion

#region tool attribute vars
# Tool attribute variables
var brush_size : float = 15.0
var ease_value : float = -1.0 # No ease
var strength : float = 1.0
var height : float = 0.0
var flatten : bool = true
var falloff : bool = true

# Grid-aligned painting (cell modes only; see BrushPatternCalculator)
var grid_aligned : bool = false
var grid_size : int = 1


## Single gate for the Grid Aligned control (terrain, brush shape, falloff).
func grid_align_gate_passes() -> bool:
	var t := current_terrain_node
	if t == null:
		return false
	if t.grid_type == MarchingSquaresTerrain.GridType.SQUARE:
		return false
	if not BrushPatternCalculator.is_hexagon_brush(current_brush_index):
		return false
	return falloff == false

var should_mask_grass : bool = false

# Currently selected preset for vertex textures (DOES change the global terrain)
var current_texture_preset : MarchingSquaresTexturePreset = EMPTY_TEXTURE_PRESET.duplicate():
	set(value):
		current_texture_preset = value
		current_quick_paint = null
		if not _syncing_from_terrain:
			_set_new_textures(value)

# Currently selected preset for quick painting (does NOT change the global terrain)
var current_quick_paint : MarchingSquaresQuickPaint = null

# Toggle for painting walls vs ground in VERTEX_PAINTING mode
var paint_walls_mode : bool = false:
	set(value):
		paint_walls_mode = value

var vertex_color_idx : int = 0:
	set(value):
		vertex_color_idx = value
		_set_vertex_colors(value)
var vertex_color_0 : Color = Color(1.0, 0.0, 0.0, 0.0)
var vertex_color_1 : Color = Color(1.0, 0.0, 0.0, 0.0)
#endregion

#region draw-related vars
# A dictionary with keys for each tile that is currently being drawn to with the brush 
# In brush mode, the value is the height that preview was drawn to, aka the height BEFORE it is set
# In ground texture mode, the value is the color of the point BEFORE the draw
var current_draw_pattern : Dictionary

var terrain_hovered : bool
var is_chunk_plane_hovered : bool
var current_hovered_chunk : Vector2i

# True if the mouse is currently held down to draw
var is_drawing : bool

# When the brush draws, if the gizmo sees the draw height is not set, it will set the draw height
var draw_height_set : bool

# Height of the current pattern that is being drawn at for the brush tool
var draw_height : float

# Is set to true when the user clicks on a tile that is part of the current draw pattern, will enter heightdrag setting mode
var is_setting : bool

var is_making_bridge : bool
var bridge_start_pos : Vector3

# The point where the height drag started
var base_position : Vector3
#endregion

#region raycast variables
# Use script-wide variables to provide data to the physics process function
var raycast_queued := false
var ray_origin : Vector3
var ray_dir : Vector3
var ray_camera : Camera3D
var queued_ray_result := {}
#endregion


func _enter_tree():
	instance = self
	call_deferred("_deferred_enter_tree")
	
	print_rich("Welcome to [color=MEDIUM_ORCHID][url=https://www.youtube.com/@yugen_seishin]YÃƒâ€¦Ã‚Â«gen[/url][/color]'s [wave]Marching Squares Terrain Authoring Toolkit[/wave]\nThis plugin is under MIT license")


func _deferred_enter_tree() -> void:
	if not _safe_initialize():
		push_error("Failed to initialize plugin: " + initialization_error)
	else:
		print_verbose("[MarchingSquaresTerrainPlugin] initialized succesfully!")


func _safe_initialize() -> bool:
	if is_initialized:
		return true
	
	if not EngineWrapper.is_editor():
		initialization_error = "Plugin was initialized during runtime"
		return false
	
	if not EditorInterface:
		initialization_error = "No EditorInterface detected"
		return false
	
	if not get_tree():
		initialization_error = "No tree detected while initializing"
		return false
	
	var terrain_script := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain.gd")
	var chunk_script := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_chunk.gd")
	var terrain_icon := preload("res://addons/MarchingSquaresTerrain/editor/icons/Marching_Squares_Terrain_Icon.svg")
	var chunk_icon := preload("res://addons/MarchingSquaresTerrain/editor/icons/Marching_Squares_Terrain_Chunk_Icon.svg")
	
	if terrain_script and chunk_script:
		add_custom_type("MarchingSquaresTerrain", "Node3D", terrain_script, terrain_icon)
		add_custom_type("MarchingSquaresTerrainChunk", "MeshInstance3D", chunk_script, chunk_icon)
	else:
		initialization_error = "Failed to load algorithm scripts"
		return false
	
	if gizmo_plugin:
		add_node_3d_gizmo_plugin(gizmo_plugin)
	else:
		initialization_error = "Failed to create gizmo plugin"
		return false
	
	if not ui:
		ui = UI.new()
		if ui:
			ui.plugin = self
			add_child(ui)
		else:
			initialization_error = "Failed to create UI system"
			return false
	
	is_initialized = true
	return true


func _exit_tree():
	if ui:
		ui.queue_free()
		ui = null
	
	remove_custom_type("MarchingSquaresTerrain")
	remove_custom_type("MarchingSquaresTerrainChunk")
	
	if gizmo_plugin:
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null
	
	is_initialized = false
	initialization_error = ""


func _ready():
	BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", falloff)


func _queue_raycast(origin: Vector3, dir: Vector3, cam: Camera3D) -> void:
	ray_origin = origin
	ray_dir = dir
	ray_camera = cam
	raycast_queued = true


func _physics_process(delta: float) -> void:
	# Raycast inside the physics process function to prevent
	# crashes when "run physics on a different thread" is enabled.
	if not raycast_queued:
		return
	raycast_queued = false
	
	var world_3d := ray_camera.get_world_3d()
	var space_state := PhysicsServer3D.space_get_direct_state(world_3d.space)
	
	var ray_length := 10000.0 # Adjust ray length as needed
	var end := ray_origin + ray_dir * ray_length
	var collision_mask = 16 # only terrain
	var query := PhysicsRayQueryParameters3D.create(ray_origin, end, collision_mask)
	
	queued_ray_result = space_state.intersect_ray(query)


func _on_chunk_dimensions_changed(value: Vector3i):
	brush_size *= ((value.x / 33) + (value.y / 33)) / 2.0

#region input-handlers

func _edit(object: Object) -> void:
	if not is_initialized:
		push_error("Plugin not yet initialized, calling _safe_initialize() as failsafe")
		if not _safe_initialize():
			push_error("Failed to initialize plugin for editing")
			return
	if object is MarchingSquaresTerrain:
		if ui:
			ui.set_visible(true)
			current_terrain_node = object
			if not current_terrain_node.chunk_dimensions_changed.is_connected(_on_chunk_dimensions_changed):
				current_terrain_node.chunk_dimensions_changed.connect(_on_chunk_dimensions_changed)
			
			# Sync plugin's preset from the selected terrain's saved preset
			# This ensures each terrain keeps its own preset on selection/reload
			_syncing_from_terrain = true
			current_texture_preset = object.current_texture_preset
			_syncing_from_terrain = false
	else:
		if ui:
			ui.set_visible(false)
		current_draw_pattern.clear()
		is_drawing = false
		draw_height_set = false
		gizmo_plugin.clear()


# This function handles the mouse click in the 3D viewport
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_initialized:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	var selected = EditorInterface.get_selection().get_selected_nodes()
	# Only proceed if exactly 1 terrain system is selected
	if not selected or len(selected) > 1:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Handle clicks
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return handle_mouse(camera, event)
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handles(object: Object) -> bool:
	if not is_initialized:
		return false
	
	return object is MarchingSquaresTerrain


func handle_hotkey(keycode: int) -> bool:
	pass
	return false


func handle_mouse(camera: Camera3D, event: InputEvent) -> int:
	terrain_hovered = false
	var terrain : MarchingSquaresTerrain = EditorInterface.get_selection().get_selected_nodes()[0]
	
	var mouse_pos := camera.get_viewport().get_mouse_position()
	
	var _ray_origin := camera.project_ray_origin(mouse_pos)
	var _ray_dir := camera.project_ray_normal(mouse_pos)
	
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	
	# If not in a settings mode, perform terrain raycast
	if mode == TerrainToolMode.BRUSH or mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.LEVEL or mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.BRIDGE or mode == TerrainToolMode.VERTEX_PAINTING or mode == TerrainToolMode.DEBUG_BRUSH:
		var draw_position
		var draw_area_hovered : bool = false
		
		if is_setting and draw_height_set:
			var local_ray_dir := _ray_dir * terrain.transform
			var set_plane := Plane(Vector3(local_ray_dir.x, 0, local_ray_dir.z), base_position)
			var set_position := set_plane.intersects_ray(terrain.to_local(_ray_origin), local_ray_dir)
			if set_position:
				brush_position = set_position
		
		# If there is any pattern and flatten is enabled, draw along that height plane instead of the terrain intersection
		elif not current_draw_pattern.is_empty() and flatten:
			var chunk_plane := Plane(Vector3.UP, Vector3(0, draw_height, 0))
			draw_position = chunk_plane.intersects_ray(_ray_origin, _ray_dir)
			if draw_position:
				draw_position = terrain.to_local(draw_position)
				draw_area_hovered = true
		
		else:
			# Perform the raycast to check for intersection with a physics body (terrain)
			_queue_raycast(_ray_origin, _ray_dir, camera)
			if queued_ray_result and queued_ray_result.has("position"):
				draw_position = terrain.to_local(queued_ray_result.position)
				draw_area_hovered = true
			else:
				# FALLBACK: If we didn't hit a chunk, project onto a virtual plane at draw_height
				# This allows painting onto chunks while the mouse is in "negative space"
				var fallback_height := 0.0
				if is_drawing or is_setting or not current_draw_pattern.is_empty():
					fallback_height = draw_height
				
				var virtual_plane := Plane(Vector3.UP, Vector3(0, fallback_height, 0))
				var plane_pos := virtual_plane.intersects_ray(ray_origin, ray_dir)
				if plane_pos:
					draw_position = terrain.to_local(plane_pos)
					draw_area_hovered = true
		
		# ALT or Right Click to clear the current draw pattern. Don't clear while setting
		var _right_clicked : bool = (
			event is InputEventMouseButton and 
			event.button_index == MOUSE_BUTTON_RIGHT and 
			event.pressed
		)
		
		if not is_setting:
			if _right_clicked or Input.is_key_pressed(KEY_ALT):
				current_draw_pattern.clear()
		
		# Check for terrain collision
		if draw_area_hovered:
			terrain_hovered = true
			var chunk_coords : Vector2i
			if terrain.grid_type == MarchingSquaresTerrain.GridType.SQUARE:
				chunk_coords = Vector2i(
					floori(draw_position.x / (terrain.dimensions.x * terrain.cell_size.x)),
					floori(draw_position.z / (terrain.dimensions.z * terrain.cell_size.y)))
			else:
				chunk_coords = terrain.chunk_of_cell(
					terrain.world_to_cell(Vector2(draw_position.x, draw_position.z)))
			
			is_chunk_plane_hovered = true
			current_hovered_chunk = chunk_coords
		
		if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if event.is_pressed() and draw_area_hovered:
				draw_height_set = false
				if mode == TerrainToolMode.BRIDGE and not is_making_bridge:
					flatten = false
					is_making_bridge = true
					bridge_start_pos = brush_position
				if mode == TerrainToolMode.SMOOTH and falloff == false:
					falloff = true
				if (mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.DEBUG_BRUSH) and falloff == true:
					falloff = false
				if (mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.VERTEX_PAINTING or mode == TerrainToolMode.DEBUG_BRUSH) and flatten == true:
					flatten = false
				if mode == TerrainToolMode.LEVEL and Input.is_key_pressed(KEY_CTRL):
					height = brush_position.y
				elif Input.is_key_pressed(KEY_SHIFT):
					is_drawing = true
					brush_position = draw_position
				else:
					is_setting = true
					if not flatten:
						draw_height = draw_position.y
			elif event.is_released():
				if is_making_bridge:
					is_making_bridge = false
				if is_drawing:
					is_drawing = false
					if mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.LEVEL or mode == TerrainToolMode.BRIDGE or mode == TerrainToolMode.DEBUG_BRUSH:
						draw_pattern(terrain)
						current_draw_pattern.clear()
					if mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.VERTEX_PAINTING:
						current_draw_pattern.clear()
				if is_setting:
					is_setting = false
					draw_pattern(terrain)
					if Input.is_key_pressed(KEY_SHIFT):
						draw_height = brush_position.y
					else:
						current_draw_pattern.clear()
			gizmo_plugin.trigger_redraw(terrain)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# Adjust brush size
		if event is InputEventMouseButton and Input.is_key_pressed(KEY_SHIFT):
			var cell_scale_factor := clamp(((terrain.cell_size.x + terrain.cell_size.y) / 4.0), 0.3, 1.0)
			var dimensions_scale_factor := clamp((((terrain.dimensions.x / 33) + (terrain.dimensions.z / 33)) / 2.0), 0.5, 2.0)
			var size_scale_factor : float = dimensions_scale_factor * cell_scale_factor
			var factor : float = event.factor if event.factor else 1
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				brush_size += (0.5 * size_scale_factor) * factor
				if brush_size > 50 * size_scale_factor:
					brush_size = 50 * size_scale_factor
				gizmo_plugin.trigger_redraw(terrain)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				brush_size -= (0.5 * size_scale_factor) * factor
				if brush_size < 1.0 * size_scale_factor:
					brush_size = 1.0 * size_scale_factor
				gizmo_plugin.trigger_redraw(terrain)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		if draw_area_hovered and event is InputEventMouseMotion:
			brush_position = draw_position
			# Smooth and vertex paint apply continuously while dragging. The
			# other brush tools accumulate a selection in current_draw_pattern
			# (through the gizmo) and apply it once on release.
			if is_drawing and (mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.VERTEX_PAINTING):
				draw_pattern(terrain)
				current_draw_pattern.clear()
		
		gizmo_plugin.trigger_redraw(terrain)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Check for hovering over/clicking a new chunk
	var chunk_plane := Plane(Vector3.UP, terrain.global_position)
	var intersection := chunk_plane.intersects_ray(_ray_origin, _ray_dir)
	
	if intersection:
		var local_pos := terrain.to_local(intersection)
		var chunk_coords : Vector2i
		if terrain.grid_type == MarchingSquaresTerrain.GridType.SQUARE:
			chunk_coords = Vector2i(
				floori(local_pos.x / ((terrain.dimensions.x-1) * terrain.cell_size.x)),
				floori(local_pos.z / ((terrain.dimensions.z-1) * terrain.cell_size.y)))
		else:
			chunk_coords = terrain.chunk_of_cell(
				terrain.world_to_cell(Vector2(local_pos.x, local_pos.z)))
		
		var chunk = terrain.chunks.get(chunk_coords)
		
		current_hovered_chunk = chunk_coords
		is_chunk_plane_hovered = true
		
		# On click, add or remove chunk if in chunk_management mode
		if mode == TerrainToolMode.CHUNK_MANAGEMENT and event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			# Select chunk
			if Input.is_key_pressed(KEY_CTRL):
				selected_chunk = terrain.chunks.get(current_hovered_chunk)
				ui.tool_attributes.show_tool_attributes(TerrainToolMode.CHUNK_MANAGEMENT)
				ui.tool_attributes.selected_chunk = selected_chunk
			
			# Remove chunk
			elif chunk:
				var removed_chunk = terrain.chunks[chunk_coords]
				get_undo_redo().create_action("remove chunk")
				get_undo_redo().add_do_method(terrain, "remove_chunk_from_tree", chunk_coords.x, chunk_coords.y, self)
				get_undo_redo().add_undo_method(terrain, "add_chunk", chunk_coords, removed_chunk, self)
				get_undo_redo().commit_action()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			
			# Add new chunk
			elif not chunk:
				# Can add a new chunk here if there is a neighbouring non-empty chunk
				# Also add if there are no chunks at all in the current terrain system
				var can_add_empty : bool = terrain.chunks.is_empty()
				if not can_add_empty:
					for neighbor_coords in terrain.chunk_neighbors(chunk_coords):
						if terrain.chunks.has(neighbor_coords):
							can_add_empty = true
							break
				if can_add_empty:
					get_undo_redo().create_action("add chunk")
					get_undo_redo().add_do_method(terrain, "add_new_chunk", chunk_coords.x, chunk_coords.y, self)
					get_undo_redo().add_undo_method(terrain, "remove_chunk", chunk_coords.x, chunk_coords.y, self)
					get_undo_redo().commit_action()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		gizmo_plugin.trigger_redraw(terrain)
	else:
		is_chunk_plane_hovered = false
	
	# Consume clicks but allow other click / mouse motion types to reach the gui, for camera movement, etc
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS

#endregion

#region draw-related functions

# Calculates brush pattern and updates current_draw_pattern
func update_draw_pattern(b_pos: Vector3):
	var terrain_system : MarchingSquaresTerrain = current_terrain_node
	var brush_pos : Vector2 = Vector2(b_pos.x, b_pos.z)
	
	if terrain_system.grid_type != MarchingSquaresTerrain.GridType.SQUARE:
		_update_draw_pattern_cells(terrain_system, brush_pos)
		return
	
	var bounds := BrushPatternCalculator.calculate_bounds(b_pos, brush_size, terrain_system)
	var max_distance : float = BrushPatternCalculator.calculate_max_distance(brush_size, current_brush_index)
	
	for chunk_z in range(bounds.chunk_tl.y, bounds.chunk_br.y + 1):
		for chunk_x in range(bounds.chunk_tl.x, bounds.chunk_br.x + 1):
			var cursor_chunk_coords : Vector2i = Vector2i(chunk_x, chunk_z)
			if not terrain_system.chunks.has(cursor_chunk_coords):
				continue
			
			var cell_range : Dictionary = BrushPatternCalculator.get_cell_range_for_chunk(cursor_chunk_coords, bounds, terrain_system)
			
			for z in range(cell_range.z_min, cell_range.z_max):
				for x in range(cell_range.x_min, cell_range.x_max):
					var cursor_cell_coords : Vector2i = Vector2i(x, z)
					var world_pos : Vector2 = BrushPatternCalculator.cell_to_world_pos(cursor_chunk_coords, cursor_cell_coords, terrain_system)
					
					var sample : float = BrushPatternCalculator.calculate_falloff_sample(
						world_pos, brush_pos, brush_size, current_brush_index,
						max_distance, falloff, falloff_curve
					)
					
					if sample < 0:
						continue  # Outside brush
					
					# Store largest sample
					if not current_draw_pattern.has(cursor_chunk_coords):
						current_draw_pattern[cursor_chunk_coords] = {}
					if current_draw_pattern[cursor_chunk_coords].has(cursor_cell_coords):
						var prev_sample = current_draw_pattern[cursor_chunk_coords][cursor_cell_coords]
						if sample > prev_sample:
							current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
					else:
						current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample


## Cell-mode variant of update_draw_pattern. Mirrors the gizmo's cell preview.
func _update_draw_pattern_cells(terrain_system: MarchingSquaresTerrain, brush_pos: Vector2) -> void:
	var max_distance : float = BrushPatternCalculator.calculate_max_distance(brush_size, current_brush_index)
	
	# Grid aligned selection sets every selected cell to 1.0 (no falloff).
	if grid_aligned and grid_align_gate_passes():
		for global in BrushPatternCalculator.grid_aligned_cells(terrain_system, brush_pos, grid_size):
			var chunk_coords := terrain_system.chunk_of_cell(global)
			if not terrain_system.chunks.has(chunk_coords):
				continue
			var local := terrain_system.local_cell(global)
			if not current_draw_pattern.has(chunk_coords):
				current_draw_pattern[chunk_coords] = {}
			current_draw_pattern[chunk_coords][local] = 1.0
		return
	
	for chunk_coords: Vector2i in terrain_system.chunks.keys():
		var candidates := BrushPatternCalculator.cell_candidates_for_chunk(
			chunk_coords, terrain_system, brush_pos, brush_size, 2)
		for local: Vector2i in candidates:
			var global := terrain_system.global_of_local(chunk_coords, local)
			var center := BrushPatternCalculator.cell_center_for(terrain_system, global)
			var sample : float
			if terrain_system.grid_type == MarchingSquaresTerrain.GridType.TRIANGLE:
				sample = BrushPatternCalculator.tri_cell_sample(
					brush_pos, center, brush_size, current_brush_index,
					max_distance, falloff, falloff_curve, terrain_system.cell_size)
			else:
				var spacing := MarchingSquaresHexGrid.spacing_for(terrain_system.cell_size)
				sample = BrushPatternCalculator.hex_cell_sample(
					brush_pos, center, brush_size, current_brush_index,
					max_distance, falloff, falloff_curve,
					terrain_system.cell_center_of(terrain_system.world_to_cell(brush_pos)), spacing)
			if sample < 0:
				continue
			if not current_draw_pattern.has(chunk_coords):
				current_draw_pattern[chunk_coords] = {}
			if current_draw_pattern[chunk_coords].has(local):
				var prev_sample = current_draw_pattern[chunk_coords][local]
				if sample > prev_sample:
					current_draw_pattern[chunk_coords][local] = sample
			else:
				current_draw_pattern[chunk_coords][local] = sample


func draw_pattern(terrain: MarchingSquaresTerrain):
	if terrain.grid_type != MarchingSquaresTerrain.GridType.SQUARE:
		draw_pattern_cells(terrain)
		return
	var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
	
	var pattern := {}
	var pattern_cc := {}
	var restore_pattern := {}
	var restore_pattern_cc := {}
	
	# Ensure points on both sides of chunk borders are updated
	var first_chunk = null
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		if first_chunk == null:
			first_chunk = draw_chunk_coords
		pattern[draw_chunk_coords] = {}
		restore_pattern[draw_chunk_coords] = {}
		pattern_cc[draw_chunk_coords] = {}
		restore_pattern_cc[draw_chunk_coords] = {}
		var draw_chunk_dict = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.001, 0.999)
			var restore_value
			var draw_value
			var restore_value_cc
			var draw_value_cc
			if mode == TerrainToolMode.GRASS_MASK:
				restore_value = chunk.get_grass_mask(draw_cell_coords)
				draw_value = Color(0.0, 0.0, 0.0, 0.0) if should_mask_grass else Color(1.0, 0.0, 0.0, 0.0)
			elif mode == TerrainToolMode.LEVEL:
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = lerp(restore_value, height, sample)
			elif mode == TerrainToolMode.SMOOTH:
				var heights : Array[float] = []
				var global_cells : Array[Vector2i] = []
				
				for chunk_coords in current_draw_pattern.keys():
					var chunk_dict = current_draw_pattern[chunk_coords]
					for cell_coords in chunk_dict.keys():
						var global_x = chunk_coords.x * terrain.dimensions.x + cell_coords.x
						var global_y = chunk_coords.y * terrain.dimensions.z + cell_coords.y
						global_cells.append(Vector2i(global_x, global_y))
				
				for global_cell in global_cells:
					var current_chunk_coords := Vector2i(floor(float(global_cell.x) / terrain.dimensions.x), floor(float(global_cell.y) / terrain.dimensions.z))
					if not terrain.chunks.has(current_chunk_coords):
						continue
					var current_chunk = terrain.chunks[current_chunk_coords]
					var local_cell := Vector2i(posmod(global_cell.x, terrain.dimensions.x), posmod(global_cell.y, terrain.dimensions.z))
					heights.append(current_chunk.get_height(local_cell))
				
				var avg_height := 0.0
				for h in heights:
					avg_height += h
				avg_height /= heights.size()
				
				for global_cell in global_cells:
					var current_chunk_coords := Vector2i(floor(float(global_cell.x) / terrain.dimensions.x), floor(float(global_cell.y) / terrain.dimensions.z))
					if not terrain.chunks.has(current_chunk_coords):
						continue
					var current_chunk = terrain.chunks[current_chunk_coords]
					var local_cell := Vector2i(posmod(global_cell.x, terrain.dimensions.x), posmod(global_cell.y, terrain.dimensions.z))
					
					if not restore_pattern.has(current_chunk_coords):
						restore_pattern[current_chunk_coords] = {}
					if not pattern.has(current_chunk_coords):
						pattern[current_chunk_coords] = {}
					
					# Overwrite sample var with neighbouring chunks' data included
					sample = clamp(current_draw_pattern.get(current_chunk_coords, {}).get(local_cell, sample), 0.001, 0.999)
					restore_value = current_chunk.get_height(local_cell)
					draw_value = lerp(restore_value, avg_height, sample * strength)
					
					restore_pattern[current_chunk_coords][local_cell] = restore_value
					pattern[current_chunk_coords][local_cell] = draw_value
			elif mode == TerrainToolMode.BRIDGE:
				var b_end := Vector2(brush_position.x, brush_position.z)
				var b_start := Vector2(bridge_start_pos.x, bridge_start_pos.z)
				var bridge_length := (b_end - b_start).length()
				if bridge_length < 0.5 or draw_chunk_dict.size() < 3: # Skip small bridges so the terrain doesn't glitch
					return
				
				# Convert cell to world-space
				var global_cell := Vector2(
					(draw_chunk_coords.x * terrain.dimensions.x + draw_cell_coords.x) * terrain.cell_size.x,
					(draw_chunk_coords.y * terrain.dimensions.z + draw_cell_coords.y) * terrain.cell_size.y)
				
				if draw_chunk_coords != first_chunk:
					global_cell.x += (first_chunk.x - draw_chunk_coords.x) * terrain.cell_size.x
				if draw_chunk_coords != first_chunk:
					global_cell.y += (first_chunk.y - draw_chunk_coords.y) * terrain.cell_size.y
				
				# Calculate the 2D bridge direction vector
				var bridge_dir := (b_end - b_start) / bridge_length
				var cell_vec := global_cell - b_start
				var linear_offset := cell_vec.dot(bridge_dir)
				var progress := clamp(linear_offset / bridge_length, 0.0, 1.0)
				
				if ease_value != -1.0:
					progress = ease(progress, ease_value)
				var bridge_height := lerpf(bridge_start_pos.y, brush_position.y, progress)
				
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = bridge_height
			elif mode == TerrainToolMode.VERTEX_PAINTING:
				if paint_walls_mode:
					restore_value = chunk.get_wall_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_wall_color_1(draw_cell_coords)
				else:
					restore_value = chunk.get_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_color_1(draw_cell_coords)
				draw_value = vertex_color_0
				draw_value_cc = vertex_color_1
			elif mode == TerrainToolMode.DEBUG_BRUSH:
				var g_pos := chunk.to_global(Vector3(float(draw_cell_coords.x), chunk.get_height(draw_cell_coords), float(draw_cell_coords.y)))
				var normal := get_cell_normal(chunk, draw_cell_coords)
				print("DEBUG INFO: global pos = " + str(g_pos) +
					", color id = " + str(chunk.get_color_0(draw_cell_coords)) + " " + str(chunk.get_color_1(draw_cell_coords)) +
					", normal = " + str(normal))
				continue
			else: # Brush tool
				restore_value = chunk.get_height(draw_cell_coords)
				if flatten:
					draw_value = lerp(restore_value, brush_position.y, sample)
				else:
					var height_diff := brush_position.y - draw_height
					draw_value = lerp(restore_value, restore_value + height_diff, sample)
			
			restore_pattern[draw_chunk_coords][draw_cell_coords] = restore_value
			pattern[draw_chunk_coords][draw_cell_coords] = draw_value
			if mode == TerrainToolMode.VERTEX_PAINTING:
				restore_pattern_cc[draw_chunk_coords][draw_cell_coords] = restore_value_cc
				pattern_cc[draw_chunk_coords][draw_cell_coords] = draw_value_cc
	if mode == TerrainToolMode.DEBUG_BRUSH:
		return
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		var draw_chunk_dict = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.001, 0.999)
			for cx in range(-1, 2):
				for cz in range(-1, 2):
					if (cx == 0 and cz == 0):
						continue
					
					var adjacent_chunk_coords = Vector2i(draw_chunk_coords.x + cx, draw_chunk_coords.y + cz)
					if not terrain.chunks.has(adjacent_chunk_coords):
						continue
					
					var x : int = draw_cell_coords.x
					var z : int = draw_cell_coords.y
					
					if cx == -1:
						if x == 0: x = terrain.dimensions.x-1
						else: continue
					elif cx == 1:
						if x == terrain.dimensions.x-1: x = 0
						else: continue
					
					if cz == -1:
						if z == 0: z = terrain.dimensions.z-1
						else: continue
					elif cz == 1:
						if z == terrain.dimensions.z-1: z = 0
						else: continue
					
					var adjacent_cell_coords := Vector2i(x, z)
					
					if not pattern.has(adjacent_chunk_coords):
						pattern[adjacent_chunk_coords] = {}
					if not restore_pattern.has(adjacent_chunk_coords):
						restore_pattern[adjacent_chunk_coords] = {}
					
					var draw_value_cc
					var restore_value_cc
					if mode == TerrainToolMode.VERTEX_PAINTING:
						if not pattern_cc.has(adjacent_chunk_coords):
							pattern_cc[adjacent_chunk_coords] = {}
						if not restore_pattern_cc.has(adjacent_chunk_coords):
							restore_pattern_cc[adjacent_chunk_coords] = {}
						draw_value_cc = pattern_cc[draw_chunk_coords][draw_cell_coords]
						restore_value_cc = restore_pattern_cc[draw_chunk_coords][draw_cell_coords]
					
					var draw_value = pattern[draw_chunk_coords][draw_cell_coords]
					var restore_value = restore_pattern[draw_chunk_coords][draw_cell_coords]
					
					var adj_draw_value
					var adj_draw_value_cc
					if current_draw_pattern.has(adjacent_chunk_coords) and current_draw_pattern[adjacent_chunk_coords].has(adjacent_cell_coords) and current_draw_pattern[adjacent_chunk_coords][adjacent_cell_coords] > sample:
						adj_draw_value = pattern[adjacent_chunk_coords][adjacent_cell_coords]
						if mode == TerrainToolMode.VERTEX_PAINTING:
							adj_draw_value_cc = pattern_cc[adjacent_chunk_coords][adjacent_cell_coords]
					else:
						adj_draw_value = draw_value
						if mode == TerrainToolMode.VERTEX_PAINTING:
							adj_draw_value_cc = draw_value_cc
					
					pattern[adjacent_chunk_coords][adjacent_cell_coords] = adj_draw_value
					restore_pattern[adjacent_chunk_coords][adjacent_cell_coords] = restore_value
					if mode == TerrainToolMode.VERTEX_PAINTING:
						pattern_cc[adjacent_chunk_coords][adjacent_cell_coords] = adj_draw_value_cc
						restore_pattern_cc[adjacent_chunk_coords][adjacent_cell_coords] = restore_value_cc
	
	if mode == TerrainToolMode.VERTEX_PAINTING:
		# Standard 2D painting (ground or walls)
		# Create ONE composite action instead of 2 separate actions
		# Use wall_color keys when painting walls, color keys when painting ground
		var color_key_0 := "wall_color_0" if paint_walls_mode else "color_0"
		var color_key_1 := "wall_color_1" if paint_walls_mode else "color_1"
		var do_patterns := {
			color_key_0: pattern,
			color_key_1: pattern_cc
		}
		var undo_patterns := {
			color_key_0: restore_pattern,
			color_key_1: restore_pattern_cc
		}
		
		var action_name := "terrain wall paint" if paint_walls_mode else "terrain vertex paint"
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
		undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
		undo_redo.commit_action()
	elif mode == TerrainToolMode.GRASS_MASK:
		undo_redo.create_action("terrain grass mask draw")
		undo_redo.add_do_method(self, "draw_grass_mask_pattern_action", terrain, pattern)
		undo_redo.add_undo_method(self, "draw_grass_mask_pattern_action", terrain, restore_pattern)
		undo_redo.commit_action()
	else:
		# Handle BRUSH, LEVEL, SMOOTH, BRIDGE modes
		if current_quick_paint:
			# QUICK PAINT MODE: Apply all changes as ONE atomic undo/redo action
			# This fixes the issue where 6 separate actions are created
			_set_vertex_colors(current_quick_paint.wall_texture_slot)
			
			var wall_color_pattern := {}
			var wall_color_pattern_cc := {}
			var wall_color_restore := {}
			var wall_color_restore_cc := {}
			
			# First pass: collect all cells in the pattern
			for chunk_coords in pattern:
				wall_color_pattern[chunk_coords] = {}
				wall_color_pattern_cc[chunk_coords] = {}
				wall_color_restore[chunk_coords] = {}
				wall_color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					wall_color_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
					wall_color_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
					wall_color_pattern[chunk_coords][cell_coords] = vertex_color_0
					wall_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Second pass: expand to adjacent cells (walls appear at boundaries between cells)
			# This ensures uniform wall color by painting adjacent cells that share wall corners
			for chunk_coords in pattern:
				for cell_coords in pattern[chunk_coords]:
					# Check all 8 adjacent cells
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							if dx == 0 and dz == 0:
								continue
							
							var adj_x : int = cell_coords.x + dx
							var adj_z : int = cell_coords.y + dz
							var adj_chunk_coords : Vector2i = chunk_coords
							
							# Handle chunk boundary crossings
							if adj_x < 0:
								adj_chunk_coords = Vector2i(chunk_coords.x - 1, chunk_coords.y)
								adj_x = terrain.dimensions.x - 1
							elif adj_x >= terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >= terrain.dimensions.z:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y + 1)
								adj_z = 0
							
							# Skip if chunk doesn't exist
							if not terrain.chunks.has(adj_chunk_coords):
								continue
							
							var adj_cell := Vector2i(adj_x, adj_z)
							
							# Skip if already in pattern
							if wall_color_pattern.has(adj_chunk_coords) and wall_color_pattern[adj_chunk_coords].has(adj_cell):
								continue
							
							# Add adjacent cell
							if not wall_color_pattern.has(adj_chunk_coords):
								wall_color_pattern[adj_chunk_coords] = {}
								wall_color_pattern_cc[adj_chunk_coords] = {}
								wall_color_restore[adj_chunk_coords] = {}
								wall_color_restore_cc[adj_chunk_coords] = {}
							
							var adj_chunk : MarchingSquaresTerrainChunk = terrain.chunks[adj_chunk_coords]
							wall_color_restore[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_0(adj_cell)
							wall_color_restore_cc[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_1(adj_cell)
							wall_color_pattern[adj_chunk_coords][adj_cell] = vertex_color_0
							wall_color_pattern_cc[adj_chunk_coords][adj_cell] = vertex_color_1
			
			# Build grass mask patterns
			var grass_pattern := {}
			var grass_restore := {}
			for chunk_coords in pattern:
				grass_pattern[chunk_coords] = {}
				grass_restore[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					grass_restore[chunk_coords][cell_coords] = chunk.get_grass_mask(cell_coords)
					if current_quick_paint.has_grass:
						grass_pattern[chunk_coords][cell_coords] = Color(1, 1, 0, 0)
					else:
						grass_pattern[chunk_coords][cell_coords] = Color(0, 0, 0, 0)
			
			# Build ground color patterns
			_set_vertex_colors(current_quick_paint.ground_texture_slot)
			
			var color_pattern := {}
			var color_pattern_cc := {}
			var color_restore := {}
			var color_restore_cc := {}
			
			for chunk_coords in pattern:
				color_pattern[chunk_coords] = {}
				color_pattern_cc[chunk_coords] = {}
				color_restore[chunk_coords] = {}
				color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					color_restore[chunk_coords][cell_coords] = chunk.get_color_0(cell_coords)
					color_restore_cc[chunk_coords][cell_coords] = chunk.get_color_1(cell_coords)
					color_pattern[chunk_coords][cell_coords] = vertex_color_0
					color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Create ONE composite action instead of 6 separate actions
			var do_patterns := {
				"height": pattern,
				"wall_color_0": wall_color_pattern,
				"wall_color_1": wall_color_pattern_cc,
				"grass_mask": grass_pattern,
				"color_0": color_pattern,
				"color_1": color_pattern_cc
			}
			var undo_patterns := {
				"height": restore_pattern,
				"wall_color_0": wall_color_restore,
				"wall_color_1": wall_color_restore_cc,
				"grass_mask": grass_restore,
				"color_0": color_restore,
				"color_1": color_restore_cc
			}
			
			undo_redo.create_action("terrain brush with quick paint")
			undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
			undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
			undo_redo.commit_action()
		else:
			# NON-QUICK PAINT MODE: Apply height + default wall texture
			# Use the terrain's default_wall_texture for wall colors
			_set_vertex_colors(terrain.default_wall_texture)
			
			var wall_color_pattern := {}
			var wall_color_pattern_cc := {}
			var wall_color_restore := {}
			var wall_color_restore_cc := {}
			
			# First pass: collect all cells in the pattern
			for chunk_coords in pattern:
				wall_color_pattern[chunk_coords] = {}
				wall_color_pattern_cc[chunk_coords] = {}
				wall_color_restore[chunk_coords] = {}
				wall_color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					wall_color_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
					wall_color_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
					wall_color_pattern[chunk_coords][cell_coords] = vertex_color_0
					wall_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Second pass: expand to adjacent cells (walls appear at boundaries between cells)
			for chunk_coords in pattern:
				for cell_coords in pattern[chunk_coords]:
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							if dx == 0 and dz == 0:
								continue
							
							var adj_x : int = cell_coords.x + dx
							var adj_z : int = cell_coords.y + dz
							var adj_chunk_coords : Vector2i = chunk_coords
							
							if adj_x < 0:
								adj_chunk_coords = Vector2i(chunk_coords.x - 1, chunk_coords.y)
								adj_x = terrain.dimensions.x - 1
							elif adj_x >= terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >= terrain.dimensions.z:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y + 1)
								adj_z = 0
							
							if not terrain.chunks.has(adj_chunk_coords):
								continue
							
							var adj_cell := Vector2i(adj_x, adj_z)
							
							if wall_color_pattern.has(adj_chunk_coords) and wall_color_pattern[adj_chunk_coords].has(adj_cell):
								continue
							
							if not wall_color_pattern.has(adj_chunk_coords):
								wall_color_pattern[adj_chunk_coords] = {}
								wall_color_pattern_cc[adj_chunk_coords] = {}
								wall_color_restore[adj_chunk_coords] = {}
								wall_color_restore_cc[adj_chunk_coords] = {}
							
							var adj_chunk : MarchingSquaresTerrainChunk = terrain.chunks[adj_chunk_coords]
							wall_color_restore[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_0(adj_cell)
							wall_color_restore_cc[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_1(adj_cell)
							wall_color_pattern[adj_chunk_coords][adj_cell] = vertex_color_0
							wall_color_pattern_cc[adj_chunk_coords][adj_cell] = vertex_color_1
			
			# Create composite action with height + wall colors
			var do_patterns := {
				"height": pattern,
				"wall_color_0": wall_color_pattern,
				"wall_color_1": wall_color_pattern_cc
			}
			var undo_patterns := {
				"height": restore_pattern,
				"wall_color_0": wall_color_restore,
				"wall_color_1": wall_color_restore_cc
			}
			
			undo_redo.create_action("terrain height draw")
			undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
			undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
			undo_redo.commit_action()


#region cell-mode painting

## Cell-mode draw path. Pattern keys are chunk coords -> local cell -> value.
func draw_pattern_cells(terrain: MarchingSquaresTerrain) -> void:
	var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
	var pattern := {}
	var restore_pattern := {}
	var pattern_cc := {}
	var restore_pattern_cc := {}
	# Bridge-painted cells blend with their neighbours so the bridge renders as
	# a slanted surface instead of discrete flat steps (cell grid parity).
	var smooth_pattern := {}
	var smooth_restore := {}
	
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		pattern[draw_chunk_coords] = {}
		restore_pattern[draw_chunk_coords] = {}
		pattern_cc[draw_chunk_coords] = {}
		restore_pattern_cc[draw_chunk_coords] = {}
		smooth_pattern[draw_chunk_coords] = {}
		smooth_restore[draw_chunk_coords] = {}
		var chunk : MarchingSquaresCellChunk = terrain.chunks[draw_chunk_coords]
		if chunk == null:
			continue
		var draw_chunk_dict : Dictionary = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.001, 0.999)
			var global := terrain.global_of_local(draw_chunk_coords, draw_cell_coords)
			var restore_value
			var draw_value
			match mode:
				TerrainToolMode.GRASS_MASK:
					restore_value = chunk.get_grass_mask(draw_cell_coords)
					draw_value = Color(0.0, 0.0, 0.0, 0.0) if should_mask_grass else Color(1.0, 0.0, 0.0, 0.0)
				TerrainToolMode.VERTEX_PAINTING:
					if paint_walls_mode:
						restore_value = chunk.get_wall_color_0(draw_cell_coords)
						restore_pattern_cc[draw_chunk_coords][draw_cell_coords] = chunk.get_wall_color_1(draw_cell_coords)
					else:
						restore_value = chunk.get_color_0(draw_cell_coords)
						restore_pattern_cc[draw_chunk_coords][draw_cell_coords] = chunk.get_color_1(draw_cell_coords)
					draw_value = vertex_color_0
					pattern_cc[draw_chunk_coords][draw_cell_coords] = vertex_color_1
				TerrainToolMode.DEBUG_BRUSH:
					var center := BrushPatternCalculator.cell_center_for(terrain, global)
					var h_debug = terrain.get_cell_height(global)
					print("DEBUG INFO: global cell = ", global, " center = ", center,
						", height = ", h_debug,
						", color id = ", chunk.get_color_0(draw_cell_coords), " ", chunk.get_color_1(draw_cell_coords))
					continue
				TerrainToolMode.LEVEL:
					restore_value = chunk.get_height(draw_cell_coords)
					draw_value = lerp(restore_value, height, sample)
				TerrainToolMode.SMOOTH:
					var total : float = chunk.get_height(draw_cell_coords)
					var count : float = 1.0
					for nb in chunk.edge_neighbors(global):
						var h_nb = terrain.get_cell_height(nb)
						if h_nb != null:
							total += h_nb
							count += 1.0
					var avg : float = total / count
					restore_value = chunk.get_height(draw_cell_coords)
					draw_value = lerp(restore_value, avg, sample * strength)
				TerrainToolMode.BRIDGE:
					var b_end := Vector2(brush_position.x, brush_position.z)
					var b_start := Vector2(bridge_start_pos.x, bridge_start_pos.z)
					var bridge_length := (b_end - b_start).length()
					if bridge_length < 0.5:
						return
					var cell_center := BrushPatternCalculator.cell_center_for(terrain, global)
					var bridge_dir := (b_end - b_start) / bridge_length
					var progress := clamp((cell_center - b_start).dot(bridge_dir) / bridge_length, 0.0, 1.0)
					if ease_value != -1.0:
						progress = ease(progress, ease_value)
					restore_value = chunk.get_height(draw_cell_coords)
					draw_value = lerpf(bridge_start_pos.y, brush_position.y, progress)
					smooth_restore[draw_chunk_coords][draw_cell_coords] = chunk.get_smooth(draw_cell_coords)
					smooth_pattern[draw_chunk_coords][draw_cell_coords] = true
				_:
					# BRUSH tool (fallthrough for any other height tool)
					restore_value = chunk.get_height(draw_cell_coords)
					if flatten:
						draw_value = lerp(restore_value, brush_position.y, sample)
					else:
						var height_diff := brush_position.y - draw_height
						draw_value = lerp(restore_value, restore_value + height_diff, sample)
			restore_pattern[draw_chunk_coords][draw_cell_coords] = restore_value
			pattern[draw_chunk_coords][draw_cell_coords] = draw_value
	
	if pattern.is_empty():
		return
	
	# Regenerate affected chunks and the chunks owning their neighbours' walls.
	var affected := _collect_cell_affected_chunks(terrain, pattern)
	
	if mode == TerrainToolMode.GRASS_MASK:
		undo_redo.create_action("terrain grass mask draw")
		undo_redo.add_do_method(self, "draw_grass_mask_pattern_action", terrain, pattern)
		undo_redo.add_undo_method(self, "draw_grass_mask_pattern_action", terrain, restore_pattern)
		undo_redo.commit_action()
		for chunk in affected:
			chunk.regenerate_mesh()
		return
	
	if mode == TerrainToolMode.VERTEX_PAINTING:
		var color_key_0 := "wall_color_0" if paint_walls_mode else "color_0"
		var color_key_1 := "wall_color_1" if paint_walls_mode else "color_1"
		var do_patterns := {color_key_0: pattern, color_key_1: pattern_cc}
		var undo_patterns := {color_key_0: restore_pattern, color_key_1: restore_pattern_cc}
		var action_name := "terrain wall paint" if paint_walls_mode else "terrain vertex paint"
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
		undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
		undo_redo.commit_action()
		for chunk in affected:
			chunk.regenerate_mesh()
		return
	
	_set_vertex_colors(terrain.default_wall_texture)
	var wall_color_pattern := {}
	var wall_color_pattern_cc := {}
	var wall_color_restore := {}
	var wall_color_restore_cc := {}
	for chunk_coords: Vector2i in pattern:
		wall_color_pattern[chunk_coords] = {}
		wall_color_pattern_cc[chunk_coords] = {}
		wall_color_restore[chunk_coords] = {}
		wall_color_restore_cc[chunk_coords] = {}
		var chunk : MarchingSquaresCellChunk = terrain.chunks[chunk_coords]
		for cell_coords: Vector2i in pattern[chunk_coords]:
			wall_color_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
			wall_color_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
			wall_color_pattern[chunk_coords][cell_coords] = vertex_color_0
			wall_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
	
	if current_quick_paint:
		# QUICK PAINT: height + wall, grass and ground textures in one action.
		_set_vertex_colors(current_quick_paint.wall_texture_slot)
		var qp_wall_pattern := {}
		var qp_wall_pattern_cc := {}
		var qp_wall_restore := {}
		var qp_wall_restore_cc := {}
		for chunk_coords: Vector2i in pattern:
			qp_wall_pattern[chunk_coords] = {}
			qp_wall_pattern_cc[chunk_coords] = {}
			qp_wall_restore[chunk_coords] = {}
			qp_wall_restore_cc[chunk_coords] = {}
			var chunk : MarchingSquaresCellChunk = terrain.chunks[chunk_coords]
			for cell_coords: Vector2i in pattern[chunk_coords]:
				qp_wall_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
				qp_wall_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
				qp_wall_pattern[chunk_coords][cell_coords] = vertex_color_0
				qp_wall_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
		
		var grass_pattern := {}
		var grass_restore := {}
		for chunk_coords: Vector2i in pattern:
			grass_pattern[chunk_coords] = {}
			grass_restore[chunk_coords] = {}
			var chunk : MarchingSquaresCellChunk = terrain.chunks[chunk_coords]
			for cell_coords: Vector2i in pattern[chunk_coords]:
				grass_restore[chunk_coords][cell_coords] = chunk.get_grass_mask(cell_coords)
				grass_pattern[chunk_coords][cell_coords] = Color(1, 1, 0, 0) if current_quick_paint.has_grass else Color(0, 0, 0, 0)
		
		_set_vertex_colors(current_quick_paint.ground_texture_slot)
		var qp_color_pattern := {}
		var qp_color_pattern_cc := {}
		var qp_color_restore := {}
		var qp_color_restore_cc := {}
		for chunk_coords: Vector2i in pattern:
			qp_color_pattern[chunk_coords] = {}
			qp_color_pattern_cc[chunk_coords] = {}
			qp_color_restore[chunk_coords] = {}
			qp_color_restore_cc[chunk_coords] = {}
			var chunk : MarchingSquaresCellChunk = terrain.chunks[chunk_coords]
			for cell_coords: Vector2i in pattern[chunk_coords]:
				qp_color_restore[chunk_coords][cell_coords] = chunk.get_color_0(cell_coords)
				qp_color_restore_cc[chunk_coords][cell_coords] = chunk.get_color_1(cell_coords)
				qp_color_pattern[chunk_coords][cell_coords] = vertex_color_0
				qp_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
		
		var qp_do := {
			"height": pattern,
			"wall_color_0": qp_wall_pattern,
			"wall_color_1": qp_wall_pattern_cc,
			"grass_mask": grass_pattern,
			"color_0": qp_color_pattern,
			"color_1": qp_color_pattern_cc,
		}
		var qp_undo := {
			"height": restore_pattern,
			"wall_color_0": qp_wall_restore,
			"wall_color_1": qp_wall_restore_cc,
			"grass_mask": grass_restore,
			"color_0": qp_color_restore,
			"color_1": qp_color_restore_cc,
		}
		if mode == TerrainToolMode.BRIDGE:
			qp_do["smooth"] = smooth_pattern
			qp_undo["smooth"] = smooth_restore
		undo_redo.create_action("terrain brush with quick paint")
		undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, qp_do)
		undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, qp_undo)
		undo_redo.commit_action()
		for chunk in affected:
			chunk.regenerate_mesh()
		return
	
	var do_patterns := {
		"height": pattern,
		"wall_color_0": wall_color_pattern,
		"wall_color_1": wall_color_pattern_cc,
	}
	var undo_patterns := {
		"height": restore_pattern,
		"wall_color_0": wall_color_restore,
		"wall_color_1": wall_color_restore_cc,
	}
	if mode == TerrainToolMode.BRIDGE:
		do_patterns["smooth"] = smooth_pattern
		undo_patterns["smooth"] = smooth_restore
	undo_redo.create_action("terrain cell height draw")
	undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
	undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
	undo_redo.commit_action()
	for chunk in affected:
		chunk.regenerate_mesh()


## Chunks to regenerate for a cell pattern: painted chunks plus neighbours.
func _collect_cell_affected_chunks(terrain: MarchingSquaresTerrain, pattern: Dictionary) -> Array:
	var affected : Dictionary = {}
	for chunk_coords: Vector2i in pattern.keys():
		affected[chunk_coords] = true
		for neighbor_coords in terrain.chunk_neighbors(chunk_coords):
			affected[neighbor_coords] = true
	var result : Array = []
	for coords in affected.keys():
		if terrain.chunks.has(coords):
			result.append(terrain.chunks[coords])
	return result

#endregion


# For each cell in pattern, raise/lower by y delta
func draw_height_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var _height : float = draw_chunk_dict[draw_cell_coords]
			chunk.draw_height(draw_cell_coords.x, draw_cell_coords.y, _height)
		chunk.regenerate_mesh()


func draw_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_grass_mask_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunkBase = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var mask : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_grass_mask(draw_cell_coords.x, draw_cell_coords.y, mask)
		chunk.regenerate_mesh()


func draw_wall_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_wall_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


# Applies all terrain patterns  (for quick paint brush and vertex painting operations)
func apply_composite_pattern_action(terrain: MarchingSquaresTerrain, patterns: Dictionary) -> void:
	var affected_chunks : Dictionary = {}  # chunk_coords -> chunk reference
	
	var composite_disabled := false
	if mode == TerrainToolMode.SMOOTH and current_quick_paint == null:
		composite_disabled = true
	
	# Apply wall colors FIRST (before height changes that create ridge vertices)
	if patterns.has("wall_color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_0:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_0[chunk_coords]:
					chunk.draw_wall_color_0(cell_coords.x, cell_coords.y, patterns.wall_color_0[chunk_coords][cell_coords])
	
	if patterns.has("wall_color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_1:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_1[chunk_coords]:
					chunk.draw_wall_color_1(cell_coords.x, cell_coords.y, patterns.wall_color_1[chunk_coords][cell_coords])
	
	# Apply height changes (triggers ridge creation which uses wall colors)
	if patterns.has("height"):
		for chunk_coords: Vector2i in patterns.height:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.height[chunk_coords]:
					chunk.draw_height(cell_coords.x, cell_coords.y, patterns.height[chunk_coords][cell_coords])
	
	# Apply smooth (bridge-blended) flags for cell modes
	if patterns.has("smooth"):
		for chunk_coords: Vector2i in patterns.smooth:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.smooth[chunk_coords]:
					chunk.draw_smooth(cell_coords.x, cell_coords.y, patterns.smooth[chunk_coords][cell_coords])
	
	# Apply grass mask
	if patterns.has("grass_mask") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.grass_mask:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.grass_mask[chunk_coords]:
					chunk.draw_grass_mask(cell_coords.x, cell_coords.y, patterns.grass_mask[chunk_coords][cell_coords])
	
	# Apply ground colors LAST
	if patterns.has("color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_0:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_0[chunk_coords]:
					chunk.draw_color_0(cell_coords.x, cell_coords.y, patterns.color_0[chunk_coords][cell_coords])
	
	if patterns.has("color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_1:
			var chunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_1[chunk_coords]:
					chunk.draw_color_1(cell_coords.x, cell_coords.y, patterns.color_1[chunk_coords][cell_coords])
	
	# Regenerate mesh ONCE for each affected chunk (instead of 6 times!)
	for chunk in affected_chunks.values():
		chunk.regenerate_mesh()

#endregion

#region vertex/texture setters and getters

func _set_vertex_colors(vc_idx: int) -> void:
	match vc_idx:
		0: #rr
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		1: #rg
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		2: #rb
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		3: #ra
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		4: #gr
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		5: #gg
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		6: #gb
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		7: #ga
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		8: #br
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		9: #bg
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		10: #bb
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		11: #ba
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		12: #ar
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		13: #ag
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		14: #ab
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		15: #aa
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)


func _set_new_textures(_preset: MarchingSquaresTexturePreset) -> void:
	if _preset == null:
		_preset = EMPTY_TEXTURE_PRESET.duplicate()
	
	# Set BatchUpdate flag to avoid indivudal setters triggering updates
	current_terrain_node.is_batch_updating = true
	
	for i in range(5): # The range is 5 because MarchingSquaresTextureList has 5 export variables (terrain textures, texture scales, grass sprites, grass colors, has_grass)
		match i:
			0: # terrain_textures (unified for both floor and wall painting)
				for i_tex in range(_preset.new_textures.terrain_textures.size()):
					var tex : Texture2D = _preset.new_textures.terrain_textures[i_tex]
					match i_tex:
						0:
							current_terrain_node.texture_1 = tex
						1:
							current_terrain_node.texture_2 = tex
						2:
							current_terrain_node.texture_3 = tex
						3:
							current_terrain_node.texture_4 = tex
						4:
							current_terrain_node.texture_5 = tex
						5:
							current_terrain_node.texture_6 = tex
						6:
							current_terrain_node.texture_7 = tex
						7:
							current_terrain_node.texture_8 = tex
						8:
							current_terrain_node.texture_9 = tex
						9:
							current_terrain_node.texture_10 = tex
						10:
							current_terrain_node.texture_11 = tex
						11:
							current_terrain_node.texture_12 = tex
						12:
							current_terrain_node.texture_13 = tex
						13:
							current_terrain_node.texture_14 = tex
						14: # texture_15 is reserved for VOID
							current_terrain_node.texture_15 = tex
			1: # texture_scales
				for i_tex_scale in range(_preset.new_textures.texture_scales.size()):
					var scale : float = _preset.new_textures.texture_scales[i_tex_scale]
					match i_tex_scale:
						0:
							current_terrain_node.texture_scale_1 = scale
						1:
							current_terrain_node.texture_scale_2 = scale
						2:
							current_terrain_node.texture_scale_3 = scale
						3:
							current_terrain_node.texture_scale_4 = scale
						4:
							current_terrain_node.texture_scale_5 = scale
						5:
							current_terrain_node.texture_scale_6 = scale
						6:
							current_terrain_node.texture_scale_7 = scale
						7:
							current_terrain_node.texture_scale_8 = scale
						8:
							current_terrain_node.texture_scale_9 = scale
						9:
							current_terrain_node.texture_scale_10 = scale
						10:
							current_terrain_node.texture_scale_11 = scale
						11:
							current_terrain_node.texture_scale_12 = scale
						12:
							current_terrain_node.texture_scale_13 = scale
						13:
							current_terrain_node.texture_scale_14 = scale
						14:
							current_terrain_node.texture_scale_15 = scale
			2: # grass_sprites
				for i_grass_tex in range(_preset.new_textures.grass_sprites.size()):
					var tex : Texture2D = _preset.new_textures.grass_sprites[i_grass_tex]
					if tex == null:
						continue
					match i_grass_tex:
						0:
							current_terrain_node.grass_sprite_tex_1 = tex
						1:
							current_terrain_node.grass_sprite_tex_2 = tex
						2:
							current_terrain_node.grass_sprite_tex_3 = tex
						3:
							current_terrain_node.grass_sprite_tex_4 = tex
						4:
							current_terrain_node.grass_sprite_tex_5 = tex
						5:
							current_terrain_node.grass_sprite_tex_6 = tex
			3: # grass_colors
				for i_grass_col in range(_preset.new_textures.grass_colors.size()):
					var col : Color = _preset.new_textures.grass_colors[i_grass_col]
					if col == null:
						continue
					match i_grass_col:
						0:
							current_terrain_node.texture_albedo_1 = col
						1:
							current_terrain_node.texture_albedo_2 = col
						2:
							current_terrain_node.texture_albedo_3 = col
						3:
							current_terrain_node.texture_albedo_4 = col
						4:
							current_terrain_node.texture_albedo_5 = col
						5:
							current_terrain_node.texture_albedo_6 = col
			4: # has_grass
				for i_has_grass in range(_preset.new_textures.has_grass.size()):
					var val : bool = _preset.new_textures.has_grass[i_has_grass]
					match i_has_grass:
						0:
							current_terrain_node.tex2_has_grass = val
						1:
							current_terrain_node.tex3_has_grass = val
						2:
							current_terrain_node.tex4_has_grass = val
						3:
							current_terrain_node.tex5_has_grass = val
						4:
							current_terrain_node.tex6_has_grass = val
	
	vp_texture_names.texture_names = _preset.new_tex_names.texture_names
	
	# Apply a batch update
	current_terrain_node.force_batch_update()
	
	# Mark scene as modified so user knows to save
	EditorInterface.mark_scene_as_unsaved()
	
	# Store current preset
	current_terrain_node.current_texture_preset = _preset
	
	# Set batch update to false, to allow setters to work individually
	current_terrain_node.is_batch_updating = false
	
	# Ensure the Editor is updated live (trick it to redraw - There might be an easier way but this works)
	EditorInterface.inspect_object(current_terrain_node)


func get_cell_normal(chunk: MarchingSquaresTerrainChunkBase, cell: Vector2i) -> Vector3:
	if chunk is MarchingSquaresCellChunk:
		return _get_cell_normal_cells(chunk, cell)
	
	var h_c := chunk.get_height(cell)
	
	var x0 := max(cell.x - 1, 0)
	var x1 := min(cell.x + 1, chunk.dimensions.x - 1)
	var y0 := max(cell.y - 1, 0)
	var y1 := min(cell.y + 1, chunk.dimensions.y - 1)
	
	var h_left := chunk.get_height(Vector2i(x0, cell.y))
	var h_right := chunk.get_height(Vector2i(x1, cell.y))
	var h_below := chunk.get_height(Vector2i(cell.x, y0))
	var h_above := chunk.get_height(Vector2i(cell.x, y1))
	
	var sx := (h_right - h_left) / (2.0 * current_terrain_node.cell_size.x)
	var sz := (h_above - h_below) / (2.0 * current_terrain_node.cell_size.y)
	
	var normal := Vector3(-sx, 1.0, -sz).normalized()
	return normal


## Approximate normal for a cell chunk: slope from the cell to its neighbours.
func _get_cell_normal_cells(chunk: MarchingSquaresCellChunk, cell: Vector2i) -> Vector3:
	var terrain := current_terrain_node
	var global := chunk.chunk_coords * chunk.cells_per_chunk() + cell
	var center := BrushPatternCalculator.cell_center_for(terrain, global)
	var h := chunk.get_height(cell)
	var sum := Vector3.ZERO
	for nb in chunk.edge_neighbors(global):
		var h_nb = terrain.get_cell_height(nb)
		if h_nb == null:
			continue
		var dir2 := BrushPatternCalculator.cell_center_for(terrain, nb) - center
		var dir := Vector3(dir2.x, 0, dir2.y)
		if dir.length_squared() < 0.000001:
			continue
		var normal := Vector3(-dir.x, float(h_nb) - h, -dir.z)
		sum += normal
	if sum.length_squared() < 0.000001:
		return Vector3.UP
	return (sum + Vector3.UP).normalized()

#endregion
