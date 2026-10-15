shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform bool falloff_visible = false;
uniform float rotation = 0.0;

// Equilateral triangle SDF matching the triangle brush: apex on +Y with the
// flat bottom edge at -0.5. Rotating by PI flips it point-down (Triangle180).
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float c = cos(rotation);
	float s = sin(rotation);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	float h = max(abs(p.x) * 1.7320508 + p.y, -2.0 * p.y);
	if (falloff_visible) {
		float sample = smoothstep(1.0, 0.0, h);
		ALPHA = sample * 0.6;
	} else {
		ALPHA = h <= 1.0 ? 0.25 : 0.0;
	}
}
