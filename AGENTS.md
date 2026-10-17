# AGENTS.md — godot-pixelizer-3d

Pixelizer3D: consolidated Godot 4.7 (Forward+) 3D pixel-art addon
(`addons/pixelizer_3d/`).

## Build / test

Godot binary: `C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe`
(4.7.1 mono, use the `_console` variant).

```bash
# 1. Import + parse check (REQUIRED after every .glsl / .gdshader edit — SPIR-V
#    is baked at import; a stale cache silently runs the old shader or errors at
#    load). The pipeline globals are declared in project.godot, so this prints no
#    SHADER ERROR on a clean tree — any error here is real.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --editor --quit --path .

# 2. Run the demo (real GPU, interactive).
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path .

# 3. Shader-bridge fixtures (headless, no GPU): scan/generate, include
#    flattening, determinism, manifest round-trip, registry gating, stale-entry
#    reporting, cloud-owner vs bundled-cloud injection, and "the vendored addon
#    tree is never written". Exit 0 = all pass. Fixtures wipe/rebuild
#    tests/bridge/generated/ (untracked; the fixtures own it).
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/bridge/bridge_fixtures.gd

# 4. (Re)generate the MST bridge shaders for the TESTS, and refresh the three
#    MST entries of the production manifest. Additive and path-faithful: other
#    manifest entries, approvals and exclusions survive, and output paths match
#    the bridge dock's. Run after ANY MST shader change — and before step 5,
#    which has nothing to load without it; a new INJECTION_RULES_VERSION makes
#    old entries stale until this runs.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/bridge/generate_bridges.gd

# 5. Windowed compile smoke test for the generated bridge shaders (needs step 4
#    in the same checkout). Prints no SHADER ERROR on success.
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path . res://tests/bridge/compile_test.tscn
```

The demo and the addon implement no custom CLI flags beyond the capture CLI
(`demo/capture.gd`, driven by `tests/run_captures.py`; see "Captures" below).
`tests/` holds the bridge
fixtures (`tests/bridge/`), the dither/palette unit tools
(`tests/dither_matrix_check.gd`, `tests/bake_palette_lut_debug.gd`), headless
unit checks (`tests/mover_snap_check.gd`, `tests/unsupported_material_check.gd`,
`tests/bridge_watchdog_check.gd`; `--headless --path . --fixed-fps 60 --script
res://tests/<name>.gd`, exit 0 = pass), the in-game probes (`tests/verify/`,
windowed; see `VERIFICATION.md` Part 3), the capture matrix
(`tests/run_captures.py` + `tests/reference/`) and a standalone PNG diff tool
(`tests/compare_captures.py`); `tests/captures/` is the designated output
directory for captures.

## Captures

`tests/run_captures.py` drives `demo/demo.tscn` through the small capture CLI in
`demo/capture.gd` (`--capture=<path>`, `--resolution=WxH`, `--fixed-view=<name>`,
`--mode=anchor|lowres`, `--plain`, `--debug-view=N`, `--pixel-size=N`,
`--no-overlay`, `--overlay`, `--settle=<frames>`, `--outline-terrain`,
`--ortho`, `--mover-snap`, `--palette-lut`; flags go after a bare `--`). The
matrix has eight entries: `anchor`, `debug_anchor_map`, `lowres`, `plain`,
`pixel_size_3`, `outline_dense` (every applier outlined, terrain included),
`ortho_mover` (orthographic camera + mover snap — the only entry where the
vertex-stage snap runs) and `palette_lut` (a runtime-baked LUT through the
global uniform and `ANCHOR_GRADE`).
Each run prints one `PIXELIZER_CAPTURE {json}` diagnostics line, and the runner
fails the entry if a requested flag is not reflected there. With `--fixed-fps 60`
and the helper's pinned god-ray phase the demo is deterministic frame-by-frame,
so the references in `tests/reference/` compare at zero tolerance on one machine.
`--plain` turns the pipeline off from both ends (manager *and* appliers), so it
is a real baseline rather than a half-disabled frame. `docs/images/*.png` are
shot through the same CLI (`--fixed-view=wide|characters`, `--overlay` for the
diagnostics shot).

## Demo (`demo/demo.tscn`, main scene)

- `demo/demo.tscn` + `demo/player.gd`. `demo/demo.gd.uid` has no matching script.
- Scene tree: an explicit `PixelizerManager3D` (auto-follows the viewport's
  current camera; no camera export/path) — the demo places it because wiring is
  explicit. Top-level `PixelizerApplier3D` contains: 6 character FBX instances
  under one `Node3D` row (`Barbarian`, `Knight`, `Mage`, `Ranger`, `Rogue`,
  `Rogue_Hooded`), a playable `CharacterBody3D` (Knight visual + arcball
  `Camera3D` child), a nested `PixelizerApplier3D` around
  `MarchingSquaresTerrain` (`data_directory =
  res://demo/demo_TerrainData/MarchingSquaresTerrain_126b8b50`) + `GrassPlanter`
  (MultiMeshInstance3D), and `PixelizerPointLightVolume3D`. The effect nodes
  (`PixelizerSkyClouds3D`, `PixelizerGodRays3D`, `PixelizerWater3D`,
  `PixelizerFireflies3D`) live under a `PixelizerEffects` node at the scene root,
  outside every applier — an applier binds any supported geometry in its subtree,
  so effects that are `MeshInstance3D`s must stay outside one (or be added to the
  `pixelizer_ignore` group).
- Assets: `demo/assets/characters/` (FBX + `*_texture.png`, KayKit Adventurers
  pack per `CREDITS.md`); MST save data in `demo/demo_TerrainData/`.
- Bridge wiring: the manager trusts the production manifest
  (`bridge_manifests = [res://pixelizer_bridges/pixelizer_bridge_manifest.tres]`)
  with `auto_bridge_custom_shaders = true`, so the pristine MST shaders are
  swapped for generated bridge shaders at runtime. `res://pixelizer_bridges/`
  is generated output — rebuild it from the bridge dock, **not**
  `generate_bridges.gd` (see step 4 above).
- No applier pins `pixel_size` (the top-level pin, equal to the settings
  default, was removed 2026-10-16), so every subtree follows
  `settings.default_pixel_size` and the tuner's Look → default pixel size row
  moves the whole scene.
- Nested terrain applier: inherits the settings default `pixel_size = 5`,
  `anchor_mode = 1` (UNIFIED), `outline_enabled = 0`. UNIFIED is load-bearing:
  the chunk meshes + grass share one world-origin macro lattice, otherwise the
  outline pass samples phase-shifted neighbour anchor cells across chunk borders
  and draws false inner-edge outlines along them. `outline_enabled = 0` keeps the
  terrain tag out of the outline pass entirely (an outlined terrain marks every
  convex elevation step, and the old first-difference depth test flooded every
  slope).
