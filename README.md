# 3ds Max Material Tools

MaxScript tools for managing `.mat` material libraries in Autodesk 3ds Max. All scripts are interactive (GUI dialogs, no hardcoded paths) and support V-Ray materials.

Requires 3ds Max 2018+.

## Quick Start

1. Open 3ds Max.
2. Open the Scripting Listener (**F11**) to watch progress logs.
3. Go to **Scripting > Run Script** and select the script you need.
4. Follow the on-screen dialogs.

## Tools

### [material-serializer](material-serializer/)

Reads a `.mat` library and serializes each top-level material to an individual file, recursively capturing sub-materials, texture maps, and all properties.

- **v1** — JSON output, hardcoded paths (edit before running).
- **v2** — YAML output with prefixed keys, interactive GUI, idiomatic YAML types and local tags.

### [material-namechecker](material-namechecker/)

Scans subdirectories for `.mat` files and verifies that each material's inner name matches its parent folder name. Shows mismatches in an interactive table with batch rename and log export.

### [material-relink](material-relink/)

Find-and-replace path strings inside `.mat` files. Walks every material's property tree to locate texture paths, previews old/new values with target file existence checks, and batch-replaces. Supports single-file and directory-scan modes.
