class_name DemoCapture
extends Node

## Small, documented capture CLI for the demo (`demo/demo.tscn`), created by
## `player.gd` when any capture flag is present. It applies the flags, waits for
## the scene to settle, saves one screenshot and quits, printing a diagnostics
## JSON line so a silently ignored flag fails a capture run.
##
## Flags go after a bare `--`:
##
##   --capture=<path>      screenshot destination (default res://tests/captures/capture.png;
##                         absolute paths are accepted)
##   --resolution=WxH      window size (default 1152x648)
##   --fixed-view=<name>   camera preset: overhead | wide | characters
##   --mode=anchor|lowres  pipeline mode (default anchor)
##   --plain               pipeline off (`manager.enabled = false`)
##   --debug-view=<0-9>    manager.debug_view
##   --pixel-size=<N>      override every PixelizerApplier3D pixel size for the shot
##   --no-overlay          hide the diagnostics overlay (it starts hidden; the
##                         flag makes the intent explicit for scripted runs)
##   --overlay             show the diagnostics overlay (HUD + tuner docks) in
##                         the shot — used for the docs images
##   --settle=<frames>     frames to wait before the shot (default 150, min 30)
##   --outline-terrain     outlines on for every applier, the terrain included
##                         (the dense outline case the demo normally leaves off)
##   --ortho               orthographic camera (size 30) after the view preset
##   --mover-snap          mover snap on the top-level applier (the characters);
##                         the UNIFIED terrain applier is pinned off. Needs --ortho.
##   --palette-lut         bake a small 8-colour palette LUT at runtime and assign
##                         it as `settings.global_palette_lut`
##
## Example: tests/run_captures.py drives this for the capture matrix.

const DIAG_PREFIX := "PIXELIZER_CAPTURE "

var capture_path := "res://tests/captures/capture.png"
var resolution := Vector2i(1152, 648)
var fixed_view := "overhead"
var mode := "anchor"
var plain := false
var debug_view := 0
var pixel_size := -1
var no_overlay := false
var show_overlay := false
var settle_frames := 150
var outline_terrain := false
var ortho := false
var mover_snap := false
var palette_lut := false

## The fixed palette `--palette-lut` bakes (gamma-space swatches).
const LUT_SWATCHES := [
	Color8(26, 28, 44), Color8(93, 39, 93), Color8(177, 62, 83), Color8(239, 125, 87),
	Color8(255, 205, 117), Color8(167, 240, 112), Color8(56, 183, 100), Color8(41, 54, 111),
]

var _frames := 0


## True when the command line carries any capture flag.
static func is_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") or argument == "--no-overlay" or argument == "--plain":
			return true
		if argument in ["--outline-terrain", "--ortho", "--mover-snap", "--palette-lut"]:
			return true
		if argument.begins_with("--resolution=") or argument.begins_with("--fixed-view=") \
				or argument.begins_with("--mode=") or argument.begins_with("--debug-view=") \
				or argument.begins_with("--pixel-size=") or argument.begins_with("--settle="):
			return true
	return false


## Parse the flags into a new helper (does not touch the scene yet).
static func parse() -> DemoCapture:
	var capture := DemoCapture.new()
	capture.name = "DemoCapture"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture.capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--resolution="):
			var parts := argument.trim_prefix("--resolution=").split("x")
			if parts.size() == 2:
				capture.resolution = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--fixed-view="):
			capture.fixed_view = argument.trim_prefix("--fixed-view=")
		elif argument.begins_with("--mode="):
			capture.mode = argument.trim_prefix("--mode=")
		elif argument == "--plain":
			capture.plain = true
		elif argument.begins_with("--debug-view="):
			capture.debug_view = int(argument.trim_prefix("--debug-view="))
		elif argument.begins_with("--pixel-size="):
			capture.pixel_size = int(argument.trim_prefix("--pixel-size="))
		elif argument == "--no-overlay":
			capture.no_overlay = true
		elif argument == "--overlay":
			capture.show_overlay = true
		elif argument.begins_with("--settle="):
			capture.settle_frames = maxi(30, int(argument.trim_prefix("--settle=")))
		elif argument == "--outline-terrain":
			capture.outline_terrain = true
		elif argument == "--ortho":
			capture.ortho = true
		elif argument == "--mover-snap":
			capture.mover_snap = true
		elif argument == "--palette-lut":
			capture.palette_lut = true
	return capture


func _ready() -> void:
	# Late enough that the scene tree exists (the helper is added at the end of
	# the scene's `_ready` chain).
	call_deferred("_apply")


