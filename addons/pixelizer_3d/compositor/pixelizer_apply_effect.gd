class_name PixelizerApplyPixelizationEffect
extends PixelizerEffectBase

## Raster pass: finds each pixel's anchor in the lower-left block-sized
## metadata search, replicates anchor colours across macro blocks, and writes
## the anchor depth back into the scene depth buffer (so transparents depth-test
## against the pixelated silhouette). Runs last, after the snapshot pass.

const CONTEXT := &"pixelizer"
const COPY_TEXTURE := &"color_copy"
const DEPTH_COPY_TEXTURE := &"depth_copy"
## The engine's normal-roughness target, a named scene-buffer texture (Forward+
## registers it as `forward_clustered / normal_roughness`). The manager sets
## `needs_normal_roughness` while `outline_normal_threshold > 0`, which makes the depth
## prepass write it; `has_texture()` alone proves only that it is allocated (an
## unrequested buffer can exist with uninitialised contents). Missing (e.g. a
## non-Forward+ renderer) = the crease term is skipped.
const NR_SCOPE := &"forward_clustered"
const NR_TEXTURE := &"normal_roughness"

const SAMPLE_COUNT := RenderingDevice.TEXTURE_SAMPLES_1

var _render_pipeline: RID
var _pipeline_format := -1
var _framebuffer: RID
var _framebuffer_color := RID()
var _framebuffer_depth := RID()
var _vertex_format := -1
var _vertex_buffer: RID
## Last bound source RIDs and the RDUniform array built from them; rebuilt only
## when an RID changes (resize / render-target recreation).
var _last_copy := RID()
var _last_metadata := RID()
var _last_depth_copy := RID()
var _last_outline := RID()
var _last_normal := RID()
var _uniforms: Array = []
## One-shot guard for the normal-roughness availability warning.
var _normal_warned := false
## Cached push-constant array + bytes; rebuilt only when an input changes.
var _push := PackedFloat32Array()
var _push_bytes := PackedByteArray()


func _init() -> void:
	shader_path = "res://addons/pixelizer_3d/shaders/compute/apply_pixelization.glsl"
	super._init(CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT)


func _create_pipeline() -> void:
	# The render pipeline needs the scene framebuffer format, only known from
	# the callback; built lazily there. The dummy vertex buffer exists so the
	# pipeline has a bound vertex array (positions come from gl_VertexIndex).
	var attribute := RDVertexAttribute.new()
	attribute.location = 0
	attribute.offset = 0
	attribute.stride = 8
	attribute.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	_vertex_format = rd.vertex_format_create([attribute])
	_vertex_buffer = rd.vertex_buffer_create(24, PackedByteArray())


