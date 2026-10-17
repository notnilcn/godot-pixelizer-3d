@tool
class_name PixelizerManager3D
extends Node3D

## Pixelizer3D pipeline driver: owns the metadata SubViewport + camera, attaches
## the compositor effects to the active Camera3D, exposes the shared pipeline
## settings, and keeps the metadata camera in sync.
##
## The manager is **explicit** wiring: place one `PixelizerManager3D` node in the
## scene (a sibling of the appliers/effects that use it). Appliers no longer
## create one automatically; a top-level applier resolves the sibling named
## `PixelizerManager3D`, and a nested applier resolves its parent applier's
## manager. `editor_preview` runs the pipeline live in the editor 3D viewport
## (toggleable, non-destructive).

enum Mode { ANCHOR, LOW_RES }

## Selects the apply pass's debug output (see apply_pixelization.glsl).
enum DebugView {
	NORMAL, ## Full pixelization (view 0).
	ANCHOR_MAP, ## Anchor offsets as colour.
	METADATA, ## Raw metadata payload.
	LINEAR_DEPTH, ## Linearised scene depth.
	COLOR_COPY, ## Pre-pixelization colour copy.
	SHIFTED_SAMPLE, ## Replicated colour without the occlusion guard.
	OCCLUSION_FLAGS, ## Occlusion diagnostics as binary flags.
	RAW_DEPTH, ## Raw depth at this pixel.
	ANCHOR_RAW_DEPTH, ## Raw depth at the snapped anchor.
	REVERT_FLAG, ## Occlusion revert decisions.
}

@export_group("General")
## Master toggle. Disabling detaches the pipeline: the manager stops syncing and
## the bound camera's compositor / cull-mask changes are restored (the applier
## materials stay converted — set the appliers' `enabled = false` for a plain
## baseline; `demo/capture.gd --plain` does both).
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not is_inside_tree() or _camera == null:
			return
		if enabled:
			# Re-resolve and re-attach on the next update; unbind saved the
			# authored camera state.
			_camera.update()
		else:
			_camera.unbind(_camera.bound_camera)
@export var mode: Mode = Mode.ANCHOR:
	set(value):
		if mode == value:
			return
		mode = value
		if is_inside_tree():
			_apply_mode()
## Run the pixelizer live in the editor 3D viewport. Preview binds are restored
## before the scene is saved, so converted materials are never written to disk.
@export var editor_preview := false:
	set(value):
		if editor_preview == value:
			return
		editor_preview = value
		if Engine.is_editor_hint():
			call_deferred("_refresh_editor_preview")
## The magic value that means "inherit" on applier / profile properties. Must be
## negative (every inheritable property is non-negative or a 0-based enum) and
## is validated by `_get_configuration_warnings()`.
@export var inherit_sentinel := PixelizerInherit.INHERIT
## Per-object overrides, replacing the old `PixelizerObject3D` child node. Each
## profile's `target` is the geometry node it configures.
@export var object_profiles: Array[PixelizerObjectProfile] = []
## Directional light used by cloud shadows / god rays. Left unset, the manager
## binds the first sibling `DirectionalLight3D`; several siblings is ambiguous
## and is reported. (Stays on the manager: a scene-node reference cannot be
## serialized inside a Resource.)
@export var sun: DirectionalLight3D:
	set(value):
		sun = value
		_sun_resolved = true

@export_group("Look")
## Per-scene look: the resolution model, palette, outline tuning, camera snap and
## the applier inherit defaults (see `PixelizerSettings`). Auto-created when
## unset, so existing scenes keep working; assign a saved resource to make the
## look diffable and swappable (one settings resource per camera is the point).
@export var settings: PixelizerSettings:
	set(value):
		if settings == value:
			return
		settings = value
		if is_inside_tree():
			_bind_settings()
## Phase origin for the camera snap; world origin is used when unset. (Node
## reference: stays on the manager.)
@export var snap_origin: Node3D
## Target of `auto_focus` (node reference: stays on the manager).
@export var auto_focus_target: Node3D
## Forwarded to `settings.global_palette_lut`. The name is the main-client
## contract: external pipeline components probe the property list and push their
## LUT here, so it stays reachable on the manager even though the value lives in
## the settings resource.
var global_palette_lut: Texture2D:
	get:
		return get_settings().global_palette_lut
	set(value):
		get_settings().global_palette_lut = value

