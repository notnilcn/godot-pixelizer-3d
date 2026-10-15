# AGENTS.md — `addons/MarchingSquaresTerrain` (Yūgen's Terrain Authoring Toolkit)

This folder is the **entire plugin**. It is distributed by copying the folder into another project's `addons/` — keep it self-contained: no imports from outside `res://addons/MarchingSquaresTerrain/` (engine/editor APIs excepted). Read this file before touching any `.gd` here.

## Layout

| Path | Role |
|---|---|
| `plugin.cfg`, `editor/marching_squares_terrain_plugin.gd` | Entry point. `MarchingSquaresTerrainPlugin` (`EditorPlugin`, static `instance`): owns tool mode (`TerrainToolMode`), brush state, selection, and the paint pipeline (`draw_pattern`). |
| `editor/marching_squares_ui.gd` | Dock UI; builds tool settings from attribute dictionaries and forwards changes to the plugin. |
| `editor/gizmos/` | `MarchingSquaresTerrainGizmo` (brush/selection drawing), `MarchingSquaresTerrainChunkGizmo`, `MarchingSquaresTerrainCellChunkGizmo` (per-cell height handles), and the gizmo plugin that registers them. |
| `editor/tools/scripts/` | Tool resources + attribute system: `MarchingSquaresTool`, `MarchingSquaresToolbox`, `MarchingSquaresToolbar`, `MarchingSquaresToolAttributes(+List,+Settings)`, texture presets/lists/names/quick paints, geometry baker. |
| `editor/utils/` | `BrushPatternCalculator` (brush sampling, `grid_aligned_cells`, `grid_aligned_outline`), `MSTGridSnap` (shared square-lattice snapping helper for the bundled ports), `EngineWrapper` (editor-vs-runtime helpers), file utils. |
| `algorithm/terrain/marching_squares_terrain.gd` | `MarchingSquaresTerrain` (`Node3D`): `GridType {SQUARE, TRIANGLE, HEX, HEX_RINGS}`, chunk lifecycle, data directory, save hooks, wrap props. |
| `algorithm/terrain/marching_squares_terrain_chunk.gd` | Original square marching-squares chunk. |
| `algorithm/terrain/marching_squares_terrain_chunk_base.gd` | `MarchingSquaresTerrainChunkBase`: shared virtual API for all chunk types (heights, colors, dirty flag). |
| `algorithm/terrain/marching_squares_terrain_cell.gd`, `..._vertex_color_helper.gd` | Per-cell data plus texture/grass vertex-color math (consumed by the `mst_terrain` shader). |
| `algorithm/cells/marching_squares_cell_chunk.gd` | `MarchingSquaresCellChunk`: shared mesh generation for triangle/hex (`_emit_cell`, `_emit_wall`, `_emit_ramp`), merge modes, grass + save hooks. |
| `algorithm/cells/marching_squares_cell_grass_planter.gd` | Grass placement for cell chunks. |
| `algorithm/hex/`, `algorithm/tri/` | `MarchingSquaresHexGrid`/`MarchingSquaresHexChunk` and `MarchingSquaresTriGrid`/`MarchingSquaresTriChunk`: per-mode coordinate math and shape/neighbour implementations. |
| `algorithm/hex_rings/` | `MarchingSquaresHexRingsGrid`/`MarchingSquaresHexRingsChunk`: hex-ring mode — a low-res chunk hex owning a disk of micro-hexes (the server hexmod layout), coordinate math + wrap (`wrap_cell`). |
| `algorithm/grass/marching_squares_grass_planter.gd` | Square-grid grass (MultiMesh). |
| `resources/mst_chunk_data.gd` | `MSTChunkData`: serialized per-chunk payload. |
| `resources/mst_data_handler.gd` | `MSTDataHandler`: all external save/load, per-mode subfolders, legacy data migration. |
| `resources/shaders/` | `mst_terrain` (+ `.gdshaderinc`), `mst_grass`, bake/baked variants, brush visuals. |
| `resources/plugin_materials/`, `texture_presets/`, `quick_paints/` | Default materials/visuals, texture presets, quick paints. |
| `utils/marching_squares_thread_pool.gd` | Background mesh regeneration. |
| `documentation/` | `plugin_quick_guide.md` (user-facing) and `documentation+/` (code style, internal tool system, code locations, navmesh guide). |

## Core architecture

