# Pixelizer3D

A Godot 4.7 (Forward+) 3D pixel-art pipeline for Godot — per-object macro-pixel
sizes, screen-space outlines with a 256-id palette, subject focus, palette
LUT + ordered-dither grading, a projection-space orthographic camera snap, god
rays, cloud shadows, water, foliage, fireflies, point-light volumes, a day/night
rig and optional low-res SubViewport mode.

The renderer combines ideas from several open-source Godot demos (see the
repository `CREDITS.md` for the full inspiration list).

## Requirements

- Godot **4.7** with the **Forward+** renderer (the anchor pipeline needs
  `CompositorEffect`, storage textures and normal-roughness).
- MSAA/TAA off, render scale 1.0 (the defaults in `project.godot`).
- `Compatibility`/headless degrade with a warning; low-res mode also runs on
  `Mobile`, but the anchor pipeline is Forward+ only.

## Contents

| Path | What lives there |
|---|---|
| `plugin.cfg`, `plugin.gd` | Addon registration; adds the **Bake PaletteLUT to PNG** tool-menu item and builds the shader-bridge dock. |
| `nodes/` | The core runtime/config nodes: `PixelizerManager3D`, `PixelizerApplier3D` and `PixelizerDiagnosticsOverlay`, plus the `PixelizerObjectProfile` per-object override resource (`core/`). See below. |
| `effects/` | Optional per-scene effect nodes (`water`, `sky_clouds`, `point_light_volume`, `fireflies`, `day_night`). Place only the effects a scene needs. |
| `compositor/` | The `CompositorEffect` subclasses that drive the render passes (`*_effect.gd`). |
| `shaders/` | Runtime spatial shaders (`.gdshader`) and shared includes (`.gdshaderinc`). |
| `shaders/compute/` | The GLSL compute/ raster passes used by the compositor effects (`*.glsl`). |
| `core/` | Pipeline helpers (camera binding, cloud field, outline registry, focus, low-res view), per-object geometry state, palette LUT, dither matrix, outline palette, material factory and the shader-bridge data types. |
| `editor/` | Editor-only tooling: the bridge dock/plugin and the palette baker. |

## Quick start

```gdscript
# 1. Place ONE PixelizerManager3D in the scene, named exactly
#    "PixelizerManager3D" (the addon never creates one). Appliers and effects
#    resolve it explicitly: top-level -> the sibling named PixelizerManager3D,
#    nested -> the parent applier's manager. No manager means a configuration
#    warning and no pixelization.
var manager := PixelizerManager3D.new()
manager.sun = sun              # optional: defaults to a sibling DirectionalLight3D
add_child(manager)

# 2. Wrap content in an applier; everything under it is pixelized (subtree
#    watcher catches runtime spawns too). Applier properties left at
#    PixelizerInherit.INHERIT (-1) fall through to the parent applier / manager.
var applier := PixelizerApplier3D.new()
applier.pixel_size = 3
applier.anchor_mode = 1        # UNIFIED (one lattice for the group)
add_child(applier)             # must be a sibling of the manager
applier.add_child(my_model)

# 3. Custom spatial shaders opt in with the macros header:
#    #include "res://addons/pixelizer_3d/shaders/anchor_macros.gdshaderinc"
applier.manager.register_pixelized_material(my_water_material)

# 4. Optional: snap moving objects onto the pixel lattice in the vertex stage
#    (the scene transform is never touched). Registering sets the
#    `anchor_mover_snap` instance uniform on a GeometryInstance3D, so the mesh
#    must run a pixelizer material. Orthographic cameras only (reported).
applier.manager.register_mover(my_moving_object)   # or applier.mover_snap = 1

# 5. Optional effects are self-contained scene nodes — add only what the scene
#    needs. Each resolves the manager explicitly and has an optional `manager`
#    override:
#      PixelizerSkyClouds3D      # cloud shadows + optional deck (deck_enabled)
#      PixelizerGodRays3D        # god rays (owns its pass; `enabled` toggles it)
#      PixelizerWater3D          # cloud-shadow-receiving water tile
#      PixelizerFireflies3D      # MultiMesh firefly swarm
#      PixelizerDayNight3D       # sun + environment rig
#      PixelizerPointLightVolume3D
```

