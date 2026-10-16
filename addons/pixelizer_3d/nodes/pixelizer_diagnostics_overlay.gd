class_name PixelizerDiagnosticsOverlay
extends CanvasLayer

## Optional on-screen debug readout: pipeline state (from
## `PixelizerManager3D.get_debug_status_line()`) plus FPS and draw calls.
## Toggle with `toggle()` or `toggle_key` (TAB by default).
##
## The overlay also hosts runtime tuning docks:
##
## - Manager tuner (right dock): one foldable panel per export group of the
##   resolved `PixelizerManager3D`, built from the reflected export list, plus
##   one panel set per scene effect node (`PixelizerGodRays3D`, ...), so plugin
##   parameters can be adjusted while the game runs. Writes go through the
##   property setters the pipeline already uses for live propagation.
## - Object inspector (left dock): press "Select Object", then click a mesh in
##   the viewport. Only visible geometry is selectable: physics bodies are
##   resolved to the mesh they drive and collision-only bodies fall through to
##   mesh ray tests (AABB pre-pass + triangle tests). `PixelizerApplier3D` is
##   never selectable; `unselectable_parent_types` / `unselectable_parents`
##   extend that block list, and a blocked node's children stay selectable.
##   The selection's `PixelizerObjectProfile` (created on demand), its nearest
##   ancestor applier and the node's own exports get editable panels.
##
## A yellow translucent box marks the current selection in the 3D view.

@export var manager: PixelizerManager3D
@export var update_interval := 0.25
## Build the tuner docks. Disable for a status-only HUD.
@export var tuner_enabled := true
## Create the manager group panels folded (click a group title to open it).
@export var sections_start_folded := true
## Width of both tuner docks in pixels.
@export var panel_width := 350
## Key that toggles the overlay while its host scene runs. 0 disables the
## built-in handler (games can call `toggle()` from their own input).
@export var toggle_key: Key = KEY_TAB
## Parent nodes the picker must never select; their children stay selectable.
## Entries are class names: a script's global class name ("PixelizerApplier3D",
## or your own `class_name`) or an engine class ("StaticBody3D"). Subclasses of
## a listed script class are covered too. PixelizerApplier3D is always blocked
## and needs no entry here.
@export var unselectable_parent_types: Array[String] = []
## Specific nodes the picker must never select (assign them in the inspector);
## their children stay selectable.
@export var unselectable_parents: Array[Node] = []

## Export groups that are not safe to change at runtime (derived state, or
## values only read during setup). Everything else is editable from the tuner.
const IGNORE_CLASS_PROPERTIES := {
	&"PixelizerManager3D": [
		# `enabled` is deliberately NOT here: its setter unbinds/rebinds the
		# camera, so the tuner toggle is a real (and useful) plain baseline.
		&"editor_preview", &"inherit_sentinel",
		&"metadata_layer", &"sync_process_priority",
		&"object_profiles", &"bridge_manifests",
		# Read during bind()/refresh only; already-applied states never re-run
		# the manifest lookup.
		&"auto_bridge_custom_shaders",
	],
	&"PixelizerApplier3D": [&"ignore_group"],
	&"PixelizerObjectProfile": [&"target_path"],
	# Resolution model only: read via the LOW_RES / manage_camera_size path,
	# never by the anchor lattice (screen-space). See AGENTS.md.
	&"PixelizerSettings": [&"texel_density", &"view_zoom"],
	# Mesh built in `_ready`; no live consumer.
	&"PixelizerWater3D": [&"size", &"subdivisions"],
	&"PixelizerSkyClouds3D": [&"plane_size"],
}

const SELECT_HINT := "Press \"Select Object\", then click a mesh in the viewport."
const SELECTING_HINT := "Click a mesh in the viewport to select it (Esc cancels)."
## How many nearest AABB candidates get the exact triangle test per click.
const MAX_TRIANGLE_CANDIDATES := 32
## How many scene effect nodes get tuner panels (safety bound).
const MAX_EFFECT_PANELS := 8

var _label: Label
var _timer := 0.0
var _root: Control
var _manager_panel: PanelContainer
var _manager_sections: VBoxContainer
var _manager_built_for := 0
var _manager_effect_signature := ""
var _object_panel: PanelContainer
var _object_title: Label
var _object_subtitle: Label
var _object_sections: VBoxContainer
var _select_button: Button
var _select_mode := false
var _selected: Node3D
var _selection_marker: MeshInstance3D
var _bindings: Array = []
var _object_bindings: Array = []
var _base_group_cache: Dictionary = {}


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.85, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	if tuner_enabled:
		_build_tuner()
	visible = false
	call_deferred("_ensure_manager_panel")


