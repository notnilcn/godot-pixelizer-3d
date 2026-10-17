extends SceneTree

## Generates the MST bridge shaders into:
##   1. `res://tests/bridge/generated/` - fixtures for the windowed compile
##      smoke test (`compile_test.tscn`). Wiped/rebuilt by bridge_fixtures.gd.
##   2. `res://pixelizer_bridges/` - the production manifest the demo manager
##      trusts (`PixelizerManager3D.bridge_manifests`).
##
## **Additive and path-faithful**: an existing manifest is loaded and updated in
## place (other entries, approvals and exclusions survive; output paths come from
## the same `PixelizerShaderBridge.output_path_for()` the dock uses), so running
## this script never drops approved entries or orphans generated files.
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script res://tests/bridge/generate_bridges.gd

const TARGETS := [
	"res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain.gdshader",
	"res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain_baked.gdshader",
	"res://addons/MarchingSquaresTerrain/resources/shaders/mst_grass.gdshader",
]
const FIXTURE_DIR := "res://tests/bridge/generated"
const PRODUCTION_DIR := "res://pixelizer_bridges"


func _initialize() -> void:
	var failed := 0
	failed += _generate_into(FIXTURE_DIR, "mst_bridge_manifest.tres")
	failed += _generate_into(PRODUCTION_DIR, PixelizerBridgeManifest.FILE_NAME)
	quit(1 if failed > 0 else 0)


func _generate_into(out_dir: String, manifest_name: String) -> int:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var manifest_path := out_dir + "/" + manifest_name
	var manifest := _load_manifest(manifest_path)
	manifest.output_dir = out_dir + "/"
	manifest.roots = PackedStringArray(["res://addons/MarchingSquaresTerrain"])
	var failed := 0
	var added := 0
	var unapproved := 0
	for source: String in TARGETS:
		var result := PixelizerShaderBridge.generate(FileAccess.get_file_as_string(source), source)
		if not result["ok"]:
			print("SKIP %s: %s" % [source, result["reason"]])
			failed += 1
			continue
		var path := PixelizerShaderBridge.output_path_for(manifest.output_dir, source)
		var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if dir_error != OK:
			print("SKIP %s: cannot create %s (err %d)" % [source, path.get_base_dir(), dir_error])
			failed += 1
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("SKIP %s: cannot write %s" % [source, path])
			failed += 1
			continue
		file.store_string(String(result["code"]))
		file.close()
		var scan := PixelizerShaderBridge.scan_candidate(FileAccess.get_file_as_string(source), source)
		var existed := manifest.find_entry(source) != null
		var entry := manifest.get_or_create_entry(source)
		# New entries are approved (this script exists to generate them); an
		# existing entry's approval decision is the dock's and is never reset.
		if not existed:
			entry.approved = true
			added += 1
		elif not entry.approved:
			unapproved += 1
		entry.has_vertex = scan["has_vertex"]
		entry.has_fragment = scan["has_fragment"]
		entry.writes_alpha = scan["writes_alpha"]
		entry.source_hash = PixelizerShaderBridge.hash_source_file(source)
		entry.output_path = path
		entry.generated_hash = PixelizerShaderBridge.hash_text(String(result["code"]))
		entry.rules_version = PixelizerBridgeRegistry.INJECTION_RULES_VERSION
		print("WROTE %s%s" % [path, "" if existed else " (new entry, approved)"])
	# `save_to()` keeps the manifest's UIDs, which a bare ResourceSaver.save()
	# drops in a `--script` run (`demo.tscn` references the manifest by uid).
	var error := manifest.save_to(manifest_path)
	print("MANIFEST %s (%d entries, %d new, %d left unapproved) err=%d" % [
		manifest_path, manifest.entries.size(), added, unapproved, error])
	return failed


func _load_manifest(path: String) -> PixelizerBridgeManifest:
	if FileAccess.file_exists(path):
		var resource := ResourceLoader.load(path)
		if resource is PixelizerBridgeManifest:
			print("LOADED %s (%d entries)" % [path, (resource as PixelizerBridgeManifest).entries.size()])
			return resource
		push_warning("Pixelizer3D: %s is not a PixelizerBridgeManifest; a new manifest will be saved over it." % path)
	return PixelizerBridgeManifest.new()
