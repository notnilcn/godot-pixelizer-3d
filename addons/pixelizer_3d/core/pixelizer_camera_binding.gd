class_name PixelizerCameraBinding
extends RefCounted

## Camera plumbing for `PixelizerManager3D`: resolves the active camera, attaches
## the compositor to it, syncs the metadata camera, and applies the projection
## snap via `h_offset`/`v_offset`. Save/restore keeps a camera the manager did
## not author coming back exactly as it was.

var manager: PixelizerManager3D
## Explicit override set with `set_target_camera()`.
var target_camera: Camera3D = null
## Camera resolved this frame (override -> viewport current).
var active_camera: Camera3D = null
## Camera currently carrying the compositor / metadata cull-mask change.
var bound_camera: Camera3D = null
## Last snap remainder in texels ((-0.5, 0.5]); consumed by smooth scroll.
var subtexel_remainder := Vector2.ZERO

var metadata_viewport: SubViewport
var metadata_camera: Camera3D
var _metadata_environment: Environment
var _metadata_texture_rd := RID()
var _metadata_texture_source := RID()

## Fields saved from `_saved_camera` at bind time; restored once on unbind so a
## camera the manager did not author comes back exactly as it was.
var _saved_camera: Camera3D = null
var _saved_cull_mask := 0
var _saved_compositor: Compositor
var _saved_h_offset := 0.0
var _saved_v_offset := 0.0
var _saved_size := 0.0
## True when the manager may write `_saved_camera.size` (manage_camera_size);
## only then is the size restored on unbind.
var _saved_size_managed := false
var _perspective_warned := false


# ── Active camera (auto-resolved; one manager per viewport) ─────────────────

## The camera whose view is pixelized: the explicit target when set, else the
## viewport's current camera. In low-res mode the acquired camera is cached
## (reparenting it into the display SubViewport removes it from the viewport's
## current-camera slot).
func get_active_camera() -> Camera3D:
	if target_camera != null and is_instance_valid(target_camera):
		return target_camera
	if manager.mode == PixelizerManager3D.Mode.LOW_RES and active_camera != null and is_instance_valid(active_camera):
		return active_camera
	if not manager.is_inside_tree():
		return null
	return manager.get_viewport().get_camera_3d()


## Pin the camera this manager pixelizes. Null clears the override, restoring
## automatic `get_viewport().get_camera_3d()` resolution.
func set_target_camera(cam: Camera3D) -> void:
	target_camera = cam
	if manager.is_inside_tree() and cam != bound_camera:
		unbind(bound_camera)
		if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
			bind(cam)


func clear_target_camera() -> void:
	target_camera = null


## Per-frame camera resolution + bind/unbind. Switching `Camera3D.current` (or
## adding/removing cameras) just works.
func update() -> void:
	var cam := get_active_camera()
	if cam != bound_camera:
		unbind(bound_camera)
		if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
			bind(cam)
	active_camera = cam


# ── Bind / unbind ────────────────────────────────────────────────────────────

## Attach the compositor to `cam`, saving the fields we touch once so a later
## unbind restores the camera exactly. Only ANCHOR mode modifies the camera
## (cull mask + compositor); snap offsets and `size` are written per frame.
func bind(cam: Camera3D) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var compositor := manager.get_compositor()
	if compositor == null:
		return
	_saved_camera = cam
	_saved_cull_mask = cam.cull_mask
	_saved_compositor = cam.compositor
	_saved_h_offset = cam.h_offset
	_saved_v_offset = cam.v_offset
	_saved_size = cam.size
	_saved_size_managed = manager.get_settings().manage_camera_size
	if manager.mode == PixelizerManager3D.Mode.ANCHOR:
		cam.set_cull_mask_value(manager.metadata_layer, false)
		cam.compositor = compositor
	bound_camera = cam


