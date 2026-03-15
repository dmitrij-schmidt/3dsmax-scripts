# Material Relink

Find-and-replace path strings inside `.mat` material library files. Walks every material's property tree to locate file paths (texture maps, IES files, etc.) and lets you preview, select, and batch-replace them.

## Usage

1. In 3ds Max, go to **Scripting > Run Script** and select `material_relink_v1.ms`.
2. Choose a mode:
   - **Single file** — browse for one `.mat` file.
   - **Directory scan** — browse for a root directory; the script collects `.mat` files from its subdirectories. Optionally enable **Deep recursive search** to scan nested subdirectories.
3. Enter a **Find** string and a **Replace** string (e.g. find `D:\old_server\textures` replace with ``D:\new_server\textures`).
4. Click **Scan** to preview all matching paths.
5. A results window shows every path that contains the find string, with old/new values and whether the replacement target file exists on disk (**OK** or **ERROR**).
6. Use the selection buttons (**Select All**, **Deselect All**, **Select OK**, **Select ERROR**) to pick which paths to update.
7. Click **Replace selected** to apply changes and save each `.mat` file.

## Results Window

| Column      | Description                                              |
|-------------|----------------------------------------------------------|
| Checkbox    | Select items for replacement or export                   |
| Material    | Name of the material containing the path                 |
| Property    | Property name where the path was found                   |
| Path        | Old and new path values shown together                   |
| Target file | **OK** if the new path exists on disk, **ERROR** if not  |

In directory mode, results are grouped by `.mat` file with bold header rows.

## Options

- **Backup .mat file** — creates a timestamped `.bak` copy next to each original before modifying.
- **Store execution log** — writes a text log of all replacements made.
- **Export selected to log** — does not modify the file - performs a "dry run" instead. Saves the current selection to a text file for review.

## Requirements

- Autodesk 3ds Max 2018+
- Uses .NET WinForms (built into 3ds Max) for the results UI.

## Known Limitations

- `findString` matching is case-sensitive.
- Only the first occurrence of the find string per path is replaced.
- `loadMaterialLibrary` replaces the current material library in the Material Editor — save any work in progress first.
- The `#bitmap` property is skipped during scanning to avoid triggering file dialogs or slow texture loading.
