shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform bool falloff_visible = false;

// Pointy-top hexagon SDF matching the landscape hexagon brush.
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float h = max(abs(p.y), max(abs(p.x) * 1.1547005, abs(p.y) + abs(p.x) * 0.5773503));
	if (falloff_visible) {
		float sample = smoothstep(1.0, 0.0, h);
		ALPHA = sample * 0.6;
	} else {
		ALPHA = h <= 1.0 ? 0.25 : 0.0;
	}
}