func _process(delta: float) -> void:
	if not visible:
		return
	_tick_selection()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	_ensure_manager_panel()
	_label.text = get_status_text()
	_refresh_bindings(_bindings)
	_refresh_bindings(_object_bindings)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and toggle_key != KEY_NONE and key.keycode == toggle_key:
			toggle()
			get_viewport().set_input_as_handled()
			return
	if not visible or not _select_mode:
		return
	if event is InputEventKey:
		var escape := event as InputEventKey
		if escape.pressed and not escape.echo and escape.keycode == KEY_ESCAPE:
			_set_select_mode(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and get_viewport().gui_get_hovered_control() == null:
			_pick_at(mouse.position)
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _selection_marker != null and is_instance_valid(_selection_marker):
		_selection_marker.queue_free()
		_selection_marker = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func get_status_text() -> String:
	var lines: PackedStringArray = []
	if manager == null or not is_instance_valid(manager):
		manager = PixelizerManager3D.resolve_manager(self)
	if manager != null and is_instance_valid(manager):
		lines.append(manager.get_debug_status_line())
	else:
		lines.append("Pixelizer3D [no manager]")
	lines.append("fps=%d  draw_calls=%d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	return "\n".join(lines)


func toggle() -> void:
	visible = not visible
	if visible:
		_timer = 0.0
		_ensure_manager_panel()
		_update_selection_marker()
	else:
		_set_select_mode(false)
		if _selection_marker != null and is_instance_valid(_selection_marker):
			_selection_marker.visible = false


## Select a node programmatically (skips picking); the inspector panel is
## rebuilt for it. Pass null to clear.
func select_node(node: Node3D) -> void:
	_selected = node
	_set_select_mode(false)
	_rebuild_object_panel()
	_update_selection_marker()


func get_selected_node() -> Node3D:
	return _selected


# ── Tuner construction ───────────────────────────────────────────────────────

func _build_tuner() -> void:
	_root = Control.new()
	_root.name = "PixelizerTunerRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_manager_panel()
	_build_object_panel()


func _build_manager_panel() -> void:
	_manager_panel = PanelContainer.new()
	_manager_panel.name = "ManagerTuner"
	_style_dock(_manager_panel)
	_manager_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_manager_panel.offset_left = float(-panel_width - 12)
	_manager_panel.offset_right = -12.0
	_manager_panel.offset_top = 12.0
	_manager_panel.offset_bottom = -12.0
	_root.add_child(_manager_panel)

	var column := VBoxContainer.new()
	_manager_panel.add_child(column)

	var header := Label.new()
	header.text = "Pixelizer3D — Manager"
	header.add_theme_font_size_override("font_size", 14)
	column.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_manager_sections = VBoxContainer.new()
	_manager_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manager_sections.add_theme_constant_override("separation", 4)
	scroll.add_child(_manager_sections)


func _build_object_panel() -> void:
	_object_panel = PanelContainer.new()
	_object_panel.name = "ObjectTuner"
	_style_dock(_object_panel)
	_object_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_object_panel.offset_left = 12.0
	_object_panel.offset_right = float(panel_width + 12)
	_object_panel.offset_top = 210.0
	_object_panel.offset_bottom = -12.0
	_root.add_child(_object_panel)

	var column := VBoxContainer.new()
	_object_panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_object_title = Label.new()
	_object_title.text = "No object selected"
	_object_title.add_theme_font_size_override("font_size", 14)
	_object_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_title.clip_text = true
	header.add_child(_object_title)
	_select_button = Button.new()
	_select_button.text = "Select Object"
	_select_button.toggle_mode = true
	_select_button.tooltip_text = "Click, then pick a mesh in the viewport"
	_select_button.toggled.connect(_on_select_toggled)
	header.add_child(_select_button)

	_object_subtitle = Label.new()
	_object_subtitle.text = SELECT_HINT
	_object_subtitle.add_theme_font_size_override("font_size", 11)
	_object_subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.85))
	_object_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_object_subtitle)
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_object_sections = VBoxContainer.new()
	_object_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_sections.add_theme_constant_override("separation", 4)
	scroll.add_child(_object_sections)