`PixelizerObjectProfile` is the per-object override: a `Resource` in the
manager's `object_profiles` array that targets a geometry node (`target_path`,
relative to the manager, or `manager.register_object_profile(profile, geometry)`).
Fields left at the inherit sentinel fall through to the owning applier;
`outline_id_mode` separates inherit / auto-allocate / explicit.
`outline_color` overrides **both** the silhouette and inner-edge (depth-edge)
rows of the tag's outline palette, with the colour's alpha as the row opacity
(`alpha = 0` hides the outline, `1` replaces the scene colour);
`outline_enabled = false` hides that tag's outline entirely
(its palette rows get opacity 0, which the apply pass composites as
`mix(scene, outline_rgb, opacity)`). `anchor_mode` `UNIFIED` anchors the
macro blocks to the world origin (a common lattice for a group) instead of each
object's own pivot.

The manager's `editor_preview` toggle runs the pipeline live in the editor 3D
viewport; preview binds are restored before the scene is saved.

Look (resolution model, palette, outline tuning, snap toggles and the applier
inherit defaults) lives in the `PixelizerSettings` resource on
`PixelizerManager3D.settings` (auto-created when unset), so a scene can swap it
per camera; manager fields left on the node are wiring and node references
(`sun`, `snap_origin`, `auto_focus_target`) plus `debug_view`.

See `nodes/pixelizer_manager_3d.gd` for the full export set and the generic
`register_*` slots (`register_cloud_provider`, `register_cloud_material`,
`register_pixelized_material`, `register_mover`, `register_object_profile`). The
god-ray pass is owned by `PixelizerGodRays3D` and inserted through
`manager.add_pre_pixelization_effect()`; no node means no pass.

## Composition model

Every effect is an optional `effects/` node that resolves the manager explicitly
(no viewport-group fallback). Add only the effects a scene needs:

| Scene wants | Nodes to place |
|---|---|
| Anchor pixelization only | `PixelizerManager3D` + `PixelizerApplier3D` |
| + cloud shadows (no visible deck) | + `PixelizerSkyClouds3D` with `deck_enabled = false` |
| + visible cloud deck | + `PixelizerSkyClouds3D` (set `cloud_shadow_strength = 0` for deck only) |
| + god rays | + `PixelizerGodRays3D` |
| + water / fireflies / day-night / … | + the matching `effects/` node |

Cloud shadows/rays without a deck: `PixelizerSkyClouds3D` with
`deck_enabled = false`. A scene with no cloud node renders cloud-free (the
manager pushes neutral params). The ray look is authored on the
`PixelizerGodRays3D` node, which inserts and removes its own compositor pass
(`enabled` toggles it); with no node there is no pass.

## Nodes

The core runtime/config nodes live in `nodes/`; the optional effects in
`effects/`.