@export_group("Metadata")
## Rendering layer reserved for the metadata camera (1-20).
@export_range(1, 20) var metadata_layer := 20
## The manager must sync the metadata camera after camera hosts (PhantomCamera
## Host runs at 300); 301 is the default.
@export var sync_process_priority := 301

@export_group("Shader Bridge")
## Manifests of approved bridge entries (see the Pixelizer3D bridge dock). The
## registry maps each approved, non-stale source shader to a pre-generated
## `.gdshader`; runtime only performs a lookup + in-place shader swap. There is
## no runtime source generation.
@export var bridge_manifests: Array[PixelizerBridgeManifest] = []:
	set(value):
		bridge_manifests = value
		if is_node_ready():
			_rebuild_bridge_registry()
## Safety switch: when false (default) custom ShaderMaterials are left exactly as
## authored, even if a manifest entry is approved. Enable to let objects swap in
## their pre-generated bridge shader. Only approved, non-stale entries apply.
@export var auto_bridge_custom_shaders := false

@export_group("Debug")
@export var debug_view: DebugView = DebugView.NORMAL

var metadata_bit := 0
## True once `sun` was authored (explicitly assigned or resolved from a sibling),
## so the per-frame resolver stops probing.
var _sun_resolved := false
## One-shot guards for the loud diagnostics.
var _sun_error_reported := false
var _preview_active := false
## Settings resource currently connected to `_on_settings_changed`.
var _bound_settings: PixelizerSettings

var _camera: PixelizerCameraBinding
var _clouds: PixelizerCloudField
var _outlines: PixelizerOutlineRegistry
var _focus: PixelizerFocus
var _lowres: PixelizerLowResView
var _compositor: Compositor
var _snapshot_effect: PixelizerSnapshotEffect
var _apply_effect: PixelizerApplyPixelizationEffect
var _material_factory: PixelizerMaterialFactory
var _rd_warned := false
## Manifest-backed lookup of pre-generated bridge shaders (never generates).
var _bridge_registry: PixelizerBridgeRegistry
var _palette_dirty := true
## Number of scene effects inserted before the snapshot pass (god rays today);
## reported by the diagnostics HUD.
var _pre_effect_count := 0
## Effects added before the compositor existed; inserted once it is created.
var _pending_pre_effects: Array[CompositorEffect] = []

## Process-wide manager count + one-shot warning flag. The pipeline-wide
## parameters (metadata bit, screen size, low-res flag, palette LUT/dither) are
## global shader uniforms, so two live managers silently overwrite each other;
## per-viewport managers need those to move to per-material parameters first.
static var _live_managers := 0
static var _multi_manager_warned := false


## Emitted after a look field changed or the settings resource was replaced.
## Appliers re-resolve their inherited defaults from it; other consumers may
## re-read. The manager itself re-publishes the pipeline globals.
signal settings_changed

## Emitted when a custom material opts in through `register_pixelized_material()`.
## Appliers re-scan, so a node whose first bind ran before the (usually
## deferred) registration is bound instead of staying skipped.
signal pixelized_material_registered(material: ShaderMaterial)


## Register the pipeline-wide globals before any material specializes: a shader
## that declares a global registered later warns "removed at some point". The
## group is joined here (not in `_ready`) so an applier whose `_ready` runs first
## finds a manager declared later in the scene.
func _enter_tree() -> void:
	add_to_group("pixelizer_manager")
	_live_managers += 1
	if _live_managers > 1 and not _multi_manager_warned:
		_multi_manager_warned = true
		push_warning("Pixelizer3D: %d PixelizerManager3D nodes are live in this process. Pipeline-wide parameters (metadata bit, screen size, low-res flag, palette LUT/dither) are global shader uniforms, so the managers overwrite each other; place a single manager per process. Splitting the globals per material is the prerequisite for multi-viewport support." % _live_managers)
	if metadata_layer < 1:
		metadata_layer = 1
	metadata_bit = 1 << (metadata_layer - 1)
	_ensure_services()
	PixelizerGlobals.ensure()
	PixelizerGlobals.set_param(PixelizerGlobals.META_BIT, metadata_bit)
	PixelizerGlobals.set_param(PixelizerGlobals.LOWRES_MODE, mode == Mode.LOW_RES)
	# Binds (creating if needed) the look settings and publishes the palette /
	# screen-size globals from them.
	_bind_settings()


