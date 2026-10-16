# VERIFICATION.md — what still needs work

Written 2026-10-16, at the end of a verification pass over the audit fixes.
**Audience: a fresh session with no prior context.** Read in this order:

1. this file (open work),
2. `SUMMARY.md` → "In-game verification pass" (what was verified, how, and what
   the verification itself got wrong),
3. `AGENTS.md` (architecture + the invariants that must survive any change),
4. `PLAN.md` (the original task spec; sections A–G, already executed).

Branch `audit-fixes-2026-10` holds four commits: the fixes+tests, the tests, the
docs, the plan+record, then `ada9947` (this verification pass). Nothing is
pushed. The working tree is clean apart from the owner's untracked
`docs/references/`.

Everything below was found by running the demo with a real renderer. Nothing
here is speculative about *whether* a problem exists — but where I could not
determine a cause, it says so.

---

## Part 1 — Open defects

### 1. The outline gate does not fire for a full-block non-pixelized occluder
*(highest priority: it is a shipped behaviour defect, and the plan's item D3 was
supposed to fix exactly this)*

**Symptom.** A non-pixelized object in front of pixelized geometry is correctly
not colour-smeared, but it still receives the pixelized object's **outline ink**:
the character's silhouette is painted onto the wall in front of it.

**Mechanism** (`addons/pixelizer_3d/shaders/compute/apply_pixelization.glsl`):

- `:121-122` — `base_raw = texture(depth_copy, uv).r` and
  `anchor_raw = texture(depth_copy, snapped_uv).r`. Both are samples of the
  **scene depth buffer**.
- `:174-177` — `revert = base_depth < snapped_depth - tolerance`.
- `:194` — the outline block runs `if (params.outline_enabled > 0.5 && !revert)`;
  the focus tint has the same guard near `:290`.

When the occluder spans the whole macro block, the anchor's screen position is
*also* on the occluder, so both depth samples are the occluder's and `revert`
stays `false`. The outline test then runs against the **metadata** texture, which
the metadata camera rendered from the pixelized object behind it (`:195-199`),
and inks the occluder.

**Evidence.** A subagent's per-36-row band profile of a frame with a magenta
occluder quad covering the left half: in the bands fully covered by the quad the
non-magenta pixel count equals the ink pixel count (i.e. those pixels *are* ink,
not other scene), and a dumped frame shows the character's outline drawn on the
quad. Independently, the shader reading above is unambiguous.

**Why the obvious fix fails — do not repeat it.** I tried gating on the anchor's
own metadata depth (`anchor_meta.b`, the pixelized surface's view depth) instead
of the depth-copy sample. That suppresses legitimate ink: on a block that
straddles a silhouette the anchor often sits on the *far* surface, which by depth
alone is indistinguishable from an occluder. The **capture matrix caught it** —
`anchor` changed 0.41 % (mean 0.45, over the 0.2 tolerance) — and it was
reverted. Treat the matrix as the guard against "fixing" this by removing ink.

**What a real fix needs.** A signal that separates "same object, different
depth" from "foreign surface". Candidates, none validated:

- Have the metadata pass record the pixelized layer's **tag at every pixel** of
  the surface rather than only at survivors (today `ANCHOR_CLIP` limits the
  metadata buffer to a lattice, so a fragment's own position is empty for
  non-survivors — which is why a naive "sample the metadata at `uv`" test cannot
  work).
- A second render target holding the pixelized layer's depth (a "pixelized-only
  depth"), so a fragment can be classified as "in front of the pixelized
  surface" without relying on the screen-space neighbour.
- A cheaper mitigation worth evaluating first: pass depth *and* the anchor's
  metadata depth together and require *both* to indicate the fragment is nearer
  **and** the block to be depth-continuous — i.e. exclude blocks whose own depth
  spread already marks a silhouette.

**Acceptance test.** With an occluder covering half the frame and a proven 0 px
whole-frame noise floor: toggling the outline changes **0 px** in the occluded
region while an exposed control region changes **>100 px**. `tests/verify/verify_outline3.gd`
is the scaffold, but its exposed-rect control currently reports 0 px (see item 7)
— fix the framing first or use the band-profile method described in `SUMMARY.md`.

### 2. Unregistered custom materials are skipped with no diagnostic

`core/pixelizer_geometry_state.gd:113-115` returns `false` from `bind()` when any
slot holds a `ShaderMaterial` the pipeline cannot convert, leaving the whole node
untouched — **silently**. The addon documents a "one-shot hint" in
`addons/pixelizer_3d/AGENTS.md`, and
`uses_unsupported_custom_material()` / `collect_materials()`
(`core/pixelizer_geometry_state.gd:80`, `:90`) exist but have **no callers**, so
the hint was never implemented. The only diagnostic lives in
`core/pixelizer_material_factory.gd:40`, which is unreachable on this path.

This was reported in the original audit but never made it into `PLAN.md`, so the
executing session correctly did not implement it.

**Fix.** Emit one warning per node naming the node path and the offending
material's shader path, and say what to do (`register_pixelized_material()`,
or bridge it). Either wire the dead helpers into that message or delete them.

