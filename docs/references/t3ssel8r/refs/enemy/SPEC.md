# Enemy (quadruped walker mech) — modelling spec

Target: a small, boxy, low-poly walker drone built entirely from axis-aligned
boxes, flat shaded, solid colours, rendered through a pixelization pass.
Recreate the mech from t3ssel8r's Unity test clip (`enemy.mp4`).

All references are next to this file (see `../README.md`). The bright Unity
**Scene view** crops (`view_*`, `detail_*`) are the model reference; the
`game_*` crops are the same mech through the pixel-art pipeline (`*_bright` =
levels-adjusted). `view_*.png` have the floor flat-filled dark grey; the
`view_*_raw.png` twins keep the original background — use those to see the
**thin antenna**, which the background clean-up removed. `turnaround.png` =
five views at one scale with 0.1 m lines; `palette.png` = sampled colours.

**Ignore in every image:**
* the **white box with a smaller white block under/in front of it** — a separate
  untextured scene object, not part of the mech (see uncertainty 1);
* the **yellow ellipse, thin red/blue arcs and the mouse cursor** — Unity
  selection/rotation gizmos;
* the Unity axis gizmo in the corner.

All views are from a high camera (~35-45 deg down); there is no level
orthographic view. Feet therefore sit low in frame and vertical edges are
foreshortened.

---

## 1. Scale, units, orientation

| Item | Value |
|---|---|
| Units | metres, scale 1.0, transforms applied |
| Height to top of roof ridge | **0.90 m** (≈ 0.6 x the 1.50 m player) |
| Antenna tip | ~1.30 m |
| Leg footprint (outer foot edges) | ~1.15 m wide x 1.05 m long |
| Origin | floor level, centred under the hull (between the four feet) |
| Facing in Blender | **-Y** forward (eye panel faces -Y), up = +Z, mech's left = +X |
| Export | glTF 2.0, +Y up |

Size justification: the clip never shows the player and the mech together, so
the size is a proposal. Measured against the Unity checkerboard in the Scene
view, the hull is ~0.4-0.5 floor-tile sides wide and the leg span ~1.9-2.2 hull
widths; assuming 1 m tiles (the same assumption that gives the player 1.5 m in
its own arena) the hull is ~0.48 m wide and the whole mech ~0.9 m to the roof.
That makes it a knee-to-chest-high drone next to the 1.5 m player — readable
and threatening without dwarfing the character. Scale uniformly if needed.

Axis note: Blender (x, y, z) exports to glTF/Godot (x, z, -y), so the mech
faces **+Z** in Godot (`Vector3.MODEL_FRONT`). Rotate 180 deg in Godot (or use
`look_at(..., use_model_front = true)`) if game code treats -Z as forward.

## 2. Part list (all boxes unless noted; coordinates in Blender, metres)

Hull centre at (0, 0, 0.64). Front = -Y.

