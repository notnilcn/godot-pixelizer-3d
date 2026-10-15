@tool
extends Node
class_name MarchingSquaresToolbox


var tools : Array[MarchingSquaresTool] = [
	# Landscaping tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/brush_tool.tres"), # Brush tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/level_tool.tres"), # Level tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/smooth_tool.tres"), # Smooth tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/bridge_tool.tres"), # Bridge tool
	# Terrain visuals tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/grass_mask_tool.tres"), # Grass mask tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/vertex_paint_tool.tres"), # Vertex paint tool
	# General plugin tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/debug_brush_tool.tres"), # Debug brush tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/chunk_manager_tool.tres"), # Chunk manager tool
	preload("res://addons/MarchingSquaresTerrain/editor/tools/terrain_settings_tool.tres"), # Terrain settings tool
]
