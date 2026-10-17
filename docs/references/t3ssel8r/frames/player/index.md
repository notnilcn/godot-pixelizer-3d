# Player character — reference frames

Curated frames extracted with ffmpeg from `docs/references/videos/model2.mp4`
(24.0 s) and `docs/references/videos/model3.mp4` (20.0 s), both 1920x1080 @ 60 fps.
Every `*.png` here is a full 1920x1080 frame grabbed with an accurate seek.

Naming: `<clip>_<ss.ss>s.png` (timestamp within that clip). A companion
`<clip>_<ss.ss>s_crop.png` is a tight crop around the character, upscaled 2x with
`scale=iw*2:ih*2:flags=neighbor` so the pixel-art edges stay crisp — the
character is only ~170–350 px tall in the in-game footage. The in-game crops are
`crop` of the original frame; nothing else is altered (no brightening, no
colour correction). `contact_sheet.png` shows all 29 kept frames at a glance.

Subject: a low-poly humanoid with white/silver hair, a brown cape + tunic, boots
and a straight grey sword, seen both in the animation tool (Cascadeur) and
in-game after the pixelation pass. The white crescent/swoosh that appears during
attacks is the sword **smear mesh**, generated in-engine (see the workflow
transcript `docs/references/videos/model.txt`: a script measures the sword's
per-frame motion and sweeps a Bezier-interpolated smear along the blade, with a
texture that gets streakier as it fades out).

## What each clip contains

| Clip | Range | Content |
|---|---|---|
| model2 | 0.0–2.5 s | Fade-in from black; the character is barely lit, walking away from the camera. Not kept (unusable). |
| model2 | 2.5–5.0 s | Still dark; the character walks away from the camera on the dark checkerboard arena, camera following. |
| model2 | 5.0–9.0 s | Lit section: the character walks around a grey rock that has a thin sword stuck upright in it (olive-yellow hilt). |
| model2 | 9.0–13.5 s | Combat: first big sword swings — the smear mesh arcs around the body. |
| model2 | 13.5–19.5 s | Continued combat: lunges, crouches, spins, more smear arcs; the camera follows from a high 3/4 angle. |
| model2 | 19.5–24.0 s | More swings and running; ends on a swing with the smear trailing. |
| model3 | 0.0–0.5 s | Cascadeur 2021.1EA editor, full UI visible (menus, two viewports, outliner, tracks/timeline). |
| model3 | 0.5–8.4 s | Cascadeur viewport only (diamond floor grid): a two-hit sword attack animation played back, posed from several angles — anticipation, leap, swing, lunge, recovery. |
| model3 | 8.4–18.0 s | Hard cut to in-game footage (dark checkerboard arena, same character), walking then a spinning attack with the smear. |
| model3 | 18.0–20.0 s | Fades to black; the tail of the clip is unusable. |

## Colours (approximate, sampled from the frames)

| Element | In-game (model2 / model3 after 8.4 s) | Cascadeur viewport (model3 before 8.4 s) |
|---|---|---|
| Floor | dark neutral checkerboard `#282828` / `#283838`, lighter pair near the camera `#383838` / `#384848` | flat light grey `#D8D8D8` with a lighter diamond floor grid |
| Cape / tunic | warm grey-brown `#706058`–`#786058` | dark rust brown `#592B0D`–`#653A1F`, lit folds `#785038` |
| Hair | `#98A0A8` (brightest thing in frame) | white `#E8E8E8`–`#FFFFFF` |
| Skin (face, hands, bare legs) | desaturated by the dark grade | warm peach `#DDA284` |
| Legs / tights | pale (bare legs read grey-brown under the grade) | pure black `#000000` (tights) |
| Boots | dark brown | brown (lighter than the robe) |
| Sword blade | light grey | light grey `#A8A8A8` |
| Sword smear | `#B0B8B8` → `#C8D0D8` (pale cool white) | — (no smear in Cascadeur) |
| Shadow | near-black `#101018`–`#181818`, long and soft | soft grey |
| Prop rock (with sword) | lit top `#968E83`, shaded side `#606072`; sword hilt olive `#A4A873` | — |

## On-screen text / software (what the UI tells us)

* **Cascadeur 2021.1EA Base** — watermark at the bottom-left of each Cascadeur
  viewport (`model3_00.05s.png`).
  * Menu bar: File, Edit, View, Filters, Mirror tool, Timeline, Interpolation,
    Objects, Synchronization, Settings, Help.
  * Document tab: **`character_attack_001`** — the file being edited is the
    sword-attack clip.
  * Tracks panel: `Scene` → `Body`, `Head`, `Arms` (`Arm_R`, `Arm_L`), `Legs`,
    with keys marked `FH`; timeline ruler 0–30 frames with a `1.00 sec` field.
  * Outliner (Name / Type / Track columns) lists rig points, truncated in the
    UI: `DEF-ha…`, `DEF-spine_004`, `DEF-shoulder`, `DEF-upper_a…`,
    `DEF-forear…`, `DEF-for… Limb Direction` (types `Point` / `Body`, tracks
    `Arm_L`, `Arm_R`, `Body`), plus `Number of selected objects: 0` and an
    `Object properties` panel. The `DEF-…` naming is a Blender/Rigify-style
    deform-bone rig, so the character was authored in Blender and rigged before
    import.
  * The second viewport at `model3_00.05s.png` shows the same rig as a skeleton
    with Cascadeur's auto-posing handles.
* In-game HUD: a small white pixel-font label **`Inventory`** at the bottom
  right of every in-game frame (≈ x 1830–1872, y 938–946).

## Frames

