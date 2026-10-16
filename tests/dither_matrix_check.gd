extends SceneTree

## Unit check for DitherMatrix (PLAN.md C2): the baked LUT bands must use the
## same thresholds as the shader's alpha dither.
## Run:
##   Godot-stable_mono_win64_console.exe --headless --path . \
##     --script res://tests/dither_matrix_check.gd
## Exit 0 = all pass.

var _failures := PackedStringArray()
var _checks := 0


func _initialize() -> void:
	var matrix := DitherMatrix.new()
	var values := matrix.values

	# Sorted thresholds are (n + 1) / 17 for n = 0..15: nonzero everywhere and
	# never reaching 1.0 (a fraction of exactly 1.0 must pick the lighter colour
	# in every cell).
	var sorted := Array(values)
	sorted.sort()
	var expected: Array = []
	for n in 16:
		expected.append(float(n + 1) / 17.0)
	_check(sorted.size() == 16, "matrix has 16 values")
	if sorted.size() == 16:
		for i in 16:
			_check(is_equal_approx(float(sorted[i]), float(expected[i])),
				"threshold[%d] is (%d + 1) / 17" % [i, i])

	# Every cell picks the darker colour at fraction 0 and the lighter at 1.
	var darker_all := true
	var lighter_all := true
	for index in 16:
		darker_all = darker_all and matrix.pick_first(0.0, index)
		lighter_all = lighter_all and not matrix.pick_first(1.0, index)
	_check(darker_all, "fraction 0.0 picks the darker colour in every cell (no zero-threshold cell)")
	_check(lighter_all, "fraction 1.0 picks the lighter colour in every cell")

	# The 16 cells cover the fraction range exactly once each: at a fraction just
	# below (m + 1) / 17, exactly 16 - m cells still pick the darker colour (at
	# just below 16/17 only the cell holding 16/17 does).
	for m in 16:
		var fraction := float(m + 1) / 17.0 - 1.0e-4
		var darker := 0
		for index in 16:
			if matrix.pick_first(fraction, index):
				darker += 1
		_check(darker == 16 - m, "fraction just below (%d + 1) / 17 keeps %d cells on the darker colour" % [m, 16 - m])

	if _failures.is_empty():
		print("DITHER MATRIX CHECK: %d checks, ALL PASS" % _checks)
		quit(0)
		return
	for failure in _failures:
		print("FAIL: ", failure)
	print("DITHER MATRIX CHECK: %d checks, %d FAILURE(S)" % [_checks, _failures.size()])
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