| # | Part | Size X x Y x Z (m) | Position / notes |
|---|---|---|---|
| 1 | **Hull** (head + body in one) | 0.48 x 0.62 x 0.40 | z 0.44-0.84, front face at y = -0.31. Main mass; a slightly long box (length ≈ 1.3-1.5 x height in side views). |
| 2 | **Eye bezel** (black) | 0.22 x 0.015 x 0.20 | on the front face, centred in X, centre z ≈ 0.60 (lower half of the face). Protrudes 0.015. |
| 3 | **Eye** (red, emissive) | 0.14 x 0.01 x 0.13 | centred inside the bezel, flush or 0.005 recessed. Unshaded/emissive; blooms in game. |
| 4 | **Vent bars** (black), 2 per side | 0.03 x 0.40 x 0.03 each | on both side faces, standing 0.01 proud (x = ±0.255), at z ≈ 0.53 and 0.59 (gap 0.03), running from y ≈ -0.01 (mid-hull) forward to y ≈ -0.41, i.e. **sticking 0.10 past the front face** like mandibles. Seen from the front they read as vertical black bars beside the eye. |
| 5 | **Roof ridge** | 0.20 x 0.50 x 0.06 | centred on top, from y -0.27 to +0.23, z 0.84-0.90. A notch 0.06 wide x 0.06 deep at its front end gives two small front prongs (front view: "castellated" top). |
| 6 | **Roof rear step** | 0.26 x 0.16 x 0.04 | on top of the ridge's rear end (y +0.07 to +0.23) — the stepped profile seen in side views. Optional. |
| 7 | **Side pods** (2) | 0.07 x 0.28 x 0.13 | one on each flank, rear half (y -0.02 to +0.26), z 0.62-0.75, protruding 0.07 beyond the hull side. They make the hull look wider at the "shoulders" in the front view. |
| 8 | **Rear block** | 0.40 x 0.10 x 0.32 | behind the hull, y +0.31 to +0.41, z 0.47-0.79. |
| 9 | **Rear corner slabs** (2) | 0.07 x 0.12 x 0.38 | at the rear corners, overlapping hull + rear block, z 0.45-0.83; a small black wedge notch between slab and side pod is visible on the left rear (`detail_body_top_rear.png`) — optional black triangle. |
| 10 | **Belly hub** (cylinder, 8 sides) | Ø 0.20 x 0.06 | under the hull centre, z 0.38-0.44. Legs visually emerge from around it. Optional (mostly hidden). |
| 11 | **Antenna** (cylinder, 4-6 sides) | Ø 0.012 x 0.42 | vertical, base on the roof at (-0.10, +0.15, 0.88), tip ≈ 1.30 m. Light grey. Reads as a 1-px line in game — keep it. |
| 12 | **Cables** (2, thin tubes) | Ø 0.012, ~0.35 long | red, drooping loops from each side pod down to the rear hip. Visible as red streaks in the game view; optional, 3-4 segment curves. |

### Legs (×4, identical, mirrored)

Hips sit just inside the hull's bottom corners. X = mech left(+)/right(-),
Y = forward(-)/back(+):

| Joint | FL | FR | BL | BR |
|---|---|---|---|---|
| Hip (thigh root) | (+0.22, -0.20, 0.47) | (-0.22, -0.20, 0.47) | (+0.22, +0.20, 0.47) | (-0.22, +0.20, 0.47) |
| Knee | (+0.47, -0.43, 0.30) | (-0.47, -0.43, 0.30) | (+0.47, +0.43, 0.30) | (-0.47, +0.43, 0.30) |
| Ankle / foot | (+0.55, -0.50, 0.03) | (-0.55, -0.50, 0.03) | (+0.55, +0.50, 0.03) | (-0.55, +0.50, 0.03) |

