# Enemy — reference frames

Curated frames extracted with ffmpeg from `docs/references/videos/enemy.mp4`
(17.05 s, 1920x1080 @ 60 fps). Every `*.png` here is a full 1920x1080 frame
grabbed with an accurate seek.

**This clip is not a plain gameplay capture — it is a screencast of the Unity
editor with two panels side by side, and the split never moves:**

* **left half** = Unity **Scene view**, "Shaded" mode, bright light-grey
  checkerboard floor, the pixelation post-process not applied;
* **right half** = Unity **Game view** ("Display 1", `2x (1280x720)`, Scale
  slider at `3x`), the same scene rendered through the project's pixel-art
  pipeline — dark violet grade, visible macro-pixels, a blooming red eye.

Both halves are inside every kept frame, so each frame carries the model *and*
its pixelated result. Naming: `enemy_<ss.ss>s.png`; the `_crop.png` companion is
a 2x `neighbor` upscale of a tight crop — frames 00.00–04.00 crop the **Scene
view** mech (true colours, clean shape), later frames crop the **Game view**
mech (the pixelated look; it is smaller in frame, so a crop is needed to read
it). `contact_sheet.png` shows all 17 kept frames.

Subject: a low-poly **quadruped mech** ("walker") — a boxy head/body with a
glowing red sensor panel on the front, black stripe bands along the flanks, four
splayed insect-like legs and a thin antenna on top. A plain **white cube** sits
under/at the front of the mech in every frame (a separate untextured object in
the scene, not part of the model's silhouette). Around 6–7.5 s a bright
white/yellow **muzzle flash** appears at the mech's front-left.

## What the clip contains

| Range | Content |
|---|---|
| 0.0–4.5 s | Mech walking on the checkerboard floor, camera following the mech. The mech rotates through front, front-left and front-right angles; the white cube stays at its front. |
| 4.5–8.5 s | Same scene, game view emphasised: the pixelated render of the walk, ending with the muzzle flash (6.0 s and 7.5 s) and the mech rearing. |
| 8.5–17.0 s | The mech keeps walking and slowly turning (front 3/4 to side views); the clip ends mid-walk at 16.0 s. |

## Colours (approximate, sampled from the frames)

| Element | Scene view (left panel) | Game view (right panel) |
|---|---|---|
| Floor | light grey checkerboard `#C8C8C8` / `#9898A8` | dark violet checkerboard `#584868` / `#786888` |
| Mech body | pale blue-grey `#A4B2C9` on top, `#7B7F9C` in shade | lavender `#A8A8B8`–`#C0B8C8` on the lit faces |
| Mech stripes | pure black `#000000` | near-black, banded |
| Eye / sensor | pure red `#FF0000` (emissive, unshaded) | hot red `#D80E23` with an orange-white core and a bloom halo |
| White cube | white, `#E8E8E8`–`#FFFFFF` lit / cool grey in shade | white, blown out by the grade |
| Editor chrome | Unity dark theme: near-black `#080808` bars with white `#F8F8F8` text/icons | same |

## On-screen text (what the UI tells us)

* Menu bar: **File, Edit, Assets, GameObject, Component, Tools, Window, Help** —
  this is **Unity**, not Godot/Unreal.
* Scene view toolbar: the scene name renders as `# Scene`, plus `Shaded`, `2D`
  (enabled), `Gizmos`, `All`.
* Right of the toolbar: `Account`, `Layers`, `Recording`.
* Game view: tab `Game`, `Display 1`, `2x (1280x720)`, `Scale` (at `3x`),
  `Maximize On Play`, `Mute Audio`, `Stats`, `Gizmos`; play/pause/step transport
  buttons to the left of the tab.
* No asset/object names, bone names or hierarchy text is legible — the
  Hierarchy/Inspector panels are not on screen.

## Frames

| File | Crop file (panel) | t (s) | What it shows |
|---|---|---|---|
| `enemy_00.00s.png` | `enemy_00.00s_crop.png` (Scene) | 0.00 | Mech standing on all four legs, seen from the front-left, eye panel facing the camera-left; white cube under the front-right leg. |
| `enemy_01.00s.png` | `enemy_01.00s_crop.png` (Scene) | 1.00 | Same angle, legs spread wider mid-step, cube pushed forward. |
| `enemy_02.00s.png` | `enemy_02.00s_crop.png` (Scene) | 2.00 | Mech turned — now viewed from its front-right; body raised, walking. |
| `enemy_03.00s.png` | `enemy_03.00s_crop.png` (Scene) | 3.00 | Mech rotated further (near-frontal), legs crossed mid-stride. |
| `enemy_04.00s.png` | `enemy_04.00s_crop.png` (Scene) | 4.00 | Front-left 3/4, eye to camera, cube under the front legs — the clearest untextured read of the model. |
| `enemy_04.50s.png` | `enemy_04.50s_crop.png` (Game) | 4.50 | Pixelated version of the same walk; the eye glows with a bloom halo, macro-pixel edges visible. |
| `enemy_05.00s.png` | `enemy_05.00s_crop.png` (Game) | 5.00 | Game view, mech walking, cube in front, violet grade. |
| `enemy_05.50s.png` | `enemy_05.50s_crop.png` (Game) | 5.50 | Game view, mid-step, legs splayed. |
| `enemy_06.00s.png` | `enemy_06.00s_crop.png` (Game) | 6.00 | **Muzzle flash**: a bright white blob at the mech's front-left; the body rears back. |
| `enemy_07.50s.png` | `enemy_07.50s_crop.png` (Game) | 7.50 | Second flash, larger; the mech seen more from behind/above. |
| `enemy_08.50s.png` | `enemy_08.50s_crop.png` (Game) | 8.50 | Game view, walking, front 3/4, cube clearly visible. |
| `enemy_09.50s.png` | `enemy_09.50s_crop.png` (Game) | 9.50 | Seen from the front-top: all four legs splayed outwards, eye centred. |
| `enemy_10.50s.png` | `enemy_10.50s_crop.png` (Game) | 10.50 | Front 3/4, eye bright, antenna silhouetted against the floor. |
| `enemy_11.50s.png` | `enemy_11.50s_crop.png` (Game) | 11.50 | Side-front, mid-stride, cube nearest the camera. |
| `enemy_13.50s.png` | `enemy_13.50s_crop.png` (Game) | 13.50 | Near-frontal walk with the cube directly in front of the legs. |
| `enemy_15.50s.png` | `enemy_15.50s_crop.png` (Game) | 15.50 | Front 3/4, walking; the black stripe bands read clearly against the lit panels. |
| `enemy_16.00s.png` | `enemy_16.00s_crop.png` (Game) | 16.00 | Last frame of the clip: front 3/4, mid-step. |
