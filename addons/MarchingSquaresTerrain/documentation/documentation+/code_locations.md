# Code Locations

This small guide explains where you can find the code for several (smaller) features inside the plugin.

### Grass and Texture Mixing

* **MarchingSquaresTerrainVertexColorHelper** (The whole script)
* **MarchingSquaresChunk** script → `add_point(x: float, y: float, z: float, uv_x: float = 0, uv_y: float = 0, diag_midpoint: bool = false)` function.
* **mst_terrain** gdshader → fragment function.

Here you can change the logic for how the color_0 and color_1 variables are calculated to change how the grass appears and floor textures get mixed.

Although the variables are called _color_, the shader logic uses these two vec4 variables and checks wether any of the channels are a 1 or 0. It then calculates which texture it should use based on which channels in both variables are "turned on".

### Grass Animations

* **mst_grass** gdshader → at the top of the vertex function.

Right now having the fps at 0 means that the shader will use a noise texture to apply a global smooth wind effect. Turning the fps up in the terrain_settings tool mode in the editor makes the individual grass sprites move from left to right giving it a pixel art look.

Feel free to change these animations to what looks best for your project! The two animation types present right now are only a base to get people started.

### Cell Normal Calculations

* **MarchingSquaresTerrainPlugin** script → `get_cell_normal(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Vector3:` function.
  
### Chunk UI Lines

* **MarchingSquaresTerrainGizmo** script → `try_add_chunk(terrain_system: MarchingSquaresTerrain, coords: Vector2i):` function.
* **MarchingSquaresTerrainGizmo** script → `add_chunk_lines(terrain_system: MarchingSquaresTerrain, coords: Vector2i, material: Material):` function.

### Terrain (Triplanar) Mapping

* **mst_terrain** gdshaderinc → fragment function.

### Ridge & Ledge Texture Calculations

* **mst_terrain** gdshaderinc → end of the fragment function.
* **MarchingSquaresTerrainVertexColorHelper** script → at the start of the `blend_colors(vertex: Vector3, uv: Vector2, diag_midpoint: bool = false) -> Dictionary[String, Color]:` function

### Triangle / Hexagon Cell Modes

* **MarchingSquaresTerrainHexGrid** / **MarchingSquaresTriGrid** scripts → all coordinate math (world <-> cell, neighbours, hexagon selections).
* **MarchingSquaresCellChunk** script → shared cell mesh generation (`_emit_cell`, `_emit_wall`, `_emit_ramp`), grass hooks and cell-mode save hooks.
* **MarchingSquaresHexChunk** / **MarchingSquaresTriChunk** scripts → per-mode shape/neighbour implementations.
* **MarchingSquaresCellGrassPlanter** script → grass placement for cell chunks.
* The per-mode data subfolders (`square/`, `triangle/`, `hex/`) are handled by **MSTDataHandler** (`mode_name`, `mode_subdir`, `export_cell_chunk_data`, `import_cell_chunk_data`).

### Grid Aligned Painting and Cell Chunk Gizmos

* **brush_pattern_calculator** script → `grid_aligned_cells` and `grid_aligned_outline`.
* **marching_squares_terrain_gizmo** script → `_redraw_cell_brush`, `_grid_aligned_brush_transform`.
* **marching_squares_terrain_cell_chunk_gizmo** script → per-cell height handles.
