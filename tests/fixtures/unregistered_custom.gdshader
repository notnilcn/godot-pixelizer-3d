shader_type spatial;

// Fixture for tests/unsupported_material_check.gd: a custom shader that neither
// includes the anchor macros nor has a bridge, so the applier must skip it.
void fragment() {
	ALBEDO = vec3(0.8, 0.2, 0.6);
}
