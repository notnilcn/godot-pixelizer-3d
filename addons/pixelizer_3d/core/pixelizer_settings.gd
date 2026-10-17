@tool
class_name PixelizerSettings
extends Resource

## Per-scene *look* for the pixelizer pipeline: what the pixel art looks like,
## separate from the manager's plumbing (wiring, registries, metadata layer).
##
## `PixelizerManager3D` owns one (auto-created when unset) and forwards its
## accessors here; the diagnostics tuner renders it as the "Look" section.
## Keeping look in data is what makes a camera -> settings mapping possible:
## swap the resource when the active camera changes and each camera gets its own
## palette, outlines, pixel-size default and resolution model.
##
## Node-typed fields deliberately stay on the manager: a scene-node reference
## cannot be serialized inside a Resource, and `debug_view` stays too (its enum
## is declared on the manager; a Resource type reference both ways would be a
## GDScript cyclic dependency). Everything here is a value/asset reference and
## saves cleanly in a `.tres` or as a scene sub-resource.
##
## `default_*` fields are the fallback for appliers/profiles left at the inherit
## sentinel; the applier's own property names are unchanged (they are the ones
## users touch per subtree).

@export_group("Resolution")
## Fixed render resolution (low-res mode) and scale reference. Also published as
## the `PixelizerGlobals.SCREEN_SIZE` global shader uniform, used by
## screen-space projection materials.
@export var render_resolution := Vector2i(960, 540):
	set(value):
		render_resolution = value
		_emit()
## World texels per world unit (0.5 -> ortho width 1920). Read only by the
## resolution model: LOW_RES mode or `manage_camera_size`; the anchor lattice is
## screen-space.
@export var texel_density := 0.5:
	set(value):
		texel_density = value
		_emit()
## Renderer-owned zoom on top of the configured scale (same reach as
## `texel_density`).
@export var view_zoom := 1.0:
	set(value):
		view_zoom = value
		_emit()
## Drive `camera.size` from the resolution model (and zoom). Leave false when the
## project owns the camera size itself.
@export var manage_camera_size := false:
	set(value):
		manage_camera_size = value
		_emit()

@export_group("Pixelization")
## Default macro-pixel size for appliers/objects that inherit.
@export_range(1, 5) var default_pixel_size := 3:
	set(value):
		default_pixel_size = value
		_emit()
## Keep pixels in front of their anchor (non-pixelized geometry in front of a
## pixelized object is not smeared by the block).
@export var depth_occlusion := true:
	set(value):
		depth_occlusion = value
		_emit()
## Default for appliers that inherit (`mover_snap == -1`): snap registered
## movers onto the pixel lattice in the vertex stage. Orthographic cameras only.
@export var default_mover_snap := false:
	set(value):
		default_mover_snap = value
		_emit()

@export_group("Palette")
## 256x256 palette LUT baked by PaletteLUT (16^3 colours x 16 dither bands).
## Null disables grading. The property name is the main-client contract:
## PixelArtPipelineComponent probes the property list and pushes its LUT here —
## do not rename it. (`PixelizerManager3D.global_palette_lut` forwards here.)
@export var global_palette_lut: Texture2D:
	set(value):
		global_palette_lut = value
		_emit()
## Use the LUT's 16 ordered-dither bands (Bayer in macro-pixel space). When false
## every fragment reads band 0, i.e. the nearest palette colour. Also the default
## for appliers that inherit.
@export var default_dither_enabled := true:
	set(value):
		default_dither_enabled = value
		_emit()

@export_group("Camera")
## Snap the camera to the texel lattice via h_offset/v_offset (never transforms).
@export var snap_camera := true:
	set(value):
		snap_camera = value
		_emit()
## Disable snapping (diagnostics / regression captures). `snap_origin` (the
## phase origin; world origin when unset) stays on the manager with the other
## node references.
@export var lock_camera := false:
	set(value):
		lock_camera = value
		_emit()

@export_group("Outlines")
## Default outline on/off for appliers that inherit; also the whole-pass gate.
@export var default_outline_enabled := true:
	set(value):
		default_outline_enabled = value
		_emit()
## Default outline colour for appliers that inherit (and for re-enabled tags
## without a palette row). The alpha is the row opacity: 0 hides, 1 replaces.
@export var default_outline_color := Color(0.04, 0.05, 0.09, 1.0):
	set(value):
		default_outline_color = value
		_emit()
## Relative depth discontinuity that counts as an inner edge. The test is a
## second difference (`2*centre - a - b`, convex side only), so slopes stay clean.
@export_range(0.0, 1.0, 0.001) var outline_threshold := 0.02:
	set(value):
		outline_threshold = value
		_emit()
## Larger relative depth step that reads as an exterior edge: the mark routes
## through the silhouette row instead of the inner row.
@export_range(0.0, 1.0, 0.001) var outline_interior_threshold := 0.25:
	set(value):
		outline_interior_threshold = value
		_emit()
## Crease sensitivity: mark an inner edge when `1 - dot(normal, neighbour)`
## across one macro step exceeds this. 0 disables. Needs the engine's
## normal-roughness buffer, which the manager requests from the depth prepass
## (`CompositorEffect.needs_normal_roughness`) while this is above 0, so no SSAO
## or special material is needed. The apply pass warns once and skips the term
## when the buffer is missing (non-Forward+ renderers).
@export_range(0.0, 1.0, 0.01) var outline_normal_threshold := 0.0:
	set(value):
		outline_normal_threshold = value
		_emit()
## Optional 256-tag palette (silhouette/inner rows) and its composite mode.
## Tag 255 is reserved for focused geometry.
@export var outline_palette: PixelizerOutlinePalette:
	set(value):
		outline_palette = value
		_emit()

@export_group("Focus")
## Automatically focus every pixelized mesh under `auto_focus_target` (which
## stays on the manager: a node reference). Focus maps an instance uniform onto
## edge tag 255 without overwriting `anchor_tag`.
@export var auto_focus := false:
	set(value):
		auto_focus = value
		_emit()
## Tint focused (tag 255) blocks red in the debug view.
@export var debug_focus_mask := false:
	set(value):
		debug_focus_mask = value
		_emit()


## Bumped on every field write; the manager compares it when it needs to react
## (the `changed` signal is also emitted for listeners).
var revision := 0


func _emit() -> void:
	revision += 1
	emit_changed()