func _style_dock(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	style.border_color = Color(0.35, 0.5, 0.65, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font_size = 12
	panel.theme = theme


# ── Manager panel ────────────────────────────────────────────────────────────

func _resolve_manager() -> void:
	if manager != null and is_instance_valid(manager):
		return
	manager = PixelizerManager3D.resolve_manager(self)


func _ensure_manager_panel() -> void:
	if not tuner_enabled or _manager_sections == null:
		return
	_resolve_manager()
	var id := manager.get_instance_id() if manager != null else 0
	var signature := _effect_signature()
	if id != _manager_built_for or signature != _manager_effect_signature:
		_rebuild_manager_panel()


func _rebuild_manager_panel() -> void:
	_clear_container(_manager_sections)
	_bindings.clear()
	_manager_built_for = manager.get_instance_id() if manager != null else 0
	_manager_effect_signature = _effect_signature()
	if manager == null:
		var label := Label.new()
		label.text = "No PixelizerManager3D found in the scene."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_manager_sections.add_child(label)
		return
	for group in _collect_groups(manager):
		_add_section(_manager_sections, _section_title(group), manager, group["props"], not sections_start_folded, _bindings)
	# The per-scene look lives in `PixelizerSettings` (and is what can be swapped
	# per camera); its groups get their own "Look" panel rows.
	var look := manager.get_settings()
	for group in _collect_groups(look):
		var look_title := "Look — %s (%d)" % [
			String(group["name"]) if not String(group["name"]).is_empty() else "General",
			group["props"].size()]
		_add_section(_manager_sections, look_title, look, group["props"], not sections_start_folded, _bindings)
	for effect in _collect_effect_nodes():
		for group in _collect_groups(effect):
			var title := "%s (%d)" % [effect.name, group["props"].size()]
			var group_name := String(group["name"])
			if not group_name.is_empty():
				title = "%s — %s (%d)" % [effect.name, group_name, group["props"].size()]
			_add_section(_manager_sections, title, effect, group["props"], not sections_start_folded, _bindings)


func _section_title(group: Dictionary) -> String:
	var group_name := String(group["name"])
	var props: Array = group["props"]
	if group_name.is_empty():
		return "General (%d)" % props.size()
	return "%s (%d)" % [group_name, props.size()]


func _collect_effect_nodes() -> Array:
	var out: Array = []
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	_collect_effect_nodes_recursive(scene, out)
	return out


func _collect_effect_nodes_recursive(node: Node, out: Array) -> void:
	if node is SubViewport or out.size() >= MAX_EFFECT_PANELS:
		return
	var klass := _script_class_name(node)
	if klass.begins_with("Pixelizer") \
			and klass != "PixelizerManager3D" \
			and klass != "PixelizerApplier3D" \
			and klass != "PixelizerDiagnosticsOverlay":
		out.append(node)
	for child in node.get_children():
		_collect_effect_nodes_recursive(child, out)


func _effect_signature() -> String:
	var parts: PackedStringArray = []
	for effect in _collect_effect_nodes():
		parts.append(str(effect.get_instance_id()))
	return "|".join(parts)


# ── Object inspector ─────────────────────────────────────────────────────────

func _on_select_toggled(pressed: bool) -> void:
	_set_select_mode(pressed)


func _set_select_mode(enabled: bool) -> void:
	_select_mode = enabled
	if _select_button != null:
		_select_button.set_pressed_no_signal(enabled)
		_select_button.text = "Selecting…" if enabled else "Select Object"
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if enabled else Input.CURSOR_ARROW)
	if _object_subtitle != null and _selected == null:
		_object_subtitle.text = SELECTING_HINT if enabled else SELECT_HINT


func _pick_at(screen_position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var physics_pick := _pick_physics(camera, origin, direction)
	var mesh_pick := _pick_mesh(origin, direction)
	# Physics gives an exact hit position and resolves bodies to their mesh; the
	# mesh ray test sees geometry a collider may not cover. Prefer whichever
	# surface is nearer (a tie goes to physics, which is exact).
	var physics_distance := INF
	if not physics_pick.is_empty() and not _is_unselectable(physics_pick["node"]):
		physics_distance = float(physics_pick["distance"])
	var mesh_distance := INF
	if not mesh_pick.is_empty():
		mesh_distance = float(mesh_pick["distance"])
	if physics_distance < INF and physics_distance <= mesh_distance:
		select_node(physics_pick["node"])
	elif mesh_distance < INF:
		select_node(mesh_pick["node"])


## Nearest visible supported mesh along the ray via an AABB pre-pass plus exact
## tests on the nearest `MAX_TRIANGLE_CANDIDATES` boxes. Returns `{node,
## distance}` or an empty dictionary.
func _pick_mesh(origin: Vector3, direction: Vector3) -> Dictionary:
	var candidates: Array = []
	_collect_geometry(get_tree().root, candidates)
	var hits: Array = []
	for candidate in candidates:
		if candidate == _selection_marker:
			continue
		var aabb_value: Variant = _candidate_aabb(candidate)
		if aabb_value == null:
			continue
		var aabb: AABB = aabb_value
		var distance := _ray_aabb_distance(origin, direction, (candidate as Node3D).global_transform, aabb)
		if distance >= 0.0:
			hits.append({ "node": candidate, "t": distance })
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	var best: Node3D = null
	var best_distance := INF
	var tested := 0
	for hit in hits:
		# An AABB entry distance is a lower bound on that candidate's triangle
		# hit, so `best_distance <= hit["t"]` cannot skip a nearer mesh.
		if best_distance <= float(hit["t"]) or tested >= MAX_TRIANGLE_CANDIDATES:
			break
		if _is_unselectable(hit["node"]):
			continue
		tested += 1
		var distance := _mesh_hit_distance(origin, direction, hit["node"])
		if distance >= 0.0 and distance < best_distance:
			best_distance = distance
			best = hit["node"]
	if best == null:
		return {}
	return { "node": best, "distance": best_distance }


## True for nodes the picker must never select: every PixelizerApplier3D, the
## user's `unselectable_parents`, and any node matching a class name in
## `unselectable_parent_types` (engine class or script global class name, with
## script subclasses covered). Children of a blocked node are not blocked.
func _is_unselectable(node: Node) -> bool:
	if node is PixelizerApplier3D:
		return true
	if unselectable_parents.has(node):
		return true
	var klass := node.get_class()
	for type_name in unselectable_parent_types:
		if type_name.is_empty():
			continue
		if type_name == klass or node.is_class(type_name):
			return true
		if _script_inherits_class(node, type_name):
			return true
	return false


func _script_inherits_class(node: Node, class_name_string: String) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if String(script.get_global_name()) == class_name_string:
			return true
		script = script.get_base_script()
	return false


## Physics bodies give the exact click position; resolve them to the geometry
## they drive. Collision-only bodies (no visible geometry) return an empty
## dictionary so the mesh ray test decides: the picker never targets bodies,
## appliers or other non-geometry parents.
func _pick_physics(camera: Camera3D, origin: Vector3, direction: Vector3) -> Dictionary:
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 10000.0)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider = hit.get("collider")
	if not (collider is Node3D):
		return {}
	var distance := origin.distance_to(hit["position"])
	if PixelizerGeometryState.is_supported_node(collider):
		return { "node": collider, "distance": distance }
	var geometry := _find_geometry_descendant(collider)
	if geometry != null:
		return { "node": geometry, "distance": distance }
	var parent := (collider as Node3D).get_parent()
	while parent != null:
		if PixelizerGeometryState.is_supported_node(parent):
			return { "node": parent, "distance": distance }
		parent = parent.get_parent()
	return {}


func _find_geometry_descendant(node: Node) -> GeometryInstance3D:
	for child in node.get_children():
		if child is GeometryInstance3D and PixelizerGeometryState.is_supported_node(child):
			return child as GeometryInstance3D
		var found := _find_geometry_descendant(child)
		if found != null:
			return found
	return null


## Exact distance when the node is a plain MeshInstance3D (ray/triangle), the
## AABB fallback for MultiMesh/particle nodes (instanced geometry has no single
## face list to test against). The triangle test uses `Mesh.get_faces()`, which
## is the rest pose: a heavily posed skinned mesh is picked from its rest pose
## (the skeleton-aware `GeometryInstance3D.get_aabb()` in the pre-pass at least
## narrows the candidates).
func _mesh_hit_distance(origin: Vector3, direction: Vector3, node: Node3D) -> float:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			return -1.0
		var faces := mesh.get_faces()
		if faces.size() >= 9:
			return _ray_faces_distance(origin, direction, node.global_transform, faces)
		return _ray_aabb_distance(origin, direction, node.global_transform, (node as MeshInstance3D).get_aabb())
	var aabb_value: Variant = _candidate_aabb(node)
	if aabb_value == null:
		return -1.0
	var box: AABB = aabb_value
	return _ray_aabb_distance(origin, direction, node.global_transform, box)


## Möller-Trumbore over the mesh's triangles (local space). The inverse
## transform scales the direction, but the parameter t still equals world ray
## distance because `basis * (inverse(basis) * direction) == direction`.
func _ray_faces_distance(origin: Vector3, direction: Vector3, xform: Transform3D, faces: PackedVector3Array) -> float:
	var inverse := xform.affine_inverse()
	var source := inverse * origin
	var ray := inverse.basis * direction
	var best := INF
	var triangle_count := faces.size() / 3
	for i in triangle_count:
		var base := i * 3
		var a := faces[base]
		var edge1 := faces[base + 1] - a
		var edge2 := faces[base + 2] - a
		var pvec := ray.cross(edge2)
		var det := edge1.dot(pvec)
		if absf(det) < 1.0e-9:
			continue
		var inv_det := 1.0 / det
		var tvec := source - a
		var u := tvec.dot(pvec) * inv_det
		if u < 0.0 or u > 1.0:
			continue
		var qvec := tvec.cross(edge1)
		var v := ray.dot(qvec) * inv_det
		if v < 0.0 or u + v > 1.0:
			continue
		var t := edge2.dot(qvec) * inv_det
		if t > 1.0e-6 and t < best:
			best = t
	return best if best < INF else -1.0


func _collect_geometry(node: Node, out: Array) -> void:
	# SubViewports belong to other worlds (the metadata/low-res viewports), so
	# their geometry must not take part in picking.
	if node is SubViewport:
		return
	if node is GeometryInstance3D and node.is_visible_in_tree():
		out.append(node)
	for child in node.get_children():
		_collect_geometry(child, out)


func _candidate_aabb(node: Node) -> Variant:
	if node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		return multimesh.get_aabb() if multimesh != null else null
	if node is GPUParticles3D:
		return (node as GPUParticles3D).visibility_aabb
	if node is CPUParticles3D:
		return (node as CPUParticles3D).visibility_aabb
	if node is GeometryInstance3D:
		# Local-space AABB. MeshInstance3D resolves this through its skeleton
		# path, so a posed skinned mesh is not picked from its rest-pose box
		# (unlike `Mesh.get_aabb()`).
		return (node as GeometryInstance3D).get_aabb()
	return null


## Slab test against a mesh AABB. Returns the distance along the (normalized)
## world ray, or -1 when there is no hit. The inverse transform maps the ray
## into mesh space, so node scale is accounted for.
func _ray_aabb_distance(origin: Vector3, direction: Vector3, xform: Transform3D, aabb: AABB) -> float:
	var inverse := xform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	var t_min := -INF
	var t_max := INF
	for axis in 3:
		var start: float = aabb.position[axis]
		var size: float = aabb.size[axis]
		var dir: float = local_direction[axis]
		var source: float = local_origin[axis]
		if absf(dir) < 1.0e-9:
			if source < start or source > start + size:
				return -1.0
			continue
		var t1 := (start - source) / dir
		var t2 := (start + size - source) / dir
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return -1.0
	if t_max < 0.0:
		return -1.0
	return maxf(t_min, 0.0)


func _tick_selection() -> void:
	if _selected != null and not is_instance_valid(_selected):
		_selected = null
		_rebuild_object_panel()
	_update_selection_marker()


func _rebuild_object_panel() -> void:
	if _object_sections == null:
		return
	_clear_container(_object_sections)
	_object_bindings.clear()
	if _selected == null or not is_instance_valid(_selected):
		_object_title.text = "No object selected"
		_set_select_mode(_select_mode)
		return
	_object_title.text = _selected.name
	_object_subtitle.text = str(_selected.get_path())
	# The node's own script exports first: edits here affect only this node.
	# (The manager/applier/overlay have dedicated panels elsewhere.)
	var klass := _script_class_name(_selected)
	if klass != "PixelizerApplier3D" and klass != "PixelizerManager3D" and klass != "PixelizerDiagnosticsOverlay":
		_add_object_groups(_selected, "This object — %s" % _selected.name)
	# Per-object override resource, plus the create action for supported
	# geometry only (a profile on anything else has nothing to configure).
	var supported := PixelizerGeometryState.is_supported_node(_selected)
	if manager != null and is_instance_valid(manager) and supported:
		var profile := manager.get_object_profile(_selected)
		if profile != null:
			_add_object_groups(profile, "Object profile (this object only)")
			_add_action_button("Remove Object Profile", _remove_object_profile.bind(profile, _selected))
		else:
			_add_action_button("Create Object Profile", _create_object_profile.bind(_selected))
	# The parent applier's values are subtree-wide inherit defaults.
	var applier := _find_ancestor_applier(_selected)
	if applier != null:
		var bound := applier.get_bound_state_count()
		_add_object_groups(applier, "Parent applier — %s (shared by %d mesh%s)" % [
			applier.name, bound, "" if bound == 1 else "es"])
	if _object_sections.get_child_count() == 0:
		var label := Label.new()
		label.text = "No pixelizer configuration on this node."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_object_sections.add_child(label)


func _add_action_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	_object_sections.add_child(button)


func _create_object_profile(geometry: Node3D) -> void:
	if manager == null or not is_instance_valid(manager):
		return
	if manager.get_object_profile(geometry) != null:
		return
	var profile := PixelizerObjectProfile.new()
	manager.register_object_profile(profile, geometry)
	if geometry.is_inside_tree():
		profile.target_path = manager.get_path_to(geometry)
	var applier := _find_ancestor_applier(geometry)
	if applier != null:
		applier.reconfigure(geometry)
	_rebuild_object_panel()


func _remove_object_profile(profile: PixelizerObjectProfile, geometry: Node3D) -> void:
	if manager == null or not is_instance_valid(manager):
		return
	manager.unregister_object_profile(profile)
	var applier := _find_ancestor_applier(geometry)
	if applier != null:
		applier.reconfigure(geometry)
	_rebuild_object_panel()


func _add_object_groups(obj: Object, title: String) -> void:
	for group in _collect_groups(obj):
		var group_title := title
		var group_name := String(group["name"])
		if not group_name.is_empty():
			group_title = "%s · %s" % [title, group_name]
		_add_section(_object_sections, group_title, obj, group["props"], true, _object_bindings)


func _find_ancestor_applier(node: Node) -> PixelizerApplier3D:
	var current := node.get_parent()
	while current != null:
		if current is PixelizerApplier3D:
			return current as PixelizerApplier3D
		current = current.get_parent()
	return null


func _ensure_selection_marker() -> void:
	if _selection_marker != null and is_instance_valid(_selection_marker):
		return
	var marker := MeshInstance3D.new()
	marker.name = "PixelizerSelectionMarker"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	marker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.85, 0.2, 0.16)
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_to_group("pixelizer_ignore")
	marker.visible = false
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(marker)
	_selection_marker = marker


