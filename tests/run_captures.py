#!/usr/bin/env python3
"""Capture-regression matrix for `demo/demo.tscn`.

Runs the demo once per matrix entry with the small capture CLI implemented in
`demo/capture.gd` (`--capture`, `--resolution`, `--fixed-view`, `--mode`,
`--plain`, `--debug-view`, `--pixel-size`, `--no-overlay`, `--settle`,
`--outline-terrain`, `--ortho`, `--mover-snap`, `--palette-lut`), verifies
the diagnostics JSON line the demo prints, diffs each capture against
`tests/reference/`, and cross-checks that every non-anchor mode actually differs
from the anchor capture (a silently ignored flag fails the run).

Usage:
    python tests/run_captures.py                     # compare against references
    python tests/run_captures.py --update-references # (re)write the references
    python tests/run_captures.py --only=lowres       # one entry
    python tests/run_captures.py --godot <path>      # override the binary

Captures need a real GPU/display (Forward+); the runner passes `--fixed-fps 60`
and pins the demo's god-ray phase, which makes runs byte-identical on one
machine (`tests/captures/` is the output directory and is gitignored apart from
its `.gdignore`).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_captures import diff_images, format_metrics, load_rgb  # noqa: E402
import os  # noqa: E402

DEFAULT_GODOT = os.environ.get(
    "GODOT_BIN",
    "C:/Users/Clinton/g/Godot/Godot-stable_mono_win64_console.exe")

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "tests" / "captures"
REFERENCES = ROOT / "tests" / "reference"

DIAG_PREFIX = "PIXELIZER_CAPTURE "

# Reference tolerance: on one machine the matrix is byte-stable, so this only
# absorbs driver differences. Cross-mode differences are asserted separately.
MAX_CHANGED_PCT = 0.5
MAX_MEAN = 0.2
# A non-anchor mode must differ from the anchor capture by at least this much.
MIN_CHANGED_PCT = 1.0
MIN_MEAN = 0.5

SETTLE = 150

MATRIX = [
    {
        "name": "anchor",
        "args": ["--fixed-view=overhead", "--no-overlay"],
        "expect": {"mode": "anchor", "plain": False, "debug_view": 0, "pixel_size": 5},
    },
    {
        "name": "debug_anchor_map",
        "args": ["--fixed-view=overhead", "--no-overlay", "--debug-view=1"],
        "expect": {"mode": "anchor", "debug_view": 1},
    },
    {
        "name": "lowres",
        "args": ["--fixed-view=overhead", "--no-overlay", "--mode=lowres"],
        "expect": {"mode": "lowres"},
    },
    {
        "name": "plain",
        "args": ["--fixed-view=overhead", "--no-overlay", "--plain"],
        "expect": {"plain": True},
    },
    {
        "name": "pixel_size_3",
        "args": ["--fixed-view=overhead", "--no-overlay", "--pixel-size=3"],
        "expect": {"pixel_size": 3},
    },
    {
        # The dense outline case: every applier outlined, the terrain included
        # (the configuration the D-series outline work exists for).
        "name": "outline_dense",
        "args": ["--fixed-view=overhead", "--no-overlay", "--outline-terrain"],
        "expect": {"outline_terrain": True, "ortho": False},
    },
    {
        # Mover snap is orthographic-only, so the perspective entries never
        # reach the vertex-stage snap; this one does.
        "name": "ortho_mover",
        "args": ["--fixed-view=overhead", "--no-overlay", "--ortho", "--mover-snap"],
        "expect": {"ortho": True},
        "expect_positive": ["mover_count"],
    },
    {
        # Bake -> global uniform -> grade, which the demo never exercises.
        "name": "palette_lut",
        "args": ["--fixed-view=overhead", "--no-overlay", "--palette-lut"],
        "expect": {"palette_lut": True},
    },
]


def run_capture(entry: dict, godot: str, destination: Path, timeout: float) -> dict:
    """Run one matrix entry; returns the diagnostics dict (raises on failure)."""
    args = [
        godot,
        "--path", str(ROOT),
        "--fixed-fps", "60",
        "--",
        f"--capture={destination.as_posix()}",
        f"--settle={SETTLE}",
        *entry["args"],
    ]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    diagnostics = None
    for line in proc.stdout.splitlines():
        if line.startswith(DIAG_PREFIX):
            diagnostics = json.loads(line[len(DIAG_PREFIX):])
    if diagnostics is None:
        raise RuntimeError(
            f"{entry['name']}: no diagnostics line (exit {proc.returncode}); stderr tail:\n"
            + "\n".join(proc.stderr.splitlines()[-5:]))
    if diagnostics.get("save_error") != 0 or proc.returncode != 0:
        raise RuntimeError(f"{entry['name']}: capture failed: {diagnostics} "
                           f"exit={proc.returncode}")
    if not destination.exists():
        raise RuntimeError(f"{entry['name']}: {destination} was not written")
    for key, expected in entry["expect"].items():
        actual = diagnostics.get(key)
        if actual != expected:
            raise RuntimeError(
                f"{entry['name']}: flag not honoured: {key}={actual!r} "
                f"(expected {expected!r}); diagnostics={diagnostics}")
    for key in entry.get("expect_positive", []):
        if not diagnostics.get(key, 0) > 0:
            raise RuntimeError(
                f"{entry['name']}: expected {key} > 0; diagnostics={diagnostics}")
    return diagnostics


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--update-references", action="store_true",
                        help="run the matrix and copy the captures into tests/reference/")
    parser.add_argument("--only", default="", help="run one matrix entry by name")
    parser.add_argument("--godot", default=DEFAULT_GODOT, help="Godot binary path")
    parser.add_argument("--timeout", type=float, default=180.0,
                        help="per-capture timeout in seconds (default 180)")
    args = parser.parse_args(argv)

    entries = MATRIX
    if args.only:
        entries = [entry for entry in MATRIX if entry["name"] == args.only]
        if not entries:
            print(f"ERROR: no matrix entry named {args.only!r}", file=sys.stderr)
            return 1

    CAPTURES.mkdir(parents=True, exist_ok=True)
    REFERENCES.mkdir(parents=True, exist_ok=True)

    failures: list[str] = []
    captures: dict[str, Path] = {}
    for entry in entries:
        destination = CAPTURES / f"{entry['name']}.png"
        print(f"run   {entry['name']:<16} -> {destination.relative_to(ROOT).as_posix()}")
        try:
            diagnostics = run_capture(entry, args.godot, destination, args.timeout)
            print(f"      diagnostics {json.dumps(diagnostics, sort_keys=True)}")
            captures[entry["name"]] = destination
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as exc:
            failures.append(f"{entry['name']}: {exc}")
            print(f"FAIL  {entry['name']}: {exc}")

    if args.update_references:
        for name, path in captures.items():
            shutil.copyfile(path, REFERENCES / f"{name}.png")
            print(f"ref   {name:<16} { (REFERENCES / f'{name}.png').relative_to(ROOT).as_posix() }")
        if failures:
            print(f"\n{len(failures)} capture(s) failed; references partially updated.")
            return 1
        print(f"\nreferences updated ({len(captures)} file(s))")
        return 0

    # Reference comparison.
    for name, path in captures.items():
        reference = REFERENCES / f"{name}.png"
        if not reference.exists():
            failures.append(f"{name}: missing reference {reference.relative_to(ROOT).as_posix()} "
                            f"(run with --update-references)")
            print(f"MISS  {name}: no reference")
            continue
        try:
            metrics = diff_images(load_rgb(reference), load_rgb(path))
        except (OSError, ValueError) as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL  {name}: {exc}")
            continue
        okay = metrics["changed_pct"] <= MAX_CHANGED_PCT and metrics["mean_abs_diff"] <= MAX_MEAN
        print(f"{'PASS' if okay else 'FAIL'}  {name:<16} {format_metrics(metrics)} "
              f"(tolerance changed<={MAX_CHANGED_PCT}% mean<={MAX_MEAN})")
        if not okay:
            failures.append(f"{name}: over tolerance: {format_metrics(metrics)}")

    # Cross-checks: every other mode must differ from the anchor capture.
    anchor = captures.get("anchor")
    if anchor is not None:
        anchor_image = load_rgb(anchor)
        for name, path in captures.items():
            if name == "anchor":
                continue
            try:
                metrics = diff_images(anchor_image, load_rgb(path))
            except (OSError, ValueError) as exc:
                failures.append(f"{name}: cross-check failed: {exc}")
                continue
            differs = (metrics["changed_pct"] >= MIN_CHANGED_PCT
                       or metrics["mean_abs_diff"] >= MIN_MEAN)
            print(f"{'PASS' if differs else 'FAIL'}  {name:<16} differs from anchor: "
                  f"{format_metrics(metrics)} (floor changed>={MIN_CHANGED_PCT}% or mean>={MIN_MEAN})")
            if not differs:
                failures.append(f"{name}: does not differ from the anchor capture")

    if failures:
        print("\n" + "\n".join(f"- {failure}" for failure in failures))
        print(f"CAPTURE MATRIX: {len(failures)} failure(s)")
        return 1
    print("CAPTURE MATRIX: all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
