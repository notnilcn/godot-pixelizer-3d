# Player character — modelling spec

Target: a low-poly, flat/faceted, solid-colour-per-part humanoid that will be
rendered through a pixelization pass (the character ends up ~30-40 screen
"macro pixels" tall in game). Recreate the character from t3ssel8r's sword-combo
devlog: a small elf with white hair, a rust-brown short cloak with a lowered
pointed hood, a dark-grey long-sleeved shirt, a brown tunic skirt / shorts, dark
tights, tall brown boots and a plain straight sword.

All reference images live next to this file (see `../README.md`). The best
model references are the bright Cascadeur viewport crops (`view_*`,
`detail_*`); the `game_*` crops show the same character in-game at game scale
(`*_bright.png` = levels-adjusted so the shapes read). `turnaround.png` puts
five standing views side by side at one scale with head-height lines;
`palette.png` holds the sampled colours.

**Important caveat about the views:** every source frame is shot from a high
camera (roughly 30-45 deg looking down) — there is no true orthographic side or
back view. Only `view_front_apose.png` is close to a level front view, and the
cape is *hidden* in that frame (it was toggled off in the Cascadeur editor; the
brown band at the neck is still visible). Use the front view for body
proportions and the 3/4 / top-down views for the cape, hood and hair.

---

## 1. Scale, units, orientation

| Item | Value |
|---|---|
| Units | metres, Blender scale 1.0, apply all transforms before export |
| Total height (sole to top of hair, excl. top-knot bump) | **1.50 m** |
| Head unit H (top of hair to chin) | **0.31 m** (total = 4.85 H) |
| Origin | on the floor, centred between the feet (X = 0, Y = 0, Z = 0 at the soles) |
| Facing in Blender | **-Y** (the character looks toward the Blender "Front" view camera), up = +Z, character's left = +X |
| Export | glTF 2.0, **+Y Up** enabled (default) |

Why 1.50 m: the figure is 4.85 heads tall — a stylised, slightly chibi youth /
elf, not an adult 7-8-head figure. A rough estimate from the in-game frames
(`game_side_facing_left.png`, correcting for the camera pitch) puts the character at about
1.5-1.9 checkerboard tiles tall; with a 1 m tile that is consistent with
~1.5 m. If the
project wants a different size, scale the whole rig uniformly; all numbers below
are given both in metres and in fractions of total height (h).

**Axis convention after export (state this to whoever integrates it):**
Blender's glTF exporter maps Blender (x, y, z) -> glTF/Godot (x, z, -y). So a
character facing Blender -Y arrives in Godot facing **+Z**, which is Godot's
`Vector3.MODEL_FRONT` (the glTF "asset front" convention). Godot's *node*
forward used by `look_at()` / cameras is -Z, so either rotate the imported scene
180 deg about Y in Godot or call `look_at(target, Vector3.UP, true)`
(`use_model_front`). Do **not** rotate the mesh in Blender to compensate — keep
the standard -Y-facing authoring convention.

## 2. Vertical landmarks (front view, from the floor up)

Measured on `view_front_apose.png` (total = 307 source px).

| Landmark | Fraction of h | Height (m) |
|---|---|---|
| Top of hair (crown) | 1.000 | 1.50 |
| Top-knot bun top (back of the crown, mostly hidden from the front) | ~1.01 | ~1.52 |
| Fringe bottom / brow | 0.915 | 1.37 |
| Eyes (centre) | 0.89 | 1.33 |
| Ear tips | 0.90 | 1.35 |
| Chin | 0.793 | 1.19 |
| Shoulder top / neck band | 0.777 | 1.165 |
| Elbow (arms down) | 0.60 | 0.90 |
| Shirt hem / belt / waist | 0.511 | 0.77 |
| Wrist (arms down) | 0.49 | 0.73 |
| Crotch | 0.42 | 0.63 |
| Cape hem (sides/back) | ~0.40-0.42 | 0.60-0.63 |
| Tunic-skirt / shorts hem | 0.386 | 0.58 |
| Knee | 0.25 | 0.38 |
| Boot top (just below the knee) | 0.234 | 0.35 |
| Sole | 0 | 0 |

