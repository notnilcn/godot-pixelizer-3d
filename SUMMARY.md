# SUMMARY.md — execution of PLAN.md (2026-10-16 audit plan)

This file records what was executed against `PLAN.md`: what landed, what was
verified (and how), what was decided differently, and what remains open.
**Nothing in this work is committed** — everything is in the working tree.

Baseline: `PLAN.md` (untracked, the task spec) on top of the docs-resync
working tree from the previous session (modified `AGENTS.md` / `README.md` /
`tests/README.md` / `demo/demo.tscn`, staged deletions of the old
`tests/reference/` baselines, `tests/run_captures.py`, `tests/tmp_shot.gd` and
`docs/images/demo-diagnostics.png`).

---

## Status by plan section

### A — Diagnostics overlay and inspector

| Item | Status | Notes / evidence |
|---|---|---|
| A1 picker physics short-circuit | **Landed, verified** | `_pick_mesh()` extracted; physics and mesh hits now compete by world distance (ties to physics); `_candidate_aabb()` uses the skeleton-aware `GeometryInstance3D.get_aabb()`. Probe: the click that used to return a terrain chunk now returns `Knight_ArmRight` (nearest mesh on that ray); the 9×5 screen sweep still selects terrain chunks where they are nearest. |
| A2 object panel hides own exports / no scope labels | **Landed, verified** | `begins_with("Pixelizer")` guard removed; sections labelled `This object — X`, `Object profile (this object only)`, `Parent applier — X (shared by N meshes)`; `Create Object Profile` only for supported geometry and placed above the applier section. Probe: profile edit changed one mesh's `anchor_size` (2 vs sibling 5); selecting `Player` now shows its own `Movement` / `Arcball Camera` exports. |
| A3 dead tuner rows | **Landed, verified** | Water `coast`/`wave_phase` setters push instance uniforms live; sky `clouds_enabled`/`deck_enabled` setters recompute `visible`; all day/night arc + ramp fields got re-applying setters; `cloud_octave_drop` is now **implemented** as the detail-FBM second-octave persistence (`cloud_fbm.gdshaderinc`, mirrored in `god_rays.glsl` + `PixelizerGodRayEffect` packing); `texel_density`/`view_zoom`/`auto_bridge_custom_shaders`/water `size`+`subdivisions`/sky `plane_size` hidden via `IGNORE_CLASS_PROPERTIES`. |
| A4 perspective texel readout | **Landed, verified** | `get_debug_status_line()` prints `u/texel=n/a (perspective) remainder=n/a`; the live demo status line shows it. |

### B — Shader bridge

| Item | Status | Notes / evidence |
|---|---|---|
| B1 watchdog armed on the wrong branch | **Landed, verified** | A successful bind that swapped now arms `_watch_ids`; the applied branch re-runs `refresh_bridge()` before `push_instance_params()`; a rescan-time swap re-arms too. Probe: the nested terrain applier ends with `watch_ids = 8`, and all 4 chunks run the generated `pixelizer_bridges/.../mst_terrain.gdshader`. |
| B2 `generate_bridges.gd` destroys the manifest | **Landed, verified** | Loads and updates the existing manifest (`get_or_create_entry`), output paths via the new shared `PixelizerShaderBridge.output_path_for()` (dock uses the same helper), approvals/exclusions preserved, summary printed. Headless `ResourceSaver` drops `.tres` uid attributes, so the generator re-stamps them textually (documented in the script). Verified: 7 entries before/after, `output_path`s unchanged, no flat `.gdshader` files at the `pixelizer_bridges/` root, two consecutive runs byte-identical (`git diff` empty). |
| B3 swap-before-bail | **Landed, verified** | `bind()` pre-checks every slot (`_bridge_available()` = registry admission rules) before `refresh_bridge()`; a node with one bridgeable + one unsupported slot keeps its authored shader (probe: no swap, no surface override, layers untouched). |

### C — Core pipeline correctness