## The RefCounted helpers are safe to create in the editor (no RenderingDevice
## work), so effects can register/unregister even before `_ready`.
func _ensure_services() -> void:
	if _camera == null:
		_camera = PixelizerCameraBinding.new()
		_camera.manager = self
	if _clouds == null:
		_clouds = PixelizerCloudField.new()
		_clouds.manager = self
	if _outlines == null:
		_outlines = PixelizerOutlineRegistry.new()
		_outlines.manager = self
	if _focus == null:
		_focus = PixelizerFocus.new()


## The look settings. Auto-created when the scene did not assign one, so scenes
## authored before the settings resource keep their behaviour; assign a saved
## `PixelizerSettings` to make the look diffable and persistable (an inline
## auto-created resource is not saved anywhere).
func get_settings() -> PixelizerSettings:
	if settings == null:
		settings = PixelizerSettings.new()
	return settings


func _bind_settings() -> void:
	var active := get_settings()
	if _bound_settings != active:
		if _bound_settings != null and _bound_settings.changed.is_connected(_on_settings_changed):
			_bound_settings.changed.disconnect(_on_settings_changed)
		_bound_settings = active
		active.changed.connect(_on_settings_changed)
	_on_settings_changed()


## A settings field changed (or the resource was replaced): re-publish the
## pipeline globals, drop cached palette/outline state and notify appliers.
func _on_settings_changed() -> void:
	if not is_inside_tree():
		return
	var active := get_settings()
	PixelizerGlobals.set_param(PixelizerGlobals.SCREEN_SIZE, Vector2(active.render_resolution))
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_LUT, active.global_palette_lut)
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_GRADING, active.global_palette_lut != null)
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_DITHER, active.default_dither_enabled)
	_palette_dirty = false
	if _outlines != null:
		_outlines.invalidate()
	_sync_normal_request()
	settings_changed.emit()


## The crease term reads the engine's normal-roughness buffer. Request it from
## the depth prepass (`CompositorEffect.needs_normal_roughness`) exactly while the term is
## on: without the request Forward+ may still have the texture allocated but
## never writes it (measured 2026-10-16: uninitialised contents), and with it
## always on every frame pays for the normal write.
func _sync_normal_request() -> void:
	if _apply_effect != null:
		_apply_effect.needs_normal_roughness = get_settings().outline_normal_threshold > 0.0


func _ready() -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return
	if _lowres != null:
		return
	process_priority = sync_process_priority
	_ensure_services()
	_lowres = PixelizerLowResView.new()
	_lowres.manager = self
	_lowres.name = "PixelizerLowResView"
	add_child(_lowres)
	_camera.create_metadata_viewport()
	# Create the compositor + passes up front. Camera binding happens later, when
	# an active camera is resolved.
	_ensure_compositor()
	if mode == Mode.LOW_RES:
		call_deferred("_apply_mode")
	_rebuild_bridge_registry()
	_resolve_sun()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return
	if not enabled:
		# Disabled = plain baseline: undo any snap offsets the manager applied.
		var active := _camera.active_camera
		if active != null and is_instance_valid(active):
			active.h_offset = 0.0
			active.v_offset = 0.0
		return
	_resolve_sun()
	_clouds.update()
	_update_palette_params()
	# Camera decoupling: resolve the viewport's active camera every frame so
	# switching `Camera3D.current` (or adding/removing cameras) just works.
	_camera.update()
	var cam := _camera.active_camera
	if cam == null:
		# No camera: cloud/palette params were still pushed to registered
		# materials (effects stay free-standing); nothing else to sync.
		return
	if mode == Mode.LOW_RES:
		if not _lowres.is_active():
			_enter_lowres()
		_camera.snap()
		_lowres.sync(cam)
		_lowres.update_display()
		return
	_camera.snap()
	_camera.sync_metadata_camera()
	_camera.update_metadata_texture()
	_focus.update_auto(get_settings().auto_focus, auto_focus_target)
	if get_settings().manage_camera_size:
		_camera.apply_managed_size(cam)


