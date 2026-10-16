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
	var previous := FileAccess.get_file_as_string(manifest_path)
	var error := ResourceSaver.save(manifest, manifest_path)
	if error == OK and not previous.is_empty():
		_restore_uids(manifest_path, previous)
	print("MANIFEST %s (%d entries, %d new, %d left unapproved) err=%d" % [
		manifest_path, manifest.entries.size(), added, unapproved, error])
	return failed


## `ResourceSaver` under a plain `--script` run rewrites a `.tres` header without
## its `uid=` attributes (the editor keeps them), and `demo.tscn` references the
## production manifest by uid. Re-stamp the attributes recorded in the previous
## file text so a generator run is byte-stable and never invalidates an existing
## reference.
func _restore_uids(path: String, previous: String) -> void:
	var saved := FileAccess.get_file_as_string(path)
	if saved.is_empty():
		return
	var uids := _collect_uids(previous)
	if uids.is_empty():
		return
	var out := PackedStringArray()
	for line in saved.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("[gd_resource") and not stripped.contains("uid=") and uids.has(""):
			out.append(line.substr(0, line.rfind("]")) + " uid=\"%s\"]" % uids[""])
			continue
		if stripped.begins_with("[ext_resource") and not stripped.contains("uid="):
			var res_path := _attr(stripped, "path")
			if uids.has(res_path):
				out.append(line.replace(" path=\"", " uid=\"%s\" path=\"" % uids[res_path]))
				continue
		out.append(line)
	var restamped := "\n".join(out)
	if restamped == saved:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(restamped)
		file.close()


## Map of `path` attribute -> `uid` attribute for every line carrying a uid; the
## bare `[gd_resource]` header uses the empty-string key.
func _collect_uids(text: String) -> Dictionary:
	var uids := {}
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("["):
			continue
		var uid := _attr(stripped, "uid")
		if uid.is_empty():
			continue
		uids[_attr(stripped, "path")] = uid
	return uids


## Value of `name="value"` on a .tres line, or "".
func _attr(line: String, name: String) -> String:
	var key := name + "=\""
	var start := line.find(key)
	if start < 0:
		return ""
	var end := line.find("\"", start + key.length())
	return "" if end < 0 else line.substr(start + key.length(), end - start - key.length())


func _load_manifest(path: String) -> PixelizerBridgeManifest:
	if FileAccess.file_exists(path):
		var resource := ResourceLoader.load(path)
		if resource is PixelizerBridgeManifest:
			print("LOADED %s (%d entries)" % [path, (resource as PixelizerBridgeManifest).entries.size()])
			return resource
		push_warning("Pixelizer3D: %s is not a PixelizerBridgeManifest; a new manifest will be saved over it." % path)
	return PixelizerBridgeManifest.new()