- **Grid types.** `SQUARE` is the original marching-squares pipeline. `TRIANGLE`/`HEX` are cell modes: every cell renders as a flat polygon at its own height with walls/ramps toward lower neighbours. `HEX_RINGS` is the hexmod chunk mode: the canonical world is `wrap_chunk_cols × wrap_chunk_rows` low-res chunk hexes (axial chunk coords), each owning the disk of micro-hexes whose `to_lower_res` is that chunk; cell coords are global axial and `chunk_hex_radius` sets the disk radius. With `wrap_chunk_cols/rows` > 0, `chunk_for_cell`/`local_cell` canonicalize seam cells into the lap (`MarchingSquaresHexRingsGrid.wrap_cell`), so border chunks read their wrapped neighbours. Chunks expose `has_cell(local)` — the bounding-box corners outside the disk are skipped by the mesh/grass loops. `MarchingSquaresTerrain.make_chunk()` dispatches on `grid_type`; painting tools use the terrain's `chunk_of_cell`/`local_cell`/`global_of_local`/`world_to_cell`/`cell_center_of`/`chunk_neighbors` helpers so they work on all four modes.
- **Data.** Chunks are stored outside the scene under the terrain's `data_directory`, in per-mode subfolders `square/`, `triangle/`, `hex/`, `hex_rings/` (`MSTDataHandler.MODE_NAMES`, order must match `GridType`). Each chunk is `chunk_<x>_<y>/metadata.res` (an `MSTChunkData`). Legacy data at the directory root is migrated to `square/`. Saving is triggered from `NOTIFICATION_EDITOR_PRE_SAVE` and explicit `MSTDataHandler` calls, not on every stroke.
- **Editor tools.** `TerrainToolMode` enumerates the tools; attributes are declared in `MarchingSquaresToolAttributeSettings` + `MarchingSquaresToolAttributesList`, resolved in `MarchingSquaresToolAttributes` (`add_setting`, `_get_setting_value`) and `MarchingSquaresUI._on_setting_changed`, then executed in the plugin's `draw_pattern`. Grid-aligned painting is gated by `grid_align_gate_passes()` (cell terrain + hex brush + falloff off) and sampled with `BrushPatternCalculator.grid_aligned_cells`.
- **Rendering.** One `MeshInstance3D` per chunk plus a `StaticBody3D` collider. Texture/grass information rides in vertex colors (`color_0`, `color_1`, wall/grass maps) interpreted by `MarchingSquaresTerrainVertexColorHelper` and `mst_terrain.gdshader`; grass is a MultiMesh driven by the grass planters. Bake shaders feed runtime texture baking.

## Conventions

- Follow `documentation/documentation+/code_style_guide.md`: tabs, `MarchingSquares`/`MST` class-name prefixes, snake_case, `variable : type` spacing, 2 blank lines between sections/functions, `#region` blocks, `##` comments for editor-visible APIs.
- Scripts run in the editor: keep `@tool` behaviour safe and guard runtime-only APIs (`EngineWrapper.is_editor()`, `Engine.is_editor_hint()`).
- Never hand-edit `.uid` files. Move/rename scripts through the editor so resource `uid://` references stay valid — scripts preload by path, so update any preloads pointing at a moved file.
- Keep the addon self-contained and copy-paste friendly.

## Extending

- **New tool or attribute**: `documentation/documentation+/internal_tool_system.md` walks through the tool resource, attribute lists, UI wiring, and `draw_pattern` behaviour.
- **New grid mode**: add a `GridType` value + chunk class + grid math class, wire into the terrain's `make_chunk()` plus the coordinate dispatch helpers (`cells_per_chunk`, `chunk_of_cell`, `local_cell`, `global_of_local`, `world_to_cell`, `cell_center_of`, `chunk_neighbors`, `cell_chunk_position`), and append the folder name to `MSTDataHandler.MODE_NAMES` (order = enum order).

## Pitfalls

- `.gitignore` contains bare `square/`, `triangle/`, `hex/` patterns, so **new files under `algorithm/hex/` are git-ignored** — use `git add -f` (do not rename the folder).
- `mc.tct` is a stray copy of the square chunk script that Godot never imports (wrong extension). `algorithm/terrain/marching_squares_terrain_chunk.gd` is the source of truth.
- Square-only logic belongs in `MarchingSquaresTerrainChunk`; the cell chunks share `MarchingSquaresCellChunk` via `MarchingSquaresTerrainChunkBase`. `grass_planter` is null on cell chunks (different planter class).
- `is_data_directory_unique` + `copy_from_dir` in `MarchingSquaresTerrain._initialize_data_directory()` prevent duplicate-node data collisions — don't remove that handling.
- Per-chunk merge modes decide whether cell-mode steps become 45° ramps; `CUBIC` keeps exact columns.

## Verification

- Parse/import check from the repo root: `godot --headless --editor --quit --path .` (see the root `AGENTS.md` for the local Godot binary).
- Headless behaviour tests: `godot --headless --path . --script res://tests/run_grid_tests.gd` (also `run_cell_chunk_tests`, `run_brush_tests`, `run_grid_align_tests`, `run_merge_tests`, `run_bridge_smooth_tests`, `run_tool_tests`, `run_cell_save_tests`, `run_perf_tests`, `run_mst_snap_tests`). They print `PASSED`/`FAILED` and exit non-zero on failure.
- Windowed only (the dummy renderer has no MultiMesh readback): `run_cell_grass_tests.gd`; visual captures use `capture_*.gd -- --capture` and save PNGs to `user://`.