func _exit_tree() -> void:
	_live_managers = maxi(_live_managers - 1, 0)
	if _camera == null:
		return
	if _lowres != null and _lowres.is_active():
		_exit_lowres()
	_camera.unbind(_camera.bound_camera)


# ── Shader bridge registry ───────────────────────────────────────────────────

## The manifest-backed bridge lookup. Created lazily so objects can resolve
## before `_ready` runs; rebuilt on `_ready` and whenever `bridge_manifests`
## changes.
func get_bridge_registry() -> PixelizerBridgeRegistry:
	if _bridge_registry == null:
		_bridge_registry = PixelizerBridgeRegistry.new()
		_bridge_registry.build(bridge_manifests)
	return _bridge_registry


## Rebuild the registry from the current manifest list (approved + non-stale
## entries only). Cheap; safe to call on manifest change.
func _rebuild_bridge_registry() -> void:
	get_bridge_registry().build(bridge_manifests)


## Number of source shaders the registry can currently bridge.
func get_bridge_mapped_count() -> int:
	return get_bridge_registry().get_mapped_count()


## Human-readable registry warnings (missing outputs, stale sources, drift).
func get_bridge_warnings() -> PackedStringArray:
	return get_bridge_registry().get_warnings()


# ── Shared services ──────────────────────────────────────────────────────────

## Explicit manager resolution (the addon's default):
##   1. an ancestor `PixelizerApplier3D`'s manager,
##   2. an ancestor `PixelizerManager3D`,
##   3. a sibling of `node` or any ancestor named `PixelizerManager3D`
##      (top-level wiring),
##   4. none -> null (callers report the missing manager).
## There is no "first manager in the viewport" fallback: wiring is explicit.
## Checking siblings up the chain lets a nested applier inherit the manager that
## a top-level applier resolves, regardless of `_ready` ordering.
static func resolve_manager_explicit(node: Node) -> PixelizerManager3D:
	if node == null:
		return null
	var current: Node = node
	while current != null:
		if current is PixelizerApplier3D:
			var owned: PixelizerManager3D = (current as PixelizerApplier3D).manager
			if owned != null and is_instance_valid(owned):
				return owned
		elif current is PixelizerManager3D:
			return current as PixelizerManager3D
		current = current.get_parent()
	current = node
	while current != null:
		var parent := current.get_parent()
		if parent != null:
			for child in parent.get_children():
				if child is PixelizerManager3D and child.name == "PixelizerManager3D":
					return child as PixelizerManager3D
		current = parent
	return null


## Legacy resolver retained for the diagnostics overlay only (it can render a
## status line with no manager at all). Prefer `resolve_manager_explicit`.
static func resolve_manager(node: Node) -> PixelizerManager3D:
	var explicit := resolve_manager_explicit(node)
	if explicit != null:
		return explicit
	if node == null or not node.is_inside_tree():
		return null
	var viewport := node.get_viewport()
	for candidate in node.get_tree().get_nodes_in_group("pixelizer_manager"):
		if candidate is PixelizerManager3D and candidate.get_viewport() == viewport:
			return candidate as PixelizerManager3D
	return null


# ── Object profiles (per-object overrides) ───────────────────────────────────

## The profile configuring `geometry`, or null. Identity match against
## `object_profiles[].target`.
func get_object_profile(geometry: Node) -> PixelizerObjectProfile:
	if geometry == null:
		return null
	for profile in object_profiles:
		if profile != null and profile.resolve_target(self) == geometry:
			return profile
	return null


## Register a profile (adds it if absent) and optionally set its target.
func register_object_profile(profile: PixelizerObjectProfile, target: Node3D = null) -> void:
	if profile == null:
		return
	if target != null:
		profile.target = target
	if not object_profiles.has(profile):
		object_profiles.append(profile)


## Remove a profile and leave its target as authored.
func unregister_object_profile(profile: PixelizerObjectProfile) -> void:
	if profile == null:
		return
	object_profiles.erase(profile)


