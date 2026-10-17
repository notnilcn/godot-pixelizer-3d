@tool
class_name PixelizerApplier3D
extends Node3D

## Pixelizer entry point. Every supported geometry node (MeshInstance3D,
## MultiMeshInstance3D, GPUParticles3D, CPUParticles3D) under this node is bound
## through a `PixelizerGeometryState`; a `PixelizerObjectProfile` targeting the
## geometry overrides the applier's settings. A nested `PixelizerApplier3D` owns
## its own subtree (child appliers override the parent). Properties left at the
## inherit sentinel (`PixelizerInherit.INHERIT`) take the nearest ancestor
## applier's value, or the manager's default.
##
## The manager is explicit: a top-level applier binds the sibling node named
## `PixelizerManager3D` (or the explicit `manager` export); a nested applier
## binds its parent applier's manager. No manager means a configuration warning
## and no pixelization. Runtime additions are still picked up through
## `SceneTree.node_added` (filtered by `is_ancestor_of`) and drained in
## `_process`, so children finish `_ready` before they are bound.
##
## `editor_preview` on the manager runs this applier live in the editor (and
## restores authored materials before the scene is saved).

@export var enabled := true:
	set(value):
		enabled = value
		if not is_inside_tree() or Engine.is_editor_hint():
			return
		if enabled:
			if _ready_done:
				rescan()
			else:
				_bootstrap()
		elif _ready_done and manager != null:
			_unbind_states()
## Manager this applier binds through. Top-level: defaults to the sibling named
## `PixelizerManager3D`. Nested: defaults to the parent applier's manager.
@export var manager: PixelizerManager3D
## -1 inherits from the parent applier or the manager default.
@export_range(-10, 5) var pixel_size := PixelizerInherit.INHERIT:
	set(value):
		pixel_size = value
		_refresh_children()
## Outline id shared by every mesh in this subtree (no internal seams); the
## inherit sentinel auto-allocates from the manager. 255 is reserved for the
## focus subject.
@export_range(-10, 254) var outline_id := PixelizerInherit.INHERIT:
	set(value):
		outline_id = value
		_refresh_children()
## Register `outline_color` for this subtree's id in the outline palette.
@export var override_outline_color := false:
	set(value):
		override_outline_color = value
		_refresh_children()
## Outline colour used when `override_outline_color` is set (or `outline_enabled`
## re-enabled without a palette entry). The alpha is the row opacity: `0` hides
## this subtree's outline entirely, `1` replaces the scene colour.
@export var outline_color := Color(0.04, 0.05, 0.09, 1.0):
	set(value):
		outline_color = value
		_refresh_children()
## Inherit = parent applier, then the manager's `outline_enabled`; 0 hides this
## subtree's screen-space outline entirely, 1 forces it on.
@export_range(-10, 1) var outline_enabled := PixelizerInherit.INHERIT:
	set(value):
		outline_enabled = value
		_refresh_children()
## Inherit = parent applier or the manager default.
@export_range(-10, 1) var palette_enabled := PixelizerInherit.INHERIT:
	set(value):
		palette_enabled = value
		_refresh_children()
## Inherit = parent applier or the manager default.
@export_range(-10, 1) var dither_enabled := PixelizerInherit.INHERIT:
	set(value):
		dither_enabled = value
		_refresh_children()
## Inherit; 0 = PER_OBJECT, 1 = UNIFIED (see PixelizerGeometryState.anchor_mode).
@export_range(-10, 1) var anchor_mode := PixelizerInherit.INHERIT:
	set(value):
		anchor_mode = value
		_refresh_children()
## 0 = keep shadow casting, 1 = force off (the safe default for anchor-clipped
## meshes). Inherit = parent applier or the default.
@export_range(-10, 1) var shadow_casting := PixelizerInherit.INHERIT:
	set(value):
		shadow_casting = value
		_refresh_children()
## Opt-in periodic re-scan in seconds (0 disables). Covers nodes that move into
## the subtree without emitting `node_added` (rare).
@export_range(0.0, 10.0, 0.1) var rescan_interval := 0.0:
	set(value):
		rescan_interval = value
		if _ready_done:
			set_process(rescan_interval > 0.0)
## Inherit; 0 = off, 1 = snap this subtree's geometry onto the pixel lattice
## every frame (manager.register_mover). Orthographic cameras only.
@export_range(-10, 1) var mover_snap := PixelizerInherit.INHERIT:
	set(value):
		mover_snap = value
		_refresh_children()
