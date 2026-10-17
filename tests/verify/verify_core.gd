## TRUST: every check is valid as of 2026-10-16. F1 measures the inheriting
## Knight_Body (must follow the settings default) and a terrain chunk under an
## applier the probe pins (must not).
extends SceneTree

## In-game verification of the state-and-wiring claims that headless runs and
## code review cannot settle, on the real demo with a real renderer:
##
##   B1  the MST runtime texture baker swapped the chunk materials after the
##       first bind — all four chunks must be running a *generated* bridge
##       shader, which is what the repaired watchdog is for.
##   A3  the tuner rows that used to be inert must actually do something:
##       water `coast`/`wave_phase` reach the instance uniforms, the sky deck's
##       `deck_enabled`/`clouds_enabled` update `visible` even with
##       `follow_camera = false`, and the day/night arc params re-apply.
##   F1  a live `PixelizerSettings` change and a whole-resource swap propagate
##       to geometry that inherits, and not to geometry under a pinned applier.
##   F3  a camera-scoped cloud provider is selected by the active camera.
##
## Run (needs a real renderer for the demo to build its pipeline):
##   Godot-stable_mono_win64_console.exe --path . --fixed-fps 60 \
##     --script <abs path>/verify_core.gd

const SETTLE := 150
const STEP_FRAMES := 6

var _frames := 0
var _phase := 0
var _wait := 0
var _manager: PixelizerManager3D
var _look: PixelizerSettings
var _checks := 0
var _failures := PackedStringArray()
var _probe_camera: Camera3D
var _player_camera: Camera3D
var _provider_a: Object
var _provider_b: Object
var _original_settings: PixelizerSettings


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE:
		return false
	match _phase:
		0:
			_manager = _find_named(root, "PixelizerManager3D") as PixelizerManager3D
			_look = _manager.get_settings()
			_bridge_check()
			_phase = 1
			_wait = _frames + STEP_FRAMES
		1:
			if _frames >= _wait:
				_water_check()
				_phase = 2
				_wait = _frames + STEP_FRAMES
		2:
			if _frames >= _wait:
				_sky_check()
				_phase = 3
				_wait = _frames + STEP_FRAMES
		3:
			if _frames >= _wait:
				_daynight_check()
				_phase = 4
				_wait = _frames + STEP_FRAMES
		4:
			if _frames >= _wait:
				_settings_live_set()
				_phase = 5
				_wait = _frames + STEP_FRAMES
		5:
			if _frames >= _wait:
				_settings_live_assert_and_restore()
				_phase = 6
				_wait = _frames + STEP_FRAMES
		6:
			if _frames >= _wait:
				_settings_live_assert_restored()
				_settings_swap_set()
				_phase = 7
				_wait = _frames + STEP_FRAMES
		7:
			if _frames >= _wait:
				_settings_swap_assert_and_restore()
				_phase = 8
				_wait = _frames + STEP_FRAMES
		8:
			if _frames >= _wait:
				_settings_swap_assert_restored()
				_provider_setup()
				_phase = 9
				_wait = _frames + STEP_FRAMES
		9:
			if _frames >= _wait:
				_provider_select(_player_camera)
				_phase = 10
				_wait = _frames + STEP_FRAMES
		10:
			if _frames >= _wait:
				_provider_assert(0.2, "camera A selects provider A's field (threshold %.2f)")
				_provider_select(_probe_camera)
				_phase = 11
				_wait = _frames + STEP_FRAMES
		11:
			if _frames >= _wait:
				_provider_assert(0.8, "camera B selects provider B's field (threshold %.2f)")
				_provider_teardown()
				_report()
				quit(0 if _failures.is_empty() else 1)
				return true
	return false


# ── B1: the bridge survived MST's runtime baker ──────────────────────────────

func _bridge_check() -> void:
	var terrain := _find_named(root, "MarchingSquaresTerrain")
	_check(terrain != null, "the demo has a MarchingSquaresTerrain")
	if terrain == null:
		return
	var chunks: Array = []
	_collect_meshes(terrain, chunks)
	var total := 0
	var bridged := 0
	for c in chunks:
		var mi := c as MeshInstance3D
		total += 1
		var path := _material_shader_path(mi)
		if path.contains("pixelizer_bridges"):
			bridged += 1
		print("BRIDGE %-22s -> %s" % [mi.name, path if path != "" else "<none>"])
	_check(total > 0, "the terrain has chunk meshes to inspect")
	_check(bridged == total, "every terrain chunk runs a generated bridge shader (%d/%d)" % [bridged, total])
	# The watchdog must still be tracking them (they can be swapped again).
	var nested := terrain.get_parent() as PixelizerApplier3D
	if nested != null:
		var watched: int = (nested.get("_watch_ids") as Dictionary).size()
		print("BRIDGE nested applier watch set = %d" % watched)
		_check(watched > 0, "the nested applier still watches the swapped chunks (%d)" % watched)