# ── Sun ──────────────────────────────────────────────────────────────────────

## Directional light for cloud shadows / god rays: an explicit `sun`, else the
## single sibling `DirectionalLight3D`. Ambiguous (several siblings) or absent is
## reported once.
func _resolve_sun() -> void:
	if _sun_resolved and sun != null and is_instance_valid(sun):
		return
	var siblings := _sibling_directional_lights()
	if siblings.size() == 1:
		sun = siblings[0]
		_sun_resolved = true
		return
	if siblings.size() > 1:
		_sun_resolved = true
		push_warning("Pixelizer3D: %d sibling DirectionalLight3D nodes found; cloud shadows / god rays use `manager.sun`, set it explicitly." % siblings.size())
		return
	# No sibling light and none authored.
	if not _sun_error_reported:
		_sun_error_reported = true
		push_error("Pixelizer3D: no DirectionalLight3D found for PixelizerManager3D at '%s'; cloud shadows and god rays fall back to a fixed downward direction. Add a sibling DirectionalLight3D or assign `sun`." % get_path())


func _sibling_directional_lights() -> Array[DirectionalLight3D]:
	var out: Array[DirectionalLight3D] = []
	if not is_inside_tree():
		return out
	var parent := get_parent()
	if parent == null:
		return out
	for child in parent.get_children():
		if child is DirectionalLight3D:
			out.append(child as DirectionalLight3D)
	return out


# ── Configuration warnings (scene-tree banner) ───────────────────────────────

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not PixelizerInherit.validate_sentinel(inherit_sentinel):
		warnings.append("inherit_sentinel %d is not negative; it can collide with a real property value (use %d)." % [inherit_sentinel, PixelizerInherit.INHERIT])
	var node_name := name
	if node_name != "PixelizerManager3D":
		warnings.append("Rename this node to exactly \"PixelizerManager3D\" so top-level appliers and effects can resolve it by sibling name.")
	if sun == null and _sibling_directional_lights().is_empty():
		warnings.append("No sun: add a sibling DirectionalLight3D or assign `sun` for cloud shadows / god rays.")
	if auto_bridge_custom_shaders and bridge_manifests.is_empty():
		warnings.append("auto_bridge_custom_shaders is on but bridge_manifests is empty; no custom shader will be bridged.")
	for profile in object_profiles:
		if profile == null:
			warnings.append("object_profiles contains a null entry.")
		elif profile.resolve_target(self) == null:
			warnings.append("An object profile has no resolvable target; set target_path or call register_object_profile with a target.")
	return warnings


# ── Editor preview ───────────────────────────────────────────────────────────

## Rebuild the preview pipeline when the toggle changes in the editor.
func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview:
		_preview_active = false
		return
	if is_inside_tree():
		_ready()


func is_editor_preview_active() -> bool:
	return Engine.is_editor_hint() and editor_preview


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	# Restore authored materials before the scene is serialized so preview
	# conversions are never written to disk.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_preview_active = false


func get_material_factory() -> PixelizerMaterialFactory:
	if _material_factory == null:
		_material_factory = PixelizerMaterialFactory.new()
	return _material_factory


func get_compositor() -> Compositor:
	_ensure_compositor()
	return _compositor


func get_metadata_texture_rid() -> RID:
	return _camera.get_metadata_texture_rid()


func get_metadata_viewport() -> SubViewport:
	return _camera.metadata_viewport


## The manager-owned low-res display view (null until `_ready` has run).
func get_lowres_view() -> PixelizerLowResView:
	return _lowres


# ── Compositor effects ───────────────────────────────────────────────────────

## One-time creation of the compositor + effect passes. Safe to call repeatedly;
## no-op once the compositor exists. Scene effects (god rays) insert themselves
## in front of the snapshot pass through `add_pre_pixelization_effect`.
func _ensure_compositor() -> void:
	if _compositor != null:
		return
	if RenderingServer.get_rendering_device() == null:
		if not _rd_warned:
			_rd_warned = true
			push_warning("Pixelizer3D: RenderingDevice unavailable (Compatibility renderer or headless); pixelization disabled.")
		return

	_snapshot_effect = PixelizerSnapshotEffect.new()
	_apply_effect = PixelizerApplyPixelizationEffect.new()
	_snapshot_effect.manager = self
	_apply_effect.manager = self
	_sync_normal_request()

	_compositor = Compositor.new()
	_compositor.compositor_effects = [_snapshot_effect, _apply_effect]
	_pre_effect_count = 0
	for effect in _pending_pre_effects:
		_insert_pre_effect(effect)
	_pending_pre_effects.clear()