## Skip subtrees whose root is in this group (lights, markers, custom content).
@export var ignore_group: StringName = &"pixelizer_ignore"

const BRIDGE_WATCH_INTERVAL := 0.25

## Inheritable settings. `settings` names the `PixelizerSettings` property used
## as the final fallback ("" when the settings have no equivalent); `default` is
## the built-in value. A property equal to the manager's `inherit_sentinel`
## falls through.
const INHERITED_SETTINGS := {
	"pixel_size": {"settings": "default_pixel_size", "default": 3},
	"palette_enabled": {"settings": "", "default": 1},
	"dither_enabled": {"settings": "default_dither_enabled", "default": 1},
	"anchor_mode": {"settings": "", "default": 0},
	"outline_enabled": {"settings": "default_outline_enabled", "default": 1},
	"shadow_casting": {"settings": "", "default": 1},
	"mover_snap": {"settings": "default_mover_snap", "default": 0},
}

## geometry instance id -> PixelizerGeometryState.
var _states: Dictionary = {}
## instance id -> state that needs the throttled bridge poll (nothing to inspect
## yet, or a bridge swap actually happened).
var _watch_ids: Dictionary = {}
## Nodes added under this applier this frame; drained in `_process` (after their
## `_ready`) so material registration in child `_ready` has run.
var _queue: Array = []
var _rescan_accum := 0.0
var _watch_elapsed := 0.0
var _ready_done := false
var _rescan_queued := false
## One-shot guards for configuration diagnostics.
var _manager_error_reported := false
var _mover_unified_reported := false
var _mover_perspective_reported := false
## Resolved effective values, computed once per rescan so `_pixelize_geometry`
## does not re-walk the ancestor chain for every geometry node.
var _effective: Dictionary = {}


func _enter_tree() -> void:
	if Engine.is_editor_hint() and not _editor_preview():
		return
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


func _ready() -> void:
	if Engine.is_editor_hint() and not _editor_preview():
		return
	if enabled:
		if Engine.is_editor_hint():
			# Defer so the manager's services exist regardless of sibling order.
			call_deferred("_bootstrap")
		else:
			_bootstrap()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	# Restore authored materials before serialization; re-bind after the save.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_unbind_states()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if _editor_preview() and enabled:
			rescan()


## One-time setup: resolve the manager, allocate the outline id, apply the
## outline-colour override and run the first scan.
func _bootstrap() -> void:
	if _ready_done:
		return
	_find_manager()
	if manager == null:
		_report_missing_manager()
		return
	if outline_id == PixelizerInherit.INHERIT:
		outline_id = manager.allocate_outline_id()
	_ready_done = true
	if override_outline_color:
		manager.set_outline_color(outline_id, outline_color)
	set_process(rescan_interval > 0.0)
	_resolve_effective()
	_scan(self)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	_unbind_states()
	_queue.clear()


func _unbind_states() -> void:
	for state in _states.values():
		(state as PixelizerGeometryState).unbind()
	_states.clear()
	_watch_ids.clear()


func _process(delta: float) -> void:
	if not _manager_valid():
		set_process(false)
		return
	if rescan_interval > 0.0:
		_rescan_accum += delta
		if _rescan_accum >= rescan_interval:
			_rescan_accum = 0.0
			_scan(self)
	if not _queue.is_empty():
		var nodes: Array = _queue
		_queue = []
		for node in nodes:
			if is_instance_valid(node) and is_ancestor_of(node):
				_scan(node)
	if not _watch_ids.is_empty():
		_watch_elapsed += delta
		if _watch_elapsed >= BRIDGE_WATCH_INTERVAL:
			_watch_elapsed = 0.0
			_poll_bridge_watch()
	if _queue.is_empty() and _watch_ids.is_empty() and rescan_interval <= 0.0:
		set_process(false)


## Deferred by nature: node_added fires during tree entry; draining in `_process`
## keeps the "children finish `_ready` before bind" ordering (important for
## fireflies / glow material registration).
func _on_node_added(node: Node) -> void:
	if not enabled or not _manager_valid():
		return
	if node == self or not is_ancestor_of(node):
		return
	_queue.append(node)
	set_process(true)


## Re-configure live when an applier property changes after _ready. Coalesced:
## a burst of setters queues one deferred rescan instead of running a full
## subtree scan per setter.
func _refresh_children() -> void:
	if not _ready_done or manager == null or not is_inside_tree():
		return
	if _rescan_queued:
		return
	_rescan_queued = true
	call_deferred("_flush_rescan")