One row per kept frame; the `_crop.png` companion shows the same timestamp,
framed on the character.

| File | Crop file | t (s) | Clip | What it shows |
|---|---|---|---|---|
| `model2_05.00s.png` | `model2_05.00s_crop.png` | 5.00 | model2 | In-game, high 3/4 top-down. Walking away from the camera (back view); head, shoulders and cape fill the crop, long soft shadow to the lower left. |
| `model2_05.50s.png` | `model2_05.50s_crop.png` | 5.50 | model2 | In-game, full-body back view: white hair, cape over a darker tunic, pale lower legs, boots; shadow stretching left. |
| `model2_06.50s.png` | `model2_06.50s_crop.png` | 6.50 | model2 | In-game. The character (left, walking right) beside the grey rock with a thin sword stuck upright in it (olive-yellow hilt) — scene prop reference. |
| `model2_07.50s.png` | `model2_07.50s_crop.png` | 7.50 | model2 | In-game, clean full-body **back view**, standing still, feet together, shadow below-left. Best silhouette reference of the cape. |
| `model2_09.20s.png` | `model2_09.20s_crop.png` | 9.20 | model2 | In-game, side view standing beside the rock (rock at the left edge), sword arm down. |
| `model2_10.00s.png` | `model2_10.00s_crop.png` | 10.00 | model2 | In-game, side / 3-4 view mid-stride with the sword held out to the left; speckled dark shadow under the feet. |
| `model2_11.20s.png` | `model2_11.20s_crop.png` | 11.20 | model2 | In-game, 3/4 back view standing, sword hanging at the right side. |
| `model2_12.00s.png` | `model2_12.00s_crop.png` | 12.00 | model2 | In-game attack: the character kneels while the pale smear sweeps in from the left — the widest smear pose in the clip. |
| `model2_13.50s.png` | `model2_13.50s_crop.png` | 13.50 | model2 | In-game attack: kneeling inside a smear arc that wraps around the body. |
| `model2_14.50s.png` | `model2_14.50s_crop.png` | 14.50 | model2 | In-game: crouched / rolling recovery pose, sword held low, facing left. |
| `model2_15.50s.png` | `model2_15.50s_crop.png` | 15.50 | model2 | In-game, mid-swing: standing, sword extended left in a flat horizontal swing (side view). |
| `model2_17.50s.png` | `model2_17.50s_crop.png` | 17.50 | model2 | In-game, lunging action pose: torso twisted, sword out to the right, weight forward. |
| `model2_18.50s.png` | `model2_18.50s_crop.png` | 18.50 | model2 | In-game attack: crouched with the smear sweeping around the body, arc opening to the left. |
| `model2_19.00s.png` | `model2_19.00s_crop.png` | 19.00 | model2 | In-game attack: the character inside a large crescent smear (best single frame for the smear, hits the "single-frame smear" style directly). |
| `model2_21.50s.png` | `model2_21.50s_crop.png` | 21.50 | model2 | In-game, standing side view with the sword lowered along the body — calm/idle contrast frame. |
| `model2_22.50s.png` | `model2_22.50s_crop.png` | 22.50 | model2 | In-game, deep crouch with the sword pointing down-right (dive / recovery). |
| `model2_23.50s.png` | `model2_23.50s_crop.png` | 23.50 | model2 | In-game, running with the smear trailing behind the blade. |
| `model3_00.05s.png` | — (full frame only) | 0.05 | model3 | **Cascadeur 2021.1EA full editor UI**: menu bar, two viewports (left: shaded character; right: skeleton with auto-posing handles), Outliner / Scene settings, Object properties, Tracks panel and a 0–30 frame timeline. The document tab reads `character_attack_001`. |
| `model3_00.60s.png` | — | 0.60 | model3 | Cascadeur viewport, 3/4 view: standing with the sword held diagonally down; diamond floor grid, flat shading, no textures. |
| `model3_01.50s.png` | — | 1.50 | model3 | Cascadeur: leaping attack — legs mid-air, sword raised behind the head (anticipation). |
| `model3_02.50s.png` | — | 2.50 | model3 | Cascadeur: airborne, body curled forward, sword vertical behind the shoulder. |
| `model3_03.10s.png` | — | 3.10 | model3 | Cascadeur: crouched with the sword raised vertically in front of the chest. |
| `model3_04.60s.png` | — | 4.60 | model3 | Cascadeur: low lunge, sword swept horizontally to the left, cape flared. |
| `model3_05.60s.png` | — | 5.60 | model3 | Cascadeur: running thrust, sword extended forward-left — the "lunge" second hit. |
| `model3_06.60s.png` | — | 6.60 | model3 | Cascadeur: standing 3/4 with the sword drawn back across the body (wind-up / recovery). Cleanest untextured full-body reference. |
| `model3_08.50s.png` | `model3_08.50s_crop.png` | 8.50 | model3 | In-game, first frames after the 8.4 s cut: back view walking away, cape flared, sword held out to the left (the thin blade reads as a dotted line where it passes the cape); long shadow to the right. |
| `model3_11.00s.png` | `model3_11.00s_crop.png` | 11.00 | model3 | In-game: crouched with a long whip-like smear curling around the body from upper-left to right — the swing's mid-motion smear. |
| `model3_12.00s.png` | `model3_12.00s_crop.png` | 12.00 | model3 | In-game, clean back view standing, full body (cape, tunic, legs, boots), no smear — a good silhouette/model frame. |
| `model3_13.50s.png` | `model3_13.50s_crop.png` | 13.50 | model3 | In-game: crouched/airborne with the smear dissipating into a broken, fading streak to the left; hard black cast shadow below. |