## Insert a `CompositorEffect` before the snapshot/apply passes. Effects added
## here run before pixelization, so their output is replicated into macro
## pixels. The god-ray pass is the canonical user. Safe before the compositor
## exists (the effect is queued).
func add_pre_pixelization_effect(effect: CompositorEffect) -> void:
	if effect == null:
		return
	if _compositor == null:
		if not _pending_pre_effects.has(effect):
			_pending_pre_effects.append(effect)
		return
	_insert_pre_effect(effect)


## Remove an effect previously added with `add_pre_pixelization_effect`.
func remove_pre_pixelization_effect(effect: CompositorEffect) -> void:
	if effect == null:
		return
	_pending_pre_effects.erase(effect)
	if _compositor == null:
		return
	var effects: Array[CompositorEffect] = _compositor.compositor_effects.duplicate()
	var index := effects.find(effect)
	if index < 0:
		return
	effects.remove_at(index)
	_compositor.compositor_effects = effects
	_pre_effect_count = effects.size() - 2


func _insert_pre_effect(effect: CompositorEffect) -> void:
	var effects: Array[CompositorEffect] = _compositor.compositor_effects.duplicate()
	if effects.has(effect):
		return
	effects.insert(0, effect)
	_compositor.compositor_effects = effects
	_pre_effect_count = effects.size() - 2


# ── Cloud field ──────────────────────────────────────────────────────────────

## Register a cloud field provider. `provider` is any Object with a
## `build_cloud_params(sun: DirectionalLight3D) -> Dictionary` method. Passing a
## provider replaces any previous one.
func register_cloud_provider(provider: Object) -> void:
	_clouds.register_provider(provider)


func unregister_cloud_provider(provider: Object) -> void:
	_clouds.unregister_provider(provider)


## The current cloud-field uniform dictionary, built from the registered
## provider (neutral defaults when none). Consumers that are not ShaderMaterials
## (the god-ray pass) pull this each frame.
func get_cloud_params() -> Dictionary:
	return _clouds.get_params()


## Register a ShaderMaterial that includes `cloud_fbm.gdshaderinc` (MST terrain,
## water, the deck). Safe to call repeatedly.
func register_cloud_material(material: ShaderMaterial) -> void:
	_clouds.register_material(material)


func unregister_cloud_material(material: ShaderMaterial) -> void:
	_clouds.unregister_material(material)


# ── Material registration ────────────────────────────────────────────────────

## True when `material` is a pixelizer factory material or a custom material
## registered with register_pixelized_material().
func is_pixelized_material(material) -> bool:
	if not (material is ShaderMaterial):
		return false
	if (material as ShaderMaterial).shader == get_material_factory().shader:
		return true
	return (material as ShaderMaterial).has_meta(&"pixelizer_opt_in")


## Opt a custom ShaderMaterial that includes anchor_macros.gdshaderinc into
## the anchor pipeline. The material is marked with the `pixelizer_opt_in` meta
## (so the factory never replaces it) and tracked for the cloud field; pipeline-
## wide params (`meta_bit`, low-res, palette, screen size) are globals and need
## no per-material push. The shader is never replaced.
func register_pixelized_material(material) -> bool:
	if not (material is ShaderMaterial):
		return false
	var shader_material := material as ShaderMaterial
	var was_registered := shader_material.has_meta(&"pixelizer_opt_in")
	shader_material.set_meta(&"pixelizer_opt_in", true)
	_clouds.register_material(shader_material)
	if not was_registered:
		pixelized_material_registered.emit(shader_material)
	return true


