# PLAN.md — Pixelizer3D fix + refactor plan

**Audience:** an agent session executing this plan. Read `AGENTS.md` (root) and
`addons/pixelizer_3d/AGENTS.md` first — they carry the architecture and the
load-bearing invariants, and several items below rewrite what they describe.

**Scope:** everything from the 2026-10-16 audit of this repo against its seven
source projects (`Stable3D9ec4e65a8926V1`, `ProPixelizer`, `3DPixelArt_Tutorial`,
`godot-3d-pixel-art`, `3d-pixel-art-in-godot`, `3d-pixel-art-base-project`,
`Yugens-Terrain-Authoring-Toolkit-1.2.4`). Every finding below was verified by
reading the code; the ones marked *(reproduced)* were reproduced by running the
engine.

**Out of scope, by owner's instruction:** anything MST-specific. Do not edit
`addons/MarchingSquaresTerrain/**` (it is vendored and byte-identical upstream
apart from one brush-preview `.tres`), and do not chase the MST runtime
texture-baker interaction, the bridged MST shaders' `ALPHA` writes, or the grass
bridge injection point. B2 below fixes the *bridge tooling* that MST happens to
exercise; that is as far as this plan goes.

**Tooling available:** the Godot binary is
`C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe` (4.7 mono,
`_console` variant). The `open_godot_mcp` addon is enabled in `project.godot`
(editor plugin + autoload), so an MCP-connected editor session is possible; see
Appendix 1 for the scripted capture recipe used to reproduce the picker bug, and
Appendix 2 for the verification loops.

---

## Section A — Diagnostics overlay and inspector

### A1. The object picker lets a physics hit short-circuit the mesh ray test *(reproduced)*

`nodes/pixelizer_diagnostics_overlay.gd`, `_pick_at()` (~`:379-419`):

```gdscript
var physics_pick := _pick_physics(camera, origin, direction)
if physics_pick != null and not _is_unselectable(physics_pick):
    select_node(physics_pick)
    return                      # <-- returns without ever running the mesh test
```

`_pick_physics()` resolves a collider to *some* geometry (its first supported
descendant, else the first supported ancestor — `:455-476`). MST creates a
`StaticBody3D` per chunk at runtime, so **any** click whose ray crosses terrain
collision selects that chunk, even when a mesh is much closer. Reproduced: a
click aimed at the centre of `Knight_Head` returned
`.../MarchingSquaresTerrain/Chunk (0, 0)2`; the physics collider was
`Chunk (0, 0)2_col` at 28.491 world units while `Knight_Body`'s triangle hit was
26.534.

**Change.** Compute both candidates and pick the nearer one:

1. Extract the existing AABB pre-pass + triangle-sort loop into a helper, e.g.
   `_pick_mesh(origin, direction) -> Dictionary` returning `{node, distance}` or
   an empty dictionary.
2. Give the physics path a distance too (`hit["position"]` is available from
   `intersect_ray`).
3. Prefer the physics result only when its distance `<=` the mesh distance (tie
   goes to physics, since it is exact and resolves bodies to their mesh).
4. Keep the `MAX_TRIANGLE_CANDIDATES` early-out. It is correct as written: an
   AABB entry distance is a lower bound on that candidate's triangle hit, so
   `best_distance <= hit["t"]` cannot skip a nearer mesh.
5. While here: `_candidate_aabb()` returns `mesh.get_aabb()` for
   `MeshInstance3D`. Prefer `(node as GeometryInstance3D).get_aabb()`, which
   accounts for the skeleton on skinned meshes; the current call uses the
   **rest-pose** AABB, and `_mesh_hit_distance()`'s triangle test uses
   `mesh.get_faces()`, which ignores skinning entirely. The demo's KayKit
   characters are skinned with their `MeshInstance3D` nodes inside a
   `Skeleton3D`, so a posed character is picked from its rest pose. Document the
   limitation if you do not implement per-bone skinning in the picker.

**Verify.** Re-run the reproduction in Appendix 1: the same screen point must
return `Knight_Body` (or the nearest visible mesh), and the 9x5 sweep over the
demo must still hit terrain chunks where the terrain is the nearest surface.

### A2. The object panel hides a selected node's own exports

`_rebuild_object_panel()` (~`:606-637`) only shows the selected node's own
groups when `_script_class_name(_selected).begins_with("Pixelizer")`. A plain
`MeshInstance3D` has no script ⇒ no class name ⇒ the panel shows only
`Create Object Profile` plus `Parent Applier — <name>`, whose sliders retune the
**entire applier subtree**, not the object that was clicked. That is the reported
"it only selects PixelizerApplier3D node groups".

**Change.**

1. Drop the `begins_with("Pixelizer")` guard and show any selected node's editor
   exports (skip engine groups the way `_collect_groups()` already does).
2. Make the scope of each section explicit in its title, e.g.
   `This object — <name>`, `Object profile (this object only)`,
   `Parent applier — <name> (shared by N meshes)`. Count `N` from the applier's
   `_states.size()`.
3. Put the `Create Object Profile` button above the applier section, and only
   when the selected node is a supported geometry type
   (`PixelizerGeometryState.is_supported_node`).

**Verify.** Select a character mesh: the panel must show a per-object section
whose edits do not change sibling meshes, and the applier section must be
labelled as shared.

