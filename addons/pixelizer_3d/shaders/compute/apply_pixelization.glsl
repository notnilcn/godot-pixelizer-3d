#[vertex]
#version 450

// Procedural fullscreen triangle; the bound vertex buffer is a dummy (all
// positions come from gl_VertexIndex).

void main() {
	vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

// Replicates each macro block's anchor colour across the block and writes the
// anchor depth back into the scene depth buffer so later passes (transparents)
// composite against the pixelated silhouette. Pixels in front of their snapped
// anchor keep their own colour and depth (non-pixelized geometry guard).
// The depth lookup uses the colour-oriented R32F depth copy, never the depth
// attachment itself (attachment + uniform feedback is rejected by the RD).
// Also serves the debug views 1-9. Outline palette rows carry RGB plus an
// opacity in alpha (0 = leave the scene colour, 1 = replace it).

layout(location = 0) out vec4 frag_color;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(set = 0, binding = 1) uniform sampler2D metadata_texture;
layout(set = 0, binding = 2) uniform sampler2D depth_copy;
layout(set = 0, binding = 3) uniform sampler2D outline_palette;
// The engine's normal-roughness target (`RGB = view-space normal * 0.5 + 0.5`,
// roughness in A; see the Forward+ normal-roughness pass). Bound to a dummy
// sampler unless `outline_normal_threshold > 0` and the renderer generated the
// buffer (SSAO/SSIL/SSR or a material using `hint_normal_roughness_texture`).
layout(set = 0, binding = 4) uniform sampler2D normal_roughness_texture;

// 16 floats / 64 bytes (must match the GDScript push array byte for byte).
// outline_color was removed: the palette path is unconditional, so the outline
// colour always comes from `outline_palette`. `palette_enabled` is reserved.
layout(push_constant, std430) uniform Params {
	vec2 screen_size;
	float proj_zz; // projection[2][2] (reverse-Z, [0, 1] depth)
	float proj_wz; // projection[3][2]
	float is_ortho;
	float debug_view;
	float depth_occlusion;
	float outline_enabled;
	float outline_threshold;
	float outline_interior_threshold;
	float outline_normal_threshold;
	float outline_multiply;
	float debug_focus_mask;
	float palette_enabled;
	float pad0;
	float pad1;
} params;

// The outline palette is baked from authored (sRGB) colours into an 8-bit
// RGBA8 texture sampled without an sRGB view, so the shader must linearise it:
// the LUT grading already treats palette colours as gamma-space (see
// anchor_macros.gdshaderinc). Exact sRGB EOTF (matches Color.srgb_to_linear).
vec3 srgb_to_linear(vec3 c) {
	vec3 low = c / 12.92;
	vec3 high = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(low, high, step(vec3(0.04045), c));
}

// View-space distance of a raw depth sample, inverted from the engine's own
// projection matrix (`raw = (P22 * z + P32) / (P23 * z + P33)`, view z < 0).
// Never derive near/far through `Projection.get_z_near()`: the matrix is
// reverse-Z, and those helpers assume the OpenGL convention.
float linearize_depth(float raw) {
	if (params.is_ortho > 0.5) {
		return (params.proj_wz - raw) / params.proj_zz;
	}
	return params.proj_wz / (raw + params.proj_zz);
}

// Distance of the far plane (raw depth 0 under reverse-Z), for the debug views.
float far_distance() {
	return params.proj_wz / params.proj_zz;
}

// Inline anchor search: for this pixel, find the nearest anchor that can own
// its macro block and return the integer pixel offset to it. Metadata arrives
// from the metadata camera's SubViewport:
//   R = pixel_size / 32 (0 = not pixelized)
//   G = outline id / 256
//   B = view depth of the anchor fragment (nearest wins)
//
// The lattice is corner-anchored: a block's surviving anchor sits at
// `anchor + k * pixel_size`, so for any pixel its own block's anchor is at most
// `pixel_size - 1` pixels behind it on each axis. The search therefore scans
// only the lower-left `pixel_size x pixel_size` quadrant, which is exactly the
// set of offsets that can hold a survivor.
const int MAX_ANCHOR_SIZE = 5;

vec2 anchor_shift(vec2 uv, vec2 texel) {
	float best_depth = 1e30;
	vec2 best_shift = vec2(0.0);
	for (int y = -(MAX_ANCHOR_SIZE - 1); y <= 0; y++) {
		for (int x = -(MAX_ANCHOR_SIZE - 1); x <= 0; x++) {
			vec2 sample_uv = uv + vec2(float(x), float(y)) * texel;
			if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
				continue;
			}
			vec4 meta = texture(metadata_texture, sample_uv);
			int pixel_size = int(round(meta.r * 32.0));
			if (pixel_size <= 0) {
				continue;
			}
			int reach = pixel_size - 1;
			if (-x > reach || -y > reach) {
				continue;
			}
			float depth = meta.b;
			if (depth < best_depth) {
				best_depth = depth;
				best_shift = vec2(float(x), float(y));
			}
		}
	}
	return best_shift;
}