## Stop pushing parameters to a custom material (call before its owner frees it,
## so the registry never holds a freed material).
func unregister_pixelized_material(material) -> void:
	if not is_instance_valid(material):
		return
	if not (material is ShaderMaterial):
		return
	(material as ShaderMaterial).remove_meta(&"pixelizer_opt_in")
	_clouds.unregister_material(material as ShaderMaterial)


# ── Mover snap ───────────────────────────────────────────────────────────────
#
# Mover snap is a vertex-stage offset, not a CPU transform swap. Registering a
# node sets the `anchor_mover_snap` instance uniform it declares through
# `anchor_macros.gdshaderinc`; `ANCHOR_VERTEX` then shifts the rigid mesh so the
# projected pivot lands on a whole screen texel. The scene transform is never
# read or written per frame, so no pre/post-draw callbacks and no save/restore
# bookkeeping are needed. The shader is orthographic-guarded.

## Register a Node3D whose pivot is snapped onto the pixel lattice at draw time.
## Only effective on geometry that runs a pixelizer material (the instance
## uniform is declared by `anchor_macros.gdshaderinc`).
func register_mover(node) -> void:
	if node == null or not is_instance_valid(node) or not (node is Node3D):
		return
	_set_mover_uniform(node, 1)


func unregister_mover(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_set_mover_uniform(node, 0)


func _set_mover_uniform(node, value: int) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).set_instance_shader_parameter("anchor_mover_snap", value)


# ── Outline palette ──────────────────────────────────────────────────────────

## Next outline tag id (1-254; 255 is reserved for the focus subject).
func allocate_outline_id() -> int:
	return _outlines.allocate_id()


## Set a tag's outline colour for both the silhouette and inner-edge rows, so an
## override covers every visible outline of that tag. The colour's alpha is the
## row opacity: alpha 0 hides the outline entirely, 1 replaces the scene colour.
func set_outline_color(id: int, color: Color) -> void:
	_outlines.set_color(id, color)


## Show or hide the screen-space outline for one edge tag. Hiding writes an
## opacity-0 palette row; re-enabling restores the tag's authored row (or the
## manager's `outline_color`, whose alpha is the restored opacity).
func set_outline_enabled(id: int, enabled: bool) -> void:
	_outlines.set_enabled(id, enabled)


func get_outline_texture() -> ImageTexture:
	return _outlines.get_texture()


## True when the working outline palette composites as a modulation
## (`color *= palette_rgb * 2`, the authored value used as the factor, so the
## invisible row is 0.5) instead of replacing the scene colour at the row's
## alpha. Set on the authored palette.
func get_outline_multiply_mode() -> bool:
	return _outlines.is_multiply()


# ── Focus subject (reserved edge tag 255) ────────────────────────────────────

## Focus a node's subtree: every pixelized mesh gets edge tag 255. Focused
## pixels are exempt from smooth-scroll shifts and can be debug-tinted.
func focus_subtree(root: Node) -> void:
	_focus.focus_subtree(root)


func unfocus_subtree(root: Node) -> void:
	_focus.unfocus_subtree(root)


# ── Active camera ────────────────────────────────────────────────────────────

## Explicitly pin the camera this manager pixelizes. Null clears the override,
## restoring automatic `get_viewport().get_camera_3d()` resolution. Use this
## when a rig owns the camera node and the viewport's `current` camera is not
## the one to pixelize.
func set_target_camera(cam: Camera3D) -> void:
	if _camera == null:
		_camera = PixelizerCameraBinding.new()
		_camera.manager = self
	_camera.set_target_camera(cam)


func clear_target_camera() -> void:
	if _camera != null:
		_camera.clear_target_camera()


## The camera whose view is pixelized: the explicit target when set, else the
## viewport's current camera.
func get_active_camera() -> Camera3D:
	if _camera == null:
		return null
	return _camera.get_active_camera()


## World units covered by one screen texel (respects keep_aspect).
func get_texel_world_size() -> float:
	if _camera == null:
		return 0.0
	return _camera.get_texel_world_size()


## Effective view width (horizontal) for the configured render resolution,
## texel density and zoom.
func get_view_width() -> float:
	if _camera == null:
		return 0.0
	return _camera.get_view_width()


## Configured view width before zoom.
func get_base_view_width() -> float:
	if _camera == null:
		return 0.0
	return _camera.get_base_view_width()