### A3. Dead tuner rows

The audit's read-site analysis found these properties are read only during setup,
so their sliders can never do anything at runtime. Either give them setters or
hide them through `IGNORE_CLASS_PROPERTIES` (the mechanism already exists at
`nodes/pixelizer_diagnostics_overlay.gd:49-57`).

| Class | Property | Why it is inert |
|---|---|---|
| `PixelizerManager3D` | `texel_density`, `view_zoom` | read only via `get_view_width()` / `apply_managed_size()`, reachable only with `manage_camera_size` or LOW_RES |
| `PixelizerManager3D` | `auto_bridge_custom_shaders` | read at bind/refresh only; applied states never re-run the lookup |
| `PixelizerWater3D` | `size`, `subdivisions` | build the mesh in `_ready` |
| `PixelizerWater3D` | `coast`, `wave_phase` | pushed as instance uniforms in `_ready` only |
| `PixelizerSkyClouds3D` | `plane_size` | builds the `PlaneMesh` in `_ready` |
| `PixelizerSkyClouds3D` | `clouds_enabled`, `deck_enabled` | `visible` is recomputed only in `_update_transform()`, which `_process` calls only when `follow_camera` is true |
| `PixelizerSkyClouds3D` | `cloud_octave_drop` | declared in `cloud_fbm.gdshaderinc` and read by no shader at all |
| `PixelizerDayNight3D` | sun-arc + all ramps | read only inside `_apply()`, which runs from `_ready` and the `time_of_day` setter |

Preferred fixes, in order of value:

- `PixelizerWater3D.coast` / `.wave_phase`: add setters that call
  `set_instance_shader_parameter()`. These are the two live-looking knobs for the
  water and the demo's tile grid needs them.
- `PixelizerSkyClouds3D`: recompute `visible` in `_process` unconditionally
  (cheap), or add setters on `clouds_enabled` / `deck_enabled` that call
  `_update_transform()`.
