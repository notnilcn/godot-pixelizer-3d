# AGENTS.md — pixelizer_3d (usage)

How to use the addon. Requirements: Godot 4.7 Forward+ only; MSAA/TAA off, render scale 1.0. Compatibility/headless degrade with a warning.

## Minimal setup

1. Add a `PixelizerManager3D` node to the scene and name it **exactly** `PixelizerManager3D`.
2. Add a `PixelizerApplier3D` around any subtree to pixelize. It binds supported geometry, watches `SceneTree.node_added` for runtime spawns, and has `rescan()` as a manual fallback. A top-level applier resolves the sibling named `PixelizerManager3D`; a nested applier resolves its parent applier's manager. **No manager means a configuration warning and no pixelization** — the addon never creates one.
3. Optional per-scene `effects/` nodes — add only what the scene needs; each resolves the manager explicitly and has an optional `manager` override.

```gdscript
# Scene: PixelizerManager3D (sibling) + PixelizerApplier3D
var applier := PixelizerApplier3D.new()
applier.pixel_size = 3
applier.anchor_mode = 1  # UNIFIED (PixelizerGeometryState anchor_mode enum)
applier.add_child(my_model)
add_child(applier)      # 'applier' must be a sibling of the manager

# optional effects (resolve the manager themselves):
PixelizerSkyClouds3D            # cloud shadows + optional visible deck
PixelizerGodRays3D              # god rays: inserts/removes its own compositor pass
PixelizerWater3D
PixelizerFireflies3D
PixelizerDayNight3D
PixelizerPointLightVolume3D
```

## Nodes

| Node | Use |
|---|---|
| `PixelizerApplier3D` | The entry point. Binds supported geometry in its subtree; nested appliers own their subtree. Resolves the manager explicitly (sibling `PixelizerManager3D` at the top level). |
| `PixelizerManager3D` | One per **process**. Shared services (metadata viewport, compositor, camera, outline palette registry, cloud field, sun, object profiles) plus `settings`. **Must be placed explicitly and named `PixelizerManager3D`.** A second live manager warns (the pipeline globals are global shader uniforms). |
| `PixelizerSettings` | Per-scene look `Resource` (`manager.settings`, auto-created when unset). Swappable per camera. |
| `PixelizerObjectProfile` | Per-object override `Resource` owned by the manager (`object_profiles`), pointing at its geometry target. Replaces the old child node. |
| `PixelizerDiagnosticsOverlay` | HUD + runtime tuner (manager groups, the settings "Look" sections, scene-effect panels, object inspector), toggle `Tab`. |

Supported targets: `MeshInstance3D`, `MultiMeshInstance3D`, `GPUParticles3D`, `CPUParticles3D`. Instance uniforms are per node, so sub-instances/particles share the node's pixel size and outline id.

## Inherit sentinel

A property equal to the manager's `inherit_sentinel` (default `PixelizerInherit.INHERIT == -1`) falls through to the parent applier, then the manager's `settings` defaults (`default_pixel_size`, `default_dither_enabled`, `default_outline_enabled`, `default_mover_snap`), then the built-in default. The sentinel is adjustable on the manager but **must stay negative** (it is validated by a configuration warning), so it can never collide with a real value.

`PixelizerApplier3D` inheritable fields: `pixel_size`, `palette_enabled`, `dither_enabled`, `anchor_mode`, `outline_enabled`, `shadow_casting`, `mover_snap`. Other fields: `outline_id` (sentinel = auto-allocate), `override_outline_color`/`outline_color`, `rescan_interval`, `ignore_group` (default `pixelizer_ignore`), `enabled` (live), `manager`.

`anchor_mode`: `PER_OBJECT` anchors each object to its own pivot; `UNIFIED` anchors a group to one world-origin lattice (needed for contiguous meshes, e.g. terrain chunks, to avoid false inner-edge outlines).

## Per-object override (`PixelizerObjectProfile`)

Add a `PixelizerObjectProfile` to the manager's `object_profiles` array. Set `target_path` (relative to the manager) or call `manager.register_object_profile(profile, geometry)`. Fields left at the sentinel inherit from the applier. `outline_id_mode` separates the old `-1` overload: `INHERIT` (applier's id), `AUTO` (allocate), `EXPLICIT` (use `outline_id`).

## Manager API / fields