func set_view_zoom(value: float) -> void:
	get_settings().view_zoom = clampf(value, 0.05, 20.0)


## Write `camera.size` for the configured resolution, density and zoom (the
## low-res mirror camera and, with `manage_camera_size`, the active camera).
func apply_managed_camera_size(camera: Camera3D) -> void:
	if _camera != null:
		_camera.apply_managed_size(camera)


## Last snap remainder in texels ((-0.5, 0.5]); consumed by smooth scroll.
func get_subtexel_remainder() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.subtexel_remainder


# ── Status ───────────────────────────────────────────────────────────────────

## Combine with the manager's other diagnostics for a HUD line.
func get_debug_status_line() -> String:
	var look := get_settings()
	var mode_name := "anchor" if mode == Mode.ANCHOR else "lowres"
	var lines: PackedStringArray = []
	lines.append("Pixelizer3D [%s] %s" % [mode_name, "on" if enabled else "OFF"])
	lines.append("pixel=%d layer=%d view=%d" % [look.default_pixel_size, metadata_layer, debug_view])
	lines.append("outline=%s occl=%s palette=%s" % [
		"on" if look.default_outline_enabled else "off",
		"on" if look.depth_occlusion else "off",
		"yes" if look.outline_palette != null else "no"])
	lines.append("lut=%s dither=%s" % [
		"yes" if look.global_palette_lut != null else "no",
		"on" if look.default_dither_enabled else "off"])
	lines.append("rays=%s" % ["on" if _pre_effect_count > 0 else "off"])
	lines.append("sun=%s" % ["yes" if (sun != null and is_instance_valid(sun)) else "NO"])
	lines.append("profiles=%d" % object_profiles.size())
	lines.append("focused=%d auto=%s" % [(_focus.count() if _focus != null else 0), "on" if look.auto_focus else "off"])
	var remainder := get_subtexel_remainder()
	var active := get_active_camera()
	var orthographic := active != null and is_instance_valid(active) \
		and active.projection == Camera3D.PROJECTION_ORTHOGONAL
	if orthographic:
		lines.append("u/texel=%.4f remainder=(%.2f, %.2f) snap=%s" % [
			get_texel_world_size(), remainder.x, remainder.y,
			"on" if look.snap_camera else "off"])
	else:
		# The macro lattice is screen-space and the snap is orthographic-only by
		# construction; a perspective camera has no meaningful world texel.
		lines.append("u/texel=n/a (perspective) remainder=n/a snap=%s" % [
			"on" if look.snap_camera else "off"])
	return "\n".join(lines)


# ── Palette LUT grading ──────────────────────────────────────────────────────

## Publish the palette globals once per change (LUT + dither toggle). Grading is
## on when a LUT is assigned.
func _update_palette_params() -> void:
	if not _palette_dirty:
		return
	_palette_dirty = false
	var look := get_settings()
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_LUT, look.global_palette_lut)
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_GRADING, look.global_palette_lut != null)
	PixelizerGlobals.set_param(PixelizerGlobals.PALETTE_DITHER, look.default_dither_enabled)


# ── Mode changes ─────────────────────────────────────────────────────────────

func _apply_mode() -> void:
	if mode == Mode.LOW_RES:
		_enter_lowres()
	else:
		if _lowres != null:
			_exit_lowres()
		var cam := _camera.get_active_camera()
		if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
			_camera.active_camera = cam
			_camera.bind(cam)


func _enter_lowres() -> void:
	if _lowres == null:
		return
	var cam := _camera.active_camera
	if cam == null:
		return
	# Detach the anchor compositor (if any) and restore the user camera before
	# the mirror takes over; the low-res path renders the scene unmodified into
	# its own SubViewport through a manager-owned mirror camera.
	_camera.unbind(_camera.bound_camera)
	_lowres.enter(cam)


func _exit_lowres() -> void:
	if _lowres == null or not _lowres.is_active():
		return
	var cam := _camera.active_camera
	_lowres.exit(cam)
	# Restore the fields the manager changed (offsets, cull mask, compositor,
	# size when managed) and forget the binding; `_process` rebinds.
	_camera.unbind(cam)