**Acceptance.** A node with an unregistered custom `ShaderMaterial` under an
applier logs exactly one actionable line and is still left untouched.

---

## Part 2 — Verification gaps (behaviour unproven; may hide defects)

Each of these is a place where the code looks right but nothing has demonstrated
it in the running game. None is known to be broken.

### 3. D1b, the crease term, is unverified

`outline_normal_threshold` (default 0 = off) samples the engine's
normal-roughness buffer. It was observed to change the render with SSAO on in one
run (threshold 0 vs 0.6, with a **0 px** whole-frame noise floor) and to change
nothing in another run — inconsistent, so treat it as unverified.

**Decisive test** (suggested by the audit and not yet run): put a small mesh in
frame with `uniform sampler2D nr : hint_normal_roughness_texture;`. That both
*forces* the engine to create the buffer and acts as a positive control: with the
buffer present, threshold 0 vs 0.6 must change **more than the noise floor**.
Prove the noise floor is 0 px first (see Part 3).

### 4. B1's repaired branch is exercised only by reasoning

The B1 fix arms the bridge watchdog when a bind **succeeds and swapped**
(`nodes/pixelizer_applier_3d.gd:374-384`). In the demo the chunks are mesh-less
at first bind, so the watchdog is armed by the *older* failed-bind path instead;
a frame-by-frame trace confirmed the first `bind()` never succeeded. The
documented contract is satisfied, but the specific new branch has no coverage.