| Item | Status | Notes / evidence |
|---|---|---|
| C1 outline palette colour space | **Landed, verified** | Shader-side exact sRGB EOTF (`srgb_to_linear()`) applied to the palette sample and the focus tint (option “convert in the shader”). Before/after terrain captures: the same authored near-black renders medium navy (old) → near-black (new). |
| C2 dither matrix one step off | **Landed, verified** | `_default_values()` = `(n + 1) / 17`; new `tests/dither_matrix_check.gd` (35 checks, ALL PASS); `palette_lut_debug.png` rebaked with the current code (new tool `tests/bake_palette_lut_debug.gd`; the old showcase `.tres` palette is gone, so the swatch set is recovered from the existing image). |
| C3 LOW_RES remainder sign + texel | **Landed, verified** | `subtexel_remainder = Vector2(residual.x, -residual.y)`; LOW_RES texel comes from `PixelizerLowResView.get_texel_world_size()` (mirror camera ÷ display viewport). Probe: mirror texel 2.0 (was window-based ≈0.03), whole-texel pans keep the phase constant, half-texel pan gives `(-0.5, +0.5)` with `h/v_offset = -1.0`. |
| C4 manager/applier/profile name collisions | **Landed via F1** | The manager's look fields moved into `PixelizerSettings` with `default_*` names (`default_pixel_size`, `default_dither_enabled`, `default_outline_enabled`, `default_mover_snap`, `default_outline_color`); the applier keeps its user-facing names; the object panel labels scopes. Both AGENTS.md files + addon README updated. |
| C5 globals registered at runtime only | **Landed, verified** | All six `[shader_globals]` entries written into `project.godot` via the ProjectSettings API (engine-canonical syntax); `ensure()` stays as the addon-only fallback. The headless import check now prints **no** SHADER ERROR at all. |

### D — Outline quality and capability

| Item | Status | Notes / evidence |
|---|---|---|
| D1a depth second difference | **Landed, verified** | Per-axis `2*centre − a − b`, convex side only (`curve > threshold`), so slopes stay clean; a step beyond `outline_interior_threshold` routes to the silhouette row. Before/after captures with the terrain applier outlined: the old shader floods the slopes with dash marks, the new one marks only the convex elevation edge. |
| D1b normal/crease term | **Landed, conditional — see caveats** | `outline_normal_threshold` (default 0 = off) samples the engine’s named scene texture `forward_clustered / normal_roughness` at ±1 macro step and marks `1 − dot(n, n_neighbour) > threshold`. The pass binds it only when `has_texture()` succeeds (WARNING once + term skipped otherwise) — Forward+ only creates it for SSAO/SSIL/SSR or a `hint_normal_roughness_texture` material. Verified mechanically with an SSAO probe and a hint-material probe (buffer present, threshold toggling changes the ink). **Caveat:** the buffer holds per-pixel normals (normal maps, animated water), so a low threshold over-inks animated surfaces; the demo leaves the term off, and the caveat is documented. |
| D2 compositing + row routing | **Landed** | `PixelizerOutlinePalette.multiply_colors` (`color *= linear(rgb) * 2`, 0.5 = invisible) with the opacity mix kept as the default; depth-only edges above the interior threshold route through the silhouette row. Multiply mode is not exercised by the demo (no authored palette); the shader branch compiles and is reviewed. |
| D3 no visibility gate | **Landed** | Outline and focus tint are skipped when `revert` is true (self-colour-reverted pixels cannot ink their neighbours). Not reproducible in the current demo (no non-pixelized occluder in front of pixelized geometry); code-reviewed, depth write-back untouched. |
| D4 runtime robustness | **Landed, verified** | `pixel_size` clamped to 1–5 and `outline_id` to 0–254 with one-shot warnings; tag 255 is now settable (focus subject row) so `ANCHOR_META_LIGHT` and the registry agree; grass billboard basis derived by cross product against world up with a fallback (the old ground projection was NaN at the pitch singularity); `ANCHOR_CLIP_AT(alpha, 0.5)` gives the cutout foliage shaders a minimum scissor. |

### E — Tests and tooling

