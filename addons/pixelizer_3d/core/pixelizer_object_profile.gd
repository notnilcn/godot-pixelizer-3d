class_name PixelizerObjectProfile
extends Resource

## Per-object Pixelizer override, replacing the old `PixelizerObject3D` child
## node. A profile is a plain `Resource` owned by `PixelizerManager3D`
## (`object_profiles`); `target` points at the supported geometry node it
## configures (a `MeshInstance3D`, `MultiMeshInstance3D`, `GPUParticles3D` or
## `CPUParticles3D`).
##
## Properties left at `PixelizerInherit.INHERIT` fall through to the owning
## applier's effective value, exactly like an applier property left at the
## sentinel. `outline_id_mode` separates the three meanings the old `-1`
## overloaded (inherit / auto-allocate / explicit).

enum OutlineIdMode {
	## Take the owning applier's outline id.
	INHERIT,
	## Allocate a fresh id from the manager (old `outline_id = -1`).
	AUTO,
	## Use `outline_id` verbatim.
	EXPLICIT,
}

## Path to the geometry node this profile configures, relative to the manager
## that owns it. Used for the inspector-driven workflow.
@export var target_path: NodePath
## Direct geometry reference set from code (wins over `target_path`). Node
## references cannot be exported from a Resource, so this is API-only.
var target: Node3D
## Live toggle: when false the target is left as authored.
@export var enabled := true

@export_group("Pixelization")
## Macro-pixel size overrides the applier when >= 1; `INHERIT` uses the applier.
@export var pixel_size := PixelizerInherit.INHERIT
## Anchor lattice mode (0 = PER_OBJECT, 1 = UNIFIED); `INHERIT` uses the applier.
@export var anchor_mode := PixelizerInherit.INHERIT
## Palette LUT grading opt-out: 1 = grade, 0 = skip; `INHERIT` uses the applier.
@export var palette_enabled := PixelizerInherit.INHERIT
## Ordered-dither toggle: 1 = on, 0 = off; `INHERIT` uses the applier.
@export var dither_enabled := PixelizerInherit.INHERIT

@export_group("Outline")
## How `outline_id` is chosen.
@export var outline_id_mode: OutlineIdMode = OutlineIdMode.INHERIT
## Outline tag (1-254; 255 is reserved for the focus subject). Used when
## `outline_id_mode == EXPLICIT`.
@export var outline_id := 1
## Outline colour registered when `override_outline_color` is set. The alpha is
## the row opacity: 0 hides the outline, 1 replaces the scene colour.
@export var outline_color := Color(0.0, 0.0, 0.0, 1.0)
## Register `outline_color` for this object's id in the manager's palette.
@export var override_outline_color := false
## 1 = outline on, 0 = hidden; `INHERIT` uses the applier.
@export var outline_enabled := PixelizerInherit.INHERIT

## Convenience: true when this profile overrides any pixelization field.
func has_overrides() -> bool:
	return pixel_size != PixelizerInherit.INHERIT \
		or anchor_mode != PixelizerInherit.INHERIT \
		or palette_enabled != PixelizerInherit.INHERIT \
		or dither_enabled != PixelizerInherit.INHERIT \
		or outline_enabled != PixelizerInherit.INHERIT \
		or outline_id_mode != OutlineIdMode.INHERIT \
		or override_outline_color


## The geometry this profile configures: the code-set `target`, else
## `target_path` resolved against `owner_node` (the manager).
func resolve_target(owner_node: Node) -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	if target_path != NodePath() and owner_node != null:
		var node := owner_node.get_node_or_null(target_path)
		if node is Node3D:
			return node as Node3D
	return null
