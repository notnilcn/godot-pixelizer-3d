# VERIFICATION.md — status of the verification follow-up

Originally written 2026-10-16 as the open-work handoff after the in-game
verification pass; **updated 2026-10-16 (fourth session) with the outcome of
each item.** Read with `SUMMARY.md` → "Fourth session" and `AGENTS.md`.

Summary: both defects are fixed, and fixing the first one uncovered a bigger
one — **depth linearisation in the apply pass had never produced metric depth**,
so the `revert` occlusion guard never fired. Every gap in Part 2 is closed or
recorded with a measured result. A follow-up in the same session closed the
last two open items (item 3's unforced crease buffer, Part 5's uid re-stamp).
Nothing from the fourth session is committed yet.

---

## Part 1 — Defects

### 1. The outline gate did not fire for a full-block non-pixelized occluder — **FIXED**

**Root cause, larger than the symptom.** `pixelizer_apply_effect.gd` pushed
`projection.get_z_near()` / `get_z_far()`, but the projection the compositor
receives is reverse-Z with a [0, 1] range, and those helpers assume the OpenGL
convention: in the demo they returned −0.05 / 0.05. `linearize_depth()` thus
returned ~0.05 m everywhere (measured: scene-depth / metadata-depth ratio a
constant 0.0018), so `revert` (tolerance 0.05 m) never fired for *any* occluder.
The pass now pushes `projection.z.z` / `projection.w.z` and inverts the matrix
(measured ratio ≈ 1.00; the push block is still 16 floats).

**Gate.** `anchor_hidden`: the scene depth at the anchor's own pixel is nearer
than the metadata depth recorded at that same pixel, i.e. a non-pixelized
surface (invisible to the metadata camera) covers the anchor. Ink and the focus
tint now need `!revert && !anchor_hidden`. Unlike the reverted attempt, this
compares one pixel across two buffers, so a straddling block whose anchor sits
on the far surface still inks (the anchor is the visible survivor at its own
pixel).

**Evidence.** `tests/verify/verify_outline3.gd`: noise floor 0 px; occluded rect
**0 px**, exposed control **2130 px**. Capture matrix: `anchor` changed 0.20 %
— the guard now working (the non-pixelized water edge and the fireflies keep
their own pixels instead of terrain anchors smeared over them); inspected and
accepted into the references.

### 2. Unregistered custom materials were skipped with no diagnostic — **FIXED**

`bind()` now reports one warning per node (node path, shader path, how to opt
in: `register_pixelized_material()`, a shader bridge, or the ignore group). The
dead `uses_unsupported_custom_material()` / `collect_materials()` were deleted.

Wiring the hint exposed a real silent skip: the demo's
`PixelizerPointLightVolume3D` registers its material deferred, after the
applier's first bind, and nothing re-bound it. Registration now emits
`PixelizerManager3D.pixelized_material_registered`, appliers with an unbound
node re-scan, and the hint waits two frames and re-checks so this race is never
reported. The demo logs no hint.

**Evidence.** `tests/unsupported_material_check.gd` (headless, 9 checks):
exactly one hint across forced rescans, node and shader named, node untouched,
and a late opt-in is bound and not reported.

---

## Part 2 — Verification gaps

### 3. D1b, the crease term — **FIXED and verified**

**What was wrong.** Nothing in the addon asked the engine for the
normal-roughness buffer; the pass only checked `has_texture()`. On 4.7.1
Forward+ the texture is allocated in the demo even when nothing requests it,
but nothing writes it. A temporary debug view that blits the raw buffer showed
the unforced contents are uninitialised memory: dark blocky rectangles with no
scene structure. The crease term was inking garbage — the earlier "12 434 px
changed" was real pixels changing for a meaningless reason, and the ~20 000 px
gap to the forced render was garbage vs real normals. (With a forcing material
the depth prepass writes the buffer, and the same blit shows the scene's
normals, written only at the anchor-lattice survivors since the main pass
discards the rest — exactly where the term samples.)

**Fix.** The manager sets `CompositorEffect.needs_normal_roughness` on the apply
effect while `outline_normal_threshold > 0` (off otherwise, so the default demo
pays nothing). The warning now only fires on renderers without the buffer.

**Evidence.** `verify_outline3.gd` (12 checks, all pass): threshold 0 vs 0.6
changes 12 485 px with and without a `hint_normal_roughness_texture` forcing
quad, and the two renders differ only by the forcer quad's own 560 px — now
asserted. The capture matrix is unchanged (the term is off by default).

### 4. B1's repaired branch — **COVERED**