void main() {
	vec2 uv = gl_FragCoord.xy / params.screen_size;
	vec2 texel = 1.0 / params.screen_size;
	vec2 shift = anchor_shift(uv, texel);
	vec2 snapped_uv = uv + shift * texel;
	float base_raw = texture(depth_copy, uv).r;
	float anchor_raw = texture(depth_copy, snapped_uv).r;

	// Debug views: one integer branch replaces the previous nine ordered float
	// compares on the production path (view 0). All views 1-9 are preserved.
	int debug_mode = int(params.debug_view + 0.5);
	if (debug_mode != 0) {
		if (debug_mode == 1) {
			// 1 = anchor map (0.5, 0.5) is shift zero.
			frag_color = vec4(shift * 0.25 + vec2(0.5), 0.0, 1.0);
		} else if (debug_mode == 2) {
			// 2 = metadata payload.
			frag_color = vec4(texture(metadata_texture, uv).rgb, 1.0);
		} else if (debug_mode == 3) {
			// 3 = linearised scene depth.
			float lin = linearize_depth(base_raw) / max(far_distance(), 0.001);
			frag_color = vec4(vec3(1.0 - lin), 1.0);
		} else if (debug_mode == 4) {
			// 4 = the colour copy as-is.
			frag_color = vec4(texture(source_color, uv).rgb, 1.0);
		} else if (debug_mode == 5) {
			// 5 = shifted sample without occlusion.
			frag_color = vec4(texture(source_color, snapped_uv).rgb, 1.0);
		} else if (debug_mode == 6) {
			// 6 = occlusion diagnostics as binary flags.
			float base_depth = linearize_depth(base_raw);
			float snapped_depth = linearize_depth(anchor_raw);
			float tolerance = max(0.05, snapped_depth * 0.002);
			float half_far = far_distance() * 0.5;
			frag_color = vec4(
				base_depth < half_far ? 1.0 : 0.0,
				snapped_depth < half_far ? 1.0 : 0.0,
				base_depth < snapped_depth - tolerance ? 1.0 : 0.0,
				1.0);
		} else if (debug_mode == 7) {
			// 7 = raw depth at this pixel, amplified.
			frag_color = vec4(vec3(min(base_raw * 4.0, 1.0)), 1.0);
		} else if (debug_mode == 8) {
			// 8 = raw depth at the snapped anchor, amplified.
			frag_color = vec4(vec3(min(anchor_raw * 4.0, 1.0)), 1.0);
		} else {
			// 9 = revert flag for the current pixel.
			float b = linearize_depth(base_raw);
			float s = linearize_depth(anchor_raw);
			float revert = b < s - max(0.05, s * 0.002) ? 1.0 : 0.0;
			frag_color = vec4(vec3(revert), 1.0);
		}
		gl_FragDepth = base_raw;
		return;
	}

	bool revert = false;
	if (params.depth_occlusion > 0.5) {
		float base_depth = linearize_depth(base_raw);
		float snapped_depth = linearize_depth(anchor_raw);
		float tolerance = max(0.05, snapped_depth * 0.002);
		revert = base_depth < snapped_depth - tolerance;
	}
	vec3 color = revert ? texture(source_color, uv).rgb : texture(source_color, snapped_uv).rgb;

	// Foreign-surface test at the anchor's OWN screen position: the metadata
	// camera saw the anchor at view depth `meta.b`, and the main camera renders
	// the same pixelized geometry with the same vertex stage, so the scene depth
	// at `snapped_uv` equals that depth unless a non-pixelized surface (invisible
	// to the metadata camera) sits in front of it. `revert` misses this case when
	// the occluder spans the whole block, because then both of its depth samples
	// are the occluder's. Comparing the same pixel in both buffers keeps blocks
	// that straddle a silhouette inked (the anchor on the far surface is still
	// the visible survivor at its own pixel). The tolerance absorbs the half-float
	// metadata depth.
	bool anchor_hidden = false;
	vec4 snapped_meta = texture(metadata_texture, snapped_uv);
	if (round(snapped_meta.r * 32.0) > 0.5) {
		float meta_depth = snapped_meta.b;
		float scene_depth = linearize_depth(anchor_raw);
		anchor_hidden = scene_depth < meta_depth - max(0.1, meta_depth * 0.01);
	}
	bool visible_anchor = !revert && !anchor_hidden;

	// Screen-space outlines: mark a whole macro block when its anchor sits next
	// to a different id, to the background, or across a depth discontinuity.
	// A block that is not the visible surface (`revert`, or an anchor hidden by
	// a non-pixelized surface) must not ink its neighbours: a pixelized object
	// behind a non-pixelized wall would otherwise paint an outline onto the wall.
	//
	// Depth discontinuities use a SECOND difference (`2*centre - a - b`) and
	// only mark where the centre is the nearer (convex) side, so a slope at any
	// angle stays clean — a first difference marks every slope past the
	// threshold, which is why an outlined terrain floods with outline blocks.
	// A step beyond `outline_interior_threshold` is an exterior edge (silhouette
	// row); a smaller one is an interior detail (inner row). Tag changes and
	// the background test are unchanged (either side marks).
	if (params.outline_enabled > 0.5 && visible_anchor) {
		vec4 anchor_meta = snapped_meta;
		float anchor_ps = round(anchor_meta.r * 32.0);
		if (anchor_ps > 0.5) {
			float anchor_id = anchor_meta.g;
			float anchor_depth = anchor_meta.b;
			vec2 macro_step = texel * anchor_ps;
			bool silhouette_edge = false;
			bool inner_edge = false;
			bool exterior_edge = false;
			vec4 meta_left = texture(metadata_texture, snapped_uv - vec2(macro_step.x, 0.0));
			vec4 meta_right = texture(metadata_texture, snapped_uv + vec2(macro_step.x, 0.0));
			vec4 meta_down = texture(metadata_texture, snapped_uv - vec2(0.0, macro_step.y));
			vec4 meta_up = texture(metadata_texture, snapped_uv + vec2(0.0, macro_step.y));
			vec4 neighbours[4] = vec4[](meta_left, meta_right, meta_down, meta_up);
			for (int i = 0; i < 4; i++) {
				vec4 neighbour = neighbours[i];
				float neighbour_ps = round(neighbour.r * 32.0);
				if (neighbour_ps < 0.5) {
					silhouette_edge = true;
				} else if (abs(neighbour.g - anchor_id) > 0.001953125) {
					inner_edge = true;
				}
			}
			// Per-axis second difference; both neighbours on the axis must be
			// pixelized. `curve > 0` means the centre block is the convex side.
			float depth_scale = max(anchor_depth, 1.0);
			if (round(meta_left.r * 32.0) > 0.5 && round(meta_right.r * 32.0) > 0.5) {
				float curve = (2.0 * anchor_depth - meta_left.b - meta_right.b) / depth_scale;
				if (curve > params.outline_interior_threshold) {
					exterior_edge = true;
				} else if (curve > params.outline_threshold) {
					inner_edge = true;
				}
			}
			if (round(meta_down.r * 32.0) > 0.5 && round(meta_up.r * 32.0) > 0.5) {
				float curve = (2.0 * anchor_depth - meta_down.b - meta_up.b) / depth_scale;
				if (curve > params.outline_interior_threshold) {
					exterior_edge = true;
				} else if (curve > params.outline_threshold) {
					inner_edge = true;
				}
			}
			// Crease term: a normal-direction change across one macro step, which
			// depth alone cannot see when both sides sit at the same depth
			// (a wall/floor junction). Skipped on silhouettes (they already
			// mark) and when no normal buffer is bound (threshold 0).
			if (params.outline_normal_threshold > 0.0 && !silhouette_edge) {
				vec2 offsets[4] = vec2[](
					vec2(-macro_step.x, 0.0), vec2(macro_step.x, 0.0),
					vec2(0.0, -macro_step.y), vec2(0.0, macro_step.y));
				vec3 centre_normal = normalize(texture(normal_roughness_texture, snapped_uv).xyz * 2.0 - 1.0);
				for (int i = 0; i < 4; i++) {
					vec3 neighbour_normal = normalize(
						texture(normal_roughness_texture, snapped_uv + offsets[i]).xyz * 2.0 - 1.0);
					if (1.0 - dot(centre_normal, neighbour_normal) > params.outline_normal_threshold) {
						inner_edge = true;
					}
				}
			}
			if (silhouette_edge || exterior_edge || inner_edge) {
				// The outline colour always comes from the palette (the manager
				// writes the opacity-0 "off" row for hidden tags). Opacity mode
				// replaces; multiply mode (rows authored around 0.5, 0.5 = no-op) modulates.
				float row = (silhouette_edge || exterior_edge) ? 0.25 : 0.75;
				float id_int = round(anchor_id * 256.0);
				vec4 palette_row = texture(outline_palette, vec2((id_int + 0.5) / 256.0, row));
				if (params.outline_multiply > 0.5) {
					// The authored value IS the modulation factor, not a colour,
					// so it is not sRGB-decoded: 0.5 is invisible (ProPixelizer's
					// `_EdgeHighlightColor` convention). The opacity still applies,
					// so a hidden tag's opacity-0 row stays a no-op.
					color = mix(color, color * palette_row.rgb * 2.0, palette_row.a);
				} else {
					color = mix(color, srgb_to_linear(palette_row.rgb), palette_row.a);
				}
			}
		}
	}

	// Debug: tint focused (tag 255) blocks red. Not on occluded pixels, same as
	// the outline.
	if (params.debug_focus_mask > 0.5 && visible_anchor) {
		float focus_id = round(snapped_meta.g * 256.0);
		if (focus_id >= 254.5) {
			color = mix(color, srgb_to_linear(vec3(1.0, 0.0, 0.0)), 0.5);
		}
	}

	frag_color = vec4(color, 1.0);
	// Depth write-back: replicate the anchor depth across the block, but never
	// overwrite geometry that is in front of the block.
	gl_FragDepth = revert ? base_raw : anchor_raw;
}