Proportions in heads: head 1 H; torso (chin to crotch) 1.8 H; legs (crotch to
sole) 2.0 H. Legs are 42 % of total height — short, sturdy legs and a big head
are part of the look; do not "correct" them toward realistic proportions.

## 3. Widths and depths

| Part | Width (X) | Depth (Y) |
|---|---|---|
| Skull/face | 0.20 m (0.136 h) | 0.20 m |
| Hair shell (helmet-like) | 0.26-0.28 m | 0.26 m |
| Ear tip to ear tip | 0.42 m (0.28 h) | — |
| Neck (hidden by collar) | 0.08 m | 0.08 m |
| Shoulders (outer deltoid to outer deltoid) | 0.28 m (0.185 h) | 0.15 m |
| Chest | 0.24 m | 0.15 m |
| Waist / belt | 0.22 m | 0.14 m |
| Tunic skirt / shorts at hem (flared, both legs) | 0.38 m (0.26 h) | 0.22 m |
| Thigh | 0.11 m | 0.11 m |
| Calf (in tights) | 0.085 m | 0.09 m |
| Boot shaft | 0.10 m | 0.11 m |
| Boot foot | 0.10 m wide, 0.20 m long, 0.07 m tall at toe | — |
| Feet spacing (centre to centre, rest pose) | 0.15 m | — |
| Upper arm / forearm thickness | 0.07 / 0.06 m | — |
| Hand (mitten) | 0.06 wide x 0.09 long x 0.03 thick | — |
| Arm segment lengths | upper arm 0.22 m, forearm 0.20 m, hand 0.08 m | — |

## 4. Part-by-part breakdown and construction

Target budget: **1,500-2,500 triangles** total including cape and sword. Flat
shading everywhere (no smooth groups / auto-smooth off, or "Shade Flat"). No
textures: one material per colour (see section 5). No bevels except where
stated; at game scale a 0.01 m bevel is invisible.

### Head
* **Skull/face:** an 8-sided cylinder or a cube subdivided once and pulled into a
  slightly tapered box, 0.20 x 0.20 x 0.24 m (chin to crown under the hair).
  Chin slightly narrower than the cheeks; no nose, no mouth.
* **Eyes:** two black flat rectangles (separate planes or inset faces),
  each 0.045 m wide x 0.025 m tall, centres 0.035 m either side of the midline,
  at 1.33 m. They read as a single dark band in game — keep them, the 1-2 px
  dark slit under the white hair is part of the face read (`game_*_bright`,
  `detail_head_front.png`, `detail_head_34_*.png`).
* **Ears:** long pointed elf ears, a 4-6 face wedge each, 0.11 m long from the
  side of the head, 0.05 m tall at the root, tip pointing outward, ~15 deg up and
  ~20 deg back. They emerge from under the hair at eye level. Visible in game as
  1-2 px spikes — keep.
* **Hair** (the brightest object in every in-game frame — its silhouette matters
  more than anything else on the model):
  * A helmet-like shell over the skull, 0.26-0.28 m wide, built from a low-poly
    sphere/cube (~24-40 faces), covering the top, back and sides down to ear
    level at the back.
  * A **fringe** cut straight across the forehead, ending just above the eyes
    (1.37 m).
  * **Two side locks** (flat, slightly tapered slabs, 0.05 wide x 0.10 tall x
    0.02 thick) hanging from the temples in front of the ears down to jaw/chin
    level, angled slightly forward (`detail_head_34_left.png`,
    `detail_head_34_right.png`).
  * A **top-knot / bun** on the top-back of the crown: a low-poly sphere or
    rounded cube ~0.08 m across, set slightly behind the crown and tilted back so
    the head profile gets a little upswept peak (`detail_hair_topknot_from_above.png`,
    `view_back_high_topdown.png`; in game it is the 2-3 px bump on top-back of
    the white blob).

