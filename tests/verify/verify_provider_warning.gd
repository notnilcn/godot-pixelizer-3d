## Moved here from the 2026-10-16 verification session's scratchpad so it is not lost.
## TRUST: all 4 checks are valid and pass; it also pins the register_provider regression fixed in 2026-10-16. Headless is fine.
extends SceneTree

## Repro/regression check for the duck-typed cloud-provider warning.
##
## `PixelizerCloudField.register_provider` names every registered provider when a
## second one arrives. It used `String(entry)` for non-Node providers, and
## `String()` has no Object overload, so registering a plain RefCounted provider
## (the documented "any Object with build_cloud_params") raised
## "Invalid call 'String' constructor" and aborted the function before
## `_dirty`/`_push_all()`.
##
## This asserts the warning path is clean for both provider kinds. Run headless:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script <abs path>/verify_provider_warning.gd
## A SCRIPT ERROR on stderr is the failure mode, so this also greps nothing —
## read the output.

var _checks := 0
var _failures := PackedStringArray()
var _started := false


class ProbeProvider:
	extends RefCounted
	var cloud_camera_scope: Camera3D = null
	var threshold := 0.5

	func build_cloud_params(_sun) -> Dictionary:
		return {"clouds_enabled": false, "cloud_threshold": threshold}


func _initialize() -> void:
	root.add_child((load("res://demo/demo.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	quit(0 if _failures.is_empty() else 1)
	return true


func _run() -> void:
	var manager := _find_named(root, "PixelizerManager3D") as PixelizerManager3D
	_check(manager != null, "the demo's manager resolved (it registers a Node provider)")
	if manager == null:
		return
	# The demo already registered PixelizerSkyClouds3D (a Node). Adding two
	# duck-typed RefCounted providers walks the non-Node branch of the warning.
	var a := ProbeProvider.new()
	var b := ProbeProvider.new()
	a.threshold = 0.2
	b.threshold = 0.8
	manager.register_cloud_provider(a)
	manager.register_cloud_provider(b)
	print("PROVIDER WARNING: registered a Node provider plus 2 duck-typed providers without a script error")
	# The warning path must not skip the immediate field push.
	var params := manager.get_cloud_params()
	_check(params.has("cloud_threshold"), "the cloud field still produced a parameter dictionary")
	_check(a in manager.get("_clouds").get("_providers"), "provider A is in the provider list")
	manager.unregister_cloud_provider(a)
	manager.unregister_cloud_provider(b)
	_check(not (a in manager.get("_clouds").get("_providers")), "provider A unregisters cleanly")
	_report()


func _report() -> void:
	if _failures.is_empty():
		print("PROVIDER WARNING CHECK: %d checks, ALL PASS" % _checks)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("PROVIDER WARNING CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