## Restore a bound camera and forget its saved state. Never mutate a camera we
## did not author (`_saved_camera` identity is the guard).
func unbind(cam: Camera3D) -> void:
	if bound_camera == cam:
		bound_camera = null
	if cam == null or cam != _saved_camera:
		return
	_saved_camera = null
	if not is_instance_valid(cam):
		return
	cam.cull_mask = _saved_cull_mask
	cam.compositor = _saved_compositor
	cam.h_offset = _saved_h_offset
	cam.v_offset = _saved_v_offset
	if _saved_size_managed:
		cam.size = _saved_size


# ── Camera snap (h_offset/v_offset only — never transforms) ─────────────────

## World units covered by one screen texel. In LOW_RES mode that is the
## manager-owned mirror camera inside the display SubViewport (the user camera
## only carries the snap offsets and is mirrored every frame); measuring it
## against the window would be off by window_height / render_resolution.y.
func get_texel_world_size() -> float:
	if manager.mode == PixelizerManager3D.Mode.LOW_RES:
		var lowres := manager.get_lowres_view()
		if lowres != null and lowres.is_active():
			return lowres.get_texel_world_size()
	var cam := active_camera
	if cam == null or not is_instance_valid(cam):
		return 0.0
	var viewport := cam.get_viewport()
	if viewport == null or viewport.size.x <= 0 or viewport.size.y <= 0:
		return 0.0
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		return cam.size / float(viewport.size.x)
	return cam.size / float(viewport.size.y)


## Effective view width (horizontal) for the configured render resolution,
## texel density and zoom.
func get_view_width() -> float:
	var settings := manager.get_settings()
	return float(settings.render_resolution.x) / maxf(settings.texel_density, 0.0001) * settings.view_zoom


## Configured view width before zoom.
func get_base_view_width() -> float:
	var settings := manager.get_settings()
	return float(settings.render_resolution.x) / maxf(settings.texel_density, 0.0001)


