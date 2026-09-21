class_name PixelizerFocus
extends RefCounted

## Subject-focus bookkeeping for `PixelizerManager3D`. Focused meshes get the
## `anchor_focus` instance uniform, which the shader maps onto the reserved edge
## tag 255 without overwriting `anchor_tag` (focused pixels are exempt from
## smooth-scroll shifts and can be debug-tinted).

var _focused: Dictionary = {}
var _auto_target_id := 0
var _rescan_counter := 0

## Frames between automatic re-scans of the auto-focus target, so runtime-spawned
## children get focused too.
const AUTO_RESCAN_INTERVAL := 30


## Focus a node's subtree: every pixelized mesh gets edge tag 255.
func focus_subtree(root: Node) -> void:
	if root is GeometryInstance3D:
		_focus_mesh(root as GeometryInstance3D)
	for child in root.get_children():
		focus_subtree(child)


func unfocus_subtree(root: Node) -> void:
	if root is GeometryInstance3D:
		_unfocus_mesh(root as GeometryInstance3D)
	for child in root.get_children():
		unfocus_subtree(child)


## Keep `auto_focus_target`'s subtree focused; changing the target unfocuses the
## previous one first so no stale tags are left behind.
func update_auto(auto_focus: bool, target: Node3D) -> void:
	if not auto_focus or target == null or not is_instance_valid(target):
		return
	var target_id := target.get_instance_id()
	if target_id != _auto_target_id:
		if _auto_target_id != 0:
			var previous := instance_from_id(_auto_target_id)
			if previous != null and is_instance_valid(previous):
				unfocus_subtree(previous as Node)
		_auto_target_id = target_id
		focus_subtree(target)
		return
	_rescan_counter += 1
	if _rescan_counter >= AUTO_RESCAN_INTERVAL:
		_rescan_counter = 0
		focus_subtree(target)


func count() -> int:
	return _focused.size()


func _focus_mesh(mesh: GeometryInstance3D) -> void:
	var id := mesh.get_instance_id()
	if _focused.has(id):
		return
	_focused[id] = mesh
	mesh.set_instance_shader_parameter("anchor_focus", 1)


func _unfocus_mesh(mesh: GeometryInstance3D) -> void:
	var id := mesh.get_instance_id()
	if not _focused.has(id):
		return
	_focused.erase(id)
	if is_instance_valid(mesh):
		mesh.set_instance_shader_parameter("anchor_focus", 0)