| Item | Status | Notes / evidence |
|---|---|---|
| E1 bridge fixture gaps | **Landed, verified** | New stale-entry fixture (hash mismatch → dock reports `Stale`, regeneration clears it; the runtime-never-checks-staleness contract is pinned explicitly); the never-written hash now covers the whole vendored `addons/MarchingSquaresTerrain` tree (excluding `.uid`/`.import` sidecars); `tests/bridge/generated/` is untracked (`.gitignore` + `git rm --cached`) and `compile_test.gd` paths updated to the path-faithful nested outputs. Fixtures: **78 checks, ALL PASS**. |
| E2 capture matrix | **Landed, verified** | New `demo/capture.gd` CLI (`--capture`, `--resolution`, `--fixed-view`, `--mode`, `--plain`, `--debug-view`, `--pixel-size`, `--no-overlay`, `--overlay`, `--settle`) printing a `PIXELIZER_CAPTURE {json}` diagnostics line; `tests/run_captures.py` runs 5 entries (anchor, debug view, lowres, plain, pixel_size_3), verifies the diagnostics, diffs `tests/reference/`, and cross-checks that every mode differs from the anchor. With `--fixed-fps 60` and the pinned god-ray phase, captures are **byte-identical** run to run (0.0000% self-diff); the matrix passes end to end. |

### F — Architecture

| Item | Status | Notes / evidence |
|---|---|---|
| F1 look settings resource | **Landed, verified** | New `core/pixelizer_settings.gd` (`@tool` Resource) holds the serialisable look: resolution model, palette LUT/dither, camera snap/lock, outline tuning, focus toggles and the `default_*` applier inherit values. The manager owns `settings` (auto-created via `get_settings()`), forwards reads, re-publishes globals + invalidates the registry on `changed`, and emits `settings_changed` (appliers re-derive their subtrees). The overlay tuner shows `Look — <group>` sections. Probe: authored values load from the scene sub-resource, a live default change propagates to nested appliers and bound meshes (`anchor_size` 5→3), a whole-resource swap propagates too. |
| F2 effect base class | **Landed as a static host (deviation)** | `effects/pixelizer_effect_3d.gd` (`PixelizerEffect3D`, RefCounted) owns resolution+caching, the editor gate, the one-shot missing-manager report and the warnings content. A base class is impossible without changing the node types scenes already reference (the effects split across `Node3D` and `MeshInstance3D`), so all six effects call the host — the drift the plan listed (fireflies not caching, editor-gate differences) is gone. |
| F3 cloud provider conflicts | **Landed, verified** | Providers are a list; one is active per frame (camera-scoped provider matching the active camera, else the first unscoped one); the second registration warns once with node paths; the per-manager (one-field) hard limit is documented. Probe: switching the current camera switches the field (threshold 0.6 ↔ 0.2). |
| F4 geometry effects in appliers | **Landed** | `PixelizerWater3D` and `PixelizerSkyClouds3D` add themselves to `pixelizer_ignore`; the point-light volume deliberately keeps opting in. |
| F5 two managers | **Landed** | One-shot process-wide warning naming the fought-over globals; documented in both AGENTS.md files. |
| F2/F3 “per-camera” payoff | **Partially** | Provider scoping works per camera now; settings swapping per camera is supported by F1 (the manager re-binds on `settings` change) but no demo wiring exists for it. |

### G — Demo authoring and docs

| Item | Status | Notes / evidence |
|---|---|---|
| G1 floating water tile | **Landed (decision made)** | Root cause found while verifying: `PixelizerEffects` was authored `visible = false`, so the water (and fireflies/deck) never rendered — which is *why* the tile read as terrain. Decision: the container is visible (the demo showcases those nodes) and the tile is seated at `y = 0.15` (above the ±0.12 m vertex waves), shore `coast = 1.0`. Captures show a proper water patch beside the light volume. |
| G2 demo camera | **Not changed (needs owner confirmation)** | The near-vertical overhead rig (`orbit_distance = 24`, `pitch = 89.9`) is left as authored; `AGENTS.md` documents the real values. Flipping it to a gameplay camera is a one-line change plus doc/hero re-shoot. |
| G3 docs | **Landed** | Root `AGENTS.md`, `addons/pixelizer_3d/AGENTS.md`, `addons/pixelizer_3d/README.md` and `tests/README.md` updated for every behaviour change (tuner table, settings split, 16-float push block, outline/LUT/LOW_RES/cloud contracts, capture CLI, one-manager limit). `docs/images/hero.png`, `demo-terrain.png`, `demo-diagnostics.png` re-shot through the capture CLI (wide view / overhead / overlay). |