func _update_selection_marker() -> void:
	if not is_inside_tree():
		return
	if _selection_marker == null or not is_instance_valid(_selection_marker):
		if _selected == null or not is_instance_valid(_selected):
			return
		_ensure_selection_marker()
	var target := _selected
	if target == null or not is_instance_valid(target):
		_selection_marker.visible = false
		return
	var aabb_value: Variant = _candidate_aabb(target)
	if aabb_value == null:
		_selection_marker.visible = false
		return
	var aabb: AABB = aabb_value
	_selection_marker.visible = true
	var size := aabb.size
	size.x = maxf(size.x, 0.001)
	size.y = maxf(size.y, 0.001)
	size.z = maxf(size.z, 0.001)
	_selection_marker.global_transform = target.global_transform * Transform3D(Basis().scaled(size), aabb.get_center())


# ── Property reflection ──────────────────────────────────────────────────────

## Groups the object's script exports by their @export_group, dropping empty
## groups (the built-in Node groups carry no script properties, and would
## otherwise swallow ungrouped exports declared after the last built-in group).
## Ungrouped exports land in a single group with an empty name.
func _collect_groups(obj: Object) -> Array:
	var base_groups := _base_group_names(obj)
	var groups: Array = []
	var current: Dictionary = { "name": "", "props": [] }
	groups.append(current)
	for prop in obj.get_property_list():
		var usage: int = int(prop["usage"])
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP):
			continue
		if usage & PROPERTY_USAGE_GROUP:
			if not base_groups.has(String(prop["name"])):
				current = { "name": String(prop["name"]), "props": [] }
				groups.append(current)
			continue
		if not (usage & PROPERTY_USAGE_EDITOR) or not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not _is_runtime_property(obj, prop["name"]):
			continue
		current["props"].append(prop)
	var out: Array = []
	for group in groups:
		if not group["props"].is_empty():
			out.append(group)
	return out


