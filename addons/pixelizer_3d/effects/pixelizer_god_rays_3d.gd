@tool
class_name PixelizerGodRays3D
extends Node3D

## God rays through the banded cloud layer. This node owns a
## `PixelizerGodRayEffect` and inserts it into the manager's compositor before
## the snapshot pass, so the rays are part of the image the apply pass
## replicates into macro pixels. Disabling the node removes the pass entirely:
## no node, no pass.
##
## The cloud field is the manager's (same dictionary the shadow materials
## receive), so rays pour through the same gaps the ground shadows come from.
## `time_override >= 0` pins the cloud-field phase for reproducible captures;
## the pass otherwise reads the wall clock.

## Manager whose compositor hosts the ray pass. Resolved via the ancestor walk /
## "pixelizer_manager" group when unset.
@export var manager: PixelizerManager3D

@export_group("God Rays")
## Master toggle: on inserts the pass, off removes it.
@export var enabled := false:
	set(value):
		enabled = value
		if is_inside_tree():
			_register() if enabled else _unregister()
@export_range(1, 128) var ray_steps := 24
@export var ray_max_distance := 600.0
@export var ray_intensity := 0.5
## Exponential decay of the accumulation along the normalized march.
@export var ray_decay := 2.0
## Quantize the ray intensity to this many bands (<= 1 disables).
@export var ray_quantize_bands := 4.0
## How strongly a second, slower high-threshold noise modulates the shafts.
@export_range(0.0, 1.0) var ray_dust_strength := 0.15
## Distance along the ray where the near fade-in starts (world units).
@export var ray_near_fade_start := 0.0
## Fade-in range past the start; 0 disables the near fade.
@export var ray_near_fade_range := 0.0
## Near fade curve exponent.
@export var ray_near_fade_power := 1.0
## Kill rays past this distance; 0 disables the cutoff.
@export var ray_depth_cutoff := 0.0
## Fade within this distance of the surface hit; 0 disables.
@export var ray_surface_fade := 0.0
## Clamp applied after `ray_quantum` scales the accumulation; 0 disables.
@export var ray_max_stack := 10.0
## Scale applied to the accumulation before the max-stack clamp; <= 0 -> 1.
@export var ray_quantum := 0.0
## Exponential falloff per world unit along the march; 0 disables.
@export var ray_distance_falloff := 0.0
## Cloud-field phase in seconds. < 0 uses the wall clock; >= 0 pins the phase so
## ray captures are reproducible.
@export var time_override := -1.0

var _effect: PixelizerGodRayEffect


func _ready() -> void:
	# Deferred: an owning PixelizerApplier3D may create the shared manager in its
	# own `_ready`, which runs after this node's.
	call_deferred("_register")


func _exit_tree() -> void:
	_unregister()


func _process(_delta: float) -> void:
	if not PixelizerEffect3D.is_live(self):
		return
	if _effect == null or not _manager_valid():
		return
	_effect.apply_provider(self)
	_effect.set_cloud_params(manager.get_cloud_params())
	if manager.sun != null and is_instance_valid(manager.sun):
		_effect.ray_tint = manager.sun.light_color


func _register() -> void:
	if not enabled:
		return
	if not PixelizerEffect3D.is_live(self):
		return
	manager = PixelizerEffect3D.resolve(self)
	if not _manager_valid():
		PixelizerEffect3D.report_missing(self, "the ray pass is inert.")
		return
	if _effect == null:
		_effect = PixelizerGodRayEffect.new()
		_effect.manager = manager
	manager.add_pre_pixelization_effect(_effect)
	set_process(true)


func _unregister() -> void:
	set_process(false)
	if _effect == null:
		return
	if _manager_valid():
		manager.remove_pre_pixelization_effect(_effect)
	_effect = null


func _manager_valid() -> bool:
	return manager != null and is_instance_valid(manager)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not enabled:
		return warnings
	return PixelizerEffect3D.warnings(self, "the god-ray pass cannot be inserted.")