- The pristine MST shader uses `cull_disabled`; the pre-bridge fork used
  `cull_back` to hide underside geometry at shallow pitches. The bridge only
  rewrites stage functions, never `render_mode`, so re-adding that fix needs a
  bridge render_mode rule or an addon patch.
- `PixelizerEffects` is **visible** (it is the demo's showcase of the optional
  nodes: water, fireflies, cloud deck, god rays). The `PixelizerWater3D` tile
  sits at `y = 0.15` on the flat ground around the world origin — a 4 m shallow
  (`coast = 1.0`) patch beside the point-light volume, high enough that the
  ±0.12 m vertex waves never dip under the terrain (a single tile,
  `wave_phase = 0`; the node is built for a contiguous grid).
- Controls (`demo/player.gd`): WASD camera-relative move, Space jump, arrow
  keys orbit (yaw/pitch), mouse drag orbits, wheel zooms. The authored camera is
  a near-vertical overhead rig: `orbit_distance = 24`, `pitch_deg = 89.9` with
  `pitch_max_deg = 89.9`, `pivot_height = 0.6`, distance clamped 2–60.
  `Tab` toggles `PixelizerDiagnosticsOverlay` — the status readout plus runtime
  tuner docks: one foldable panel per manager export group, the "Look" sections
  of the `settings` resource, and one panel set per scene-effect node (right),
  and a "Select Object" click-to-pick inspector for
  `PixelizerObjectProfile` / parent-applier parameters (left).
  `PixelizerApplier3D` is never pickable; `unselectable_parent_types` /
  `unselectable_parents` extend the block list, and children of blocked nodes
  stay selectable.
  InputMap actions (`player_forward`/`back`/`left`/
  `right`/`jump`, `camera_orbit_*`) are created at runtime, idempotently;
  `project.godot` also carries its own `[input]` section (w/a/s/d + the orbit
  keys), which the runtime registration leaves alone.
- Capture CLI (see "Captures" below): `--capture=<res://path>`,
  `--resolution=WxH`, `--fixed-view=<name>`, `--plain`, `--debug-view=N`,
  `--no-overlay`, `--outline-terrain`, `--ortho`, `--mover-snap`,
  `--palette-lut`; a diagnostics JSON line goes to stdout so a silently ignored
  flag fails a capture run.
- `capture.png`, `capture_metadata.png`, `palette_lut_debug.png` at the repo
  root are generated artifacts and are **tracked**, not gitignored.
  `palette_lut_debug.png` is rebaked by `tests/bake_palette_lut_debug.gd`; the
  first two are historical outputs of the deleted showcase captures (the current
  matrix writes to `tests/captures/`).

## Composition model (per-scene effects)

`PixelizerApplier3D` is the entry point: it binds its subtree and resolves the
shared `PixelizerManager3D` (it never creates one). The manager is a neutral
pipeline hub: it owns only shared services (metadata
viewport + camera, compositor, material factory, outline palette registry,
camera snap, mover snap, focus, bridge registry, the shared
`sun`) plus the per-scene look in a `PixelizerSettings` resource
(`manager.settings`, auto-created when unset: resolution model, palette,
outline tuning, snap toggles and the applier `default_*` inherit values — swapping
it per camera is the supported way to give two cameras different looks). Every
*visual* effect is an optional, self-contained scene node in `effects/` that owns
its own settings and resolves the manager itself:

| Scene wants | Nodes to place |
|---|---|
| Anchor pixelization only | `PixelizerManager3D` + `PixelizerApplier3D` |
| + cloud shadows (no deck) | + `PixelizerSkyClouds3D` (`deck_enabled = false`) |
| + visible cloud deck | + `PixelizerSkyClouds3D` (shadows off via `cloud_shadow_strength = 0`) |
| + god rays | + `PixelizerGodRays3D` (owns its pass; `enabled` inserts/removes it) |
| + water / fireflies / day-night / … | + the matching `effects/` node |

The manager is **explicit** and must be named exactly `PixelizerManager3D`;
appliers never create one. A top-level applier resolves the sibling named
`PixelizerManager3D`; a nested applier resolves its parent applier's manager. A
missing manager is a `push_error` + configuration warning and no pixelization.
The sun follows the same rule: explicit `sun`, else the first sibling
`DirectionalLight3D` (several siblings warns; none errors).

Omit a node to omit the effect. Generic slots (all duck-typed where possible, so
new effect types need no manager change):

- `register_cloud_provider(provider)` / `unregister_cloud_provider(provider)` —
  any Object with `build_cloud_params(sun) -> Dictionary`. `PixelizerSkyClouds3D`
  is the provider node. With no provider the manager pushes neutral params
  (`clouds_enabled = false`) so consumers never read stale uniforms.
  `get_cloud_params()` exposes the dictionary to non-material consumers (the
  god-ray pass pulls it). Several providers may register; one is active per frame:
  a provider whose optional `cloud_camera_scope` matches the active camera wins,
  else the first unscoped provider. The second registration warns once.
  **Hard limit:** the field is per manager (material uniforms), so two cameras
  visible at once still share one field.
- `add_pre_pixelization_effect(effect)` / `remove_pre_pixelization_effect(effect)`
  — inserts a `CompositorEffect` before the snapshot/apply passes (so its output
  is replicated into macro pixels) and removes it. Additions made before the
  compositor exists are queued. `PixelizerGodRays3D` owns its
  `PixelizerGodRayEffect`, inserts it on `_ready`, and removes it on
  `_exit_tree` / `enabled = false`; no node means no pass and no early-out.
- `register_cloud_material(material)` / `unregister_cloud_material(material)` —
  consumers that only receive cloud uniforms (water, terrain, deck).