func _base_group_names(obj: Object) -> Dictionary:
	var klass := obj.get_class()
	if not _base_group_cache.has(klass):
		var names := {}
		for prop in ClassDB.class_get_property_list(klass, false):
			if int(prop["usage"]) & PROPERTY_USAGE_GROUP:
				names[String(prop["name"])] = true
		_base_group_cache[klass] = names
	return _base_group_cache[klass]


func _is_runtime_property(obj: Object, property: StringName) -> bool:
	var klass := _script_class_name(obj)
	if not IGNORE_CLASS_PROPERTIES.has(klass):
		return true
	return not (IGNORE_CLASS_PROPERTIES[klass] as Array).has(property)


func _script_class_name(obj: Object) -> String:
	var script := obj.get_script() as Script
	if script == null:
		return ""
	return String(script.get_global_name())


# ── Widget building ──────────────────────────────────────────────────────────

func _add_section(parent: VBoxContainer, title: String, obj: Object, props: Array, expanded: bool, bindings: Array) -> void:
	var section := FoldableContainer.new()
	section.title = title
	section.folded = not expanded
	parent.add_child(section)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	section.add_child(body)
	for prop in props:
		_add_property_row(body, obj, prop, bindings)


func _add_property_row(parent: VBoxContainer, obj: Object, prop: Dictionary, bindings: Array) -> void:
	var property := StringName(prop["name"])
	var type := int(prop["type"])
	var hint := int(prop["hint"])
	var hint_string := String(prop["hint_string"])
	var write := _make_writer(obj, property)
	var row := HBoxContainer.new()
	row.name = String(property)
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var label := Label.new()
	label.text = String(property).capitalize()
	label.tooltip_text = String(property)
	label.custom_minimum_size.x = 144.0
	label.clip_text = true
	row.add_child(label)

	if type == TYPE_BOOL:
		_add_bool_editor(row, obj, property, write, bindings)
	elif hint == PROPERTY_HINT_ENUM:
		_add_enum_editor(row, obj, property, hint_string, write, bindings)
	elif type == TYPE_INT or type == TYPE_FLOAT:
		if hint == PROPERTY_HINT_RANGE:
			_add_range_editor(row, obj, property, hint_string, type == TYPE_INT, write, bindings)
		else:
			_add_spin_editor(row, obj, property, type == TYPE_INT, write, bindings)
	elif type == TYPE_COLOR:
		_add_color_editor(row, obj, property, write, bindings)
	elif type == TYPE_VECTOR2:
		_add_vector_editor(row, obj, property, false, write, bindings)
	elif type == TYPE_VECTOR2I:
		_add_vector_editor(row, obj, property, true, write, bindings)
	elif type == TYPE_STRING or type == TYPE_STRING_NAME:
		_add_string_editor(row, obj, property, write, bindings)
	else:
		_add_read_only_row(row, obj, property, bindings)