func _material_shader_path(mi: MeshInstance3D) -> String:
	var mat: Material = mi.get_surface_override_material(0)
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.mesh.surface_get_material(0)
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		return (mat as ShaderMaterial).shader.resource_path
	return ""


# ── A3: the previously inert tuner rows ─────────────────────────────────────

func _water_check() -> void:
	var water := _find_named(root, "PixelizerWater3D") as PixelizerWater3D
	_check(water != null, "the demo has water")
	if water == null:
		return
	water.coast = 0.25
	_check(is_equal_approx(float(water.get_instance_shader_parameter("coast")), 0.25),
		"setting water.coast reaches the instance uniform (%.3f)" % float(water.get_instance_shader_parameter("coast")))
	water.wave_phase = 0.75
	_check(is_equal_approx(float(water.get_instance_shader_parameter("wave_phase")), 0.75),
		"setting water.wave_phase reaches the instance uniform (%.3f)" % float(water.get_instance_shader_parameter("wave_phase")))
	water.coast = 1.0
	water.wave_phase = 0.0


func _sky_check() -> void:
	var sky := _find_named(root, "PixelizerSkyClouds3D") as PixelizerSkyClouds3D
	_check(sky != null, "the demo has a cloud deck")
	if sky == null:
		return
	# This is the exact pre-fix failure: with follow_camera false, `_process`
	# never recomputed `visible`.
	sky.follow_camera = false
	sky.deck_enabled = false
	_check(not sky.visible, "deck_enabled = false hides the deck with follow_camera off")
	sky.deck_enabled = true
	_check(sky.visible, "deck_enabled = true shows the deck again")
	sky.clouds_enabled = false
	_check(not sky.visible, "clouds_enabled = false hides the deck")
	sky.clouds_enabled = true
	_check(sky.visible, "clouds_enabled = true restores the deck")
	_check(sky.visible == (sky.enabled and sky.deck_enabled and sky.clouds_enabled),
		"the deck's visibility matches its three toggles")


func _daynight_check() -> void:
	var sun := _find_named(root, "DirectionalLight3D") as DirectionalLight3D
	_check(sun != null, "the demo has a sun")
	if sun == null:
		return
	var rig := PixelizerDayNight3D.new()
	rig.manager = _manager
	rig.sun = sun
	root.add_child(rig)
	var before := sun.rotation_degrees.x
	# The setter must re-apply the arc (it used to be read only at _ready).
	rig.max_elevation_deg = 12.0
	var after := sun.rotation_degrees.x
	print("DAYNIGHT elevation %.2f -> %.2f (cap 12)" % [before, after])
	_check(not is_equal_approx(before, after), "changing max_elevation_deg re-applies the sun arc live")
	_check(absf(after) <= 12.0001, "the re-applied elevation respects the new 12 degree cap (%.2f)" % after)
	rig.queue_free()


# ── F1: settings propagation ────────────────────────────────────────────────
#
# Two subjects, because `_resolve_setting()` is nearest-author-wins:
# `Knight_Body` INHERITS `pixel_size` (demo.tscn pins no applier, so it must
# follow the settings default), while the probe PINS the nested terrain applier
# at `pixel_size = 4` (its chunks must NOT follow it). Asserting both makes the
# check able to fail in either direction.

## The write and the read are split across frames: an applier reacts to a
## settings change through a deferred rescan, so a same-frame read returns the
## pre-change value.
func _settings_live_set() -> void:
	_check(_inheriting_mesh() != null, "an inheriting bound mesh (Knight_Body) exists for the settings check")
	_check(_pinned_mesh() != null, "a pinned bound mesh (terrain chunk) exists for the settings check")
	_terrain_applier().pixel_size = 4
	_look.default_pixel_size = 3


func _settings_live_assert_and_restore() -> void:
	_check(_anchor_size(_inheriting_mesh()) == 3,
		"a live default_pixel_size change reaches inheriting geometry (anchor_size = %d)" % _anchor_size(_inheriting_mesh()))
	_check(_anchor_size(_pinned_mesh()) == 4,
		"geometry under a pinned applier ignores the settings default (anchor_size = %d)" % _anchor_size(_pinned_mesh()))
	_look.default_pixel_size = 5


func _settings_live_assert_restored() -> void:
	_check(_anchor_size(_inheriting_mesh()) == 5,
		"restoring default_pixel_size restores anchor_size (%d)" % _anchor_size(_inheriting_mesh()))


