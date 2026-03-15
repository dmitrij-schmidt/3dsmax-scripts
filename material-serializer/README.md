# Material Serializer

Reads a 3ds Max `.mat` material library and serializes each top-level material to an individual file, recursively capturing sub-materials, texture maps, and all property data. Supports all material and map types including V-Ray.

## Scripts

### v1 — JSON (`material_serializer_v1.ms`)

Serializes materials to **JSON** files. Requires editing two hardcoded paths before running:

1. Open the script and set `material_library` to your `.mat` file path and `output_dir` to the desired output folder.
2. In 3ds Max, go to **Scripting > Run Script** and select the script.
3. Output `.json` files appear in the configured directory.

Each property is stored as a typed object (`{"type": "float", "value": 1.0}`), making the output self-describing but verbose.

### v2 — YAML with prefixed keys (`material_serializer_v2.ms`)

Serializes materials to **YAML** files using an interactive GUI — no hardcoded paths to edit.

1. In 3ds Max, go to **Scripting > Run Script** and select the script.
2. A dialog asks whether to load a `.mat` file or use the library already loaded in the scene.
3. Pick an output directory for the generated `.yaml` files.
4. Confirm to run.

Output uses idiomatic YAML:
- Native types written as bare values (`42`, `3.14`, `true`, `'hello'`).
- MaxScript-specific types use YAML local tags (`!color`, `!point3`, `!matrix3`, `!bitarray`, `!name`).
- Special floats use `.inf` / `.nan` notation.
- Nested material/map property keys include their full dot-separated parent path (e.g., `texmap_diffuse.coords.blur`).

## Requirements

- Autodesk 3ds Max 2018+
- Pure MaxScript — no external dependencies.

## Known Limitations

- Animation data (keyframes, controllers) is not captured.
- Instance relationships between shared maps are not preserved.
- Custom attributes are not serialized.