func _render_callback(p_callback_type: int, p_render_data: RenderData) -> void:
	if p_callback_type != effect_callback_type or not _initialized or manager == null:
		return
	var buffers := p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or buffers.get_view_count() > 1:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not buffers.has_texture(CONTEXT, COPY_TEXTURE) or not buffers.has_texture(CONTEXT, DEPTH_COPY_TEXTURE):
		return
	var metadata_rid: RID = manager.get_metadata_texture_rid()
	if not metadata_rid.is_valid():
		return
	var outline_texture: ImageTexture = manager.get_outline_texture()
	var outline_rid := RID()
	if outline_texture != null:
		outline_rid = RenderingServer.texture_get_rd_texture(outline_texture.get_rid(), false)
	if not outline_rid.is_valid():
		return
	var copy_rid := buffers.get_texture(CONTEXT, COPY_TEXTURE)
	var depth_copy_rid := buffers.get_texture(CONTEXT, DEPTH_COPY_TEXTURE)
	var color_rid := buffers.get_color_layer(0)
	var depth_rid := buffers.get_depth_layer(0)
	if not copy_rid.is_valid() or not depth_copy_rid.is_valid() or not color_rid.is_valid() or not depth_rid.is_valid():
		return
	# Optional crease source. When unavailable, bind the metadata texture as a
	# dummy (the shader's `> 0` guard never samples it) and pass threshold 0.
	var look: PixelizerSettings = manager.get_settings()
	var normal_threshold: float = look.outline_normal_threshold
	var normal_rid := RID()
	if normal_threshold > 0.0 and buffers.has_texture(NR_SCOPE, NR_TEXTURE):
		normal_rid = buffers.get_texture(NR_SCOPE, NR_TEXTURE)
	if not normal_rid.is_valid():
		normal_rid = metadata_rid
		if normal_threshold > 0.0:
			normal_threshold = 0.0
			if not _normal_warned:
				_normal_warned = true
				push_warning("Pixelizer3D: outline_normal_threshold is set but the engine's normal-roughness buffer is not available (the crease term needs the Forward+ renderer). It stays off until then.")

	# Framebuffer format is derived from the engine textures themselves (the
	# RenderSceneBuffers format descriptions can disagree with the actual RIDs).
	var framebuffer := _get_framebuffer(color_rid, depth_rid)
	if not framebuffer.is_valid():
		return
	var format_id := rd.framebuffer_get_format(framebuffer)
	var pipeline := _get_render_pipeline(format_id)
	if not pipeline.is_valid():
		return

	var scene_data := p_render_data.get_render_scene_data()
	var projection := scene_data.get_cam_projection()
	var is_ortho := 1.0 if projection.is_orthogonal() else 0.0

	if copy_rid != _last_copy or metadata_rid != _last_metadata or depth_copy_rid != _last_depth_copy \
			or outline_rid != _last_outline or normal_rid != _last_normal:
		_last_copy = copy_rid
		_last_metadata = metadata_rid
		_last_depth_copy = depth_copy_rid
		_last_outline = outline_rid
		_last_normal = normal_rid
		_uniforms = [
			_make_sampler_uniform(_sampler, copy_rid, 0),
			_make_sampler_uniform(_sampler, metadata_rid, 1),
			_make_sampler_uniform(_sampler, depth_copy_rid, 2),
			_make_sampler_uniform(_sampler, outline_rid, 3),
			_make_sampler_uniform(_sampler, normal_rid, 4),
		]
	var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, _uniforms)
	# 16 floats / 64 bytes; must match apply_pixelization.glsl's Params struct
	# byte for byte. Outline colour rides the palette, not the push block.
	# Rebuild the packed array/bytes only when an input changes.
	var push := PackedFloat32Array([
		float(size.x),
		float(size.y),
		# The two depth terms of the projection the engine renders with. It is
		# reverse-Z with a [0, 1] depth range, so `get_z_near()` / `get_z_far()`
		# (which assume the OpenGL convention) return nonsense (about -0.05 /
		# 0.05); the shader linearises from these terms directly.
		projection.z.z,
		projection.w.z,
		is_ortho,
		float(manager.debug_view),
		1.0 if look.depth_occlusion else 0.0,
		1.0 if look.default_outline_enabled else 0.0,
		look.outline_threshold,
		look.outline_interior_threshold,
		normal_threshold,
		1.0 if manager.get_outline_multiply_mode() else 0.0,
		1.0 if look.debug_focus_mask else 0.0,
		1.0,
		0.0,
		0.0,
	])
	if push != _push:
		_push = push
		_push_bytes = push.to_byte_array()
	var ignore_flags := RenderingDevice.DRAW_IGNORE_COLOR_ALL | RenderingDevice.DRAW_IGNORE_DEPTH
	var list := rd.draw_list_begin(framebuffer, ignore_flags)
	rd.draw_list_bind_render_pipeline(list, pipeline)
	rd.draw_list_bind_uniform_set(list, uniform_set, 0)
	rd.draw_list_bind_vertex_buffers_format(list, _vertex_format, 3, [_vertex_buffer])
	rd.draw_list_set_push_constant(list, _push_bytes, _push_bytes.size())
	rd.draw_list_draw(list, false, 1)
	rd.draw_list_end()


func _get_render_pipeline(format_id: int) -> RID:
	if _render_pipeline.is_valid() and _pipeline_format == format_id:
		return _render_pipeline
	if _render_pipeline.is_valid() and rd.render_pipeline_is_valid(_render_pipeline):
		rd.free_rid(_render_pipeline)
	var raster := RDPipelineRasterizationState.new()
	raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
	var multisample := RDPipelineMultisampleState.new()
	multisample.sample_count = SAMPLE_COUNT
	var depth_state := RDPipelineDepthStencilState.new()
	depth_state.enable_depth_test = false
	depth_state.enable_depth_write = true
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_ALWAYS
	var blend := RDPipelineColorBlendState.new()
	blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
	_render_pipeline = rd.render_pipeline_create(
		_shader,
		format_id,
		_vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		raster,
		multisample,
		depth_state,
		blend)
	_pipeline_format = format_id
	return _render_pipeline


func _get_framebuffer(color_rid: RID, depth_rid: RID) -> RID:
	if _framebuffer.is_valid() and _framebuffer_color == color_rid and _framebuffer_depth == depth_rid:
		return _framebuffer
	if _framebuffer.is_valid():
		# Engine-side reconfiguration (window resize) can free the framebuffer
		# while our RID stays non-null.
		if rd.framebuffer_is_valid(_framebuffer):
			rd.free_rid(_framebuffer)
	_framebuffer = rd.framebuffer_create([color_rid, depth_rid])
	if _framebuffer.is_valid():
		_framebuffer_color = color_rid
		_framebuffer_depth = depth_rid
	return _framebuffer


## Frees only the RIDs this class owns. The base class's `_notification` runs
## separately (Godot calls `_notification` on every script in the chain), so do
## not call `super._notification()` here.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if not is_instance_valid(rd):
		return
	if _framebuffer.is_valid() and rd.framebuffer_is_valid(_framebuffer):
		rd.free_rid(_framebuffer)
		_framebuffer = RID()
	if _render_pipeline.is_valid() and rd.render_pipeline_is_valid(_render_pipeline):
		rd.free_rid(_render_pipeline)
		_render_pipeline = RID()
	if _vertex_buffer.is_valid():
		rd.free_rid(_vertex_buffer)
		_vertex_buffer = RID()
