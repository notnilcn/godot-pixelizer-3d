class_name PixelizerEffect3D
extends RefCounted

## Shared host for the optional scene-effect nodes (`effects/`).
##
## The six effects cannot share a base class: some are `Node3D`s (god rays,
## fireflies, day/night) and some are `MeshInstance3D`s (water, sky clouds,
## point-light volume), and GDScript has single inheritance, so a common
## `extends` is impossible without changing the node types scenes already use.
## They share this static host instead, which owns the contract they had each
## re-implemented (and drifted on):
##
##  - manager resolution with caching (`manager` export override -> ancestor
##    applier's manager -> manager ancestor -> sibling `PixelizerManager3D`),
##  - the editor gate: `_process` / registration run in the editor only with
##    `editor_preview`,
##  - the deferred register/unregister shape and the one-shot missing-manager
##    report,
##  - `_get_configuration_warnings()` content.
##
## Usage inside an effect:
##
##   @export var manager: PixelizerManager3D
##
##   func _ready() -> void:
##       call_deferred("_register")
##
##   func _register() -> void:
##       if not PixelizerEffect3D.is_live(self):
##           return
##       manager = PixelizerEffect3D.resolve(self)
##       if manager == null:
##           PixelizerEffect3D.report_missing(self, "the effect is inert.")
##           return
##       # ... register with the manager ...
##
##   func _exit_tree() -> void:
##       if manager != null and is_instance_valid(manager):
##           # ... unregister ...
##
##   func _get_configuration_warnings() -> PackedStringArray:
##       return PixelizerEffect3D.warnings(self, "the effect is inert.")


## The resolved manager, cached back on the effect's `manager` property.
## Returns null when none resolves (never creates one).
static func resolve(effect: Node) -> PixelizerManager3D:
	var cached = effect.get("manager")
	if cached is PixelizerManager3D and is_instance_valid(cached):
		return cached
	var resolved := PixelizerManager3D.resolve_manager_explicit(effect)
	if resolved != null:
		effect.set("manager", resolved)
	return resolved


## True when the effect may register/process now: always at runtime; in the
## editor only while the resolved manager's `editor_preview` is on.
static func is_live(effect: Node) -> bool:
	if not Engine.is_editor_hint():
		return true
	var manager := resolve(effect)
	return manager != null and manager.editor_preview


## One-shot missing-manager report (`what` names the consequence, e.g. "the ray
## pass is inert"). Silent in the editor, where the scene-tree warning covers it.
static func report_missing(effect: Node, what: String) -> void:
	if Engine.is_editor_hint():
		return
	if effect.has_meta(&"pixelizer_missing_manager_reported"):
		return
	effect.set_meta(&"pixelizer_missing_manager_reported", true)
	var script := effect.get_script() as Script
	var klass := String(script.get_global_name()) if script != null else "effect"
	push_error("Pixelizer3D: %s at '%s' found no PixelizerManager3D; %s" % [klass, effect.get_path(), what])


## `_get_configuration_warnings()` content for the unresolved-manager case.
static func warnings(effect: Node, what: String) -> PackedStringArray:
	var out := PackedStringArray()
	if resolve(effect) == null:
		out.append("No PixelizerManager3D resolved; %s" % what)
	return out
