@tool
class_name PixelizerBridgeManifest
extends Resource

## A reviewable, diffable record of which external shaders the bridge is allowed
## to rewrite and where the generated assets live. Saved as a plain `.tres` with
## ResourceSaver and edited from the bridge dock.
##
## The manifest is intentionally NOT a global singleton: every manager names the
## manifests it trusts (`PixelizerManager3D.bridge_manifests`), so a project can
## ship several (e.g. one per addon) and remove one by deleting the resource.

const DEFAULT_OUTPUT_DIR := "res://pixelizer_bridges/"
const FILE_NAME := "pixelizer_bridge_manifest.tres"

## Folder that generated bridge shaders are written into. Refused at scan time
## when it lies inside a scanned root (the bridge never writes into a source
## addon).
@export var output_dir := DEFAULT_OUTPUT_DIR
## Source trees the scanner walks for `shader_type spatial;` shaders.
@export var roots := PackedStringArray()
## One entry per discovered/approved source shader.
@export var entries: Array[PixelizerBridgeEntry] = []


## Save this manifest to `path`, keeping its UIDs. Use this instead of a bare
## `ResourceSaver.save()` (the dock and `tests/bridge/generate_bridges.gd` both
## do).
##
## The text saver asks an editor-installed hook for UIDs, so outside the editor
## (a `--headless --script` run) it writes the header and every `ext_resource`
## WITHOUT `uid=` even though `ResourceUID` knows them all — and `demo.tscn`
## references the production manifest by uid. The UIDs therefore come from the
## engine, never from the previous file text: the header keeps the uid the file
## already had (a fresh file gets a new one) and is set through
## `ResourceSaver.set_uid()`; each `ext_resource` gets the uid
## `ResourceLoader.get_resource_uid()` reports for its path. Inside the editor
## the saver already writes them and this pass changes nothing.
func save_to(path: String) -> Error:
	var uid := ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var error := ResourceSaver.save(self, path)
	if error != OK:
		return error
	error = ResourceSaver.set_uid(path, uid)
	if error != OK:
		return error
	if ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, path)
	else:
		ResourceUID.add_id(uid, path)
	return _stamp_ext_resource_uids(path)


## Add the engine's uid to every `[ext_resource ...]` line that lacks one, in the
## position the editor writes it (`type=... uid=... path=... id=...`). Lines the
## engine has no uid for are left path-only, which loads the same.
static func _stamp_ext_resource_uids(path: String) -> Error:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ERR_FILE_CANT_READ
	var lines := text.split("\n")
	var changed := false
	var path_attr := RegEx.create_from_string(" path=\"([^\"]*)\"")
	for i in lines.size():
		var line := lines[i]
		if not line.begins_with("[ext_resource ") or line.contains(" uid=\""):
			continue
		var found := path_attr.search(line)
		if found == null:
			continue
		var uid := ResourceLoader.get_resource_uid(found.get_string(1))
		if uid == ResourceUID.INVALID_ID:
			continue
		lines[i] = line.replace(found.get_string(0), " uid=\"%s\"%s" % [ResourceUID.id_to_text(uid), found.get_string(0)])
		changed = true
	if not changed:
		return OK
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines))
	file.close()
	return OK


## The entry for `source_path`, or null.
func find_entry(source_path: String) -> PixelizerBridgeEntry:
	for entry in entries:
		if entry != null and entry.source_path == source_path:
			return entry
	return null


## The entry for `source_path`, created (approved = false, excluded = false) when
## absent. Never auto-approves.
func get_or_create_entry(source_path: String) -> PixelizerBridgeEntry:
	var existing := find_entry(source_path)
	if existing != null:
		return existing
	var entry := PixelizerBridgeEntry.new()
	entry.source_path = source_path
	entries.append(entry)
	return entry


## True when `path` (a res:// or absolute path) is inside any configured root.
func is_inside_roots(path: String) -> bool:
	var target := path.replace("\\", "/").trim_suffix("/")
	for root in roots:
		var base := String(root).replace("\\", "/").trim_suffix("/")
		if base.is_empty():
			continue
		if target == base or target.begins_with(base + "/"):
			return true
	return false
