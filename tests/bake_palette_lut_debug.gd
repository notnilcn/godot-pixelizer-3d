extends SceneTree

## Rebakes `palette_lut_debug.png` (repo root) with the current PaletteLUT +
## DitherMatrix code. The swatch palette is recovered from the existing image:
## every distinct colour in a baked LUT is a palette swatch, and the original
## showcase .tres resources are gone, so this keeps the artifact reproducible
## instead of stale.
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script res://tests/bake_palette_lut_debug.gd

const OUTPUT := "res://palette_lut_debug.png"


func _initialize() -> void:
	# Raw file read (not ResourceLoader): the imported copy in .godot/ can lag a
	# rebake, and this tool must always read what is on disk.
	var bytes := FileAccess.get_file_as_bytes(OUTPUT)
	var image := Image.new()
	var loaded := image.load_png_from_buffer(bytes) if not bytes.is_empty() else FAILED
	if loaded != OK:
		push_error("Pixelizer3D: cannot load %s to recover the palette from (err %d)." % [OUTPUT, loaded])
		quit(1)
		return
	var colours := PackedColorArray()
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var colour := image.get_pixel(x, y)
			var key := colour.to_rgba32()
			if not seen.has(key):
				seen[key] = true
				colours.append(colour)
	var lut := PaletteLUT.new()
	lut.source = PaletteLUT.source_texture_from_colors(colours)
	lut.dither_matrix = DitherMatrix.new()
	lut.output_path = OUTPUT
	lut.save_lut_png()
	print("PALETTE LUT DEBUG: %d swatches recovered, saved %s" % [colours.size(), OUTPUT])
	quit(0)