func _make_writer(obj: Object, property: StringName) -> Callable:
	if obj is PixelizerObjectProfile:
		return Callable(self, "_write_profile_property").bind(obj, property)
	return Callable(self, "_write_property").bind(obj, property)


## Call arguments come first, bound arguments last (Callable.bind appends).
func _write_property(value, obj: Object, property: StringName) -> void:
	obj.set(property, value)


func _write_profile_property(value, obj: Object, property: StringName) -> void:
	obj.set(property, value)
	_reconfigure_profile(obj)


func _reconfigure_profile(profile: PixelizerObjectProfile) -> void:
	if manager == null or not is_instance_valid(manager):
		return
	var target := profile.resolve_target(manager)
	if target == null:
		return
	var applier := _find_ancestor_applier(target)
	if applier != null:
		applier.reconfigure(target)


func _add_bool_editor(row: HBoxContainer, obj: Object, property: StringName, write: Callable, bindings: Array) -> void:
	var check := CheckBox.new()
	check.button_pressed = bool(obj.get(property))
	check.toggled.connect(func(pressed: bool) -> void: write.call(pressed))
	row.add_child(check)
	bindings.append({
		"busy": Callable(self, "_focus_busy").bind(check),
		"refresh": Callable(self, "_refresh_bool").bind(obj, property, check),
	})