---

## Verification battery (final state, all green)

```bash
# 1. Import + parse check — no SHADER/Script errors (C5 removed the last one).
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --editor --quit --path .

# 2. Headless bridge fixtures — 78 checks, ALL PASS.
".../Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/bridge/bridge_fixtures.gd

# 3. Dither matrix unit check — 35 checks, ALL PASS.
".../Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/dither_matrix_check.gd

# 4. Generator — additive; production manifest stays byte-identical (7 entries).
".../Godot-stable_mono_win64_console.exe" --headless --path . --script res://tests/bridge/generate_bridges.gd

# 5. Windowed compile smoke test — no SHADER ERROR.
".../Godot-stable_mono_win64_console.exe" --path . res://tests/bridge/compile_test.tscn

# 6. Capture matrix — all entries at 0.0000% vs references, cross-checks pass.
python tests/run_captures.py
```

Ad-hoc probes used during the work (kept outside the repo, in the session temp
dir) covered: the A1 pick, the A2 panel structure/scoping, A3 setters +
ignored rows, the B1 watchdog, the B3 no-strand case, the C3 LOW_RES math, the
F1 settings propagation, and the F3 provider scoping.

---

## Decisions and deviations from the plan

1. **C1** uses the shader-side sRGB conversion (plan option 3) instead of an
   sRGB texture view or a linear 8-bit bake — explicit, format-independent, and
   it matches `Color.srgb_to_linear` exactly.
2. **Push constant block grew 12 → 16 floats** (64 bytes) instead of fitting the
   new fields into the existing padding slots: D1/D2 need three new fields
   (interior threshold, normal threshold, multiply flag) plus the existing
   reserved slot. Both sides and the docs stay field-for-field identical.
3. **F1 node-typed fields stay on the manager** (`sun`, `snap_origin`,
   `auto_focus_target`) because a scene-node reference cannot be serialized in a
   Resource; `debug_view` also stays (its enum is declared on the manager — a
   Resource type reference both ways would be a GDScript cyclic dependency).
   The manager additionally keeps a **forwarding** `global_palette_lut`
   property because that exact name is a documented main-client contract.
4. **F2 is a static host, not a base class** (see the table above).
5. **`PixelizerEffects` made visible + water at `y = 0.15`** (G1) — the tile was
   not “floating” in the rendered demo at all; it was hidden. This is the one
   authoring change that alters the demo’s look; easy to revert by re-setting
   `visible = false` on the container.
6. **`manager.enabled` now actually toggles the pipeline** (unbinds/rebinds the
   camera) — needed so `--plain` is a real baseline; previously the compositor
   stayed attached.
7. **E2’s CLI has three flags beyond the plan’s list** (`--mode`, `--pixel-size`,
   `--overlay`) because the matrix and the docs shots need them.
8. **`cloud_octave_drop` was implemented** rather than removed (plan offered
   either): it is the second-octave persistence of the optional detail FBM, and
   the old fixed 0.65/0.35 blend is reproduced at its 0.5 default, so scenes
   with `cloud_detail_strength = 0` (the demo) are visually unchanged.

---

## Not landed, deliberately out of scope, or still open

- **D1 normal crease term tuning**: works mechanically, but only in scenes that
  make the engine generate the normal-roughness buffer, and low thresholds
  over-ink normal-mapped/animated surfaces. It ships off by default; the demo
  warns once if enabled without the buffer. No demo scene exercises it.
- **D2 multiply compositing** is not visually verified (no authored
  `PixelizerOutlinePalette` exists in the repo); only the code path is.
