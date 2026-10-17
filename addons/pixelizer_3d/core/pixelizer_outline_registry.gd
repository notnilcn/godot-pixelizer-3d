class_name PixelizerOutlineRegistry
extends RefCounted

## Outline-tag bookkeeping for `PixelizerManager3D`: id allocation, the working
## 256-tag palette and its baked texture the apply pass samples.
##
## `outline_palette` is the authored base; per-applier / per-object colours are
## written into a working copy, so overrides never mutate the authored resource.

var manager: PixelizerManager3D
var _next_id := 1
var _working: PixelizerOutlinePalette
var _texture: ImageTexture
var _dirty := true
## Per-tag runtime state written through `set_color` / `set_enabled`
## (id -> {"color": Color} or {"enabled": false}). Re-applied whenever the
## working copy is reseeded, so a settings change or palette swap never drops a
## hidden tag or a per-applier colour while the appliers' re-scan is pending.
var _tag_state: Dictionary = {}


## Next outline tag id (1-254; 255 is reserved for the focus subject).
func allocate_id() -> int:
	var id := _next_id
	_next_id = _next_id % 254 + 1
	return id


## Set a tag's outline colour for both the silhouette and inner-edge rows, so an
## override covers every visible outline of that tag. The colour's alpha is the
## row opacity: alpha 0 hides the outline entirely, 1 replaces the scene colour.
## Id 255 is the focus subject's row (not auto-allocated, but settable).
func set_color(id: int, color: Color) -> void:
	if id < 0 or id > 255:
		return
	_tag_state[id] = {"color": color}
	_ensure_working()
	_write_color(id, color)


## Show or hide the screen-space outline for one edge tag. Hiding writes an
## opacity-0 palette row (the apply pass composites `mix(scene, outline_rgb,
## opacity)`, so an opacity of 0 leaves the sampled scene colour untouched and the
## shader needs no special case). Re-enabling restores the tag's row from
## `outline_palette` when set, else the manager's `outline_color` (whose alpha is
## the restored opacity).
func set_enabled(id: int, enabled: bool) -> void:
	if id < 0 or id > 255:
		return
	if enabled:
		_tag_state.erase(id)
	else:
		_tag_state[id] = {"enabled": false}
	_ensure_working()
	_write_enabled(id, enabled)


func _write_color(id: int, color: Color) -> void:
	_working.set_entry(id, color, color, color.a, color.a)
	_dirty = true


func _write_enabled(id: int, enabled: bool) -> void:
	var palette: PixelizerOutlinePalette = manager.get_settings().outline_palette
	if enabled and palette != null and id < palette.silhouette_colors.size():
		_working.set_entry(
			id,
			palette.silhouette_colors[id],
			palette.inner_colors[id],
			palette.silhouette_alpha[id],
			palette.inner_alpha[id])
	elif enabled:
		var color: Color = manager.get_settings().default_outline_color
		_working.set_entry(id, color, color, color.a, color.a)
	else:
		_working.set_entry(id, Color.WHITE, Color.WHITE, 0.0, 0.0)
	_dirty = true


func get_texture() -> ImageTexture:
	_ensure_working()
	if _texture == null or _dirty:
		_texture = _working.bake_texture()
		_dirty = false
	return _texture


## Composite mode of the working palette (see
## `PixelizerOutlinePalette.multiply_colors`).
func is_multiply() -> bool:
	_ensure_working()
	return _working.multiply_colors


## Drop the working copy so the next use reseeds from the authored palette /
## manager colour (call when those change). Per-tag state survives the reseed.
func invalidate() -> void:
	_working = null
	_dirty = true


func _ensure_working() -> void:
	if _working != null:
		return
	_working = PixelizerOutlinePalette.new()
	var palette: PixelizerOutlinePalette = manager.get_settings().outline_palette
	if palette != null:
		_working.silhouette_colors = palette.silhouette_colors.duplicate()
		_working.inner_colors = palette.inner_colors.duplicate()
		_working.silhouette_alpha = palette.silhouette_alpha.duplicate()
		_working.inner_alpha = palette.inner_alpha.duplicate()
		_working.multiply_colors = palette.multiply_colors
	else:
		var color: Color = manager.get_settings().default_outline_color
		for i in PixelizerOutlinePalette.ROW_COUNT:
			_working.set_entry(i, color, color, color.a, color.a)
	for id in _tag_state:
		var state: Dictionary = _tag_state[id]
		if state.has("color"):
			_write_color(id, state["color"])
		else:
			_write_enabled(id, false)
	_dirty = true