func _apply() -> void:
	var window := get_tree().root
	if window != null and resolution.x > 0 and resolution.y > 0:
		window.size = resolution
	var scene := get_tree().current_scene
	var manager: Node = _find_first(scene, "PixelizerManager3D")
	if manager == null:
		push_error("Pixelizer3D capture: no PixelizerManager3D in the scene; nothing to capture.")
		get_tree().quit(1)
		return
	if plain:
		manager.enabled = false
		# Unbind the appliers too: the manager toggle restores the camera, but
		# converted materials would still anchor-clip without the compositor.
		for applier in _collect_all(scene, &"PixelizerApplier3D"):
			applier.enabled = false
	elif mode == "lowres":
		manager.mode = PixelizerManager3D.Mode.LOW_RES
	manager.debug_view = debug_view
	if pixel_size > 0:
		for applier in _collect_all(scene, &"PixelizerApplier3D"):
			applier.pixel_size = pixel_size
	# Pin the god-ray cloud phase so captures are comparable run to run (the
	# effect otherwise reads the wall clock — see `PixelizerGodRayEffect.time_override`).
	for rays in _collect_all(scene, &"PixelizerGodRays3D"):
		rays.time_override = 0.0
	var appliers := _collect_all(scene, &"PixelizerApplier3D")
	if outline_terrain:
		for applier in appliers:
			applier.outline_enabled = 1
	if mover_snap:
		for applier in appliers:
			# Nested appliers (the UNIFIED terrain) are pinned off: mover snap is a
			# no-op under UNIFIED and the applier reports the mismatch.
			applier.mover_snap = 0 if applier.get_parent() is PixelizerApplier3D else 1
	if palette_lut:
		var lut := PaletteLUT.new()
		lut.source = PaletteLUT.source_texture_from_colors(PackedColorArray(LUT_SWATCHES))
		lut.dither_matrix = DitherMatrix.new()
		manager.get_settings().global_palette_lut = ImageTexture.create_from_image(lut.build_lut_image())
	var player: Node = _find_first(scene, "Player")
	if player != null and player.has_method("apply_camera_preset"):
		player.call("apply_camera_preset", fixed_view)
	if ortho:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 30.0
	if no_overlay or show_overlay:
		var overlay: Node = _find_first(scene, "PixelizerDiagnosticsOverlay")
		if overlay is CanvasLayer:
			var canvas := overlay as CanvasLayer
			if show_overlay:
				if not canvas.visible:
					canvas.call("toggle")
			else:
				canvas.visible = false
	set_process(true)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < settle_frames:
		return
	set_process(false)
	_capture_and_quit()


func _capture_and_quit() -> void:
	var image := get_tree().root.get_texture().get_image()
	var error := image.save_png(capture_path)
	print("%s%s" % [DIAG_PREFIX, JSON.stringify(_diagnostics(error))])
	get_tree().quit(0 if error == OK else 1)


func _diagnostics(save_error: int) -> Dictionary:
	var scene := get_tree().current_scene
	var manager: Node = _find_first(scene, "PixelizerManager3D")
	var movers := 0
	# By engine class: `_collect_all()` matches script class names, and these
	# meshes have no script (it used to report 0 movers unconditionally).
	var meshes: Array = []
	_collect_geometry(scene, meshes)
	for mesh in meshes:
		if mesh.get_instance_shader_parameter("anchor_mover_snap") == 1:
			movers += 1
	var look: Resource = manager.get_settings() if manager != null else null
	var camera := get_viewport().get_camera_3d()
	return {
		"mode": "lowres" if manager != null and manager.mode == PixelizerManager3D.Mode.LOW_RES else "anchor",
		"plain": plain,
		"window": [resolution.x, resolution.y],
		# The applied macro-pixel size: the --pixel-size override when set, else
		# the settings default (what appliers at the inherit sentinel resolve).
		"pixel_size": pixel_size if pixel_size > 0 else (look.get("default_pixel_size") if look != null else -1),
		"mover_count": movers,
		"ortho": camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"outline_terrain": outline_terrain,
		"palette_lut": look != null and look.get("global_palette_lut") != null,
		"debug_view": debug_view,
		"fixed_view": fixed_view,
		"capture": capture_path,
		"save_error": save_error,
	}


func _find_first(node: Node, name: String) -> Node:
	if node == null:
		return null
	if node.name == name:
		return node
	for child in node.get_children():
		var found := _find_first(child, name)
		if found != null:
			return found
	return null


func _collect_all(node: Node, script_class: StringName, out: Array = []) -> Array:
	if node == null:
		return out
	var script := node.get_script() as Script
	if script != null and String(script.get_global_name()) == String(script_class):
		out.append(node)
	for child in node.get_children():
		_collect_all(child, script_class, out)
	return out


func _collect_geometry(node: Node, out: Array) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_geometry(child, out)
