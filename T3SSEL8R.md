# T3SSEL8R.md — recreating the t3ssel8r 3D pixel-art scene

Goal: recreate the look and content of `docs/references/videos/t3ssel8r.mp4`
(a 3D scene rendered as 2D pixel art) in this project as faithfully as possible,
as a new scene `t3ssel8r/t3sell8r.tscn` built on the Pixelizer3D addon.

> Open question: the scene name was requested as `t3sell8r.tscn` while the
> video/artist is `t3ssel8r`. Using the requested spelling until told otherwise.

## Reference material (`docs/references/videos/`)

| File | What it is | Used in |
|---|---|---|
| `model2.mp4`, `model3.mp4` | player character turnarounds / animation clips (1080p60, ~20–24 s) | Phase 1 |
| `model.txt` | transcript of the animation-process devlog (Cascadeur, stepped "on twos" keys, programmatic sword smear, cape secondary motion) | Phase 1 / 4 |
| `enemy.mp4` | enemy model reference (1080p60, 17 s) | Phase 1 |
| `t3ssel8r.mp4` (+ `_old`) | the target scene | Phase 2+ (not yet) |
| `stable3d*.mp4` | pixel-stable camera motion references | Phase 3 |
| `Procedural Pixel Art Fire`, `Fire/Rain/Grass Interaction`, `Day/Night Cycle`, `Realtime Reflections` (`.mkv`) | effect references | Phase 3 |

Tools: ffmpeg/ffprobe on PATH (chocolatey); Blender 5.2 at
`C:/Program Files/Blender Foundation/Blender 5.2/blender.exe` (run headless with
`--background --python <script>`).

## Directory layout

```
docs/references/t3ssel8r/
  frames/<subject>/<clip>_<time>.png   raw extracted frames (Phase 1a)
  frames/<subject>/index.md            what each frame shows
  refs/<subject>/                      cleaned reference sheets (Phase 1b)
  refs/<subject>/SPEC.md               model spec: proportions, parts, palette
t3ssel8r/
  models/blend/<subject>.blend         Blender sources
  models/blend/build_<subject>.py      reproducible Blender build scripts
  models/<subject>.glb                 exported for Godot
  t3sell8r.tscn                        the scene (Phase 2+)
```

## Plan

### Phase 1 — models (current)
- [x] **1a. Frame extraction** (deepseek-flash agent): scene-change + interval
      sampling with ffmpeg from `model2.mp4`, `model3.mp4`, `enemy.mp4`; dedupe;
      keep frames that show distinct angles (front/side/back/3⁄4, top-down game
      view) and poses; write `index.md` per subject.
- [x] **1b. Reference curation** (Opus agent): pick the best views, crop/scale
      to the subject, build orthographic-style turnaround sheets + a colour
      palette swatch, and write `SPEC.md` (silhouette, proportions in heads,
      part list, colours as hex, low-poly/flat-shading notes, rig needs).
- [x] **1c. Modelling** (Blender agent): scripted low-poly models from the specs
      (`build_<subject>.py`, re-runnable), flat-coloured materials, simple
      armature for the player (humanoid + cape bones) and enemy; render
      turnaround PNGs to compare against the refs; export `.glb`.
- [ ] **1d. Review**: compare Blender renders against the reference sheets,
      iterate; import into Godot and check under a `PixelizerApplier3D`.

### Phase 2 — scene blockout
- [ ] Extract frames from `t3ssel8r.mp4`; catalogue terrain, props, camera angle
      and pixel size.
- [ ] Block out terrain/props; camera rig matching the video (ortho, fixed pitch).

### Phase 3 — look
- [ ] Palette/LUT, outlines, lighting, clouds/god rays, water, grass, fire,
      day/night — mapped onto existing `effects/` nodes where possible.

### Phase 4 — animation & gameplay
- [ ] Player idle/run/sword combo (stepped keys, smear mesh), enemy animation.

## Progress log

- 2026-10-16: plan created; tool check done (ffmpeg, Blender 5.2 present).
  Phase 1a started.
- 2026-10-16: **1a done.** player: 29 frames + 21 crops (model2 = in-game,
  dark checkerboard; model3 0–8.4 s = Cascadeur 2021.1 `character_attack_001`,
  bright flat-shaded — the best model reference; Rigify-style `DEF-*` bones).
  enemy: 17 frames + 17 crops — `enemy.mp4` is a Unity editor split (Scene view
  left, pixelated Game view right) of a **low-poly quadruped walker mech** with a
  red eye; the white cube in front of it is a separate scene object, not part of
  the mech. In-game crops are faithful (dark, unbrightened). Phase 1b started.
- 2026-10-16: **1b done.** `refs/{player,enemy}/` with views, turnaround,
  palette, SPEC.md. Player 1.50 m / 4.85 heads, elf ears, white top-knot hair,
  open brown cloak + lowered hood, 0.78 m bar sword, Rigify `DEF-*` + cape
  chains. Enemy 0.90 m hull-top (~0.6x player), boxy hull, red emissive eye,
  black vent bars, 4 splayed 3-segment legs. Axis note: Blender -Y exports to
  Godot +Z (`MODEL_FRONT`). Open: leg colour (Cascadeur black tights vs pale
  in-game), hilt shape, enemy scale, whether the white box is a gun arm.
  Phase 1c started (two Blender agents in parallel).
- 2026-10-17: **1c done.** `t3ssel8r/models/{player,enemy}.glb` from
  re-runnable `blend/build_*.py` (Blender 5.2, `--background --factory-startup
  --python`); review renders + `*_compare.png` in `models/renders/`.
  Player: 1,382 tris (body / cape / sword), 47 bones (`DEF-*`, cape chains,
  hood, `prop.sword` under `DEF-hand.R`), explicit vertex-group skinning,
  `LEG_STYLE` constant switches tights ↔ skin. Enemy: 632 tris, one skinned
  mesh, 21 exported bones (`DEF-leg_{hip,upper,lower,foot}.{FL,FR,BL,BR}`,
  `DEF-muzzle` + `muzzle` socket); Blender-only IK controls not exported; hull
  and legs a bit chunkier than SPEC to match refs. Godot 4.7.2 import is clean:
  player → Skeleton3D(47) + BoneAttachment3D `prop_sword`; enemy →
  Skeleton3D(21) + `muzzle` attachment. Sword global basis.z runs grip→tip.
  Known gaps — player: smooth helmet hair, cape flares less, forearms poke
  through cape in A-pose, hood reads weakly. Enemy: rear detailing approximated,
  cables are straight segments.
  Next: 1d — view both under a `PixelizerApplier3D` at game scale/camera and
  iterate on what survives pixelization.
