## Moved here from the 2026-10-16 verification session's scratchpad so it is not lost.
## TRUST: all 8 checks are valid and pass (D1a). Run windowed. Hides the effects container and grass planters and freezes the cloud wind and god-ray phase - do not remove that.
extends SceneTree

## In-game verification of the shaded-outline change (PLAN.md D1a).
##
## The claim: the depth test is a one-sided SECOND difference
## (`2*centre - a - b > threshold`), not a first difference. The property that
## separates them — and that a first difference provably cannot have — is that
## **a flat plane produces zero depth ink at any viewing angle**: the second
## difference of a planar depth ramp is exactly zero, while a first difference
## grows with the per-block depth step.
##
## The demo's terrain has two perfectly flat chunks (`Chunk (0, 0)2` and
## `Chunk (0, -1)2`, height 1e-5), so this is measurable on real geometry.
##
## Ink is detected by DIFFERENCING the same view with the outline pass off and
## on — no colour predicate, so dark terrain cannot be mistaken for ink. The
## control is a convex box added UNDER THE SAME APPLIER, so the same toggle
## controls it (a character would not work: it lives under a different applier,
## so its outline is unchanged by this toggle and never appears in the
## difference).
##
## CRITICAL: `root.get_texture().get_image()` returns the LAST RENDERED frame.
## Two grabs inside one `_process` call return the SAME image, which makes the
## diff trivially zero and the measurement vacuous. An earlier version of this
## probe did exactly that and "passed" the flat-plane half while its control
## also reported 0 px. Each capture below therefore happens in its own frame.
##
## Run (needs a real renderer):
##   Godot-stable_mono_win64_console.exe --path . --fixed-fps 60 \
##     --script <abs path>/verify_terrain.gd

const SETTLE := 150
const STEP := 6
## Measuring rect over bare flat terrain, in pixels.
const RECT_FLAT := Rect2i(430, 240, 300, 200)
## Half-size of the control-object rect, built from the box's projection.
const EDGE_RADIUS := 90

var _frames := 0
var _phase := 0
var _wait := 0
var _terrain_applier: PixelizerApplier3D
var _camera: Camera3D
var _box: MeshInstance3D
var _rect_edge := Rect2i()
var _img_off: Image
var _img_on: Image
var _img_off_repeat: Image
var _checks := 0
var _failures := PackedStringArray()


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE:
		return false
	match _phase:
		0:
			_setup()
			_phase = 1
			_wait = _frames + SETTLE
		1:
			if _frames >= _wait:
				_capture_outline(false)
				_phase = 2
				_wait = _frames + STEP
		2:
			if _frames >= _wait:
				_capture_outline(true)
				_phase = 3
				_wait = _frames + STEP
		3:
			if _frames >= _wait:
				# A second capture with the SAME outline state: with the
				# time-varying sources frozen this must be identical, which is
				# what makes the off/on difference attributable to the outline.
				_capture_outline(false)
				_img_off_repeat = _grab()
				_phase = 4
				_wait = _frames + STEP
		4:
			if _frames >= _wait:
				_evaluate()
				quit(0 if _failures.is_empty() else 1)
				return true
	return false