## Write `camera.size` for the configured resolution, density and zoom.
func apply_managed_size(camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var settings := manager.get_settings()
	var units := 1.0 / maxf(settings.texel_density, 0.0001)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		camera.size = float(settings.render_resolution.x) * units * settings.view_zoom
	else:
		camera.size = float(settings.render_resolution.y) * units * settings.view_zoom


## Snap the camera to the texel lattice via h_offset/v_offset (never transforms).
## The phase anchor is projected into camera view space, converted to texel
## coordinates, and the frustum is shifted so that position lands on a whole
## texel; the residual sub-texel phase is what `h_offset`/`v_offset` cancel.
func snap() -> void:
	var cam := active_camera
	if not manager.get_settings().snap_camera or cam == null or not is_instance_valid(cam):
		_zero_snap(cam)
		return
	if cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		if not _perspective_warned:
			_perspective_warned = true
			push_error("Pixelizer3D: camera snap only supports orthographic cameras; the macro-pixel lattice will crawl as the camera moves. Set `snap_camera = false` to silence this, or use an orthographic Camera3D.")
		_zero_snap(cam)
		return
	if manager.get_settings().lock_camera:
		_zero_snap(cam)
		return
	var texel := get_texel_world_size()
	if texel <= 0.0:
		_zero_snap(cam)
		return
	var basis := cam.global_transform.basis.orthonormalized()
	var anchor_world := Vector3.ZERO
	if manager.snap_origin != null and is_instance_valid(manager.snap_origin):
		anchor_world = manager.snap_origin.global_position
	var anchor_view: Vector3 = basis.inverse() * (anchor_world - cam.global_position)
	var anchor_texel := Vector2(anchor_view.x / texel, anchor_view.y / texel)
	var snapped := Vector2(round(anchor_texel.x), round(anchor_texel.y))
	var residual := anchor_texel - snapped
	cam.h_offset = residual.x * texel
	cam.v_offset = residual.y * texel
	# The camera shift moves the rendered content by -residual in texel space;
	# the smooth-scroll consumer counter-shifts by (+x, -y) (x in columns, y
	# negated because screen rows increase downward while view-space y increases
	# upward). A bare `-residual` gets y right by accident but doubles the x
	# error.
	subtexel_remainder = Vector2(residual.x, -residual.y)


## Clear the snap offsets when snapping is inactive, so a camera does not keep
## last frame's offsets (e.g. after toggling `snap_camera` off).
func _zero_snap(cam: Camera3D) -> void:
	subtexel_remainder = Vector2.ZERO
	if cam != null and is_instance_valid(cam):
		cam.h_offset = 0.0
		cam.v_offset = 0.0


# ── Metadata camera ──────────────────────────────────────────────────────────

## Copy the pose and lens fields shared by the metadata camera and the low-res
## mirror camera, so the two sync paths cannot drift apart.
static func copy_camera_lens(from: Camera3D, to: Camera3D) -> void:
	to.global_transform = from.global_transform
	to.projection = from.projection
	to.fov = from.fov
	to.near = from.near
	to.far = from.far
	to.keep_aspect = from.keep_aspect
	to.frustum_offset = from.frustum_offset
	to.h_offset = from.h_offset
	to.v_offset = from.v_offset


func create_metadata_viewport() -> void:
	metadata_viewport = SubViewport.new()
	metadata_viewport.name = "PixelizerMetadataViewport"
	metadata_viewport.own_world_3d = false
	metadata_viewport.handle_input_locally = false
	metadata_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	metadata_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	metadata_viewport.use_hdr_2d = true
	metadata_viewport.msaa_3d = Viewport.MSAA_DISABLED
	metadata_viewport.use_taa = false
	metadata_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	metadata_viewport.use_debanding = false
	metadata_viewport.size = Vector2i(960, 540)
	manager.add_child(metadata_viewport)

	_metadata_environment = Environment.new()
	_metadata_environment.background_mode = Environment.BG_COLOR
	_metadata_environment.background_color = Color(0.0, 0.0, 0.0, 1.0)
	_metadata_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_metadata_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_metadata_environment.glow_enabled = false
	_metadata_environment.ssao_enabled = false
	_metadata_environment.ssil_enabled = false
	_metadata_environment.sdfgi_enabled = false
	_metadata_environment.fog_enabled = false
	_metadata_environment.volumetric_fog_enabled = false

	metadata_camera = Camera3D.new()
	metadata_camera.name = "MetadataCamera"
	metadata_camera.current = true
	metadata_camera.environment = _metadata_environment
	metadata_camera.cull_mask = manager.metadata_bit
	metadata_camera.near = 0.05
	metadata_viewport.add_child(metadata_camera)


func sync_metadata_camera() -> void:
	if metadata_viewport == null or metadata_camera == null:
		return
	var cam := active_camera
	if cam == null or not is_instance_valid(cam):
		return
	var main_viewport := cam.get_viewport()
	if main_viewport == null:
		return
	if metadata_viewport.size != main_viewport.size:
		metadata_viewport.size = main_viewport.size
	copy_camera_lens(cam, metadata_camera)
	metadata_camera.size = cam.size


func update_metadata_texture() -> void:
	if metadata_viewport == null:
		return
	var texture_rid := RenderingServer.viewport_get_texture(metadata_viewport.get_viewport_rid())
	if not texture_rid.is_valid():
		return
	# Re-fetch every frame: the viewport recreates its render target on resize
	# (and other reconfigurations), and the previous RD texture goes stale while
	# its wrapper RID stays non-null. Caching it caused invalid bindings after a
	# window resize. texture_get_rd_texture is a cheap RenderingServer getter.
	_metadata_texture_source = texture_rid
	_metadata_texture_rd = RenderingServer.texture_get_rd_texture(texture_rid, false)


func get_metadata_texture_rid() -> RID:
	return _metadata_texture_rd