- `register_pixelized_material(material)` / `unregister_pixelized_material(material)`
  — custom spatial materials that include `anchor_macros.gdshaderinc`. A first
  registration emits `pixelized_material_registered`; appliers with an unbound
  node re-scan, so a node whose material opts in late (every effect node
  registers deferred, after the applier's first bind) is bound rather than
  skipped.

All effect nodes resolve the manager through the shared static
`PixelizerManager3D.resolve_manager_explicit(node)` (nearest ancestor applier's
manager → manager ancestor → sibling named `PixelizerManager3D` → null) via the
shared host in `effects/pixelizer_effect_3d.gd`
(`PixelizerEffect3D.resolve(self)` caches the result on the effect's `manager`
override, `is_live()` applies the editor gate, `report_missing()` is the one-shot
loud error and `warnings()` is the `_get_configuration_warnings()` content). The
host is a static mixin rather than a base class because the effects split across
`Node3D` and `MeshInstance3D` and scenes already reference those node types.
Because an applier may bind before
a sibling manager's `_ready` has run, consumers that may live inside an applier
subtree still register deferred. The legacy `resolve_manager()` keeps the
viewport-group fallback and is used only by `PixelizerDiagnosticsOverlay`.

**One manager per process.** The pipeline-wide parameters (metadata bit, screen
size, low-res flag, palette LUT/dither) are global shader uniforms; a second live
`PixelizerManager3D` overwrites the first and warns once. Multi-viewport support
requires moving those to per-material parameters first.

## Diagnostics overlay (runtime tuner scope)

`PixelizerDiagnosticsOverlay` is a `CanvasLayer` (`Tab` to toggle) with three
parts: a status line from `PixelizerManager3D.get_debug_status_line()`, a
manager/effect tuner dock (right), and a click-to-pick object inspector (left).
The tuner reflects **every** script export of the manager, of the
`PixelizerSettings` resource (`Look — <group>` sections) and of each
`Pixelizer*` effect node it finds, grouped by `@export_group`, and writes
through the normal property setters (a settings write reaches the manager
through the resource's `changed` signal).

**A tuner row is only useful if the property is read after setup.** Everything
else is live through its property setter; `IGNORE_CLASS_PROPERTIES` in
`nodes/pixelizer_diagnostics_overlay.gd` hides the rows that cannot do anything
at runtime:

| Class | Setup-only (hidden from the tuner) | Why |
|---|---|---|
| `PixelizerSettings` | `texel_density`, `view_zoom` | read only by the resolution model (`get_view_width()` / `apply_managed_size()`), reachable only when `manage_camera_size` is on or in LOW_RES mode; the anchor lattice itself is screen-space. `get_view_width()`, `get_base_view_width()` and `set_view_zoom()` have no callers at all. |
| `PixelizerManager3D` | `auto_bridge_custom_shaders` | read during `bind()` / `refresh_bridge()` only; the toggle is a wiring decision, not a live dial. |
| `PixelizerWater3D` | `size`, `subdivisions` | build the mesh in `_ready`. (`coast` / `wave_phase` have setters and push their instance uniforms live.) |
| `PixelizerSkyClouds3D` | `plane_size` | builds the `PlaneMesh` in `_ready`. (`clouds_enabled` / `deck_enabled` recompute `visible` directly.) |
| `PixelizerDayNight3D` | — | every arc and ramp has a setter that re-applies the rig, so edits land while the clock is stopped. |

`get_debug_status_line()` reports `u/texel=n/a (perspective)` when the active
camera is not orthographic: the macro lattice is screen-space and the snap is
orthographic-only by construction.

The applier and `PixelizerObjectProfile` deliberately share property
names (`pixel_size`, `dither_enabled`, `outline_enabled`, `mover_snap`,
`outline_color`) because the applier/profile values are *inherit defaults*; the
settings resource owns the `default_*` fallbacks, so a label is unambiguous
wherever it appears. The
object panel labels every section’s scope: `This object — <name>`, `Object
profile (this object only)`, `Parent applier — <name> (shared by N meshes)`.

The object picker resolves the physics hit and the mesh ray test independently
and keeps the nearer one (physics wins a tie, since it is exact and resolves
bodies to their mesh); `Create Object Profile` is offered only for supported
geometry. The mesh triangle test uses the rest-pose faces for skinned meshes
(the AABB pre-pass is skeleton-aware, so posed characters are at least
culled/picked with the posed box).

## Architecture (anchor mode — the default)

1. `PixelizerManager3D` creates a metadata `SubViewport` + duplicate `Camera3D`
   on its own cull layer (default layer 20). Pixelized meshes get that layer in
   `PixelizerGeometryState.bind()`; the main camera gets it removed.
2. `pixelizer_object.gdshader` serves both cameras via the
   `anchor_macros.gdshaderinc` branch on `CAMERA_VISIBLE_LAYERS & meta_bit`. On
   the metadata camera `ANCHOR_META_LIGHT` writes the payload `R =
   anchor_size/32, G = anchor_tag/256, B = view depth` (`ANCHOR_SIZE_SCALE`,
   `ANCHOR_TAG_SCALE`); the main-camera branch grades/clips the albedo.
3. Compositor effects on the main camera, in this array order (same-stage
   effects run in array order — this is the ordering contract, see
   `pixelizer_manager_3d.gd:add_pre_pixelization_effect`):
   `[god_rays]?` (compute, additive into the scene colour **before** the
   snapshot; present only while a `PixelizerGodRays3D` node is enabled) →
   `snapshot` (compute, copies scene colour + depth in one dispatch) →
   `apply_pixelization` (RASTER with depth write-back).
4. The apply raster pass runs the inline anchor search over the lower-left
   `pixel_size x pixel_size` quadrant — the exact set of offsets that can hold a
   corner-anchored survivor — replicates anchor colours across macro blocks,
   applies the occlusion guard, draws screen-space outlines, and writes the
   anchor depth into the scene depth attachment (`gl_FragDepth`).

Materials are converted per source material (`PixelizerMaterialFactory` cache)
and assigned via `material_override` or per-surface override materials, so
`MeshInstance3D.mesh` replacement (MST chunk rebuilds) survives automatically.
Per-object parameters ride on instance uniforms.

Third-party spatial shaders under an applier cannot call the macros (their
addon must not be edited, and Godot cannot merge their stage functions with the
header). They opt in through the **shader bridge**: an editor-time text transform
writes a separate generated `.gdshader` + a manifest (anchor hooks plus the
bundled cloud toolkit are injected as needed), and runtime only does a manifest
lookup and an in-place `material.shader` swap. See the "Shader bridge contract"
in Additional invariants and the addon `README.md`.

## Status

- Addon core (`addons/pixelizer_3d/`): applier (entry point, explicit manager
  resolution), manager facade with focused helpers (`core/pixelizer_camera_binding.gd`,
  `core/pixelizer_cloud_field.gd`, `core/pixelizer_outline_registry.gd`,
  `core/pixelizer_focus.gd`, `core/pixelizer_lowres_view.gd`),
  `core/pixelizer_settings.gd` (the per-scene look resource),
  `core/pixelizer_object_profile.gd` (per-object override resource),
  `core/pixelizer_inherit.gd` (inherit sentinel), material factory, outline
  palette, LUT/dither core, the snapshot/apply
  compositor passes plus the god-ray pass owned by `effects/pixelizer_god_rays_3d.gd`,
  `effects/pixelizer_effect_3d.gd` (the shared effect host), and the
  water / sky-clouds / point-light-volume / firefly-swarm / day-night /
  foliage / screen-projection shaders + `effects/` nodes. `editor_preview` on the
  manager runs the pipeline non-destructively in the editor viewport.
- Shader bridge (`core/pixelizer_shader_bridge.gd`,
  `core/pixelizer_bridge_{entry,manifest,registry}.gd`,
  `editor/pixelizer_bridge_{plugin,dock}.gd`): editor-time generator + manifest +
  runtime lookup for third-party shaders (MST), including the bundled cloud
  toolkit + shadow term for sources that do not own one. The **dock** is the
  authority for `res://pixelizer_bridges/` (trusted via
  `PixelizerManager3D.bridge_manifests`); `tests/bridge/generate_bridges.gd` is
  additive and path-faithful (see build step 4).
- Demo: MST + character playground described above.
- `tests/`: `tests/bridge/` holds the headless bridge fixtures and the windowed
  generated-shader compile smoke test, `tests/dither_matrix_check.gd` unit-checks
  the ordered-dither thresholds, `tests/bake_palette_lut_debug.gd` rebakes the
  repo-root LUT artifact, and `tests/compare_captures.py` is a standalone PNG diff
  tool with `tests/captures/` as its output directory (see `tests/README.md`).
- Interactivity: the picker, object panel and tuner-scope fixes landed with this
  plan (A1-A4); the LOW_RES snap sign/texel and the outline colour space and depth
  test are fixed (C1-C3, D1); look lives in `PixelizerSettings` (F1) behind a
  shared effect host (F2), with provider scoping (F3) and one-manager and
  geometry-effect guards (F4/F5). MST interactions remain deliberately out of
  scope.

## Load-bearing invariants

- **Never write/read `ALPHA` in the pixelizer shader** — it moves the material
  to the transparent pipeline. Dither/scissor use `discard` (`ANCHOR_CLIP`).
- **Depth and colour targets share one orientation** in RD: the engine copies
  depth with plain UVs (`copy_effects.cpp`), and a texture-row coordinate
  addresses the same screen pixel in both. `copy_scene.glsl` and the god-ray
  pass therefore sample depth at `uv`; an extra `1.0 - uv.y` mirrors the depth
  relative to the colour pass (the god-ray pass once did this and terminated
  rays on the wrong screen pixel).
- **The camera projection the compositor receives is reverse-Z with a [0, 1]
  depth range**, so `Projection.get_z_near()` / `get_z_far()` (OpenGL
  convention) return nonsense (about -0.05 / 0.05 in the demo). The apply pass
  pushes the matrix terms `projection.z.z` / `projection.w.z` and inverts
  `raw = (P22 * z + P32) / (P23 * z + P33)` directly. Until 2026-10-16 it pushed
  near/far, so `linearize_depth()` returned ~0.05 for everything and the
  `revert` occlusion guard (0.05 tolerance) never fired.
- **A texture cannot be a framebuffer attachment and a uniform in the same
  pass** — that is why the `snapshot` pass exists (it copies scene colour +
  depth in one dispatch; the apply pass attaches the scene colour/depth and
  samples the copies under the `"color_copy"` / `"depth_copy"` keys).
- **Compute cannot write depth.** Depth write-back only works in a raster pass.
- **`draw_list_bind_vertex_buffers_format` (4.7)** — not
  `draw_list_bind_vertex_buffer`. The pipeline's `vertex_format` must be the
  *same* vertex format ID bound at draw time or RD debug validation errors.
- **Push constants** must be a multiple of 4 floats and match the GLSL std430
  struct byte-for-byte (apply pass: 16 floats / 64 bytes).
- **`RenderSceneBuffersRD.create_texture`** with `Vector2i.ZERO` size and
  `layers = 0` gives internal size / view count; textures are resize-safe.
- **Metadata viewport** needs `use_hdr_2d = true` (raw float payload),
  linear tonemap env, no glow/SSAO/fog, `UPDATE_ALWAYS` (see
  `_create_metadata_viewport`).
- The manager syncs the metadata camera in `_process` at priority 301
  (`sync_process_priority`).
- **Camera auto-follow**: the manager has no `camera` export. It resolves
  `get_viewport().get_camera_3d()` every frame (or an explicit
  `set_target_camera()` override), binds the compositor to it, and saves/restores
  `cull_mask`, `compositor`, `h_offset`, `v_offset` and (when
  `manage_camera_size`) `size` for the single bound camera when the active camera
  changes or the manager exits — so switching `Camera3D.current` at runtime just
  works. **One manager per process** (the pipeline globals are global shader
  uniforms; a second manager warns); simultaneous split-screen is unsupported
  (the effects bail on `view_count > 1`). **Deferred by owner decision
  (2026-10-16):** supporting it first needs the four process-wide globals
  (`pixelizer_meta_bit`, `pixelizer_screen_size`, `pixelizer_lowres_mode`, the
  palette LUT/dither pair) moved to per-material parameters; until then F5's
  warning is the whole behaviour. Per-camera *switching* works. Camera snap resolves the active camera
  at call time (mover snap is fully shader-side and needs no camera lookup).
- `create_pipeline` for compute must run on the render thread
  (`RenderingServer.call_on_render_thread`); raster pipelines are built lazily
  in `_render_callback` from the derived framebuffer format
  (`rd.framebuffer_get_format(fb)`).
- MSAA stays off — the depth write-back attachment path and the whole pipeline
  assume it (`project.godot` leaves the engine default; metadata/lowres
  viewports force `MSAA_DISABLED` explicitly).

## Additional invariants

- **Save bridge manifests with `PixelizerBridgeManifest.save_to(path)`, never a
  bare `ResourceSaver.save()`.** Outside the editor (any `--script` run) the
  text saver writes the header and every `ext_resource` without `uid=`, and
  `demo.tscn` references the production manifest by uid. `save_to()` keeps the
  existing header uid via `ResourceSaver.set_uid()` and stamps each
  `ext_resource` with the uid `ResourceLoader.get_resource_uid()` reports (a
  no-op inside the editor). Pinned by `tests/bridge/bridge_fixtures.gd`.

- **Low-res mode** always uses a manager-owned `MirrorCamera` inside a
  manager-owned display SubViewport (`core/pixelizer_lowres_view.gd`); the user
  camera stays in place (set `current = false`, saved value restored on exit)
  and is mirrored every frame by `PixelizerLowResView.sync()`. The display
  `SubViewportContainer` uses `pixelizer_upscale.gdshader` (resolution-derived
  texel reconstruction: flat interiors, a one-output-pixel boundary ramp) and
  `scroll_shift` carrying `subtexel_remainder` (smooth scroll); the view pushes
  `source_size`. The `PixelizerGlobals.LOWRES_MODE` global uniform disables the
  anchor clip in materials for that mode. `PixelizerLowResView.update_camera_size`
  writes the mirror camera; the user camera's size and snap offsets are saved at
  bind and restored on unbind.
  **Texel and remainder semantics** (`PixelizerCameraBinding.snap()`): the snap
  period in LOW_RES comes from `PixelizerLowResView.get_texel_world_size()`
  (mirror camera size / display viewport size — measuring the user camera in the
  window is off by `window_height / render_resolution.y`). A camera shift of
  `+residual` moves the rendered content by `-residual` in texel space, so the
  consumer counter-shifts with `scroll_shift = Vector2(residual.x, -residual.y)`
  (x in columns; y negated because screen rows increase downward while view-space
  y increases upward). A bare `-residual` doubles the x error.
- **Per-object instance uniforms** (`anchor_macros.gdshaderinc`):
  `anchor_size`, `anchor_tag`, `anchor_focus`, `edge_tint`,
  `use_grade_lut`, plus `anchor_mode` (0 = PER_OBJECT,
  1 = UNIFIED world-origin anchor), `use_dither` (1 = on; gates both the
  alpha dither and the LUT dither band) and `anchor_mover_snap` (1 = shift the
  mesh so its projected pivot lands on a whole texel). The shader branches on the metadata
  camera for the payload; the anchor mode only changes the projected pivot in
  `ANCHOR_VERTEX`. `PixelizerGeometryState` sets these on bind; a
  `PixelizerObjectProfile` or applier change re-pushes them live through the
  owning applier;
  `outline_enabled` / `override_outline_color` re-register the
  palette tag (the apply pass samples the palette, not the instance uniform) —
  see the "Outline palette contract" below.
- **Applier inheritance / overrides** (`PixelizerApplier3D`): `pixel_size`,
  `palette_enabled`, `dither_enabled`, `anchor_mode`, `outline_enabled`,
  `shadow_casting` and `mover_snap` use `-1` = inherit (nearest ancestor with a
  set value, then the manager's `settings` default). `INHERITED_SETTINGS` names
  each property's `PixelizerSettings` fallback and built-in default, so one
  resolver handles all of them; `_resolve_effective()` caches the values for a
  scan and nested appliers resolve through their parent. Setters call
  `_refresh_children()` → `rescan()`, which re-scans the subtree and re-derives
  nested appliers, so runtime property changes propagate down; the applier also
  subscribes to the manager's `settings_changed` so a look change re-derives
  every subtree. `rescan_interval > 0` keeps
  `_process` alive for a periodic scan; otherwise the watcher disables
  processing when idle.
- **Mover snap** (`PixelizerManager3D.register_mover` / `unregister_mover`, and
  `PixelizerApplier3D.mover_snap`): a **vertex-stage** offset. Registration sets
  the `anchor_mover_snap` instance uniform on the `GeometryInstance3D`; on the
  next draw `ANCHOR_VERTEX(0)` (`anchor_macros.gdshaderinc`) rounds the projected
  pivot to a whole screen texel and shifts the rigid mesh by the matching
  world-space offset (world units per texel derived from `PROJECTION_MATRIX`,
  orthographic-guarded). The scene transform is never read or written per frame,
  so there are no `RenderingServer.frame_pre_draw` / `frame_post_draw` callbacks
  and no save/restore bookkeeping. The mesh must run a pixelizer material (the
  instance uniform is declared by the macros header). Registration is explicit;
  the manager `mover_snap` is the inheritance default for appliers left at `-1`.
- **Subtree watcher**: appliers connect `SceneTree.node_added` once
  (`_enter_tree`) and filter with `is_ancestor_of`; additions queue and drain in
  `_process`, so children finish `_ready` before bind (important for
  firefly/glow material registration). Processing is disabled when the queue and
  the bridge watchdog are idle. Per-object state lives in `_states`
  (id -> `PixelizerGeometryState`); `_prune_states()` drops states whose target
  was freed or left the subtree, restoring authored materials. `_scan` skips
  nested appliers, the `PixelizerManager3D` node and the `pixelizer_ignore`
  group, applied both at the top
  of `_scan` and in the child loop. Property setters coalesce into one deferred
  `rescan()`, and each rescan resolves the inherited values once
  (`_resolve_effective`) by comparing against the manager's `inherit_sentinel`.
- **Cloud contract**: uniform names in `cloud_fbm.gdshaderinc` (`clouds_enabled`,
  `cloud_noise`, `cloud_sun_dir`, `cloud_height`, `cloud_noise_scale`,
  `cloud_threshold`, `cloud_bands`, `cloud_tightness`, `cloud_octave_drop`,
  `cloud_gap_erosion`, `cloud_detail_strength`, `cloud_wind`,
  `cloud_shadow_strength`, `cloud_shadow_banding_enabled`,
  `cloud_shadow_levels`, `cloud_shadow_softness`) are built by the active
  cloud **provider** (`PixelizerSkyClouds3D.build_cloud_params()`) and pushed by
  the manager (`core/pixelizer_cloud_field.gd`) to every registered cloud /
  pixelized material. `cloud_octave_drop` is the second-octave persistence of the
  optional detail FBM in `cloud_noise_at` (mirrored by the god-ray pass); with
  `cloud_detail_strength = 0` it is inert. With no provider
  the manager pushes neutral params (`clouds_enabled = false`, key defaults).
  Third-party sources without a
  cloud toolkit get the bundled include plus an injected
  `ALBEDO *= 1.0 - cloud_shadow(v_world_pos);` through the shader bridge, so a
  pristine `MarchingSquaresTerrain` receives the same coverage as water, the sky
  deck and the god-ray pass. The field re-pushes only when the provider
  dictionary's `hash()` changes (provider register/unregister forces a push).
- **Manager cloud registry**: the cloud field's material list
  (`id -> ShaderMaterial`) is the **cloud-field push list only** — pipeline-wide
  params are global shader uniforms (`PixelizerGlobals`). `register_cloud_material`
  and every `register_pixelized_material` opt-in join it; entries are pruned when
  their material is freed. `PixelizerWater3D` / `PixelizerSkyClouds3D` /
  `PixelizerPointLightVolume3D` unregister in `_exit_tree`.
- **Material-factory eviction**: `PixelizerMaterialFactory` keeps a
  `WeakRef(source)` per cache id and drops the cached conversion when the source
  material is freed (MST chunk rebuilds / runtime swaps), bounding the cache.
- The apply pass push-constant block is **16 floats** (64 bytes); the GLSL
  std430 struct must match byte-for-byte and any new field needs a matching pad.
  Outline colour rides the palette, not the push block.
- **Geometry state / single slot iterator**: `PixelizerGeometryState` binds
  `MeshInstance3D`, `MultiMeshInstance3D`, `GPUParticles3D` and `CPUParticles3D`
  through one `_material_slots()` iterator yielding a `Slot` (`source` +
  `apply`/`restore` callables) per authored slot; `bind`/`unbind`/the bridge all
  iterate it. Instance uniforms are per node, so sub-instances/particles share
  the node's pixel size and outline id. `MeshInstance3D` keeps surface override
  materials; MMIs and particles get a **duplicated mesh** with converted surface
  materials (or a converted `material_override` when present) assigned through
  the caller's `assign` callable. Only `GPUParticles3D.draw_pass_1` is converted
  — querying `draw_pass_2..4` when unset logs an engine error.
- **First-bind push ordering**: `bind()` must set `_applied = true` *before*
  calling `push_instance_params()` — the push early-outs while the state is not
  applied. Reversing them silently dropped every per-subtree setting on the
  first bind (instance uniforms kept their shader defaults, and
  `outline_enabled = 0` never reached the palette), which is what made terrain
  chunks render on per-object lattices with default outlines across chunk
  borders. All fresh-bind paths (applier scan, watchdog retry) rely on `bind()`
  doing the push itself.
- **Custom-shader macros** (`anchor_macros.gdshaderinc`): Godot 4.7
  preprocessor limits — no zero-arg macros (all entry points take a throwaway
  first argument: `ANCHOR_VERTEX(0)`), and `return` is illegal in the
  fragment processor function, so the metadata branch is
  `if (ANCHOR_META_ACTIVE(0)) { ANCHOR_META_LIGHT(0); } else { ... }`.
  A material registered via `register_pixelized_material()` is marked with the
  `pixelizer_opt_in` meta and joined to the cloud push list; it must be
  recognized by `PixelizerGeometryState._is_pixelizer_material()` (through
  `manager.is_pixelized_material()`) so the factory never replaces it.
  Pipeline-wide params ride `PixelizerGlobals` (global uniforms), so there is no
  per-material push for them.
  `cloud_fbm.gdshaderinc` is include-guarded (safe to include directly or
  through the macros header). **Function parameters must not shadow globals**:
  Godot rejects a parameter that collides with any source declaration
  ("Redefinition of 'world_pos'"), and these includes sit next to arbitrary
  third-party globals, so every helper parameter is `anchor_*` / `cloud_*`
  prefixed (e.g. MST declares `varying vec3 world_pos`).
- **Shader bridge contract** (`core/pixelizer_shader_bridge.gd`,
  `core/pixelizer_bridge_{entry,manifest,registry}.gd`,
  `editor/pixelizer_bridge_{plugin,dock}.gd`):
  - **Generation is editor-only.** `PixelizerShaderBridge` is a pure static text
    transform (reads files; no live materials/RenderingServer). The game path
    must never build/generate shader source — no `Shader.new().code = ...`
    anywhere under `core/nodes/compositor`. Runtime does a manifest lookup and at
    most one in-place `material.shader = <pre-generated Shader>`
    (`PixelizerBridgeRegistry.apply`). Keep it that way.
  - **Approval is explicit and not automatic.** `PixelizerBridgeEntry.approved`
    defaults false; `excluded` is sticky and persisted. The runtime registry
    (`PixelizerBridgeRegistry`) maps only approved entries whose
    `rules_version == INJECTION_RULES_VERSION` and whose `output_path` exists; it
    never hashes or reads source files. Stale detection and `generated_hash`
    drift reporting are editor/dock concerns. Unapproved / excluded /
    version-mismatch / missing-output entries are never applied, so the failure
    mode is always "rendered as authored", never a broken shader.
    `PixelizerGeometryState.bind()` leaves unsupported custom materials untouched
    and logs a one-shot hint per node (node path, shader path, how to opt in).
    The hint waits two frames and re-checks first, so the deferred-registration
    race above never reports a node that then binds
    (`tests/unsupported_material_check.gd`).
  - **`auto_bridge_custom_shaders` defaults to `false`** (safety gate) on
    `PixelizerManager3D`; enable it (and set `bridge_manifests`) to let objects
    swap in approved bridges. The manifest list is the trust boundary — there is
    no global singleton. The `bridge_manifests` setter rebuilds the registry;
    diagnostics are `get_bridge_mapped_count()` / `get_bridge_warnings()`.
  - **The source addon is never written.** The dock refuses an `output_dir` that
    lies inside any scanned root. `tests/bridge/bridge_fixtures.gd` hashes the
    whole vendored `addons/MarchingSquaresTerrain` tree (excluding `.uid` /
    `*.import` engine sidecars) before/after scan+generate and asserts it is
    byte-identical.
  - **Injection vocabulary.** Generated shaders include
    `anchor_macros.gdshaderinc` and use the `PIXELIZER_*` aliases defined at the
    end of that header (`PIXELIZER_VERTEX(0)` first in `vertex()`;
    `PIXELIZER_META_ACTIVE` / `PIXELIZER_META_LIGHT` then `PIXELIZER_CLIP(...)`
    last in `fragment()`). `pixelizer_macros.gdshaderinc` is a forwarding shim
    only (no duplicate definitions). Cloud handling is **conditional**: a source
    whose flattened text owns `clouds_enabled` / `cloud_shadow` /
    `cloud_coverage_from_noise` gets the macros include wrapped in
    `#define PIXELIZER_NO_CLOUD` / `#undef` (compiling out the bundled
    `cloud_fbm.gdshaderinc` and `anchor_grade()`, so its own toolkit does not
    collide); every other source includes the bundled toolkit and gets
    `ALBEDO *= 1.0 - cloud_shadow(v_world_pos);` injected as the first fragment
    statement. Bump `INJECTION_RULES_VERSION` whenever the transform changes
    (current: 2).
  - **`\bALPHA\b` only** matches an ALPHA write — `ALPHA_SCISSOR_THRESHOLD` must
    not (fixture asserts this); opaque fragments clip `1.0`.
  - **Watchdog**: some systems create/replace the rendered material after the
    first bind (MST's runtime texture baker swaps every chunk mesh to its own
    `mst_terrain_baked.gdshader` duplicate, and chunks may be mesh-less while
    they rebuild). `PixelizerApplier3D` keeps a throttled `_watch_ids` poll
    (shared `_process`, `BRIDGE_WATCH_INTERVAL`) after a swap actually happened —
    including when the material was already bridged through a **shared** sibling
    material — or while there is nothing to inspect yet; it then retries the
    bind and registers newly mapped materials. `PixelizerGeometryState.unbind()`
    restores the authored shaders.
  - The dock registers via `add_control_to_dock` (deprecated in 4.7 in favour of
    `add_dock(EditorDock)`), called dynamically so the deprecation analyzer stays
    quiet, and removes via `remove_control_from_docks`.
- **Outline palette contract** (`core/pixelizer_outline_palette.gd` + the apply
  pass): a 256x2 RGBA8 texture. Row 0 = silhouette/exterior colour, row 1 = inner
  (id / depth-discontinuity) colour; the alpha channel is an **opacity**
  (`0` = leave the sampled scene colour, `1` = replace it). The apply shader
  composites `mix(scene, linear(outline_rgb), opacity)` — the palette is baked
  from authored (sRGB) colours into an 8-bit texture sampled without an sRGB
  view, so the shader linearises with the exact sRGB EOTF (`srgb_to_linear()`;
  the same trap the LUT documents). Skipping that conversion renders a
  near-black authored colour ~5× lighter.
  `PixelizerManager3D.set_outline_color()` writes **both** rows with the
  colour's alpha as the opacity (`alpha = 0` hides the outline, `1` replaces the
  scene colour), so a per-applier `override_outline_color` also colours
  elevated-rim depth edges; `set_outline_enabled(false)` writes opacity 0 and
  re-enabling restores the `outline_palette` row (or `default_outline_color`, at
  its alpha) — the apply shader needs no branch.
  `PixelizerOutlinePalette` stores per-row `silhouette_alpha` / `inner_alpha`
  (float 0..1) and a `multiply_colors` mode: the default replaces at `alpha`;
  multiply modulates with the authored value as the factor
  (`mix(color, color * rgb * 2, alpha)`, **no** sRGB decode — the ProPixelizer
  `_EdgeHighlightColor` convention, so 0.5 is invisible; owner decision
  2026-10-16). The opacity applies in both modes, so a hidden tag's opacity-0
  row never modulates.
  **Ink gate** (`visible_anchor` in the apply pass): a block inks (and gets the
  focus tint) only when the pixel is not in front of its anchor (`revert`) AND
  the anchor's own screen pixel is not hidden by a non-pixelized surface
  (`anchor_hidden`: the scene depth at `snapped_uv` is nearer than the
  metadata depth recorded there). The second test is what keeps a whole-block
  occluder from being inked — `revert` cannot see it, since both of its depth
  samples land on the occluder. It compares the *same* pixel in both buffers;
  comparing the current pixel against the anchor's metadata depth instead
  suppresses legitimate ink on blocks that straddle a silhouette (measured; the
  capture matrix catches it). `tests/verify/verify_outline3.gd` holds the
  in-game acceptance test.
  The depth test is a **second difference** (`2*centre - a - b` per axis,
  convex side only), so a slope at any angle stays clean; a step beyond
  `outline_interior_threshold` routes to the silhouette row. An optional crease
  term (`outline_normal_threshold`, 0 = off) samples the engine's
  normal-roughness scene texture at ±1 macro step for `1 - dot(n, n_neighbour)`;
  the manager sets `needs_normal_roughness` on the apply effect while the
  threshold is above 0, so the depth prepass writes the buffer without SSAO or
  a requesting material (the pass warns once and skips the term when it is
  missing). **Never infer "written" from `has_texture()`:** 4.7.1 Forward+ left
  the texture allocated but unwritten (uninitialised contents) when nothing
  requested it, and the term inked that garbage. The buffer is written only at
  the anchor-lattice survivors (the main pass discards the rest), which is
  exactly where the term samples. The buffer holds **per-pixel** normals (normal maps and
  animated surfaces included), so a low threshold inks normal-mapped water or
  foliage; the demo leaves the term off. Row 255 is the focus subject's row
  (`set_outline_color(255, c)`
  colours focused geometry).
  `PixelizerApplier3D.outline_enabled` (inherit sentinel / 0 off /
  1 on) and `PixelizerObjectProfile.outline_enabled` expose this per subtree.
  Outlines paint whole macro blocks: a tag viewed at grazing angles (dense depth
  steps) can still read busy, and terrain-like subtrees conventionally set
  `outline_enabled = 0`.
- **Palette LUT contract**: `PixelizerSettings.global_palette_lut` (Texture2D,
  forwarded byte-for-byte by a non-exported `PixelizerManager3D.global_palette_lut`
  property) must keep its exact name
  — external pipeline components probe the property
  list and push their LUT there. The LUT is 256x256,
  `x = r + 16*b`, `y = g + 16*ditherBand` (16^3 gamma-space colours x 16
  ordered-dither bands), baked by `PaletteLUT` (core/) with
  `DitherMatrix` (core/; thresholds `(n + 1) / 17`, matching the shader's alpha
  dither cell for cell). The shader sampler is the
  `PixelizerGlobals.PALETTE_LUT` global uniform
  (`global uniform sampler2D pixelizer_palette_lut : source_color,
  filter_nearest, repeat_disable`) — `source_color` is mandatory (ALBEDO is
  linear; without it the palette renders washed out / hue-shifted). Grading runs
  inside `ANCHOR_GRADE` (after `ANCHOR_CLIP`), so the graded colour rides the
  anchor fragment; the dither band comes from the object-grid macro-pixel delta
  (`anchor_macro_delta`), never screen space. The pipeline-wide palette params
  (`pixelizer_palette_lut`, `pixelizer_palette_grading_enabled`,
  `pixelizer_palette_dither_enabled`) are global uniforms set once by the manager
  (`_palette_dirty` gate); per-object opt-out is the instance uniform
  `use_grade_lut` (`PixelizerObjectProfile.palette_enabled`).
- **God-ray pass contract**: `PixelizerGodRays3D` creates a
  `PixelizerGodRayEffect`, gives it `manager`, and registers it through
  `manager.add_pre_pixelization_effect()`; the manager inserts it at the FRONT
  of the PRE_TRANSPARENT array (before `snapshot`), so the pass `imageStore`s an
  additive term into the scene colour layer (an `rgba16f` `image2D`) before the
  `snapshot` pass copies it and the rays are replicated into macro-pixels by the
  apply pass. Disabling the node (or freeing it) removes the pass from the
  compositor; there is no `rays_enabled` flag and no inert pass. The engine depth
  layer shares the colour layer's orientation — the ray pass samples depth at
  `uv` for the same screen pixel. Parameters ride a
  **uniform buffer** (not push constants): 15 vec4s / **240 bytes**, std140,
  and `PixelizerGodRayEffect.PARAMS_SIZE` must match byte-for-byte. The cloud
  field mirrors `cloud_fbm.gdshaderinc` (`cloud_noise_at` +
  `cloud_coverage_from_noise`) so rays share gaps with the shadows. The march is
  a Beer-Lambert transmittance integration (`accum += transmittance * gap *
  fade * ds; transmittance *= exp(-extinction * ds)`) with a per-pixel jittered
  start, not an independent sum of samples; the result is scaled by
  `ray_quantum` **before** the `ray_quantize_bands` step. The `ray_steps` …
  `ray_distance_falloff` / `time_override` fields are plain vars on the effect
  (the `ray_decay` meaning is the extinction coefficient). The provider node
  owns the tuning exports, copies them into the effect from `_process`
  (`apply_provider`, main thread) and pulls `set_cloud_params()` from
  `manager.get_cloud_params()` plus the sun's `light_color` as `ray_tint`. The
  phase reads the wall clock (`Time.get_ticks_msec()`) while `time_override`
  `< 0`; a value `>= 0` pins it.
- **Sky cloud sheet**: `PixelizerSkyClouds3D` is the cloud **provider**
  (`register_cloud_provider(self)`) and also a cloud consumer
  (`register_cloud_material()`), so the deck follows its own
  noise/height/wind/threshold/bands (the 15 cloud exports moved off the
  manager). Opaque alpha-scissor only. The sheet
  samples a **second, mipmapped** copy of the noise (`cloud_noise_hi`): the
  include's `cloud_noise` is `filter_linear` (MST contract) and the deck is
  viewed at near-grazing angles, where a mip-less 256px noise aliases into dot
  moiré (and the aliased sheet depth makes the god-ray march jitter). The
  manager generates the noise with `generate_mipmaps()`. The helper pushes
  `cam_fwd = (0,0,0)` for perspective cameras, and flips the erosion side when
  `cam_fwd.y > 0` (deck above an upward-looking camera).
- **`EMISSION` is ignored for `unshaded` materials in 4.7.1** — an additive
  unshaded volume must write `ALBEDO`.
- **Point-light volume contract** (`shaders/point_light_volume.gdshader` +
  `PixelizerPointLightVolume3D`): additive unshaded sphere centred on the
  light, `blend_add, unshaded, cull_disabled, depth_draw_never,
  depth_test_disabled, shadows_disabled, fog_disabled`. Both hemispheres reach
  the same pixels, so fragments nearer than the light centre are discarded
  (`length(VERTEX) < length(v_light_view)`) for exactly one evaluation per
  pixel. The pool is evaluated on the opaque surface reconstructed from
  `hint_depth_texture` + `INV_PROJECTION_MATRIX`; the view-ray halo uses the
  closest approach; the occlusion test samples the depth at the light's
  projected position (`v_light_uv`, projected in the vertex stage) and hides
  the whole contribution when geometry sits in front of the light
  (`occlude_by_depth`; `depth_slack`, default 0.5, keeps a bulb mesh at the
  light centre from occluding its own light). Apply the occlusion test to the
  whole contribution, never per-ray. It includes `anchor_macros.gdshaderinc`
  and `discard`s in the metadata branch, so it can live under an applier; the
  helper registers its material (`register_pixelized_material`) and
  **unregisters on `_exit_tree`** (`unregister_pixelized_material`) so rebuilds
  never leave freed materials in the registry.
- **Water contract** (`shaders/water.gdshader` + `PixelizerWater3D`): always
  OPAQUE (`render_mode cull_back, shadows_disabled`, never write `ALPHA` —
  pixelized objects only write anchor depth). Banded deep→shallow from the
  `coast` instance uniform (`1.0` = shore, `0.0` = open water); `wave_phase`
  is a per-tile animation offset that a contiguous grid must leave at 0
  (otherwise vertex waves and the 4-sine normal field seam at tile borders).
  Cloud receiver via `cloud_fbm.gdshaderinc` + `register_cloud_material()`.
  Godot has a built-in `TAU` shader constant — never redeclare it.
- **Deferred watcher callbacks**: `PixelizerApplier3D._on_child_entered` takes
  an **untyped** parameter and checks `is_instance_valid` — deferred calls can
  carry a child that was already freed, and a typed `Node` parameter fails to
  bind.
- **Compositor-effect cleanup**: Godot invokes `_notification` on **every
  script in a GDScript inheritance chain**, not just the most-derived one
  (`GDScriptInstance::notification`). A `CompositorEffect` subclass must
  therefore never call `super._notification(what)` for cleanup — the engine
  already runs the base method, so calling it again double-frees every RID
  ("Attempted to free invalid ID"). Each class (`PixelizerEffectBase`,
  `PixelizerGodRayEffect`, `PixelizerApplyPixelizationEffect`) frees only the
  RIDs it created, guards with `is_instance_valid(rd)` (the `RenderingDevice`
  is not ref-counted and may already be gone at shutdown), and resets each RID
  to `RID()` so a repeated notification is a no-op.
- **Godot 4.7 `Curve` API**: `Curve.interpolation_mode` does not exist.
  Interpolation is per-point: `set_point_left_mode(i, Curve.TANGENT_LINEAR)`
  (and right mode) for straight segments; default `TANGENT_FREE` is a smooth
  Hermite.
- **Shader comments are `//` only** — a `##` doc-comment line is an unknown
  preprocessor directive and fails compilation with
  "Tokenizer: Unknown character #35: '#'" pointing at the *include* line.
- **`INSTANCE_ID` is stage-scoped**: it is only valid inside `vertex()` /
  `fragment()`, not in helper functions — pass it in as an argument.
  `LIGHT_VERTEX` is fragment-stage only; in `vertex()` use `VERTEX`.
- **Day/night rig** (`nodes/pixelizer_day_night_3d.gd`): normalized
  `time_of_day` (0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset); the sun is
  driven by `rotation_degrees = (-elevation, azimuth, 0)` from the analytic sine
  arc (or optional `elevation_curve`/`azimuth_curve`) plus `sun_color_ramp` /
  `sun_energy_ramp`, and the `WorldEnvironment` gets ambient/sky
  (`ProceduralSkyMaterial` colours)/fog/background-energy ramps. The rig assigns
  `manager.sun = sun`, and the manager reads the sun node every frame — cloud
  shadows, cloud deck and god-ray tint follow automatically.
  `set_time_of_day()`/`advance_time()`/`set_fast_forward()` are the runtime API.
  At exactly 0° elevation the ground self-shadows into stripes (grazing
  shadow-map acne).
- **Foliage contract** (`shaders/grass_billboard.gdshader`,
  `shaders/tree_leaves.gdshader`): both include `anchor_macros.gdshaderinc`
  and must be registered with `register_pixelized_material()`. Cards are unit
  quads; the shader lifts `VERTEX.y + 0.5` so the node/MultiMesh origin is the
  base. Grass is a Y-axis billboard, leaves a full billboard; both write
  `POSITION` directly, then **overwrite `v_world_pos`/`v_view_depth`** after
  `ANCHOR_VERTEX(0)` (the macro sampled the pre-billboard VERTEX), set
  `NORMAL` to world-up and `LIGHT_VERTEX` (fragment) to the card-centre view
  position. Wind is world-space, amplitude = `wind_strength` × card world
  height × bend², clock quantised by `wind_fps` (stepped pixel animation).
  Atlas variation hashes world origin + `INSTANCE_ID`; alpha-scissor only via
  `ANCHOR_CLIP_AT(alpha, 0.5)` — cutout textures need a shader-authored minimum
  threshold because the material's `alpha_scissor` uniform defaults to 0 (a bare
  `ANCHOR_CLIP` would render the quad opaque). Grass derives the billboard
  basis with a cross product against world up, with a fallback for a
  straight-down camera (the old ground projection of the camera's forward axis
  was `normalize(0, 0, 0)` = NaN at the pitch singularity). Neither shader is
  referenced by any script, scene or resource: they are unexercised examples.
- **Screen projection contract** (`shaders/screen_projection.gdshader`): the
  material is registered for clouds; the render resolution (not the window) rides
  the `PixelizerGlobals.SCREEN_SIZE` global uniform
  (`global uniform vec2 pixelizer_screen_size`), set in the manager's
  `_enter_tree` and on every `render_resolution` change via
  `PixelizerGlobals.set_param()`. The six pipeline globals are declared in
  `project.godot` under `[shader_globals]` so shaders compile before a manager
  registers them; `PixelizerGlobals.ensure()` registers them exactly once only
  when the project has no such setting (guarded by a static dict plus
  `ProjectSettings.has_setting("shader_globals/<name>")`); never call
  `global_shader_parameter_get` at runtime. Projection UV =
  `(SCREEN_UV * pixelizer_screen_size - origin_px) / texture_size`, so texels
  land on the render pixel grid and the pattern is screen-locked.
- **Character FBX import** (`demo/assets/characters/`): ufbx converts the source
  Z-up/cm to Godot Y-up/meters.
