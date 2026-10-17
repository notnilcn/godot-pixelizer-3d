# t3ssel8r modelling references

Cleaned reference images and modelling specs for two models: the **player**
(white-haired elf swordsman with a brown cloak) and the **enemy** (boxy
four-legged walker mech). Start with each subject's `SPEC.md`; every image it
cites is in the same folder.

Sources: frames from `docs/references/videos/model2.mp4`, `model3.mp4`
(player) and `enemy.mp4` (enemy) — see `../frames/*/index.md` for the original
full frames. Some extra frames (model3 at 1.0 / 2.0 / 3.6 / 4.0 s, enemy at
6.00-10.50 s) were extracted from the same videos for back/side angles.

Conventions used in the image files:
* Smooth viewport crops (Cascadeur / Unity Scene view) were scaled with Lanczos;
  pixelated in-game crops with nearest-neighbour (integer factor).
* `*_bright.png` = levels-adjusted copy of a dark in-game crop (shape reading
  only; colours are not accurate).
* Player `view_*`: background flat-filled `#8E959E` except `view_front_apose.png`
  (original background kept, because the clean-up ate the pale sword).
* Enemy `view_*`: floor flat-filled `#4E5258`; `view_*_raw.png` = same crop with
  the original background (shows the thin antenna, which the clean-up removes).
* Enemy images: ignore the white box with a small block under it (separate
  scene object) and the yellow/red/blue Unity gizmos.
* All source cameras look down 30-45 deg; there are no true orthographic views.

## player/

| File | Content |
|---|---|
| `SPEC.md` | Modelling spec: 1.50 m, 4.85 heads, part breakdown, colours, rig, rest pose, export axes, uncertainties |
| `turnaround.png` | Front / 3/4 front-left / 3/4 front-right / in-game side / in-game back at one scale, head-height lines |
| `palette.png` | Patch-averaged swatches with hex (model albedo + graded in-game comparison) |
| `view_front_apose.png` | Near-level front view, A-pose (cape hidden in this frame) — body proportions |
| `view_34_front_left_idle.png`, `view_34_front_right_idle.png` | Standing 3/4 views with cape — main model reference |
| `view_34_front_right_sword_out.png` | Standing, arm raised: cape side panel lifts with the arm |
| `view_34_front_left_windup.png`, `view_34_leap.png`, `view_34_lunge_cape_flare.png` | Action poses (cape flare, sword length) |
| `view_back_high_topdown.png`, `view_back_high_topdown_b.png`, `view_back_left_high_crouch.png` | Back / top-down: lowered pointed hood, cape back, top-knot |
| `detail_head_front.png`, `detail_head_34_left.png`, `detail_head_34_right.png` | Face (two black eye rectangles), elf ears, fringe, side locks |
| `detail_hair_topknot_from_above.png` | Hair shell + bun from above |
| `detail_cape_hood_back.png`, `detail_cape_front_open.png` | Hood flap on the back; open cloak front |
| `detail_torso_belt_front.png` | Shirt, belt buckle, shorts |
| `detail_sword.png`, `detail_sword_front.png` | Sword (rectangular bar blade) |
| `game_back_walk(.._bright).png` | In-game back view (walking away) |
| `game_back_34_idle`, `game_back_cape_flare_close` (+`_bright`) | In-game back 3/4, cape silhouette |
| `game_side_facing_left` (+`_bright`) | In-game side view |
| `game_34_idle_sword`, `game_34_sword_lowered`, `game_34_sword_beside_rock` (+`_bright`) | In-game front 3/4 with sword (pale legs visible) |
| `game_swing_side` (+`_bright`) | In-game horizontal swing |

## enemy/

| File | Content |
|---|---|
| `SPEC.md` | Modelling spec: 0.90 m to roof, box-by-box part table with coordinates, leg joint table, colours, rig, uncertainties |
| `turnaround.png` | Front / left side / rear 3/4 / 3/4 front-left / 3/4 front-right at one scale, 0.1 m lines |
| `palette.png` | Patch-averaged swatches with hex (scene-view tones, suggested albedo, graded game comparison) |
| `view_front(_raw).png` | Front: eye panel, vent bars end-on, castellated roof, side pods |
| `view_side_left`, `view_side_left_b`, `view_side_left_c` (+`_raw`) | Left side (front to the right): vent bars past the front face, roof step, side pod |
| `view_side_right(_raw).png` | Right side (front to the left) |
| `view_rear_34_left(_raw).png` | Rear 3/4: rear block, rear slabs, black notch |
| `view_34_front_left`, `view_34_front_left_b`, `view_34_front_right_high` (+`_raw`) | Front 3/4 views — clearest overall read |
| `detail_head_eye_vents_34.png`, `detail_head_front_eye.png` | Eye bezel + red eye, vent bars |
| `detail_head_body_side.png`, `detail_body_top_rear.png` | Hull side, roof steps, rear parts |
| `detail_legs_side.png` | Double-plate thighs, shins, feet |
| `game_04_00s` … `game_15_50s` (+`_bright`) | Pixelated Game-view crops (blooming eye, red cables, antenna line) |