- `cloud_octave_drop`: implement it (see D1's cloud notes) or remove it from the
  export list, the shader header and the cloud-param dictionary. Do not leave a
  knob that nothing reads.
- `PixelizerManager3D.texel_density` / `view_zoom`: either make
  `get_texel_world_size()` honour them, or hide them and document that the
  resolution model only applies in LOW_RES / with `manage_camera_size`.
- The setup-only rest: add to `IGNORE_CLASS_PROPERTIES`.

**Verify.** Toggle each row in the running demo and confirm a visible change or
that the row is gone.

### A4. The status line reports a meaningless texel size on perspective cameras *(confirmed visually)*

`get_debug_status_line()` prints `u/texel=%.4f` from
`PixelizerCameraBinding.get_texel_world_size()`, which is
`camera.size / viewport.size.y`. For a perspective camera `size` is unused by the
projection (fov drives it), so the demo shows `u/texel=0.0015` (i.e. `1.0/648`).
The demo camera is perspective (`demo/demo.tscn`, `fov = 24.0`, no
`projection = 1`).

**Change.** Report `n/a` (or `(perspective)`) for the texel size and the
remainder when the active camera is not orthographic, and keep the numeric
readout for ortho. Do not try to synthesise a perspective "texel" — the macro
lattice is screen-space, and the snap is ortho-only by construction.

---

## Section B — Shader bridge and generation

### B1. The bridge watchdog is armed on the wrong branch, and `rescan()` cannot repair it

`nodes/pixelizer_applier_3d.gd`, `_pixelize_geometry()` (~`:357-385`):

```gdscript
if state.bind(manager):
    _apply_mover(instance)
    return                       # <-- a SUCCESSFUL bind that swapped is never watched
if state.has_no_materials() or state.bridge_swapped():
    _watch_ids[id] = state
```

`_watch_ids` is written only there. The documented contract in
`addons/pixelizer_3d/AGENTS.md` ("keeps a throttled `_watch_ids` poll … after a
swap actually happened") is therefore not implemented: only a *failed* bind arms
the watchdog. When MST's runtime texture baker later replaces a chunk's mesh and
material with the pristine `mst_terrain_baked.gdshader`, that chunk keeps the
metadata cull layer it was given at bind time while running a shader with no
anchor branch — it writes ordinary albedo into the metadata target, which the
apply pass decodes as `R = size/32, G = tag/256, B = depth`. The demo survives
only because MST nulls chunk meshes on save and the applier's first scan runs
before MST's deferred init, so the first `bind()` *fails* with
`has_no_materials()` and arms the watchdog by accident.

`rescan()` does not repair it either: for an already-applied state,
`_pixelize_geometry` returns at the `state.is_applied()` branch without calling
`refresh_bridge()`, so `rescan_interval > 0` is not a workaround.

**Change.**

1. Arm the watchdog when a swap actually happened, i.e. restructure to
   ```gdscript
   var applied := state.bind(manager)
   if applied and state.bridge_swapped():
       _watch_ids[id] = state
       set_process(true)
   elif not applied and (state.has_no_materials() or state.bridge_swapped()):
       _watch_ids[id] = state
       set_process(true)
   ```
2. In the `state.is_applied()` early branch of `_pixelize_geometry`, call
   `state.refresh_bridge(manager)` before `push_instance_params()` so a rescan
   re-runs the manifest lookup. `refresh_bridge` is idempotent and cheap.
3. Consider pruning `_watch_ids` entries that have been applied and stable for
   N polls, so a permanently-watched state cannot accumulate. (Optional; a
   bounded set is fine, but document the intent.)

**Verify.** `tests/bridge/bridge_fixtures.gd` (unchanged) plus a runtime check:
run the demo with `editor_preview` on and confirm the terrain chunks still
resolve a bridge shader (they previously would not, because the editor path
binds with meshes present).

### B2. `generate_bridges.gd` destroys the production manifest

`tests/bridge/generate_bridges.gd`:

- `:30` builds a **new** `PixelizerBridgeManifest` and `:57` saves it over
  `res://pixelizer_bridges/pixelizer_bridge_manifest.tres` (`:24` passes
  `PixelizerBridgeManifest.FILE_NAME`).
- `:41` writes outputs to `out_dir + "/" + source.get_file()` — flat paths —
  while the editor dock writes res-relative paths
  (`editor/pixelizer_bridge_dock.gd`, `_output_path_for`).

The committed manifest has **7** approved entries with res-relative
`output_path`s (`res://pixelizer_bridges/addons/MarchingSquaresTerrain/resources/shaders/…`).
Running the documented build step 4 therefore drops 4 approved entries, re-points
the 3 survivors at new flat duplicates nothing reads, and orphans the 7 real
generated files. `tests/bridge/generate_bridges.gd` is cited by
`AGENTS.md` step 4 and (previously) by the README as the way to rebuild the demo's
bridge output.

**Change.** Make the generator additive and path-faithful:

1. Load the existing manifest if the file exists
   (`ResourceLoader.load()`), else create one — never start from a blank.
2. Compute `output_path` exactly as the dock does: reuse the dock's
   `_output_path_for()` by moving that helper into a shared static
   (`core/pixelizer_shader_bridge.gd` is the natural home) so the two cannot
   drift.
3. Keep the `get_or_create_entry(source)` call so existing approvals and
   exclusions survive; only refresh `source_hash` / `generated_hash` /
   `rules_version` / output paths.
4. Print a summary that names any entry whose approval state changed.

**Verify.** Copy `pixelizer_bridges/pixelizer_bridge_manifest.tres` aside, run
the generator headless, then diff: the entry count must stay 7, every
`output_path` must be unchanged, and no new flat `.gdshader` files may appear at
the root of `pixelizer_bridges/`. Restore the copy afterwards if you touched the
tree.

> **Guardrail until B2 lands:** do not run `generate_bridges.gd` against this
> repo. `AGENTS.md` step 4 carries the same warning.

### B3. `refresh_bridge()` runs before the unsupported-material bail-out, and the swap cannot be undone

`core/pixelizer_geometry_state.gd`, `bind()` (~`:101-133`):

```gdscript
refresh_bridge(manager_ref)                       # swaps approved shaders IN PLACE
for slot in slots:
    if _is_unsupported_custom_material(slot.source):
        return false                              # bails with the swap already applied
```

`unbind()` early-returns while `not _applied` (~`:138-140`), so a node that
swapped one slot and then bailed on another keeps the generated shader for the
rest of the session — with the metadata layer never set and instance uniforms
never pushed. `_watch_ids` then retries the bind forever because
`bridge_swapped()` stays true.

**Change.** Either (a) check every slot for unsupported materials *before*
calling `refresh_bridge()` and bail early, or (b) keep the order and restore
`_bridged_shaders` on the bail-out path. (a) is simpler; note that
`refresh_bridge` is what *converts* a bridged source into a supported one, so the
pre-check must treat "has an approved bridge entry" as supported — cache the
registry verdict for the node's shaders before the loop.

---

## Section C — Core pipeline correctness

### C1. The outline palette is composited in linear space without an sRGB conversion *(confirmed visually)*

`core/pixelizer_outline_palette.gd:61-68` bakes an `Image.FORMAT_RGBA8` texture
from authored `Color` values with no colour-space conversion;
`shaders/compute/apply_pixelization.glsl:196` composites it with
`color = mix(color, palette_row.rgb, palette_row.a)` into the **linear** HDR
scene colour (`color_rid = buffers.get_color_layer(0)`), sampled through a plain
RD sampler with no sRGB format (`compositor/pixelizer_effect_base.gd:36-41`). An
authored near-black `Color(0.04, 0.05, 0.09)` therefore renders at roughly
sRGB(0.04) ≈ 0.22 — about 5× lighter. Observed in a capture: the demo's outline
reads as a medium navy, not near-black. The addon already treats this as
mandatory elsewhere: `anchor_macros.gdshaderinc:101` documents `source_color` on
the palette LUT as required or "the palette renders washed out / hue-shifted".

**Change (pick one, then document it):**

- Bake linear values: `image.set_pixel(i, row, Color(r, g, b, a).srgb_to_linear())`
  — but note `set_pixel` on an RGBA8 image clamps to 8 bits, which quantises dark
  values hard. Prefer:
- Sample with an sRGB format: create the RD texture view as `_SRGB`
  (`RenderingServer.texture_get_rd_texture(rid, false)` currently yields
  `RGBA8_UNORM`), so the GPU linearises on read; or
- Convert in the shader: `palette_row.rgb = pow(palette_row.rgb, vec3(2.2))`
  (cheap, explicit, no format juggling).

Whichever you choose, apply the same treatment to the debug focus tint
(`apply_pixelization.glsl:202-208`, `vec3(1,0,0)`) for consistency.

**Verify.** Set `outline_color` to a known value, capture the demo (Appendix 1),
and read the outline pixel back: it must match the authored sRGB value within a
couple of 8-bit steps, not ~5× lighter.

### C2. The baked LUT dither matrix is one step off the shader's

`core/dither_matrix.gd:37-43` writes `float(bayer_index(x, y)) / 17.0`
(thresholds 0/17…15/17), while the shader's alpha dither uses
`(index + 1.0) / 17.0` (`anchor_macros.gdshaderinc:171`, thresholds
1/17…16/17 — which matches ProPixelizer's `TRANSPARENCY_DITHER` cell-for-cell).
`pick_first()` (`:52-55`) then tests `values[index] > fraction`, so the LUT bands
are biased one level and cell 0 (threshold 0) can never pick the darker colour.

**Change.** Use `(float(bayer_index(x, y)) + 1.0) / 17.0` in
`_default_values()`, and update the doc comment ("values n/17" →
"(n+1)/17"). Check `PaletteLUT` and any baked `.png` for an assumption about the
old range, and regenerate `palette_lut_debug.png` if it is checked in.

**Verify.** A `DitherMatrix` unit check: `values` sorted must equal
`[1,2,…,16]/17`, and `pick_first(0.0, i)` must be true for every cell except the
one holding 16/17.

### C3. LOW_RES: the sub-texel remainder has an inverted X sign, and the texel comes from the wrong camera

`core/pixelizer_camera_binding.gd`, `snap()` (~`:163-191`):

```gdscript
cam.h_offset = residual.x * texel
cam.v_offset = residual.y * texel
subtexel_remainder = -residual
```

With `residual = anchor_texel - snapped`, moving the camera by `+residual` puts
the anchor on an integer lattice index. The rendered content therefore moves by
`-residual` in texture space, so the display must apply
`scroll_shift = Vector2(residual.x, -residual.y)` (x in columns; y negated
because screen rows increase downward while view-space y increases upward).
`-residual` gets y right by accident and **doubles** the x error. The consumer is
`core/pixelizer_lowres_view.gd:130` → `shaders/pixelizer_upscale.gdshader:18`
(`src = UV * source_size - scroll_shift`, positive shift moves content by
+shift).

Separately, `get_texel_world_size()` measures `active_camera` — in LOW_RES that
is the **user** camera, still in the window viewport, while the rendering camera
is the manager-owned `MirrorCamera` inside the display `SubViewport`
(`pixelizer_lowres_view.gd:58-68`, `:109-111`) whose size is
`render_resolution * (1/texel_density) * view_zoom`. So the snap period and the
units handed to the upscaler are both off by
`window_height / render_resolution.y` under the shipped defaults.

**Change.**

1. `subtexel_remainder = Vector2(residual.x, -residual.y)`.
2. In LOW_RES, derive the texel from the mirror camera and the display
   viewport's size, not from the user camera. Give `PixelizerLowResView` a
   `get_texel_world_size()` and have `snap()` prefer it when low-res is active.
3. The reference implementations derive the texel from the projection matrix
   (`2.0 / PROJECTION_MATRIX[0][0]` divided by the internal resolution) which is
   aspect- and constraint-proof. Consider adopting that for both paths.

**Verify.** In LOW_RES with `snap_camera = true`, pan the camera horizontally
one texel at a time: the image must stay still (no 2-texel jump at each half-texel
wrap) and vertical motion must remain correct. Then a slow diagonal pan: no
jitter on either axis.

### C4. Manager/applier/profile property names collide in the UI

`pixel_size`, `dither_enabled`, `outline_enabled`, `mover_snap` and
`outline_color` exist on `PixelizerManager3D`, `PixelizerApplier3D` **and**
`PixelizerObjectProfile` with identical labels and different scopes. They are not
redundant (the shader ANDs the manager's global dither gate with the per-object
`use_dither`), but nothing says which is which.

**Change.** Rename the manager's copies to make their role explicit —
`default_pixel_size`, `default_dither_enabled`, `default_outline_enabled`,
`default_mover_snap`, `default_outline_color` — with matching `@export_group`
names ("Defaults — inherited by appliers"). Update
`INHERITED_SETTINGS` in `nodes/pixelizer_applier_3d.gd:110-118`, the
`_resolve_setting()` manager lookups, `get_debug_status_line()`, `demo/demo.tscn`
(`pixel_size = 5` on the manager), `AGENTS.md` (both) and the addon `README.md`.
Keep the *applier* names unchanged — they are the ones users touch.

> Renaming an exported property changes the `.tscn`/`.tres` layout. Update
> `demo/demo.tscn` in the same commit, or the demo silently loses the setting.

### C5. The pipeline globals are registered at runtime only, so shaders fail to compile without a manager *(reproduced)*

`shaders/anchor_macros.gdshaderinc:65` declares
`global uniform uint pixelizer_meta_bit;` (and its siblings), and
`core/pixelizer_globals.gd:42-52` registers them with
`RenderingServer.global_shader_parameter_add()` at runtime — `ensure()` returns
early when there is no RenderingDevice. There is **no `[shader_globals]` section
in `project.godot`**, so any pass that compiles the shader before a manager's
`_enter_tree` runs fails:

```
SHADER ERROR: Global uniform 'pixelizer_meta_bit' does not exist. Create it in Project Settings.
   at: (null) (res://addons/pixelizer_3d/shaders/anchor_macros.gdshaderinc:64)
ERROR: Shader compilation failed.
```

Reproduce with the documented check:
`Godot-stable_mono_win64_console.exe --headless --editor --quit --path .`

The cost is not cosmetic: the project's own "required after every .glsl edit"
step prints a shader error on every run, so a real shader error can hide in the
noise.

**Change.** Declare the six globals in `project.godot` under `[shader_globals]`:
`pixelizer_meta_bit` uint, `pixelizer_lowres_mode` bool,
`pixelizer_palette_lut` sampler2D, `pixelizer_palette_grading_enabled` bool,
`pixelizer_palette_dither_enabled` bool, `pixelizer_screen_size` vec2 — one
`{"type": …, "value": …}` entry each (let the editor write the exact syntax via
Project Settings → Shader Globals rather than hand-writing it). This is already a
supported path — `ensure()` deliberately checks
`ProjectSettings.has_setting("shader_globals/<name>")` before adding, so the
runtime registration becomes a no-op. Keep `ensure()` for projects that copy
only the addon and never touch `project.godot`.

**Verify.** The headless import check must print no SHADER ERROR, and the demo
must render identically (the globals end up with the same values, just declared
earlier).

---

## Section D — Outline quality and capability

### D1. There is no normal/crease edge source anywhere *(verified)*

`grep hint_normal_roughness addons/pixelizer_3d/` returns nothing, and the apply
pass binds only colour / depth-copy / metadata / outline
(`compositor/pixelizer_apply_effect.gd:98-103`). The outline is therefore
silhouette + tag-change + a **symmetric first** depth difference
(`shaders/compute/apply_pixelization.glsl:181-188`). Consequences:

- Creases at equal depth (a box corner, a roof ridge, a wall/floor junction) can
  never be outlined.
- Any slope exceeds a first-difference threshold, so grazing surfaces flood —
  which is why the demo must set `outline_enabled = 0` on the terrain
  (`addons/pixelizer_3d/AGENTS.md` documents the symptom as a limitation).

Every reference that solves this uses a **second** difference and/or normals.
Stable3D: `stableHorizontalCurve = left + right - 2*center`,
`farCurve = max(-h, -v)`, `step(SilhouetteThreshold, farCurve)` — zero on a plane
at any angle, and one-sided (only where the centre is nearer). The two Godot
references sample `hint_normal_roughness_texture` with a 3x3 kernel.

**Change, in two steps:**

1. **Depth: switch the depth test to a second difference.** Compare
   `2*depth(centre) - depth(a) - depth(b)` per axis against the threshold rather
   than `abs(neighbour - centre)`, and require the centre to be the *nearer* side
   (`max(-h, -v)`, i.e. convex only). This alone removes the terrain flooding and
   halves the mark on both sides of a step. Keep the tag test as-is.
2. **Normals: add a crease term.** `RenderSceneBuffersRD` exposes the engine's
   normal-roughness target in 4.7; sample it at the four neighbours one macro
   step away, and mark an inner edge when `1 - dot(n, n_neighbour)` exceeds a
   threshold — gated on the same depth test to avoid firing on silhouettes.
   Expose it as `PixelizerManager3D.outline_normal_threshold` (default off or a
   sane 0.2–0.4) and add the uniform to the apply push block (see the
   push-constant invariant below).

**Push-constant warning.** The apply block is exactly 12 floats / 48 bytes and
must match the std430 `Params` struct in `apply_pixelization.glsl` field for
field, in order. Adding a field means editing both, and the existing `1.0` and
`0.0` padding slots at the end are the natural place. Re-run the import check
afterwards (Appendix 2).

### D2. Outline compositing and row routing differ from every reference

- The port **replaces** colour (`mix(scene, palette_rgb, palette_a)` with rows
  defaulting to opacity 1.0); all the references multiply the sampled colour or
  cap the darkening (55 % in `3DPixelArt_Tutorial`, `col.rgb * outline_color.rgb`
  in `godot-3d-pixel-art`).
- Depth steps are routed to the **inner** row (`row = silhouette_edge ? 0.25 :
  0.75`), whereas Stable3D routes depth discontinuities to the exterior row and
  *suppresses* the inner line on a large step
  (`stableInsideLine = (1 - step(InteriorDepthThreshold, depthDiscontinuity)) * …`).

**Change.** Add an optional multiply mode to `PixelizerOutlinePalette` (a
`Color(0.5, 0.5, 0.5)`-centred modulation, as ProPixelizer's
`_EdgeHighlightColor` documents: <0.5 darkens, 0.5 is invisible) and route a
depth-only inner edge through the silhouette row when it exceeds a larger
"interior depth" threshold. Keep the current opacity behaviour as the default so
existing scenes do not change appearance.

### D3. Outlines and the focus tint are drawn without a visibility gate

The outline block is computed from `metadata_texture` alone
(`apply_pixelization.glsl:164-199`) and ignores the pass's own `revert` flag
(`:153-159`), and the metadata camera renders with
`cull_mask = metadata_bit` — no occluders
(`core/pixelizer_camera_binding.gd:250`). Failure: a pixelized object behind a
non-pixelized wall keeps its colour reverted but still paints its outline (and,
with `debug_focus_mask`, a red tint) onto the wall.

**Change.** Skip the outline and the focus tint for fragments where `revert` is
true, so a block that is not the visible surface cannot ink its neighbours.
Check the interaction with depth write-back (`gl_FragDepth` at `:213`) before
changing anything else.

### D4. Runtime robustness gaps in the anchor path

- `MAX_ANCHOR_SIZE = 5` caps the search (`apply_pixelization.glsl:67`) but
  nothing clamps `anchor_size` at runtime: `@export_range(-10, 5)` is an
  inspector hint and `core/pixelizer_geometry_state.gd:166` pushes the value
  straight to the instance uniform. A script setting `pixel_size = 8` renders
  the object as sparse dots. Clamp in `PixelizerGeometryState.push_instance_params()`
  and warn once.
- `ANCHOR_META_LIGHT` writes tag 255 for a focused object
  (`anchor_macros.gdshaderinc:273`) but `core/pixelizer_outline_registry.gd`
  refuses id 255 (`:28`, `:42`), so a focused object silently falls back to row
  255's default colour instead of its own. Decide the intended interaction and
  make the two agree.
- `anchor_tag > 254` is not wrapped: `anchor_tag/256` yields `G > 1` and the
  palette lookup lands outside `[0, 1]`. Clamp with the same one-shot warning.
- `shaders/grass_billboard.gdshader:85-86` computes the billboard basis with
  `normalize(vec3(INV_VIEW_MATRIX[k].x, 0, INV_VIEW_MATRIX[k].z))`, which is
  `normalize(0,0,0)` — NaN positions for every card — when the camera looks
  straight down or up. Derive `back` with a cross product against world up, as
  the reference (`3d-pixel-art-base-project`, `toon_billboard_matrix`) does.
  Note the demo's own camera clamps to `pitch_max_deg = 89.9`, one tenth of a
  degree from the singularity.
- `alpha_scissor` defaults to `0.0` (`anchor_macros.gdshaderinc:87`) and nothing
  sets it for a custom material, so `ANCHOR_CLIP(tex.a * tint.a)` in
  `tree_leaves.gdshader` and `grass_billboard.gdshader` never discards — the
  cards would render as full opaque quads. Neither shader is referenced by any
  script, scene or resource today. Give the two foliage shaders an explicit
  `alpha_scissor` default (the reference uses 0.5) or set it from the material
  when the shader is used, and either wire them into the demo or say in
  `AGENTS.md` that they are unexercised examples.

---

## Section E — Tests and tooling

### E1. Bridge fixture coverage gaps

`tests/bridge/bridge_fixtures.gd` claims "stale detection" coverage (`:9`) but no
check exercises the stale branch; `tests/bridge/fixtures/stale_src.gdshader`
exists and is unreferenced. The "source addon is never written" assertion hashes
only `resources/shaders` (`:236`), which is narrower than the stated invariant —
the vendored `resources/plugin_materials/round_brush_radius_material.tres`
differs from upstream and the test cannot see it.

**Change.** Add a stale-entry fixture (mutate a copied source, re-scan, assert the
entry reports stale and is not applied) and widen the never-written hash to the
whole vendored addon tree, excluding `.godot/`, `.uid` and `*.import`.

Also: the fixture run **wipes `tests/bridge/generated/` and does not recreate the
`.uid` files** in it, so running the documented command deletes two tracked files
(`mst_terrain.gdshader.uid`, `mst_terrain_check.gdshader.uid`) from the working
tree. Either regenerate them (Godot writes `.uid` on import) or stop tracking
that directory and let the fixtures own it.

### E2. Rebuild the capture matrix for the current demo

The deleted matrix drove `demo/showcase/`, a station-based scene that no longer
exists, and the demo never implemented the flags it passed. Rebuild it against
`demo/demo.tscn`:

1. Give the demo a small, documented capture CLI in `demo/player.gd` or a
   dedicated `demo/capture.gd` autoload-style helper: `--capture=<res://path>`,
   `--resolution=WxH`, `--fixed-view=<name>`, `--plain` (pipeline off),
   `--debug-view=N`, `--no-overlay`. Print a diagnostics JSON line
   (`mode`, `plain`, window size, `pixel_size`, `mover_count`) so a silently
   ignored flag fails the run.
2. Restore `tests/run_captures.py` with a matrix that covers: anchor default, a
   debug view, low-res mode, `plain`, and a `pixel_size` variant. Reference PNGs
   live in `tests/reference/` (recreate the directory) and captures in
   `tests/captures/`.
3. Keep the cross-checks (each mode must differ from the anchor capture) and the
   `--update-references` path.

Use `tests/compare_captures.py` as-is for the diff step.

---

## Section F — Architecture

Context for all of Section F: the manager currently does four jobs — per-viewport
render plumbing, per-scene *look* settings, registries, and process-wide globals
(`core/pixelizer_globals.gd`: `pixelizer_meta_bit`, `pixelizer_palette_lut`,
`pixelizer_screen_size`, `pixelizer_lowres_mode` are **global shader uniforms**).
Two `PixelizerManager3D`s in one process silently overwrite each other's globals
— there is no guard and no warning. That is why "one manager per camera" cannot
work today, and why the node's role is hard to reason about.

**Do not make the manager an autoload.** It creates a `SubViewport` child and
reads `get_viewport().get_camera_3d()`; it must live in the viewport it
pixelizes. An autoload lives in the root `Window` and would target the wrong
viewport for any scene hosted in a `SubViewport`. The singleton convenience
already exists in `PixelizerGlobals`, and `resolve_manager()` already does a
group+viewport lookup.

### F1. Extract the per-scene look into a settings resource

Move the properties that describe *what the pixel art looks like* off the
manager into a `PixelizerSettings` `Resource` (new file, `core/`):

`render_resolution`, `texel_density`, `view_zoom`, `manage_camera_size`,
`pixel_size` (default), `depth_occlusion`, `mover_snap` (default),
`global_palette_lut`, `dither_enabled`, `snap_camera`, `snap_origin`,
`lock_camera`, `outline_enabled`, `outline_color`, `outline_threshold`,
`outline_palette`, `auto_focus`, `auto_focus_target`, `debug_focus_mask`,
`debug_view`, `sun`.

- The manager keeps a `settings: PixelizerSettings` export (auto-created when
  unset, so existing scenes keep working) and forwards its accessors to it.
- Effects read the same resource (`PixelizerManager3D.get_settings()`).
- Everything that reads `manager.<field>` internally becomes
  `settings.<field>`.

**Payoff:** "camera A has small fast clouds, camera B has large slow ones"
becomes data — a camera→settings mapping the manager consults when the active
camera changes — instead of code. It also gives the tuner one Look panel instead
of a manager panel that is half pipeline, half look (see A3/C4).

### F2. Introduce a `PixelizerEffect3D` base class

Six effect nodes each re-implement the same ~40 lines: a `manager` export, a
deferred `_register()` (because an owning applier may create the manager in its
own `_ready`), an `_exit_tree` unregister, a `_manager_valid()` guard, an
editor-preview check and `_get_configuration_warnings()`. The copies have already
diverged: `PixelizerSkyClouds3D._process` checks the editor hint, `PixelizerWater3D`
does not; `PixelizerFireflies3D` resolves the manager without caching it;
`PixelizerGodRays3D` resolves inside `_register()`.

**Change.** Add `effects/pixelizer_effect_3d.gd` (`class_name PixelizerEffect3D`,
`extends Node`, or `Node3D` for the geometry-shaped ones via a shared mixin
function set) owning: resolution + caching of `manager`, the deferred
register/unregister contract (`_on_registered()` / `_on_unregistered()`
overridables), the editor-preview gate and one `_get_configuration_warnings()`
that reports an unresolved manager. Port all six effects onto it.

### F3. Cloud providers must not silently replace each other

`core/pixelizer_cloud_field.gd:24-30`: `register_provider()` replaces
`_provider` unconditionally, so two cloud nodes in a scene means whichever
`_ready` ran last wins, with no warning — and there is exactly one parameter
dictionary for the whole process, so the same field drives every material.

**Change.**

1. Keep one active provider, but warn loudly (once) when a second registers, and
   name both nodes.
2. Support a per-camera provider: give the provider an optional
   `cloud_camera_scope: Camera3D` (or a `Camera3D`-keyed dictionary on the
   manager) and have the manager switch the active provider when the active
   camera changes. That is the "camera 1 / camera 2" requirement, and it needs
   `F1` to be in place for the settings half of it.
3. Document the hard limit: material-level effects (cloud shadows) are
   per-manager, so two cameras visible **at once** cannot have different cloud
   fields without per-material parameter sets. Do not promise split-screen.

### F4. Effects that are geometry must not be bindable by an applier

`PixelizerSkyClouds3D` and `PixelizerWater3D` are `MeshInstance3D`s running
non-pixelizer shaders. Inside an applier subtree they are scanned; `bind()`
bails on the unsupported material, but the applier keeps re-scanning them and the
user gets a warning they cannot act on. `PixelizerDiagnosticsOverlay`'s selection
marker already does the right thing (`marker.add_to_group("pixelizer_ignore")`).
Do the same in the geometry-shaped effects' `_ready()` — except
`PixelizerPointLightVolume3D`, which deliberately opts in via
`register_pixelized_material()`.

### F5. Guard against two managers in one process

Add a warning (once per process, or per viewport) when a second
`PixelizerManager3D` enters the tree, naming the globals they will fight over,
and state the limit in both `AGENTS.md`s. If per-viewport managers are wanted
later, the four global uniforms must move to per-material parameters first —
that is a separate project, not this plan.

---

## Section G — Demo authoring and docs

### G1. The demo's water tile floats

`demo/demo.tscn` places `PixelizerWater3D` at `y = 0.706` with the default
`size = 4.0`. The terrain under the origin is flat at `y = 0` (chunk AABBs:
`Chunk (0, 0)2` and `Chunk (0, -1)2` both have height ≈ 0.00001; the raised
chunks are `(-1, 0)` at 14.6 and `(-1, -1)` at 6.0). So the water plane hovers
~0.7 m above flat ground, and at `coast = 1.0` it renders as dark green that
reads as terrain rather than water. Decide the intent (a pond in a depression, or
a shoreline grid) and place/size it accordingly; `PixelizerWater3D` is designed
for a contiguous tile grid with `wave_phase = 0` on every tile.

### G2. The demo camera versus the docs

`demo/demo.tscn`'s `Player` authors `orbit_distance = 24`,
`pitch_deg = 89.9`, `pitch_max_deg = 89.9`, `pivot_height = 0.6` — a
near-vertical overhead rig. `AGENTS.md` used to claim 2–14 m and pivot 1.5 m;
the doc now records the real values. Confirm the overhead default is intentional
(it looks like terrain-debugging residue) before changing it; if you change it,
update `AGENTS.md` and re-shoot `docs/images/hero.png`.

### G3. Docs

- `README.md`, `AGENTS.md` and `addons/pixelizer_3d/AGENTS.md` were resynced with
  the code on 2026-10-16 (manager explicitness, deleted classes, test layout,
  camera values, palette-grading scope, tuner scope table). Keep them in step as
  you land the items above — in particular F1/F2/F3 change the composition model
  text, and C4 renames manager properties.
- `docs/images/` holds `hero.png`, `demo-terrain.png` and `demo-diagnostics.png`,
  captured from the current demo. Re-capture after any visual change
  (Appendix 1).

---

## Suggested execution order

1. **A1, A2, A3, A4** — small, self-contained, and they unblock using the demo to
   verify everything else.
2. **B2**, then **B1**, then **B3** — B2 first so the bridge output is
   trustworthy before you change how it is applied.
3. **C1, C2, C3** — one-line-to-small fixes with visible payoff.
4. **D4** (robustness), then **D1** (the big visual win), then **D2, D3**.
5. **F4, F5** (cheap guards), then **F2** (base class), then **F1** (settings
   resource), then **F3** (per-camera providers — depends on F1).
6. **E1, E2** — the harness is worth more once the behaviour has settled.
7. **C4, G1, G2, G3** — renames and authoring last, since they touch scenes and
   docs.

Land each section with its verification step; do not batch sections that share a
shader or scene file without re-running the checks.

---

## Appendix 1 — Reproducing the visual checks

Headless has no renderer (`RenderingServer.get_rendering_device()` is null, the
manager warns once and disables pixelization), so anything visual needs a real
window. The recipe that worked:

```gdscript
# save as a scratch .gd, run with --script
extends SceneTree

func _initialize() -> void:
    root.size = Vector2i(1152, 648)
    root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())
# _process: wait ~120 frames for terrain + physics to settle, then
#   image = root.get_texture().get_image(); image.save_png(<absolute path>)
```

```bash
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path . \
  --fixed-fps 60 --script "C:/path/to/probe.gd" -- --out-dir="C:/path/to/shots"
```

Notes that cost time to rediscover:

- `--script` takes an absolute path outside the project; no need to copy the
  probe into `res://`.
- The player **lands** on the terrain (`on_floor = true` at `y ≈ 1.0`), so the
  demo settles by itself; the terrain needs ~1 s to build.
- To frame a shot, un-current the player's `Camera3D` and add your own
  `Camera3D` with `current = true`; the manager auto-follows
  `get_viewport().get_camera_3d()`.
- `PixelizerManager3D.resolve_manager_explicit()` called from the `SceneTree`
  root returns null **by design** (the `Window` is not in the scene). To get the
  manager from a probe, find the node by name inside the instantiated scene.
- `PixelizerDiagnosticsOverlay.tuner_enabled = false` gives a status-HUD-only
  capture; toggling `overlay.toggle()` makes the docks visible for a shot.

## Appendix 2 — Verification loops

```bash
# Import + parse check. REQUIRED after every .glsl / .gdshader edit — SPIR-V is
# baked at import, and a stale cache silently runs the old shader.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --editor --quit --path .

# Headless bridge fixtures (must stay green; they also assert the vendored
# addon is never written).
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/bridge/bridge_fixtures.gd

# Windowed compile smoke test for the generated bridge shaders.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path . res://tests/bridge/compile_test.tscn

# Run the demo.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path .
```

Invariants that must survive every change in this plan (full list in
`AGENTS.md` → "Load-bearing invariants" and "Additional invariants"):

- Never read or write `ALPHA` in a pixelizer material; dither and scissor use
  `discard` (`ANCHOR_CLIP`).
- The apply push constant is exactly 12 floats / 48 bytes and mirrors the GLSL
  std430 `Params` struct field for field.
- A texture cannot be a framebuffer attachment and a uniform in the same pass —
  that is what the `snapshot` pass exists for.
- Compute cannot write depth; depth write-back is raster-only.
- `draw_list_bind_vertex_buffers_format` (4.7) and a pipeline `vertex_format`
  identical to the one bound at draw time.
- MSAA stays off; the depth write-back path assumes it.
- A `CompositorEffect` subclass must never call `super._notification()` — Godot
  runs `_notification` on every script in the chain.