| Node | Role |
|---|---|
| `PixelizerApplier3D` | The entry point. Binds supported geometry in its subtree through a `PixelizerGeometryState` (no auto-created nodes) and watches `SceneTree.node_added` so runtime spawns are picked up. Resolves the manager explicitly (sibling `PixelizerManager3D` at top level, parent applier's manager when nested); a `-1`/sentinel property inherits from the parent applier, then the manager's settings defaults. |
| `PixelizerManager3D` | One per **process**. Owns the metadata `SubViewport` + camera, attaches the compositor effects to the active `Camera3D` (auto-follow; `set_target_camera()` to pin), keeps the metadata camera in sync, resolves the sun, holds the object profiles and the `settings` look resource. **Must be placed explicitly and named `PixelizerManager3D`** (the addon never creates one). A second live manager warns: the pipeline globals are global shader uniforms. |
| `PixelizerSettings` | The per-scene look `Resource` (`manager.settings`): resolution model, palette LUT/dither, camera snap, outline tuning and the `default_*` applier inherit values. Writes notify the manager, which re-publishes globals and re-derives every applier subtree. |
| `PixelizerObjectProfile` | Per-object override `Resource` in the manager's `object_profiles` array, targeting a geometry node (`target_path` or `register_object_profile`). Sentinels inherit from the applier; `outline_id_mode` picks inherit / auto-allocate / explicit. |
| `PixelizerDiagnosticsOverlay` | HUD status readout plus a runtime tuner: one foldable panel per manager export group, the settings "Look" sections and one per scene-effect node, and a "Select Object" click-to-pick inspector for `PixelizerObjectProfile` / parent-applier parameters (`PixelizerApplier3D` is never pickable). Toggle key defaults to `Tab`. |
| `PixelizerSkyClouds3D` | Cloud **provider** (owns the 15 cloud-field params + noise) and optional visible deck. `enabled` = node on/off, `deck_enabled` = visible sheet, `clouds_enabled` = shader master toggle. |
| `PixelizerGodRays3D` | God-ray node: owns the ray tuning exports and its `PixelizerGodRayEffect`, inserted before the snapshot pass. `enabled = false` removes the pass. |
| `PixelizerWater3D` | Opaque banded water tile (`water.gdshader`); registers its material for cloud-shadow uniforms. |
| `PixelizerPointLightVolume3D` | Additive, banded point-light volume with a view-ray halo and depth-tested occlusion. |
| `PixelizerFireflies3D` | Deterministic emissive firefly swarm (seed-stable positions) rendered as two `MultiMeshInstance3D` draw calls (bodies + camera-facing additive glow quads from `firefly_glow.gdshader`), with depth-tested glow occlusion. |
| `PixelizerDayNight3D` | Drives a `DirectionalLight3D` and a `WorldEnvironment` (ambient/sky/fog) from a normalized `time_of_day`. Resolves the manager, sun and environment explicitly (sibling defaults). |

Supported pixelization targets: `MeshInstance3D`, `MultiMeshInstance3D`,
`GPUParticles3D` and `CPUParticles3D`. Instance uniforms are per node, so a
MultiMesh's sub-instances and a particle system's particles share the node's
pixel size / outline id.

## Bridging third-party shaders (the shader bridge)

Some spatial shaders live in addons that must not be edited (a vendored terrain
addon is the canonical case). Godot cannot merge their `vertex()`/`fragment()`
with `anchor_macros.gdshaderinc` (stage built-ins are illegal in helper
functions), so they can never call `ANCHOR_*` themselves. The **shader bridge**
rewrites the *source text* into a separate generated asset. Generation is an
explicit, reviewable editor action; the game only ever performs a manifest
lookup and an in-place shader swap. **The source addon is never written to.**
Generated files are plain `.gdshader` text: diffable in git, reviewable, and
safe to delete.

### When to use it

- A third-party `shader_type spatial;` shader (with a `fragment()`) under an
  applier is left unpixelized and logs a one-shot hint.
- The shader cannot be edited to `#include` the macros yourself (vendored
  addon, read-only package, upgrade churn).

Do **not** use it for shaders you own — include `anchor_macros.gdshaderinc` and
call `ANCHOR_VERTEX(0)` / `ANCHOR_CLIP()` / `ANCHOR_META_LIGHT(0)` directly, then
`manager.register_pixelized_material(material)`.

### Workflow

1. `Project > Tools > Pixelizer3D Shader Bridge` (or the docked panel) opens the
   bridge dock.
2. Set the **manifest** path (created on demand as a `.tres`), the **output
   dir** (default `res://pixelizer_bridges/`) and one or more **scanned roots**.
   The output dir must be **outside** every scanned root — the dock refuses
   otherwise, so it can never write into an addon.
3. **Scan** lists every spatial shader with a `fragment()`, with its hook sites
   (Vertex / Fragment / Alpha) and status: `New`, `Excluded`, `Stale`,
   `Up-to-date`, `Missing output`, `Drift`, `Not bridgeable`. Already-opted-in
   shaders (macros include / `ANCHOR_VERTEX` / `PIXELIZER_VERTEX`) are rejected.
4. **Approve** the rows you want (never automatic; new rows default to
   unapproved) and **Preview** to inspect the injected lines and the generated
   source diff.
5. **Dry run** reports what would be written without touching disk.
   **Generate approved** writes the generated `.gdshader` files and saves the
   manifest. **Clean generated** deletes only the generated files (approval
   state is preserved).

### What injection does

The generator (rules version `2`) flattens `#include`s recursively (relative to
the including file, include-guard semantics, depth cap 16, fail on missing),
then:

- `fragment()`: injects `ALBEDO *= 1.0 - cloud_shadow(v_world_pos);` followed by
  `if (PIXELIZER_META_ACTIVE(0)) { PIXELIZER_META_LIGHT(0); }` and
  `PIXELIZER_CLIP(ALPHA)` when the fragment writes `ALPHA` (`\bALPHA\b`, so
  `ALPHA_SCISSOR_THRESHOLD` is not matched), else `PIXELIZER_CLIP(1.0)`. The
  cloud term is skipped when the source owns its own cloud toolkit.
- `vertex()`: injects `PIXELIZER_VERTEX(0);` after the opening brace, or appends
  a synthesized `void vertex() { PIXELIZER_VERTEX(0); }`.
- global scope, **cloud-owning source** (flattened text declares
  `clouds_enabled` / `cloud_shadow` / `cloud_coverage_from_noise`):
  `#define PIXELIZER_NO_CLOUD` around the macros include, `#undef` immediately
  after, so its own toolkit does not collide with the bundle's
  `cloud_fbm.gdshaderinc`.
- global scope, **cloud-less source**: the macros include pulls in the bundled
  `cloud_fbm.gdshaderinc`, so the injected shadow term reads the same `cloud_*`
  uniforms the manager pushes to every registered cloud / pixelized material.
- prepends a banner with the source path, source sha256 and `rules_version`.

The generated file is self-contained (no relative includes) and compiles
standalone. `anchor_macros.gdshaderinc` exposes `PIXELIZER_*` aliases for the
native `ANCHOR_*` entry points, which is the vocabulary the bridge injects.

### Manifest contract and drift

`PixelizerBridgeManifest` (`.tres`) holds `output_dir`, `roots` and an array of
`PixelizerBridgeEntry` (`source_path`, `source_hash`, `approved`, `excluded`,
`has_vertex`, `has_fragment`, `writes_alpha`, `output_path`, `generated_hash`,
`rules_version`).

- `source_hash` is the sha256 of the **source file bytes**. The dock compares it
  and reports the entry as **Stale** when it changes; regenerate from the dock to
  refresh it. Runtime never hashes sources.
- `generated_hash` is the sha256 of the generated file. A mismatch is reported as
  `Drift` (e.g. a hand edit) by the dock.
- Entries generated with an older `rules_version` are not applied.
- Unapproved, excluded, missing-output or version-mismatched entries are
  **never** applied. The failure mode is always "rendered as authored", never
  "broken shader".

### Runtime application

`PixelizerManager3D.bridge_manifests` names the manifests the manager trusts
(no global singleton). On `_ready` (and whenever the list changes) it builds a
`PixelizerBridgeRegistry` mapping `source_path -> output_path`. In
`PixelizerGeometryState.bind()` each unregistered custom `ShaderMaterial` gets
one `registry.apply(mat)` call: a lookup, and at most one in-place
`material.shader = generated`. There is **no** `Shader.new().code = ...`, no
runtime source generation, no source-file I/O and no hashing anywhere in the game
path. The in-place swap is safe
because the material is per-object (a system that duplicates its material per
instance is the usual case) and the swap only happens for explicitly approved
sources. A throttled watchdog re-runs the lookup to catch systems that create or
replace the rendered material after the first apply — e.g. a runtime texture
baker that swaps every chunk mesh to its own baked-shader duplicate. It arms
after a swap actually happened (including through a shared, sibling-bridged
material) or while an object has no mesh/material to inspect yet.

`auto_bridge_custom_shaders` is the **safety switch** (default `false`): while
off, custom shaders are left authored even if a manifest entry is approved. Set
it to `true` (or per manager instance) to enable manifest-driven swaps.

Manager diagnostics: `get_bridge_mapped_count()` and `get_bridge_warnings()`
(version drift, missing outputs).

## Asset notes

- ufbx imports source Z-up/cm assets to Godot Y-up/meters automatically; no
  per-asset conversion is required by the addon.

## Docs

`AGENTS.md` (repository root) is the architecture + load-bearing invariants
reference.
