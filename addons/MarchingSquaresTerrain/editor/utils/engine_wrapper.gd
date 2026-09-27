extends Object
class_name EngineWrapper


## True when running inside the Godot editor.
static func is_editor() -> bool:
	return Engine.is_editor_hint()


static func get_edited_scene_root():
	var editor_interface = Engine.get_singleton('EditorInterface')
	return editor_interface.get_edited_scene_root()


static func get_root_for_node(node: Node) -> Node:
	if is_editor():
		return get_edited_scene_root()
	if node and node.is_inside_tree():
		return node.get_tree().root
	return null


static func set_owner_recursive(node: Node, owner: Node = null) -> void:
	if not owner:
		owner = get_root_for_node(node)
	node.owner = owner
	for c in node.get_children():
		set_owner_recursive(c, owner)
