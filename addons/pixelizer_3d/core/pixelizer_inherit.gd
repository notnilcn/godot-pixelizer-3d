class_name PixelizerInherit
extends RefCounted

## Central definition of the "inherit" sentinel used by every
## `PixelizerApplier3D` override and `PixelizerObjectProfile`.
##
## A property left at `INHERIT` takes the nearest ancestor applier's value, then
## the manager's default, then the built-in default. `PixelizerManager3D` exposes
## an adjustable copy (`inherit_sentinel`) for projects that want a different
## magic value; it must stay strictly below every valid property value so it can
## never collide with a real setting.

const INHERIT := -1

## True when `value` should fall through to the parent applier / manager.
static func is_inherit(value: int, sentinel: int = INHERIT) -> bool:
	return value == sentinel

## A sentinel is only safe when it cannot collide with a real value. Every
## inheritable property is non-negative (or an enum whose first value is 0), so
## the sentinel must be negative.
static func validate_sentinel(sentinel: int) -> bool:
	return sentinel < 0
