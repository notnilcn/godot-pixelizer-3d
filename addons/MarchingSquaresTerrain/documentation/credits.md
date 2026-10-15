# Plugin Credits

Developed by [Yūgen](https://www.youtube.com/@yugen_seishin) and originally forked from [Jackachulian](https://github.com/jackachulian/jackachulian) on github.

Collaborators (v1.1.0 ONWARDS):
* [DanTrz](https://github.com/DanTrz)
* [powertomato](https://github.com/powertomato)
* [santarl](https://github.com/santarl)

A special thanks to DanTrz (creator of the TileMapLayer3D plugin), powertomato and santarl for co-authoring big parts of the plugin since the 1.0 release. They have been amazing contributors to the project and awesome people to work with!

Contributors:
* [Dylearn](https://www.youtube.com/@Dylearn)
* [AtSaturn](https://www.youtube.com/@AtPlayerSaturn)
* My lifelong best friends!

###
A big thanks to the above people for giving helpful insights, discussing certain features and thinking together about math related problems. Without them I couldn't have finished the plugin as fast as I have.

## Bundled ports (v1.3.0 onwards)

Two editor plugins are vendored as sibling addons under `addons/` and share the MST grid through
the `MSTGridSnap` helper. They keep their upstream MIT licenses:

* `addons/YugenCyclopsLevelBuilder/` — port of [Cyclops Level Builder](https://github.com/blackears/cyclopsLevelBuilder) v1.5.0 by Mark McKay (MIT, © 2023 Mark McKay). Contains the additional `YugenSnappingSystemMST` grid-align snapping mode. License text: `LICENSE.md` in that folder.
* `addons/YugenTileMapLayer3D/` — port of [TileMapLayer3D](https://github.com/DanTrz/TileMapLayer3D) v1.2.0 by DanTrz (MIT, © 2025 DanTrz). Contains the additional MST Grid Align mode and the dual-grid display resolver. License text: `LICENSE.txt` in that folder.

The dual-grid neighbour/mixing rules in `addons/YugenTileMapLayer3D/core/dual/` are derived from:

* [DualGrid](https://github.com/Jesse-Goertzen/DualGrid) by Jesse Goertzen and [godot-dualgrid-unlimited-adjacent-terrains](https://github.com/Exonfang/godot-dualgrid-unlimited-adjacent-terrains) by Exonfang (MIT, © 2025-2026 Exonfang).
* [TileMapDual](https://github.com/pablogila/TileMapDual) v5 by Pablo Gila-Herranz (MIT, © 2024 Pablo Gila-Herranz).
