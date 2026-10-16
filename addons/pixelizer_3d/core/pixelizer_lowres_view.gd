class_name PixelizerLowResView
extends Node

## Low-res SubViewport mode for `PixelizerManager3D`: renders the scene through a
## manager-owned mirror camera into a low-res SubViewport and upscales it with
## `pixelizer_upscale.gdshader` (resolution-derived texel reconstruction plus a
## smooth sub-texel `scroll_shift`). The user camera stays where it is (some rigs
## own the camera node); it is un-currented while this view is active and
## restored on exit.

const UPSCALE_SHADER := "res://addons/pixelizer_3d/shaders/pixelizer_upscale.gdshader"

var manager: PixelizerManager3D
var _layer: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _material: ShaderMaterial
var _mirror_camera: Camera3D
var _saved_camera_size := 0.0
var _saved_camera_current := false


func is_active() -> bool:
	return _viewport != null


## World units covered by one texel of the low-res render target: the mirror
## camera's view size over the display viewport's size (the user camera and the
## window must not be measured here — the rendering camera is the mirror inside
## the SubViewport). Respects keep_aspect like the anchor path.
func get_texel_world_size() -> float:
	if _mirror_camera == null or _viewport == null:
		return 0.0
	var viewport_size := Vector2(_viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0.0
	if _mirror_camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return _mirror_camera.size / viewport_size.x
	return _mirror_camera.size / viewport_size.y


func enter(camera: Camera3D) -> bool:
	if _viewport != null:
		return true
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false

	_layer = CanvasLayer.new()
	_layer.name = "PixelizerLowResDisplay"
	_layer.layer = 0
	manager.add_child(_layer)

	_container = SubViewportContainer.new()
	_container.name = "LowResContainer"
	_container.stretch = false
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.size = Vector2(manager.get_settings().render_resolution)
	_material = ShaderMaterial.new()
	_material.shader = load(UPSCALE_SHADER) as Shader
	_container.material = _material
	_layer.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.name = "LowResViewport"
	_viewport.size = manager.get_settings().render_resolution
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_taa = false
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_container.add_child(_viewport)

	# Mirror-camera only: the user camera stays where it is, is un-currented, and
	# a manager-owned camera inside the SubViewport is synced every frame.
	_saved_camera_size = camera.size
	_saved_camera_current = camera.current
	_mirror_camera = Camera3D.new()
	_mirror_camera.name = "MirrorCamera"
	_mirror_camera.current = true
	_viewport.add_child(_mirror_camera)
	camera.current = false
	sync(camera)
	update_camera_size()

	var metadata_viewport := manager.get_metadata_viewport()
	if metadata_viewport != null:
		metadata_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	PixelizerGlobals.set_param(PixelizerGlobals.LOWRES_MODE, true)
	return true


func exit(camera: Camera3D) -> void:
	if _viewport == null:
		return
	PixelizerGlobals.set_param(PixelizerGlobals.LOWRES_MODE, false)
	if _mirror_camera != null and is_instance_valid(_mirror_camera):
		_mirror_camera.queue_free()
	_mirror_camera = null
	if camera != null and is_instance_valid(camera):
		camera.current = _saved_camera_current
		camera.size = _saved_camera_size
	var metadata_viewport := manager.get_metadata_viewport()
	if metadata_viewport != null:
		metadata_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_container = null
	_viewport = null
	_material = null


## Copy the user camera's pose/lens/cull mask onto the manager-owned mirror
## camera inside the low-res SubViewport every frame.
func sync(camera: Camera3D) -> void:
	if _mirror_camera == null or camera == null or not is_instance_valid(camera):
		return
	PixelizerCameraBinding.copy_camera_lens(camera, _mirror_camera)
	_mirror_camera.environment = camera.environment
	_mirror_camera.cull_mask = camera.cull_mask
	update_camera_size()


func update_camera_size() -> void:
	if _mirror_camera != null:
		manager.apply_managed_camera_size(_mirror_camera)


func update_display() -> void:
	if _container == null or _viewport == null:
		return
	var window_size := Vector2(manager.get_viewport().get_visible_rect().size)
	var render_size := Vector2(_viewport.size)
	if render_size.x <= 0.0 or render_size.y <= 0.0:
		return
	var display_scale := minf(window_size.x / render_size.x, window_size.y / render_size.y)
	if display_scale <= 0.0:
		return
	_container.scale = Vector2(display_scale, display_scale)
	var target_position := (window_size - render_size * display_scale) * 0.5
	_container.position = target_position.round()
	# Counter-shift the snap remainder so motion stays smooth inside the low-res
	# viewport (the camera itself is snapped to the texel grid), and tell the
	# upscaler the exact source resolution it is reconstructing.
	_material.set_shader_parameter("scroll_shift", manager.get_subtexel_remainder())
	_material.set_shader_parameter("source_size", render_size)