func _flush_rescan() -> void:
	_rescan_queued = false
	if not _ready_done or manager == null or not is_inside_tree():
		return
	rescan()


## Manual fallback: re-scans the subtree (the live watcher normally handles
## runtime additions). Nested appliers are re-derived too, so an inherited
## property change on this applier propagates down.
func rescan() -> void:
	# A disabled applier stays unbound: settings changes and late material
	# registrations re-scan every applier, and must not re-bind this subtree.
	if not enabled or not _manager_valid():
		return
	_resolve_effective()
	_scan(self)
	for child in get_children():
		if child is PixelizerApplier3D and child != self:
			(child as PixelizerApplier3D).rescan()


## Number of geometry nodes this applier currently tracks (bound or waiting for
## materials). The diagnostics object panel labels the applier section with it.
func get_bound_state_count() -> int:
	return _states.size()


## Called when a `PixelizerObjectProfile` changes so the bound geometry refreshes.
func reconfigure(geometry: GeometryInstance3D) -> void:
	if geometry == null or not is_instance_valid(geometry) or not is_ancestor_of(geometry):
		return
	_pixelize_geometry(geometry)


## True while the shared manager exists and is alive.
func _manager_valid() -> bool:
	return manager != null and is_instance_valid(manager)


## True when the manager's editor preview is active (editor only). Resolves the
## manager without allocating so it works before `_ready`.
func _editor_preview() -> bool:
	var resolved := manager
	if resolved == null or not is_instance_valid(resolved):
		resolved = PixelizerManager3D.resolve_manager_explicit(self)
	return resolved != null and is_instance_valid(resolved) and resolved.editor_preview


## Resolve the shared manager explicitly (ancestor applier -> manager ancestor ->
## sibling `PixelizerManager3D`). Never creates one.
func _find_manager() -> void:
	if manager != null and is_instance_valid(manager):
		_connect_manager_signals()
		return
	manager = PixelizerManager3D.resolve_manager_explicit(self)
	if manager != null:
		_connect_manager_signals()


func _connect_manager_signals() -> void:
	if manager == null:
		return
	if not manager.tree_exiting.is_connected(_on_manager_tree_exiting):
		manager.tree_exiting.connect(_on_manager_tree_exiting, CONNECT_ONE_SHOT)
	if not manager.settings_changed.is_connected(_on_settings_changed):
		manager.settings_changed.connect(_on_settings_changed)
	if not manager.pixelized_material_registered.is_connected(_on_pixelized_material_registered):
		manager.pixelized_material_registered.connect(_on_pixelized_material_registered)


## A look-settings change alters inherited defaults: re-derive this subtree.
func _on_settings_changed() -> void:
	if _ready_done:
		_refresh_children()


## A custom material opted in after this subtree was scanned (effect nodes
## register deferred, after the applier's first bind attempt): re-scan when some
## node here is still unbound, so it binds now instead of staying skipped.
func _on_pixelized_material_registered(_material: ShaderMaterial) -> void:
	if not _ready_done:
		return
	for state in _states.values():
		if not (state as PixelizerGeometryState).is_applied():
			_refresh_children()
			return


## One loud report per applier when no manager resolves.
func _report_missing_manager() -> void:
	if _manager_error_reported:
		return
	_manager_error_reported = true
	push_error("Pixelizer3D: PixelizerApplier3D at '%s' found no PixelizerManager3D. Add a sibling node named exactly \"PixelizerManager3D\" (top level) or place this applier under another applier; nothing is pixelized until one resolves." % get_path())


## The shared manager left the tree while this applier is still running: recover
## after the tree has settled (resolve again; never create).
func _on_manager_tree_exiting() -> void:
	if not is_inside_tree():
		return
	manager = null
	call_deferred("_recover_manager")


func _recover_manager() -> void:
	if not is_inside_tree() or _manager_valid():
		return
	_unbind_states()
	_find_manager()
	rescan()


func _scan(root: Node) -> void:
	_prune_states()
	# The watcher hands entered children straight to `_scan`, so the skips the
	# child loop applies must also guard the entry point (nested appliers own
	# their subtree; ignored nodes stay untouched).
	if root != self:
		if root is PixelizerApplier3D or root is PixelizerManager3D:
			return
		if root is Node and root.is_in_group(ignore_group):
			return
	if PixelizerGeometryState.is_supported_node(root):
		_pixelize_geometry(root as GeometryInstance3D)
	for child in root.get_children():
		if child is PixelizerManager3D:
			continue
		if child is PixelizerApplier3D and child != self:
			continue
		if child is Node and child.is_in_group(ignore_group):
			continue
		_scan(child)


