@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunkBase
## Minimal shared base for all terrain chunk classes (square, triangle, hex).
## Keeps mode-agnostic code (terrain, plugin, data handler) typed without
## pulling square-specific logic out of MarchingSquaresTerrainChunk.


# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : Node3D
@export var chunk_coords : Vector2i = Vector2i.ZERO

@export_storage var height_map : Array
var color_map_0 : PackedColorArray
var color_map_1 : PackedColorArray
var wall_color_map_0 : PackedColorArray
var wall_color_map_1 : PackedColorArray
var grass_mask_map : PackedColorArray
var grass_planter = null # square only; null for cell chunks

var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)
var _data_dirty : bool = false # Set to true when source data changes, triggers save in MSTDataHandler


#region virtual API

## Called by the terrain system to (re)build this chunk from its source data.
func initialize_terrain(_should_regenerate_mesh: bool = true) -> void:
	pass


## Rebuild this chunk's mesh.
func regenerate_mesh(_use_threads: bool = false) -> void:
	pass


## Mark all cells for regeneration and rebuild.
func regenerate_all_cells(_use_threads: bool = false) -> void:
	pass


## Mark chunk as having modified source data - triggers save in MSTDataHandler.
func mark_dirty() -> void:
	pass


func get_height(_cc: Vector2i) -> float:
	return 0.0


func draw_height(_x: int, _z: int, _y: float) -> void:
	pass


func get_color_0(_cc: Vector2i) -> Color:
	return Color(0, 0, 0, 0)


func get_color_1(_cc: Vector2i) -> Color:
	return Color(0, 0, 0, 0)


func get_wall_color_0(_cc: Vector2i) -> Color:
	return Color(0, 0, 0, 0)


func get_wall_color_1(_cc: Vector2i) -> Color:
	return Color(0, 0, 0, 0)


func get_grass_mask(_cc: Vector2i) -> Color:
	return Color(0, 0, 0, 0)


## Whether a cell's top surface is sloped to blend with its neighbours
## (set by the bridge tool on cell-mode terrain).
func get_smooth(_cc: Vector2i) -> bool:
	return false


## True when this chunk contains at least one smoothed cell (fast path).
func has_smooth_cells() -> bool:
	return false


func draw_smooth(_x: int, _z: int, _smooth: bool) -> void:
	pass


func draw_color_0(_x: int, _z: int, _color: Color) -> void:
	pass


func draw_color_1(_x: int, _z: int, _color: Color) -> void:
	pass


func draw_wall_color_0(_x: int, _z: int, _color: Color) -> void:
	pass


func draw_wall_color_1(_x: int, _z: int, _color: Color) -> void:
	pass


func draw_grass_mask(_x: int, _z: int, _masked: Color) -> void:
	pass

#endregion