func _add_enum_editor(row: HBoxContainer, obj: Object, property: StringName, hint_string: String, write: Callable, bindings: Array) -> void:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	var ids: Array = []
	for item in hint_string.split(","):
		var parts := item.split(":")
		var id := ids.size()
		if parts.size() > 1:
			id = int(parts[1])
		ids.append(id)
		option.add_item(parts[0], id)
	option.selected = ids.find(int(obj.get(property)))
	option.item_selected.connect(func(index: int) -> void: write.call(ids[index]))
	row.add_child(option)
	bindings.append({
		"busy": Callable(self, "_popup_busy").bind(option),
		"refresh": Callable(self, "_refresh_enum").bind(obj, property, option, ids),
	})


func _add_range_editor(row: HBoxContainer, obj: Object, property: StringName, hint_string: String, is_int: bool, write: Callable, bindings: Array) -> void:
	var parts := hint_string.split(",")
	var min_value := 0.0
	var max_value := 1.0
	var step := 1.0 if is_int else 0.01
	if parts.size() >= 2:
		min_value = parts[0].to_float()
		max_value = parts[1].to_float()
	if parts.size() >= 3:
		step = absf(parts[2].to_float())
	if is_int:
		step = 1.0
	if step <= 0.0:
		step = 0.0001
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.allow_greater = hint_string.contains("or_greater")
	slider.allow_lesser = hint_string.contains("or_lesser")
	slider.scrollable = false
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = float(obj.get(property))
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 48.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format_number(slider.value, step)
	row.add_child(value_label)

	var dragging := [false]
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = _format_number(value, step)
		write.call(roundi(value) if is_int else value))
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void: dragging[0] = false)
	bindings.append({
		"busy": Callable(self, "_range_busy").bind(slider, dragging),
		"refresh": Callable(self, "_refresh_range").bind(obj, property, slider, value_label, step),
	})


func _add_spin_editor(row: HBoxContainer, obj: Object, property: StringName, is_int: bool, write: Callable, bindings: Array) -> void:
	var value := float(obj.get(property))
	var spin := SpinBox.new()
	spin.min_value = -1.0e9
	spin.max_value = 1.0e9
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.step = 1.0 if is_int else (0.001 if absf(value) < 10.0 else 0.1)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value = value
	spin.value_changed.connect(func(new_value: float) -> void: write.call(roundi(new_value) if is_int else new_value))
	row.add_child(spin)
	bindings.append({
		"busy": Callable(self, "_focus_busy").bind(spin.get_line_edit()),
		"refresh": Callable(self, "_refresh_spin").bind(obj, property, spin),
	})


func _add_color_editor(row: HBoxContainer, obj: Object, property: StringName, write: Callable, bindings: Array) -> void:
	var picker := ColorPickerButton.new()
	picker.edit_alpha = true
	picker.custom_minimum_size.x = 56.0
	picker.color = obj.get(property)
	picker.color_changed.connect(func(color: Color) -> void: write.call(color))
	row.add_child(picker)
	bindings.append({
		"busy": Callable(self, "_popup_busy").bind(picker),
		"refresh": Callable(self, "_refresh_color").bind(obj, property, picker),
	})