**Test to write.** A scene where the target material exists at first bind and is
replaced afterwards (MST's runtime texture baker does this, an
`editor_preview` pass does this, and a synthetic "swap the mesh material after
bind" probe would do it). Assert the new shader is bridged without a rescan.

### 5. The palette LUT path has no in-game coverage

The demo assigns no `global_palette_lut`, so bake → global uniform → grade has
never been exercised in the running game; C2's fix (the dither matrix values) is
covered numerically by `tests/dither_matrix_check.gd` plus the shader/matrix
agreement. A probe could author a small LUT at runtime via `PaletteLUT` and
assert the render changes and lands on palette entries. Note the known fidelity
gap: the LUT grades **albedo**, so lighting and cloud shadows act on top of the
graded colour (`pixelizer_object.gdshader:32`); the README says so.

### 6. `tests/verify/verify_core.gd`'s F1 checks are unsound as written

They fail because `demo/demo.tscn` pins `pixel_size = 5` on the top-level applier
and `_resolve_setting()` is nearest-author-wins, so a
`settings.default_pixel_size` change cannot reach `Knight_Body`. Propagation
itself works — a counter-test on an inheriting subtree shows the live write and a
whole-resource swap both landing one frame later with `rescan_interval = 0`.
**Retarget the checks at an inheriting mesh, or rewrite the claim.**

Related, and not a bug: in the demo the tuner's Look → Pixelization → default
pixel size moves the terrain (which inherits) and not the characters (pinned).
Worth deciding whether the demo should pin at all, since the tuner row is
otherwise a poor demonstration.

### 7. `verify_outline3.gd`'s exposed-rect control reports 0 px — unexplained

With a correct framing (subject projected to 576,425; the occluder's edge at
576; both rects straddling it; guards passing) toggling
`settings.default_outline_enabled` changed **0 px in the whole frame**. That is
not explicable by the code: `compositor/pixelizer_apply_effect.gd:142` pushes
`params.outline_enabled` straight from `look.default_outline_enabled`, the demo
pins nothing that would suppress the characters' outlines, and the *applier-level*
toggle demonstrably inks (item D1a's control box: 1160 px). Either the framing
still fails to include inked geometry, or something suppresses the pass-level
toggle. **Resolve this before trusting any D3 result from that probe** — note it
does *not* affect the D3 defect in Part 1, whose evidence is the shader reading
plus the audit's independent band profile.

### 8. Assigning an outline palette shifts the frame even when it should not

Assigning *any* `settings.outline_palette` moved the frame by ~0.5 % mean luma
even for a palette whose row values should be neutral. The audit's candidate
cause: `core/pixelizer_outline_registry.gd:71-75` `invalidate()` drops the
working copy, which also drops the per-tag `set_enabled(false)` writes (the
terrain applier's disabled tag) until the next rescan re-applies them. Confirm,
then decide whether an authored-palette swap should preserve per-tag enable
state.

### 9. The foliage shaders are unwired, so two fixes are unexercised

`tree_leaves.gdshader` and `grass_billboard.gdshader` are referenced by no
script, scene or resource. That leaves untested: the `ANCHOR_CLIP_AT(alpha, 0.5)`
minimum scissor that stops cutout cards rendering as opaque quads, and the
cross-product billboard basis that replaced a `normalize(0,0,0)` NaN at the
pitch singularity. Decide: wire them into the demo (a small foliage patch), or
document them in `AGENTS.md` as unexercised examples.

### 10. Mover snap still has no visual coverage

`tests/mover_snap_check.gd` pins the registration contract (8 checks), but the
capture matrix reports `mover_count: 0` on every entry because the demo's camera
is perspective and mover snap is orthographic-only. A matrix entry that switches
the camera to orthographic and sets `mover_snap = 1` would cover the actual
vertex-stage snap.

### 11. A matrix entry that exercises the outline path harder

The `anchor` entry does cover the outline pass (it is what caught my bad gate
change), but nothing frames a *dense* outline case — e.g. the terrain applier
with `outline_enabled = 1`, which is the configuration the D-series work exists
for. A sixth matrix entry would make outline regressions loud rather than 0.4 %.

---

## Part 3 — How to verify anything in this project in-game

These four traps each cost a session and each produced a plausible-looking wrong
number. Full write-up in `SUMMARY.md` → "Method notes".

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
the manager disables its compositor passes and pixelization is unobservable):

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

**The regression net.** `python tests/run_captures.py` renders five modes and
diffs against `tests/reference/`. It is the cheapest way to prove a change did
**not** alter the demo's render, and it is what caught the failed D3 gate fix.
Its references are regenerated by the same build, so a pass proves determinism,
not correctness (see `tests/README.md`). After an *intentional* visual change:
`python tests/run_captures.py --update-references`.

---

## Part 4 — Decisions for the owner (no code needed until decided)

1. **Multiply-mode semantics.** The apply pass does
   `color *= srgb_to_linear(row) * 2`, so the invisible row is
   `linear_to_srgb(0.5) ≈ 0.7354`, not 0.5. The docs now say so. The alternative
   is to drop the sRGB decode *in multiply mode only* (the row value is a
   modulation factor, not a colour), which restores the documented "0.5 is
   invisible" and matches ProPixelizer. The demo uses neither mode, so either is
   free.
2. **Split-screen / simultaneous cameras.** Still unsupported: four parameters
   (`pixelizer_meta_bit`, `pixelizer_screen_size`, `pixelizer_lowres_mode`, the
   palette LUT/dither pair) are **process-wide** global shader uniforms, and F5
   only warns. Moving them to per-material parameters is the prerequisite
   project. Per-camera *switching* works today (F3 verified).
3. **The demo camera.** Authored as a near-vertical overhead rig
   (`orbit_distance = 24`, `pitch_deg = 89.9`, `pitch_max_deg = 89.9`), which
   `AGENTS.md` now records. Confirm it is intentional or restore a gameplay
   framing (a one-line change plus a `docs/images/hero.png` re-shoot).
4. **MST interactions.** Explicitly out of scope per the owner. Still open, for
   whoever takes it: whether the bridged MST surface shaders' `ALPHA` writes put
   them in the transparent pipeline (the addon's own invariant forbids writing
   `ALPHA`), the grass bridge injection point sampling the pre-billboard
   `VERTEX`, and one vendored file differing from upstream
   (`resources/plugin_materials/round_brush_radius_material.tres`).
5. **`docs/references/`** (videos + `model.txt`) is untracked; `*.mp4`/`*.webm`/
   `*.mkv` are now ignored, so only `model.txt` is exposed to a stray
   `git add -A`.
6. **README screenshots.** The three editor screenshots were removed (they were
   missing and stale); `hero.png`, `demo-terrain.png`, `demo-diagnostics.png`
   and `demo-inspector.png` are current. Re-shoot editor shots if wanted.

---

## Part 5 — Small hygiene items

- `demo/demo.gd.uid` points at a script that does not exist (pre-existing).
- `tests/__pycache__/` could not be deleted (a safety check blocked the glob);
  it is gitignored.
- `tests/bridge/generate_bridges.gd` re-stamps the manifest's `.tres` uid
  attributes textually because the headless `ResourceSaver` drops them — a
  workaround worth confirming is robust, and worth mirroring in the dock if not.
- `SUMMARY.md` and `PLAN.md` are process records, not contracts. When a claim in
  them is superseded, correct it there rather than leaving both versions.