func _pixelize_geometry(instance: GeometryInstance3D) -> void:
	if not _manager_valid():
		return
	var id := instance.get_instance_id()
	var state: PixelizerGeometryState = _states.get(id)
	if state == null:
		state = PixelizerGeometryState.new(instance)
		_states[id] = state
	var profile := manager.get_object_profile(instance)
	if profile != null:
		if not profile.enabled:
			if state.is_applied():
				state.unbind()
			return
		_apply_profile_to_state(state, profile)
	else:
		_apply_effective_to_state(state)
	if state.is_applied():
		state.apply_shadow_setting()
		# Re-run the manifest lookup: a system may have replaced the material
		# after the first bind (MST's runtime texture baker swaps every chunk
		# mesh to its own baked shader). A swap re-arms the watchdog so the next
		# replacement is bridged too.
		if state.refresh_bridge(manager) and not _watch_ids.has(id):
			_watch_ids[id] = state
			set_process(true)
		state.push_instance_params()
		_apply_mover(instance)
		return
	if state.bind(manager):
		_apply_mover(instance)
		if state.bridge_swapped():
			# A swap happened, so the owning system may swap again later; keep
			# polling. (Only a failed bind used to arm the watchdog, so a
			# successful bind that swapped was never re-checked.)
			_watch_ids[id] = state
			set_process(true)
		return
	if state.has_no_materials() or state.bridge_swapped():
		_watch_ids[id] = state
		set_process(true)
	_apply_mover(instance)


func _apply_effective_to_state(state: PixelizerGeometryState) -> void:
	state.pixel_size = _effective["pixel_size"]
	state.outline_id = outline_id
	state.override_outline_color = override_outline_color
	state.outline_color = outline_color
	state.outline_enabled = _effective["outline_enabled"] != 0
	state.palette_enabled = _effective["palette_enabled"] != 0
	state.dither_enabled = _effective["dither_enabled"] != 0
	state.anchor_mode = _effective["anchor_mode"]
	state.disable_shadows = _effective["shadow_casting"] != 0


## Apply a `PixelizerObjectProfile`, falling through to this applier's effective
## values for every field left at the inherit sentinel.
func _apply_profile_to_state(state: PixelizerGeometryState, profile: PixelizerObjectProfile) -> void:
	state.pixel_size = _effective["pixel_size"] if PixelizerInherit.is_inherit(profile.pixel_size, _sentinel()) else profile.pixel_size
	state.anchor_mode = _effective["anchor_mode"] if PixelizerInherit.is_inherit(profile.anchor_mode, _sentinel()) else profile.anchor_mode
	state.palette_enabled = (_effective["palette_enabled"] != 0) if PixelizerInherit.is_inherit(profile.palette_enabled, _sentinel()) else profile.palette_enabled
	state.dither_enabled = (_effective["dither_enabled"] != 0) if PixelizerInherit.is_inherit(profile.dither_enabled, _sentinel()) else profile.dither_enabled
	state.outline_enabled = (_effective["outline_enabled"] != 0) if PixelizerInherit.is_inherit(profile.outline_enabled, _sentinel()) else (profile.outline_enabled != 0)
	match profile.outline_id_mode:
		PixelizerObjectProfile.OutlineIdMode.AUTO:
			state.outline_id = manager.allocate_outline_id()
		PixelizerObjectProfile.OutlineIdMode.EXPLICIT:
			state.outline_id = profile.outline_id
		_:
			state.outline_id = outline_id
	state.override_outline_color = profile.override_outline_color
	state.outline_color = profile.outline_color
	state.disable_shadows = _effective["shadow_casting"] != 0


func _apply_mover(instance: GeometryInstance3D) -> void:
	if not _manager_valid():
		return
	if _effective["mover_snap"] != 0:
		if _effective["anchor_mode"] == 1 and not _mover_unified_reported:
			_mover_unified_reported = true
			push_error("Pixelizer3D: mover_snap is enabled but the applier's anchor_mode is UNIFIED; mover snap only works with PER_OBJECT lattices and is a silent no-op here.")
		var cam := manager.get_active_camera()
		if cam != null and is_instance_valid(cam) and cam.projection != Camera3D.PROJECTION_ORTHOGONAL and not _mover_perspective_reported:
			_mover_perspective_reported = true
			push_error("Pixelizer3D: mover_snap is enabled but the active camera is perspective; mover snap is orthographic-only and is a silent no-op here.")
		manager.register_mover(instance)
	else:
		manager.unregister_mover(instance)