- **D3** has no reproduction scene in the demo (needs a non-pixelized occluder
  in front of pixelized geometry); the change is small and reviewed.
- **Per-viewport / split-screen managers** remain unsupported: F5 only warns.
  The four pipeline globals are still global shader uniforms — moving them to
  per-material parameters is the prerequisite project the plan defers.
- **F3 per-camera** has no demo wiring; it is an API (`cloud_camera_scope`).
- **G2 camera intent** unconfirmed (left as authored).
- **Stale root artifacts**: `capture.png` / `capture_metadata.png` have no
  producer left (the old showcase capture scripts are gone); they are tracked
  and documented as historical. `palette_lut_debug.png` is now reproducible and
  current.
- **Pre-existing noise, untouched**: the C# bootstrap line
  (`Failed to load project assembly` → `Resource file not found: res://<null>`),
  the god-ray “no cloud noise” first-frame warning, the skinned-mesh triangle
  test being rest-pose (documented in the picker), and `demo/demo.gd.uid`
  pointing at a deleted script.
- **Not committed**: all changes are in the working tree. The previous
  session’s staged deletions (`tests/reference/*`, old `tests/run_captures.py`,
  `tests/tmp_shot.gd`, `docs/images/demo-diagnostics.png`) are still staged;
  the new `tests/reference/` baselines, `docs/`, and the new addon/test scripts
  are untracked. Suggested commit split: (1) A–E code+tests, (2) F architecture
  + `demo.tscn` settings migration, (3) G demo authoring + docs + docs images,
  (4) tooling/gitignore churn (`tests/bridge/generated` untracking).

---

## New / removed files

**Added**

- `addons/pixelizer_3d/core/pixelizer_settings.gd` — the look resource (F1).
- `addons/pixelizer_3d/effects/pixelizer_effect_3d.gd` — the shared effect host (F2).
- `demo/capture.gd` — the demo capture CLI (E2).
- `tests/run_captures.py` — the capture matrix (E2).
- `tests/dither_matrix_check.gd` — dither unit check (C2).
- `tests/bake_palette_lut_debug.gd` — rebakes the repo-root LUT artifact (C2).
- `tests/reference/*.png` — five fresh baselines (the old ones drove the deleted
  showcase scene and were removed in the previous session).
- `docs/images/*.png` — `hero.png`, `demo-terrain.png`, `demo-diagnostics.png`
  re-shot from the current demo.

**Untracked (removed from git, kept on disk where generated)**

- `tests/bridge/generated/` — now owned by the fixtures (`.gitignore` +
  `git rm --cached`), which fixes the “fixture run deletes two tracked `.uid`
  files” defect.

**Modified (high level)**

- Addon: manager (settings split, F4/F5 guards, `enabled` toggle, status line,
  outline tuning), applier (watchdog, settings inheritance, scope labels
  plumbing), geometry state (pre-bridge check, clamps), cloud field (provider
  list + scoping), outline palette/registry (multiply, id 255, colour space),
  camera binding + low-res view (C3), apply effect + `apply_pixelization.glsl`
  (16-float block, second difference, crease term, multiply, revert gate),
  `anchor_macros.gdshaderinc` (`ANCHOR_CLIP_AT`), `cloud_fbm.gdshaderinc`
  (`cloud_octave_drop`), `god_rays.glsl` + god-ray effect (octave drop),
  water/sky-clouds/fireflies/god-rays/point-light-volume/day-night effects
  (host port + setters + ignore group), diagnostics overlay (A1–A4, Look
  panel), shader bridge + dock + generator (B2), bridge registry (B3), dither
  matrix (C2), foliage shaders (D4).
- Repo: `project.godot` (shader globals, C5), `demo/demo.tscn` (settings
  sub-resource, water seat, effects visibility), `demo/player.gd` (capture
  wiring + camera presets), `.gitignore`, both `AGENTS.md` files, addon
  `README.md`, root `README.md` (untouched by this work), `tests/README.md`,
  `tests/bridge/*`.

