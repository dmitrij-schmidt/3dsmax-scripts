# Material Name Checker

Scans a directory tree of `.mat` material libraries and verifies that each root material's inner name matches its parent folder name. Displays mismatches in an interactive table with batch rename and export capabilities.

## Usage

1. In 3ds Max, go to **Scripting > Run Script** and select `mat_name_checker_v1.ms`.
2. Pick a "mother" directory (e.g. `D:\assets`) — the script scans its immediate subdirectories for `.mat` files.
3. A results table shows only mismatches, with columns for the `.mat` file path, the expected name (parent folder), the actual inner name, and an editable suggested name (pre-filled with the folder name).
4. Check rows to fix, edit the "Suggested name" column if needed, then click **Rename selected** to apply.
5. Use **Export log** to write all mismatches to a timestamped text file.

## Example

```
D:\assets\Oak_Wood\Oak_Wood.mat   → inner name "Oak_Wood"      → OK (matches dir)
D:\assets\Oak_Wood\bark.mat       → inner name "Oak_Wod"       → MISMATCH
D:\assets\Birch_Wood\bw_v2.mat    → inner name "Birch_Wood_v2" → MISMATCH
```

## How Rename Works

- The script loads each `.mat` file, renames the matching material's inner name to the suggested value, and saves the library back to disk.
- Rows marked `<<load failed>>` are skipped automatically.
- A confirmation dialog appears before any changes are written.

## Requirements

- Autodesk 3ds Max 2018+
- Uses .NET WinForms (built into 3ds Max) for the results UI.

## Known Limitations

- `loadMaterialLibrary` replaces the current material library in the Material Editor — save any work in progress first.
- Only scans one level of subdirectories (not recursive). `.mat` files placed directly in the mother directory are skipped to avoid processing libraries.
- Comparison is case-sensitive (exact match).