(FL = front-left = the mech's left = +X, front = -Y.)

* Legs splay diagonally (an X in plan view, ~45 deg from the forward axis).
* **Thigh:** box 0.38 long x 0.11 tall x 0.08 thick, pitched ~25-30 deg below
  horizontal, from hip to knee. Most legs show a second, slightly shorter
  parallel plate on the outer side (0.28 x 0.09 x 0.04, offset 0.04 outward) —
  the "double plate" look in `detail_legs_side.png`; include it.
* **Shin:** box 0.32 long x 0.09 x 0.09, from knee to ankle, ~15-20 deg off
  vertical (leaning outward).
* **Foot:** the shin ends in a chunkier block 0.12 x 0.12 x 0.06 sitting flat on
  the floor (bottom at z = 0), slightly offset outward — no toes.
* No visible joint geometry: segments simply overlap at the knee. If desired, a
  small cube (0.10) at each knee and hip hides the intersection when posed.

Construction: every part is a plain box (8 verts) — target **400-800
triangles** total. No bevels (Unity source has hard 90-degree edges; game view
draws a light rim along edges via the outline pass). Flat shading.

## 3. Colours (from `palette.png`)

The Unity Scene view is lit, so the hull shows several tones of one albedo:
lit top `#C0C8D0`, lit side `#B4C9DC`, front/mid `#8DA0B4`, shade `#6E7C9F`.

| Part | Hex |
|---|---|
| Hull, roof, pods, rear parts, legs (one material) | **`#A9BAD2`** (pale blue-grey; average of the lit faces) |
| Eye (emissive / unshaded) | `#FF0000` (sampled `#F80206`); emission strength high enough to bloom; in game it shows an orange-white core `#FCD599` from the grade + bloom |
| Eye bezel, vent bars, rear notch | `#000000` (use `#050508`) |
| Cables | `#C02028` |
| Antenna | `#D8DCE4` |

Game-view reference (graded, comparison only): lit hull `#AEA1C0`, shade
`#5D4C68`, eye `#C10729`-`#D80E23`.

## 4. Rig

Simple mechanical rig, rigid weights (each box 100 % to one bone).

```
root                                   (origin, floor)
└ DEF-body                             (hull centre, z 0.64; hull, eye, vents, roof,
   │                                    pods, rear parts, hub, cables' upper ends)
   ├ DEF-antenna                       (base on the roof; optional jiggle)
   ├ DEF-leg_hip.FL  → DEF-leg_upper.FL → DEF-leg_lower.FL → DEF-leg_foot.FL
   ├ DEF-leg_hip.FR  → DEF-leg_upper.FR → DEF-leg_lower.FR → DEF-leg_foot.FR
   ├ DEF-leg_hip.BL  → DEF-leg_upper.BL → DEF-leg_lower.BL → DEF-leg_foot.BL
   └ DEF-leg_hip.BR  → DEF-leg_upper.BR → DEF-leg_lower.BR → DEF-leg_foot.BR
```

* `DEF-leg_hip.*`: short bone at the hip, yaw (Z) rotation only — swings the
  whole leg forward/back for walking.
* `DEF-leg_upper.*`: hip-to-knee (thigh plates). `DEF-leg_lower.*`:
  knee-to-ankle (shin). `DEF-leg_foot.*`: the foot block (keeps it flat).
* Non-deform IK controls (Blender only, not needed in export): `IK-foot.FL/FR/BL/BR`
  at the feet with pole targets above-outside each knee, so walk cycles can
  plant feet. The clip's gait is a diagonal-pair walk (FL+BR, FR+BL) with the
  body bobbing and occasionally rearing back (recoil at the muzzle flash).
* Optional `DEF-eye` (child of body) if the eye panel should be animated or
  have its own emissive material instance.
* Cables: skin the upper half to `DEF-body`, the lower half to the matching
  `DEF-leg_upper.B*`, or leave them rigid on the body.

## 5. Rest pose

Standing pose exactly as in section 2 (legs splayed, feet flat, body level at
hull bottom z = 0.44). Forward = -Y. No T-pose needed.

## 6. What matters at game scale

Keep: the red eye (brightest, blooming pixel cluster), the black eye bezel and
the two black vent bars per side (they read as dark stripes on the lit hull),
the boxy hull + roof ridge silhouette, the splayed four-leg silhouette with
thick thighs, the antenna line, the red cables (1-2 px red streaks).
Skip/simplify: belly hub, rear corner slabs, roof rear step, the black rear
notch, knee caps.

## 7. Uncertainties and best guesses

1. **The white box.** It always sits at the mech's front/underside and the
   muzzle flash (6.0 s, 7.5 s) appears right where it is; it may actually be an
   untextured gun/arm attached to the mech, or a placeholder (e.g. a stand-in
   player). Per the brief it is excluded. If a weapon is wanted later, a white
   box ~0.12 x 0.30 x 0.12 hung under the front of the hull would match.
2. **Absolute size** (see section 1): proposal, not measured against the player.
3. **Underside and rear** are only seen obliquely: the belly hub, rear block and
   rear slabs are approximations of stacked boxes; the exact stepping of the
   roof and rear is uncertain.
4. **Vent bars:** interpreted as two horizontal bars per side protruding past
   the front face. They could also be recessed slits with black inner faces;
   the protrusion past the front face in the side views suggests bars.
5. **Leg joint layout:** thigh/shin lengths are estimated from foreshortened
   views (±20 %). Whether a separate hip yaw joint exists is inferred from the
   walk (legs swing forward/back).
6. **Antenna** base position and length are estimated from 1-2 px lines
   (`*_raw.png`, game views); length ±0.1 m.
7. **Hull albedo:** the scene is lit with a coloured ambient; `#A9BAD2` is an
   average of lit faces. Pick a value between `#A9BAD2` and `#B4C9DC` if the
   Godot lighting renders it too dark.