func _setup() -> void:
	var scene := _find_named(root, "demo")
	_terrain_applier = scene.get_node("PixelizerApplier3D/PixelizerApplier3D") as PixelizerApplier3D
	var knight := scene.get_node("PixelizerApplier3D/Node3D/Knight") as Node3D
	_check(_terrain_applier != null, "the terrain applier resolved")
	if _terrain_applier == null:
		return
	# The demo authors outline_enabled = 0 on the terrain (the flooding
	# workaround); the fix is what makes enabling it viable.
	_terrain_applier.outline_enabled = 1

	# Isolate bare flat terrain: no grass, no raised chunks, no light volume,
	# and the character row parked out of frame.
	for node in _find_all_with_prefix(scene, "GrassPlanter"):
		(node as Node3D).visible = false
	for chunk_name in ["Chunk (-1, 0)2", "Chunk (-1, -1)2"]:
		var raised := _find_named(scene, chunk_name)
		if raised != null:
			(raised as Node3D).visible = false
	var volume := _find_named(scene, "PixelizerPointLightVolume3D")
	if volume != null:
		(volume as Node3D).visible = false
	if knight != null:
		knight.global_position = Vector3(60.0, 0.5, 60.0)

	# The control: a box with sharp convex edges, under the SAME applier.
	_box = MeshInstance3D.new()
	_box.name = "ConvexControl"
	var box_mesh := BoxMesh.new()
	box_mesh.surface_set_material(0, StandardMaterial3D.new())
	_box.mesh = box_mesh
	_terrain_applier.add_child(_box)
	_box.global_position = Vector3(24.0, 0.6, 22.0)
	_box.scale = Vector3(2.0, 2.0, 2.0)

	# Freeze every time-varying source so the ONLY difference between the two
	# captures is the outline toggle. Without this the cloud wind scrolls the
	# shadow pattern between frames and the god-ray pass reads the wall clock,
	# and the diff measures weather instead of ink.
	var sky := _find_named(scene, "PixelizerSkyClouds3D") as PixelizerSkyClouds3D
	var rays := _find_named(scene, "PixelizerGodRays3D") as PixelizerGodRays3D
	_check(sky != null, "the cloud provider resolved (its wind is a diff contaminant)")
	_check(rays != null, "the god-ray node resolved (its phase is a diff contaminant)")
	if sky != null:
		sky.cloud_wind = Vector2.ZERO
		print("TERRAIN froze cloud_wind (%s)" % str(sky.cloud_wind))
	if rays != null:
		rays.time_override = 0.0
		print("TERRAIN pinned god-ray phase (time_override = %.1f)" % rays.time_override)

	var player := _find_named(scene, "Player")
	if player != null:
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.current = false
	_camera = Camera3D.new()
	_camera.name = "TerrainProbeCamera"
	_camera.fov = 30.0
	_camera.current = true
	scene.add_child(_camera)
	# Looking at the interior of the flat chunk (0, 0), which spans x -1..66.
	_camera.global_position = Vector3(20.0, 14.0, 34.0)
	_camera.look_at(Vector3(20.0, 0.0, 20.0), Vector3.UP)
	_terrain_applier.rescan()

	var box_px: Vector2 = _camera.unproject_position(_box.global_position)
	var size := root.get_viewport().get_visible_rect().size
	var start := clampf(box_px.x - float(EDGE_RADIUS), 0.0, size.x)
	var stop := clampf(box_px.x + float(EDGE_RADIUS), 0.0, size.x)
	var top := clampf(box_px.y - float(EDGE_RADIUS), 0.0, size.y)
	var bottom := clampf(box_px.y + float(EDGE_RADIUS), 0.0, size.y)
	_rect_edge = Rect2i(Vector2i(start, top), Vector2i(stop - start, bottom - top))
	print("TERRAIN control box projects to %s; edge rect %s; flat rect %s" % [
		str(Vector2i(box_px)), str(_rect_edge), str(RECT_FLAT)])
	_check(_rect_edge.size.x > 60 and _rect_edge.size.y > 60, "the control rect is on screen")
	_check(not _rect_edge.intersects(RECT_FLAT), "the control and flat rects do not overlap")


func _capture_outline(enabled: bool) -> void:
	_terrain_applier.outline_enabled = 1 if enabled else 0
	_terrain_applier.rescan()
	if enabled:
		_img_on = _grab()
	else:
		_img_off = _grab()


func _evaluate() -> void:
	if _img_off == null or _img_on == null or _img_off_repeat == null:
		_check(false, "all three frames were captured")
		return
	# Setup validation first: two frames in the SAME outline state must be
	# identical. If they are not, something still animates and every number
	# below is meaningless.
	var noise := _count_changed(_img_off, _img_off_repeat, Rect2i(Vector2i.ZERO, _img_off.get_size()))
	print("TERRAIN noise floor (outline off, two frames): %d px differ over the whole frame" % noise)
	_check(noise < 50, "the scene is static between frames once the clouds and rays are frozen (%d px)" % noise)
	var flat := _count_changed(_img_off, _img_on, RECT_FLAT)
	var edge := _count_changed(_img_off, _img_on, _rect_edge)
	print("TERRAIN flat plane: %d px inked (rect %s, %d px)" % [
		flat, str(RECT_FLAT), RECT_FLAT.size.x * RECT_FLAT.size.y])
	print("TERRAIN control box: %d px inked (rect %s, %d px)" % [
		edge, str(_rect_edge), _rect_edge.size.x * _rect_edge.size.y])
	# The control first: if the toggle does not ink a convex object, the
	# flat-plane result below would be vacuous.
	_check(edge > 200, "a convex pixelized box inks under the same toggle (%d px)" % edge)
	_check(flat < 60, "a flat plane produces no depth ink (%d px)" % flat)
	if _failures.is_empty():
		print("IN-GAME TERRAIN OUTLINE CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("IN-GAME TERRAIN OUTLINE CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _grab() -> Image:
	return root.get_texture().get_image()


func _count_changed(a: Image, b: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, a.get_height())):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, a.get_width())):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > 0.02 or absf(ca.g - cb.g) > 0.02 or absf(ca.b - cb.b) > 0.02:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _find_all_with_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	if node.name.begins_with(prefix):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all_with_prefix(child, prefix))
	return out


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