func _settings_swap_set() -> void:
	_original_settings = _manager.settings
	var fresh := PixelizerSettings.new()
	fresh.default_pixel_size = 2
	# Mirror the authored resource: the default `snap_camera = true` would push
	# the addon's perspective-snap error during the extra frame this check holds
	# the fresh resource across.
	fresh.snap_camera = false
	_manager.settings = fresh


func _settings_swap_assert_and_restore() -> void:
	_check(_anchor_size(_inheriting_mesh()) == 2,
		"swapping the whole settings resource propagates (anchor_size = %d)" % _anchor_size(_inheriting_mesh()))
	_check(_anchor_size(_pinned_mesh()) == 4,
		"a settings swap leaves pinned geometry alone (anchor_size = %d)" % _anchor_size(_pinned_mesh()))
	_manager.settings = _original_settings
	_terrain_applier().pixel_size = PixelizerInherit.INHERIT


func _settings_swap_assert_restored() -> void:
	_check(_anchor_size(_inheriting_mesh()) == 5,
		"restoring the authored settings restores anchor_size (%d)" % _anchor_size(_inheriting_mesh()))


func _inheriting_mesh() -> MeshInstance3D:
	return _find_named(root, "Knight_Body") as MeshInstance3D


func _pinned_mesh() -> MeshInstance3D:
	var terrain := _find_named(root, "MarchingSquaresTerrain")
	if terrain == null:
		return null
	var chunks: Array = []
	_collect_meshes(terrain, chunks)
	return chunks[0] as MeshInstance3D if not chunks.is_empty() else null


func _terrain_applier() -> PixelizerApplier3D:
	var terrain := _find_named(root, "MarchingSquaresTerrain")
	return terrain.get_parent() as PixelizerApplier3D if terrain != null else null


func _anchor_size(mesh: MeshInstance3D) -> int:
	if mesh == null:
		return -1
	return int(mesh.get_instance_shader_parameter("anchor_size"))


# ── F3: camera-scoped cloud providers ───────────────────────────────────────

class ProbeProvider:
	extends RefCounted
	var cloud_camera_scope: Camera3D = null
	var threshold := 0.5
	var base: Dictionary = {}

	func build_cloud_params(_sun) -> Dictionary:
		var params := base.duplicate()
		params["clouds_enabled"] = true
		params["cloud_threshold"] = threshold
		return params


func _provider_setup() -> void:
	var player := _find_named(root, "Player")
	if player != null:
		_player_camera = player.get_node_or_null("Camera3D") as Camera3D
	_probe_camera = Camera3D.new()
	_probe_camera.name = "ProviderProbeCamera"
	_probe_camera.fov = 24.0
	# The camera must be in the tree before a global transform can be set.
	root.add_child(_probe_camera)
	_probe_camera.global_position = Vector3(12.0, 3.0, 10.0)
	_probe_camera.look_at(Vector3(8.0, 1.0, 0.0), Vector3.UP)
	_check(_player_camera != null and _probe_camera != null, "two cameras exist for the provider scope test")
	if _player_camera == null:
		return
	var base := _manager.get_cloud_params()
	_provider_a = ProbeProvider.new()
	_provider_a.set("base", base)
	_provider_a.set("threshold", 0.2)
	_provider_a.set("cloud_camera_scope", _player_camera)
	_provider_b = ProbeProvider.new()
	_provider_b.set("base", base)
	_provider_b.set("threshold", 0.8)
	_provider_b.set("cloud_camera_scope", _probe_camera)
	_manager.register_cloud_provider(_provider_a)
	_manager.register_cloud_provider(_provider_b)
	_player_camera.current = true


## The field is rebuilt in the manager's `_process`, so the camera switch needs
## a frame before the value is read.
func _provider_select(camera: Camera3D) -> void:
	if _provider_a == null or _provider_b == null or _player_camera == null or camera == null:
		return
	camera.current = true
	var other: Camera3D = _probe_camera if camera == _player_camera else _player_camera
	if other != null:
		other.current = false


func _provider_assert(expected: float, template: String) -> void:
	if _provider_a == null or _provider_b == null or _player_camera == null:
		return
	var value := float(_manager.get_cloud_params().get("cloud_threshold", -1.0))
	_check(is_equal_approx(value, expected), template % value)


func _provider_teardown() -> void:
	if _provider_a != null:
		_manager.unregister_cloud_provider(_provider_a)
	if _provider_b != null:
		_manager.unregister_cloud_provider(_provider_b)


# ── plumbing ────────────────────────────────────────────────────────────────

func _report() -> void:
	if _failures.is_empty():
		print("IN-GAME CORE CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("IN-GAME CORE CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
