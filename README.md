# 3DS Max material export scripts

MaxScript tools and automation scripts for Autodesk 3ds Max with V-Ray.

## Quick Start

1. Download the v5 script, as the most human-friendly. Note the download location.
2. Make sure you have created a folder where the exported material data will be saved in `*.yaml` format.
3. Open 3ds Max.
4. Open the Scripting Listener: press **F11**, or go to **Scripting > Script Listener** in the top menu. Clear any previous logs by right-clicking and selecting **Clear All**. Keep this window open.
5. Go to **Scripting > Run Script** in the top menu and follow the on-screen instructions.
6. Watch the logs in the Scripting Listener for progress.
7. Once the process is complete, the exported material data will be in your chosen output folder.

## Scripts

### material_serializer.ms

Reads a `.mat` material library and serializes each top-level material to an individual JSON file. Recursively captures sub-materials, texture maps, and all property data. Supports all material/map types including V-Ray. Requires 3ds Max 2018+.

### material_serializer_v2.ms

YAML edition of the serializer. Uses StringStream for output performance. Simple properties are written as inline flow mappings (`{type: float, value: 1.0}`), materials/maps as block mappings. Handles special floats (INF, NaN).

### material_serializer_v3.ms

Idiomatic YAML edition. Native types (int, float, bool, string) are written as bare YAML values. MaxScript-specific types use YAML local tags (`!color`, `!point3`, `!matrix3`, `!bitarray`, `!name`). Special floats use `.inf` / `.nan` notation.

### material_serializer_v4.ms

Prefixed-key YAML edition. Nested material/map property keys include their full dot-separated parent path (e.g., `texmap_diffuse.coords.blur`). Uses single-quoted YAML strings for correct Windows path handling.

### material_serializer_v5.ms

Interactive version of v4. Replaces hardcoded global paths with GUI dialogs: file picker for the `.mat` library (or option to use the currently loaded one), directory picker for output, and a confirmation prompt before running.