- Resolution: `PixelizerManager3D.resolve_manager_explicit(node)` — ancestor applier's manager → manager ancestor → sibling named `PixelizerManager3D` → null.
- Custom shaders: `register_pixelized_material(mat)` / `unregister_pixelized_material(mat)`. Opted-in materials include `anchor_macros.gdshaderinc` and are never replaced by the factory.
- Mover snap: `register_mover(node)` / `unregister_mover(node)`. Vertex-stage lattice snap; **orthographic only** and only with `PER_OBJECT` anchors (a `push_error` reports either mismatch). The mesh must run a pixelizer material.
- Outlines: `set_outline_color(id, color)` (both silhouette + inner rows; the colour's alpha is the row opacity — `0` hides the outline; id 255 is the focus subject's row), `set_outline_enabled(id, enabled)`, `allocate_outline_id()`, `outline_palette` / `get_outline_texture()` / `get_outline_multiply_mode()`.
- Focus: `focus_subtree(root)` / `unfocus_subtree(root)`, or `auto_focus` + `auto_focus_target`.
- Clouds: `register_cloud_provider(obj)`, `register_cloud_material(mat)`, `unregister_cloud_material(mat)`, `get_cloud_params()`. Providers may set `cloud_camera_scope` to be active only for one camera; a second registration warns, and two cameras visible at once share one field.
- Sun: an explicit `sun` wins; otherwise the manager binds the first **sibling** `DirectionalLight3D` (several siblings is ambiguous and warned; none is a `push_error`).
- Object profiles: `object_profiles`, `register_object_profile(profile, target)`, `unregister_object_profile(profile)`, `get_object_profile(geometry)`.
- Compositor slots: `add_pre_pixelization_effect(effect)` / `remove_pre_pixelization_effect(effect)`. `PixelizerGodRays3D` owns its pass through this slot.
- Key manager fields (wiring and node references): `enabled`, `mode` (`ANCHOR`/`LOW_RES`), `sun`, `snap_origin`, `auto_focus_target`, `inherit_sentinel`, `editor_preview`, `metadata_layer`, `object_profiles`, `bridge_manifests`, `auto_bridge_custom_shaders`, `debug_view`.
- Look fields live in `PixelizerSettings` (`manager.settings`, auto-created when unset; `get_settings()`): `render_resolution`, `texel_density`, `view_zoom`, `manage_camera_size`, `default_pixel_size`, `depth_occlusion`, `default_mover_snap`, `global_palette_lut` (kept reachable on the manager too — main-client contract), `default_dither_enabled`, `snap_camera`, `lock_camera`, `default_outline_enabled`, `default_outline_color`, `outline_threshold`, `outline_interior_threshold`, `outline_normal_threshold`, `outline_palette`, `auto_focus`, `debug_focus_mask`. Swapping the resource gives a camera its own look; writing a field notifies the manager (`settings_changed`), which re-publishes globals and re-derives every applier subtree.

## Editor preview

`PixelizerManager3D.editor_preview` (default off) runs the pipeline live in the editor 3D viewport. Preview binds are **non-destructive**: authored materials are restored before the scene is saved. Toggle it in the manager inspector.

## Writing a custom spatial shader

Include the macros, call the entry points, then register the material:

```glsl
#include "res://addons/pixelizer_3d/shaders/anchor_macros.gdshaderinc"

void vertex() { ANCHOR_VERTEX(0); /* ... */ }
void fragment() {
    if (ANCHOR_META_ACTIVE(0)) { ANCHOR_META_LIGHT(0); }
    else { /* ... */ ANCHOR_CLIP(1.0); }
}
```

```gdscript
manager.register_pixelized_material(my_material)
```

Never read/write `ALPHA` (moves the material to the transparent pipeline); use `ANCHOR_CLIP` / `discard`. Comments must be `//` only.

## Shader bridge (third-party shaders)

For vendored spatial shaders that must not be edited (e.g. MarchingSquaresTerrain) and cannot include the macros. The source is never written.

1. `Project > Tools > Pixelizer3D Shader Bridge` (or the dock).
2. Set manifest path (`.tres`), output dir (default `res://pixelizer_bridges/`, must be outside every scanned root), and scanned roots.
3. **Scan** → **Approve** rows → **Generate approved** (never automatic). `Dry run` reports without writing; `Clean generated` deletes only generated files.
4. Point the manager at the manifest and enable swaps:

```gdscript
manager.bridge_manifests = [load("res://pixelizer_bridges/pixelizer_bridge_manifest.tres")]
manager.auto_bridge_custom_shaders = true   # default false (safety gate)
```

Runtime only does a manifest lookup + in-place `material.shader` swap; unapproved / excluded / stale / version-mismatched entries are never applied. Diagnostics: `get_bridge_mapped_count()`, `get_bridge_warnings()`.

## Composition per scene

| Scene wants | Place |
|---|---|
| Pixelization only | `PixelizerManager3D` + `PixelizerApplier3D` |
| + cloud shadows, no deck | `PixelizerSkyClouds3D` with `deck_enabled = false` |
| + visible deck only | `PixelizerSkyClouds3D` with `cloud_shadow_strength = 0` |
| + god rays | `PixelizerGodRays3D` (its `enabled` inserts/removes the pass) |
| + water / fireflies / day-night / volume | matching `effects/` node |

No cloud node → cloud-free (manager pushes neutral params). No ray node → no ray pass, no cost.