### Neck band / collar
A short cylinder (8 sides) 0.05 m tall around the neck at the shoulder line,
light brown `#997967` (only clearly visible in the front view; it is probably
the cape's collar or a scarf). With the cape on, its front shows as a lighter
patch at the throat.

### Torso, shirt, belt
* Long-sleeved **undershirt**, dark grey `#393A39`: a tapered 8-sided box from
  the shoulders (1.165 m) to the hips (0.76 m), slightly wider at the chest.
  The hem sits over the top of the shorts at the belt line.
* **Belt:** a thin ring 0.03 m tall at 0.77 m, near-black, with a tiny black
  buckle square at the front centre. Skippable at game scale (it vanishes under
  the cape); keep only as a colour band if convenient.
* Sleeves run to the wrists; the forearm-to-hand boundary is the only colour
  change on the arm.

### Arms and hands
* Upper arm and forearm: 6-sided cylinders, as in the table above.
* Hands: mitten blocks in skin colour (fingers are invisible at game scale;
  optionally a separate thumb wedge so a sword grip pose reads).

### Tunic skirt / shorts
Mid brown `#784F36`. A short flared skirt-shorts piece from the belt (0.77 m) to
0.58 m: an 8-10 sided truncated cone, 0.22 m wide at the top, 0.38 m at the hem,
with a shallow split between the legs (it reads as shorts from the front,
`view_front_apose.png`, and as a skirt from 3/4). A slightly darker lower rim is
visible in the Cascadeur render — optional.

### Legs and boots
* **Tights** from the shorts hem to the boot tops: 6-sided cylinders. Colour:
  black in the Cascadeur model (use near-black `#141418` so facets still read).
  **Note:** in every in-game frame the legs read *pale*, close to the shaded skin
  tone (`#877471` graded, `game_*_bright.png`). See "Uncertainties": make the
  leg material a separate slot so it can be switched to skin `#D6A28C` (bare
  legs) or a pale beige.
* **Boots:** dark brown `#572B11`, tall riding-style boots to just below the
  knee (0.35 m), a straight 6-8 sided shaft 0.10 m across, a slight flare / cuff
  at the top, and a simple blocky foot (0.20 m long, toe slightly upturned,
  low heel). In game the boots read darker than the legs — keep that contrast.

### Cape / cloak with lowered hood (most important secondary-motion part)
Rust brown `#592B0D` on both sides (no visible lining colour).
* **Type:** a short shoulder cloak that covers the shoulders and upper arms,
  **open at the front** (a vertical gap of ~0.10-0.14 m shows the grey shirt
  down the chest — `detail_cape_front_open.png`, `view_34_front_*`).
* **Length:** from the neck to about the crotch / shorts hem at the sides and
  back (hem at 0.60-0.63 m); the front edges hang to about the same height.
* **Shape:** an A-line / bell drape: ~0.30 m wide at the shoulders flaring to
  ~0.50-0.55 m across at the hem when hanging still (in action poses it flares
  out much wider, `view_34_lunge_cape_flare.png`). The arms are *inside* the
  cloak: when an arm is raised, the cloak edge rides up with it and forms a
  wide "sleeve" flap (`view_34_front_right_sword_out.png`) — rig it so the side
  panels can follow the arms (see rig section).
* **Hood (lowered):** lies on the upper back as a pointed, cone-like flap whose
  tip points down the spine and reaches the shoulder blades (~0.95-1.0 m);
  ~0.22 m wide at the neck. Seen from above it is a large teardrop behind the
  head (`detail_cape_hood_back.png`, `view_back_high_topdown*.png`).
* **Construction:** one open cone/skirt surface: 10-12 segments around (gap at
  the front), 3-4 rings from collar to hem, Solidify 0.01-0.015 m (or a
  double-sided material — the back faces are visible when it flares). Facet it;
  do not smooth. Hood: a separate 6-10 face pyramidal flap welded/overlapping at
  the collar. Keep enough vertical edge loops (3-4) for the cape bones to bend
  it.
* At game scale the cape is the dominant silhouette from the back and 3/4
  (a brown trapezoid from the shoulders to the hips — `game_back_walk_bright.png`,
  `game_back_34_idle_bright.png`). Silhouette and flare matter; folds do not.

### Sword
* **Overall length 0.78 m** (about half the character's height): blade 0.60 m,
  guard 0.02 m, grip 0.13 m, pommel 0.03 m.
* **Blade:** in Cascadeur it is literally a long rectangular bar
  (`detail_sword.png`), ~0.035 m wide x 0.015 m thick, light grey `#A8A8A8`, with
  a squared-off/beveled tip. Model it as a 4-6 sided prism (a flattened diamond
  cross-section gives a cutting-edge highlight), optionally with a short
  2-face point. In game it is a 1-px light dotted line — thinness and length
  matter, detail does not.
* **Guard:** a small cross bar 0.08 x 0.02 x 0.02 m (not clearly visible in the
  references; keep it subtle). **Grip:** 6-sided cylinder Ø 0.025 m, dark
  (`#393A39` or dark brown `#572B11`). **Pommel:** 0.03 m cube or sphere.
* **Orientation convention (from the devlog, `model.txt`):** "blue axis points
  outward [along the blade], red axis toward the cutting edge"; swings rotate
  about green. Required in the **engine (Godot/glTF) frame**: local **+Z = along
  the blade toward the tip**, local **+X = toward the cutting edge**, local
  **+Y = blade flat normal** (the swing axis). Because the exporter maps Blender
  (x, y, z) -> (x, z, -y), author the sword in Blender with:
  * origin at the centre of the grip (the hand pivot);
  * blade extending along Blender local **-Y**;
  * cutting edge toward Blender local **+X**;
  * blade flat facing Blender local **+Z**.
  Verify after a test export: in Godot, the sword node's basis.z should point
  from grip to tip.
* Parent: a `prop.sword` bone (child of `DEF-hand.R`, head at the grip centre,
  bone tail pointing along the blade) or object-parent the sword to
  `DEF-hand.R`. Keep the sword as a **separate mesh object** (the engine attaches
  a smear-generation script to it).

## 5. Colours (from `palette.png`; flat albedo, sampled from the Cascadeur render)

| Part | Hex |
|---|---|
| Hair, fringe, side locks, bun | `#E7E7E7` (use `#E8E8E8`) |
| Skin (face, ears, hands; legs if bare) | `#D6A28C` |
| Eyes, belt buckle | `#0B0000` -> use `#101012` |
| Undershirt / sleeves | `#393A39` |
| Neck band / collar | `#997967` |
| Cape, hood | `#592B0D` |
| Tunic skirt / shorts | `#784F36` |
| Tights (Cascadeur) | `#000000` -> use `#141418` |
| Boots | `#572B11` (can go a touch lighter, `#5E3216`, to separate from the cape) |
| Belt | near-black `#1D120E` |
| Sword blade / guard | `#A8A8A8` |
| Sword grip | `#393A39` (guess) |

The in-game swatches in `palette.png` are graded (dark scene + post grade) and
are only for checking the final look, not for material albedo.

## 6. Rig

Humanoid, Rigify-compatible deform naming (the artist's Cascadeur rig shows
`DEF-spine.004`, `DEF-shoulder.R`, `DEF-upper_arm.R`, `DEF-forearm.R`,
`DEF-hand.R`, and tracks `Body / Head / Arm_L / Arm_R / Legs`). A full Rigify
meta-rig is fine; export only the `DEF-*` bones (+ root and the extra bones
below) to glTF.

```
root                          (at origin, Y-forward tail, no deform)
└ DEF-spine        (hips, ~0.70 m)
  ├ DEF-thigh.L/R → DEF-shin.L/R → DEF-foot.L/R → DEF-toe.L/R
  └ DEF-spine.001 → DEF-spine.002 → DEF-spine.003 (chest)
      ├ DEF-spine.004 (neck) → DEF-spine.005 → DEF-spine.006 (head, 1.19→1.50 m)
      │    ├ DEF-hair_bun            (optional, for a little bounce)
      │    └ DEF-ear.L/R             (optional)
      ├ DEF-shoulder.L/R → DEF-upper_arm.L/R → DEF-forearm.L/R → DEF-hand.L/R
      │                                                   └ prop.sword (R only)
      ├ DEF-cape_back.001 → .002 → .003         (centre back strip)
      ├ DEF-cape_back.L.001 → .002 → .003       (back-left strip)
      ├ DEF-cape_back.R.001 → .002 → .003
      ├ DEF-cape_side.L.001 → .002              (over the left arm)
      ├ DEF-cape_side.R.001 → .002
      ├ DEF-cape_front.L.001 → .002             (front edge flaps)
      ├ DEF-cape_front.R.001 → .002
      └ DEF-hood.001 → .002                      (hood flap, tip down the back)
```

* The cape chains root at the chest/shoulder line (child of `DEF-spine.003`),
  hang straight down in rest, and are weighted in vertical bands with smooth
  falloff between neighbouring strips. They are for hand-keyed / simulated
  secondary motion (the devlog adds cape follow-through after the swing).
* The side strips over the arms may additionally take ~30-50 % weight from
  `DEF-upper_arm.*` near the shoulder so raising an arm lifts the cloak edge.
* Mitten hands: no finger bones needed (optionally `DEF-thumb.*` for the sword
  grip).
* Weighting: mostly rigid per segment (low poly); smooth only across elbows,
  knees, shoulders and the cape bands.

## 7. Rest pose

* **A-pose:** arms ~40 deg below horizontal (as in `view_front_apose.png`),
  elbows bent ~10 deg, palms facing the thighs/inward-down. Legs straight, feet
  0.15 m apart (centre to centre), toes forward.
* Cape and hood modelled hanging straight down in the rest pose, not flared.
* Sword in rest: in the right hand, blade pointing forward-down along the
  forearm's natural line, or parked straight down; it is skinned to/parented to
  the hand so the exact rest angle is not critical, but the grip must sit inside
  the closed mitten.

## 8. What matters at game scale (pixelized, ~30-40 macro px tall)

Keep / exaggerate: white hair blob + bun peak; ear spikes; the dark eye slit;
the cape trapezoid and its flare; light shirt-vs-cape contrast at the open
front; leg-vs-boot contrast; long thin sword.
Skip or keep minimal: belt and buckle, collar band, shorts rim, fingers, any
fold detail in the cape, sword guard/pommel detail.

## 9. Uncertainties and best guesses

1. **Leg colour.** Cascadeur shows black tights; all in-game frames show pale
   legs close to the shaded skin tone. Best guess: the in-game build uses bare
   legs or pale leggings. Default to near-black tights (the Cascadeur model is
   the explicit model reference) but put the legs on their own material so it
   can be switched to skin `#D6A28C` in one step.
2. **Cape in the front view.** The only level front view has the cape hidden,
   so the cape's front opening width, front-edge length and collar are inferred
   from high 3/4 views.
3. **No true side or back view** exists in Cascadeur; the back of the cape,
   hood and hair come from top-down action frames and from tiny in-game back
   views. The hood is assumed to be a single pointed flap lying flat on the back.
4. **Boots vs cape colour** are nearly identical in the flat render; the
   in-game image separates them more (boots darker). A slightly different brown
   is acceptable.
5. **Sword hilt** is always hidden in the hand; guard, grip and pommel are
   guesses. The in-game scene prop sword stuck in a rock has an olive-yellow
   hilt (`#A4A873`), which may or may not be the same sword — not used here.
6. **Exact size.** 1.50 m is a proposal from head-count and checker-tile
   ratios; scale uniformly if the project needs another value (keep 4.85 heads).
7. **Neck band** `#997967`: could be a scarf, a collar of the cape, or the
   cape's lining. Modelled as a short collar ring.
8. The faint lavender ghost/outline around the figure in the front view is the
   Cascadeur selection highlight, not geometry.