`tests/bridge_watchdog_check.gd` (headless, 6 checks): bridged material present
at first bind → bind succeeds, swaps and arms the watchdog; the mesh is then
replaced with a fresh `mst_terrain_baked` material and the watchdog bridges it
without a rescan. Negative control: with the watch entry removed, the
replacement stays unbridged.

### 5. Palette LUT path — **COVERED (regression); fidelity gap unchanged**

Matrix entry `palette_lut` bakes an 8-colour LUT at runtime through `PaletteLUT`
and assigns it as `settings.global_palette_lut`; the render differs from
`anchor` (1.13 %, the characters are graded) and is byte-stable. "Lands on
palette entries" cannot be asserted on final pixels: the LUT grades albedo and
lighting acts on top (`pixelizer_object.gdshader:32`). The bridged MST terrain
is not graded in this capture.

### 6. `verify_core.gd` F1 — **FIXED (probe and demo)**

The terrain did not inherit either: its applier is nested in the top-level
applier, which pinned `pixel_size = 5`, so *nothing* in the demo followed the
settings default (this file's earlier note that the tuner moved the terrain was
wrong). The pin equalled the default, so it was removed (render unchanged) and
the tuner row now moves the whole scene. F1 asserts an inheriting subject
(`Knight_Body` follows a live change and a resource swap) and a pinned one (the
probe pins the terrain applier at 4; its chunks must not follow). 27 checks
pass.

### 7. `verify_outline3.gd`'s exposed control reported 0 px — **NOT REPRODUCIBLE**

The committed probe's control inks 2130 px. The probe's own comments record an
earlier version that never switched outlines off, which produces exactly this
symptom; that is the likely cause. Its TRUST header is updated.

### 8. Assigning an outline palette shifted the frame — **FIXED (two causes)**

The measurable shift came from multiply mode ignoring the row opacity: hidden
tags (the terrain) carry an opacity-0 *white* row, which `color *= rgb * 2`
doubled. Separately, `invalidate()` did drop per-tag state until the appliers'
deferred re-scan; the registry now keeps per-tag enable/colour state across a
reseed (decision: a palette swap preserves it). With rows at 0.5 the frame is
now byte-identical to outlines off.

### 9. Foliage shaders — **DECIDED: documented as unexercised examples**

Recorded in `AGENTS.md` (Foliage contract). Not wired into the demo.

### 10. Mover snap visual coverage — **COVERED**

Matrix entry `ortho_mover` (`--ortho --mover-snap`, 57 movers). `mover_count`
used to read 0 for an unrelated reason as well: the capture helper collected
meshes by *script* class name, which plain meshes lack. Fixed; the runner now
requires `mover_count > 0` for this entry.

### 11. Dense outline matrix entry — **ADDED**

`outline_dense` (`--outline-terrain`: every applier outlined, terrain
included), 2.65 % different from `anchor`.

---

## Part 3 — How to verify anything in this project in-game

These four traps each cost a session and each produced a plausible-looking wrong
number. Full write-up in `SUMMARY.md` → "Method notes". (The fourth session hit
trap 4 once more: a "forcing" quad placed just outside the frustum made a
comparison vacuous until the probe asserted its pixel count was nonzero.)

1. **`root.get_texture().get_image()` returns the last RENDERED frame.** Two
   grabs inside one `_process` call are the same image; mutating state and
   grabbing in the same call captures the *pre*-mutation frame. Every compared
   pair must be captured in its **own** phase, with a frame wait between.
2. **The demo animates far more than it looks.** Cloud wind scrolls the shadow
   field, the god-ray pass reads the wall clock, grass billboards sway, water
   waves, fireflies move. Two "identical" frames differed by ~24 % of the image
   before `PixelizerEffects` and the grass planters were hidden and
   `cloud_wind`/`time_override` were frozen. **Assert a 0 px whole-frame noise
   floor before trusting any diff.**
3. **No colour predicate can find ink on this scene.** The authored outline is
   near-black and so is much of the shaded terrain at close range (one predicate
   counted 201 590 "ink" px). Measure ink as the *difference* the outline toggle
   makes, never as an absolute colour.
4. **Design the control first, and make it able to fail.** Two probes passed
   their headline assertion while measuring nothing — a rect the occluder did not
   cover, and a control that could not respond to the toggle. Prefer a
   single-image control (two regions, one frame) or a self-validating guard
   (assert the occluder's edge falls between the rects, assert the rects are on
   screen, assert the noise floor is 0).

**Running the probes.** Windowed, never `--headless` (there is no renderer, so
the manager disables its compositor passes and pixelization is unobservable).
The headless unit checks are listed in `tests/README.md`.

```bash
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --path . \
  --fixed-fps 60 --script res://tests/verify/<probe>.gd
```