## Throttled bridge poll over the watched states: retry the bind while there is
## nothing to inspect yet, and re-run the manifest lookup on already-applied
## states (MST's runtime texture baker swaps materials after the first bind).
## Entries are intentionally not pruned once they settle: a system can replace a
## bridged material arbitrarily later, and the set is bounded by the subtree's
## geometry count.
func _poll_bridge_watch() -> void:
	var dead: Array = []
	for id in _watch_ids:
		var state: PixelizerGeometryState = _watch_ids[id]
		if state.target == null or not is_instance_valid(state.target):
			dead.append(id)
			continue
		if not state.is_applied():
			if state.bind(manager):
				continue
			if not (state.has_no_materials() or state.bridge_swapped()):
				dead.append(id)
			continue
		state.refresh_bridge(manager)
	for id in dead:
		_watch_ids.erase(id)


## Drop states whose target was freed or left this subtree (restoring authored
## materials when it did).
func _prune_states() -> void:
	var dead: Array = []
	for id in _states:
		var state: PixelizerGeometryState = _states[id]
		var target := state.target
		if target == null or not is_instance_valid(target) or not is_ancestor_of(target):
			dead.append(id)
	for id in dead:
		var state: PixelizerGeometryState = _states[id]
		state.unbind()
		_states.erase(id)
		_watch_ids.erase(id)


# ── Inheritance resolution ───────────────────────────────────────────────────

## Resolve the inherited values once per scan; `_apply_effective_to_state` reads
## `_effective` instead of re-walking the ancestor chain per node.
func _resolve_effective() -> void:
	_effective.clear()
	for setting in INHERITED_SETTINGS:
		_effective[setting] = _resolve_setting(setting)


## One setting, resolved nearest-author-wins: this applier (when it is not the
## inherit sentinel), then ancestor appliers, then the manager's look settings,
## then the built-in default.
func _resolve_setting(setting: String) -> int:
	var spec: Dictionary = INHERITED_SETTINGS[setting]
	if not PixelizerInherit.is_inherit(int(get(setting)), _sentinel()):
		return int(get(setting))
	var parent := _parent_applier()
	if parent != null:
		return parent._resolve_setting(setting)
	var settings_property: String = spec["settings"]
	if settings_property != "" and _manager_valid():
		var look: PixelizerSettings = manager.get_settings()
		if look != null:
			var value = look.get(settings_property)
			return (1 if value else 0) if value is bool else int(value)
	return int(spec["default"])


## The sentinel that means "inherit" for this applier: the manager's adjustable
## value, or the central default when no manager is resolved.
func _sentinel() -> int:
	if manager != null and is_instance_valid(manager):
		return manager.inherit_sentinel
	return PixelizerInherit.INHERIT


func _parent_applier() -> PixelizerApplier3D:
	var node: Node = get_parent()
	while node != null:
		if node is PixelizerApplier3D:
			return node as PixelizerApplier3D
		node = node.get_parent()
	return null


# ── Configuration warnings (scene-tree banner) ───────────────────────────────

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var resolved := manager
	if resolved == null or not is_instance_valid(resolved):
		resolved = PixelizerManager3D.resolve_manager_explicit(self)
	if resolved == null:
		warnings.append("No PixelizerManager3D: add a sibling node named exactly \"PixelizerManager3D\" at the top level, or nest this applier under another applier.")
	else:
		var sentinel: int = resolved.inherit_sentinel
		if not PixelizerInherit.validate_sentinel(sentinel):
			warnings.append("The manager's inherit_sentinel is not negative and can collide with real values.")
		var effective := _resolve_setting("mover_snap")
		if effective != 0:
			var mode := PixelizerManager3D.resolve_manager_explicit(self)
			if mode != null and mode.get_active_camera() != null \
					and mode.get_active_camera().projection != Camera3D.PROJECTION_ORTHOGONAL:
				warnings.append("mover_snap is enabled but the active camera is perspective; mover snap is orthographic-only and will be a silent no-op.")
			if _resolve_setting("anchor_mode") == 1:
				warnings.append("mover_snap is enabled but anchor_mode resolves to UNIFIED; mover snap is a no-op under UNIFIED.")
	return warnings