---

## Second-reviewer validation and follow-ups (2026-10-16)

An independent pass re-ran every mechanical claim and read the rest. Results:

**Reproduced first-hand**: import check clean (C5 confirmed — the pre-existing
`pixelizer_meta_bit` shader error is gone); bridge fixtures 78/78; dither check
35/35; the generator's manifest byte-identical before/after with 7 entries and
no flat outputs (B2); the capture matrix exit 0 with all five entries at
0.0000%/max=0; and the *previous session's* picker reproduction, re-run against
the new code, returns `Knight_Body` (26.53) where it used to return the terrain
chunk (28.49) — A1 verified with an instrument written before the change.

**Read and confirmed**: the 16-float/64-byte push block matches the GLSL std430
struct field for field; the sRGB EOTF is exact and applied to both the palette
sample and the focus tint; the outline is a one-sided per-axis second difference
with the exterior/inner row routing, and the crease term binds a dummy and forces
its threshold to 0 when the normal-roughness buffer is missing (so the dummy is
never sampled); `subtexel_remainder = Vector2(residual.x, -residual.y)` with the
lowres texel genuinely delegated from `get_texel_world_size()` (not dead code);
`INHERITED_SETTINGS` rewired to `settings` with no silent string fallback; no
bare `settings.` reads in the manager, so a settings-less scene cannot crash;
the watchdog arms on both the successful-swap and failed-bind paths and the
applied branch re-runs `refresh_bridge()`.

### The three open items from the review, resolved

1. **Capture-matrix evidence was weaker than "verified" implied** — the
   references were regenerated by the same build, so 0.0000% proves determinism,
   not correctness. *Recorded* here and in `tests/README.md`; the correctness
   evidence is the push-block/invariant checks and the A1 reproduction above.
2. **Mover snap had zero coverage** (`mover_count: 0` on every matrix entry).
   *Fixed*: added `tests/mover_snap_check.gd` (8 checks, headless) pinning the
   observable contract — a mesh under an applier with `mover_snap = 1` carries
   `anchor_mover_snap = 1`, the setting and the `register_mover` /
   `unregister_mover` API both clear and restore it, and a rescan does not
   resurrect it.
3. **`manager.enabled` was still hidden from the tuner** although deviation #6
   made it a working toggle. *Fixed*: removed from `IGNORE_CLASS_PROPERTIES`
   with a comment; the manager panel's `General` group now offers it.

### Residual picker limitation found while demonstrating

`_mesh_hit_distance()` falls back to the **AABB** for `MultiMeshInstance3D` /
particle nodes (they have no single face list), and a MultiMesh AABB is
conservative. Reproduced: clicking the centre of a frame containing a character
selected the terrain's `GrassPlanter` rather than the character, because the
grass AABB was entered nearer than the character's triangle hit. The distance
comparison from A1 is working — this is an accuracy limit of the AABB-only path,
not a regression, and it is now recorded rather than fixed. A real fix would
test MultiMesh instances individually (or use `multimesh.get_aabb()` per
instance), which is a bigger change than A1.

### Demonstration

`docs/images/demo-inspector.png` — the overlay in the running demo with
`Knight_Helmet` selected by a real click, the object panel's scoped sections
(`This object` / `Object profile` / `Parent applier — … (shared by 57 meshes)`)
and the `Look — …` manager groups. The accompanying candidate trace for that
click:

```
Knight_Helmet   MeshInstance3D       aabb= 12.732 hit= 12.925   <- selected
Knight_Head     MeshInstance3D       aabb= 12.809 hit= 12.967
Knight_Body     MeshInstance3D       aabb= 13.003 hit= 13.102
Chunk (0, -1)2  MeshInstance3D       aabb= 20.776 hit= 20.776
GrassPlanter    MultiMeshInstance3D  aabb= 20.776 hit= 20.776
_pick_physics would resolve to Chunk (0, -1)2 at 20.776
```

That is A1's failure mode and its fix in one table: the physics ray still resolves
to the terrain chunk, and the picker now takes the nearer character mesh.