`--script` also accepts an absolute path, so scratch probes need no copy into the
project. After ANY `.glsl`/`.gdshader` edit, run the import pass first (SPIR-V is
baked at import) or a stale cache silently runs the old shader:

```bash
"C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe" --headless --editor --quit --path .
```

**Seeing shader values.** A temporary debug view (an extra `debug_mode` branch
in `apply_pixelization.glsl`, captured with `--debug-view=N`) that encodes a
ratio into a colour channel is what exposed the depth bug; decode the PNG with
the sRGB EOTF before reading numbers off it.

**The regression net.** `python tests/run_captures.py` renders eight modes and
diffs against `tests/reference/`. It is the cheapest way to prove a change did
**not** alter the demo's render, and it is what caught the failed D3 gate fix.
Its references are regenerated by the same build, so a pass proves determinism,
not correctness (see `tests/README.md`). After an *intentional* visual change:
`python tests/run_captures.py --update-references`.

---

## Part 4 — Owner decisions

1. **Multiply-mode semantics.** The apply pass did
   `color *= srgb_to_linear(row) * 2`, so the invisible row was
   `linear_to_srgb(0.5) ≈ 0.7354`, not 0.5.

   Owner Decision: match ProPixelizer. **Done** — multiply uses the authored
   value as the factor (no sRGB decode), with one addition: the row opacity
   still applies (`mix(color, color * rgb * 2, alpha)`), because the manager
   hides a tag by writing an opacity-0 *white* row, which a bare
   `color *= rgb * 2` doubles.

2. **Split-screen / simultaneous cameras.** Still unsupported: four parameters
   (`pixelizer_meta_bit`, `pixelizer_screen_size`, `pixelizer_lowres_mode`, the
   palette LUT/dither pair) are **process-wide** global shader uniforms, and F5
   only warns. Moving them to per-material parameters is the prerequisite
   project. Per-camera *switching* works today (F3 verified).

   Owner Decision: Deferred. **Documented** in `AGENTS.md` (Load-bearing
   invariants → camera auto-follow).

3. **The demo camera.** A near-vertical overhead rig (`orbit_distance = 24`,
   `pitch_deg = 89.9`, `pitch_max_deg = 89.9`), recorded in `AGENTS.md`.

   Owner Decision: Intentional.

4. **MST interactions.** Still open, for whoever takes it: whether the bridged
   MST surface shaders' `ALPHA` writes put them in the transparent pipeline, the
   grass bridge injection point sampling the pre-billboard `VERTEX`, and one
   vendored file differing from upstream
   (`resources/plugin_materials/round_brush_radius_material.tres`).

   Owner Decision: Out of scope.

5. **`docs/references/`** (videos + `model.txt`) is untracked; `*.mp4`/`*.webm`/
   `*.mkv` are ignored, so only `model.txt` is exposed to a stray `git add -A`.

   Owner Decision: Intentional.

6. **README screenshots.** The three editor screenshots were removed;
   `hero.png`, `demo-terrain.png`, `demo-diagnostics.png` and
   `demo-inspector.png` are current.

   Owner Decision: Don't re-shoot editor shots.

---

## Part 5 — Small hygiene items

- **uid re-stamp — FIXED.** Confirmed the drop: in a `--script` run
  `ResourceUID` knows the manifest's and its scripts' UIDs, yet
  `ResourceSaver.save()` writes no `uid=` at all (the text saver asks an
  editor-installed hook for them). The old workaround copied UIDs from the
  previous file's *text*, so a first-time file got no header uid and a stale
  uid would be copied forward. Replaced by `PixelizerBridgeManifest.save_to()`:
  the header keeps the file's uid from `ResourceLoader.get_resource_uid()` (a
  fresh file gets `ResourceUID.create_id()`) applied with
  `ResourceSaver.set_uid()`, and each `ext_resource` gets the engine's live uid.
  The generator and the dock both use it (in the editor it is a no-op, since
  the saver already writes them). Evidence: new `bridge_fixtures.gd` checks (84
  pass) — a fresh header uid, stable across a re-save, every `ext_resource` uid
  equal to the engine's, plus an info line showing a bare save writes none; and
  `generate_bridges.gd` regenerates the production manifest byte-identical to
  HEAD.
- `SUMMARY.md` and `PLAN.md` are process records, not contracts. **Done for this
  session's supersessions** (D1b, D2, D3, F1, multiply mode) in `SUMMARY.md`;
  `PLAN.md` is left as the original spec.
- `docs/images/*.png` were not re-shot. The depth fix changes ~0.2 % of an
  overhead frame (water edge, fireflies); re-shoot through the capture CLI if
  they should match exactly.