func _add_vector_editor(row: HBoxContainer, obj: Object, property: StringName, is_int: bool, write: Callable, bindings: Array) -> void:
	var value: Variant = obj.get(property)
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var spin_x := _make_vector_spin(is_int)
	var spin_y := _make_vector_spin(is_int)
	spin_x.value = float(value.x)
	spin_y.value = float(value.y)
	box.add_child(spin_x)
	box.add_child(spin_y)
	row.add_child(box)
	var apply := func() -> void:
		if is_int:
			write.call(Vector2i(roundi(spin_x.value), roundi(spin_y.value)))
		else:
			write.call(Vector2(spin_x.value, spin_y.value))
	spin_x.value_changed.connect(func(_new_value: float) -> void: apply.call())
	spin_y.value_changed.connect(func(_new_value: float) -> void: apply.call())
	bindings.append({
		"busy": Callable(self, "_focus_busy").bind(spin_x.get_line_edit()),
		"refresh": Callable(self, "_refresh_vector").bind(obj, property, spin_x, spin_y, is_int),
	})


func _make_vector_spin(is_int: bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -1.0e9
	spin.max_value = 1.0e9
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.step = 1.0 if is_int else 0.001
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _add_string_editor(row: HBoxContainer, obj: Object, property: StringName, write: Callable, bindings: Array) -> void:
	var edit := LineEdit.new()
	edit.text = String(obj.get(property))
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(text: String) -> void: write.call(text))
	row.add_child(edit)
	bindings.append({
		"busy": Callable(self, "_focus_busy").bind(edit),
		"refresh": Callable(self, "_refresh_string").bind(obj, property, edit),
	})


func _add_read_only_row(row: HBoxContainer, obj: Object, property: StringName, bindings: Array) -> void:
	var value_label := Label.new()
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.clip_text = true
	value_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	value_label.text = _describe_value(obj.get(property))
	value_label.tooltip_text = value_label.text
	row.add_child(value_label)
	bindings.append({
		"busy": Callable(self, "_never_busy"),
		"refresh": Callable(self, "_refresh_read_only").bind(obj, property, value_label),
	})


# ── Widget refresh ───────────────────────────────────────────────────────────

func _refresh_bindings(bindings: Array) -> void:
	for binding in bindings:
		if binding["busy"].call():
			continue
		binding["refresh"].call()


func _never_busy() -> bool:
	return false


func _focus_busy(control: Control) -> bool:
	return control.has_focus()


func _range_busy(slider: HSlider, dragging: Array) -> bool:
	return dragging[0] or slider.has_focus()


func _popup_busy(button) -> bool:
	var popup = button.get_popup()
	return popup != null and popup.visible


func _refresh_bool(obj: Object, property: StringName, check: CheckBox) -> void:
	var value := bool(obj.get(property))
	if check.button_pressed != value:
		check.set_pressed_no_signal(value)


func _refresh_enum(obj: Object, property: StringName, option: OptionButton, ids: Array) -> void:
	var index := ids.find(int(obj.get(property)))
	if index >= 0 and option.selected != index:
		option.select(index)


func _refresh_range(obj: Object, property: StringName, slider: HSlider, value_label: Label, step: float) -> void:
	var value := float(obj.get(property))
	if not is_equal_approx(slider.value, value):
		slider.set_value_no_signal(value)
	value_label.text = _format_number(value, step)


func _refresh_spin(obj: Object, property: StringName, spin: SpinBox) -> void:
	var value := float(obj.get(property))
	if not is_equal_approx(spin.value, value):
		spin.set_value_no_signal(value)


func _refresh_color(obj: Object, property: StringName, picker: ColorPickerButton) -> void:
	var value: Color = obj.get(property)
	if picker.color != value:
		picker.color = value


func _refresh_vector(obj: Object, property: StringName, spin_x: SpinBox, spin_y: SpinBox, _is_int: bool) -> void:
	var value: Variant = obj.get(property)
	var x := float(value.x)
	var y := float(value.y)
	if not is_equal_approx(spin_x.value, x):
		spin_x.set_value_no_signal(x)
	if not is_equal_approx(spin_y.value, y):
		spin_y.set_value_no_signal(y)


func _refresh_string(obj: Object, property: StringName, edit: LineEdit) -> void:
	var value := String(obj.get(property))
	if edit.text != value:
		edit.text = value


func _refresh_read_only(obj: Object, property: StringName, value_label: Label) -> void:
	var text := _describe_value(obj.get(property))
	if value_label.text != text:
		value_label.text = text
		value_label.tooltip_text = text


# ── Formatting helpers ───────────────────────────────────────────────────────

func _format_number(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % roundi(value)
	var decimals := 2
	if step < 0.01:
		decimals = 4
	elif step < 0.1:
		decimals = 3
	return String.num(value, decimals)


func _describe_value(value: Variant) -> String:
	if value == null:
		return "—"
	if value is Texture2D:
		var texture := value as Texture2D
		var name := texture.get_class()
		if not texture.resource_path.is_empty():
			name = texture.resource_path.get_file()
		return "%s (%dx%d)" % [name, texture.get_width(), texture.get_height()]
	if value is Node:
		var node := value as Node
		return str(node.get_path()) if node.is_inside_tree() else String(node.name)
	if value is Resource:
		var resource := value as Resource
		return resource.resource_path.get_file() if not resource.resource_path.is_empty() else resource.get_class()
	return str(value)


func _clear_container(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
