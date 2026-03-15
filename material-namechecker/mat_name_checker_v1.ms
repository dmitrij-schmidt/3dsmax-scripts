/*
 * Material Name Checker
 *
 * Scans a directory tree for .mat files and verifies that each root
 * material's inner name matches its parent folder name exactly.
 * Offers batch rename functionality to fix mismatches.
 *
 * Usage:
 *   1. Run script in 3ds Max (MAXScript > Run Script)
 *   2. Pick a "mother" directory (e.g. D:\assets)
 *   3. Script scans all subdirectories for .mat files
 *   4. Results table shows only mismatches
 *   5. Edit "Suggested name" column if needed
 *   6. Check rows and click "Rename selected" to apply
 *   7. Export button writes mismatches to a text file
 *
 * Example:
 *   D:\assets\Oak_Wood\Oak_Wood.mat   -> inner name "Oak_Wood"     -> OK (matches dir)
 *   D:\assets\Oak_Wood\bark.mat       -> inner name "Oak_Wod"      -> MISMATCH
 *   D:\assets\Birch_Wood\bw_v2.mat    -> inner name "Birch_Wood_v2"-> MISMATCH
 *
 * Comparison is case-sensitive (exact match).
 *
 * Known limitations:
 *   - loadMaterialLibrary replaces the current material library in the editor
 *   - Only scans one level of subdirectories (not recursive)
 *
 * Supported: 3ds Max 2018+
 */

-- ============================================================================
-- GLOBALS
-- ============================================================================

global _mnc_dgv = undefined
global _mnc_form = undefined
global _mnc_mismatches = #()   -- #(#(matFilePath, parentDir, innerName), ...)

-- ============================================================================
-- UTILITIES
-- ============================================================================

fn _mnc_getTimestamp =
(
    local now = (dotNetClass "System.DateTime").Now
    now.ToString "yyyy-MM-dd_HH-mm-ss"
)

fn _mnc_collectSubDirs rootDir =
(
    local dirs = getDirectories (rootDir + "*")
    for d in dirs collect d
)

fn _mnc_collectMatFiles dir =
(
    getFiles (dir + "*.mat")
)

fn _mnc_getParentDirName filePath =
(
    local fileName = pathConfig.stripPathToLeaf filePath
    local parentPath = substring filePath 1 (filePath.count - fileName.count)
    -- Strip trailing backslash
    if parentPath.count > 0 and parentPath[parentPath.count] == "\\" do
        parentPath = substring parentPath 1 (parentPath.count - 1)
    pathConfig.stripPathToLeaf parentPath
)

fn _mnc_isRowChecked row =
(
    local v = row.Cells.Item[0].Value
    if v == undefined or v == false do return false
    if v == true do return true
    try (v.ToString() == "True") catch false
)

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

fn _mnc_scanDirectory rootDir =
(
    -- Normalize trailing backslash
    if rootDir.count > 0 \
        and rootDir[rootDir.count] != "\\" \
        and rootDir[rootDir.count] != "/" do
        rootDir += "\\"

    local subDirs = _mnc_collectSubDirs rootDir
    local mismatches = #()
    local totalDirs = subDirs.count
    local totalMats = 0
    local totalChecked = 0

    format "Scanning % subdirectories...\n" totalDirs

    progressStart "Checking material names..."
    for di = 1 to totalDirs do
    (
        local cancelled = not (progressUpdate (100.0 * di / (amax totalDirs 1)))
        if cancelled do
        (
            progressEnd()
            format "Cancelled at [%/%]\n" di totalDirs
            return mismatches
        )

        local dir = subDirs[di]
        local parentDir = pathConfig.stripPathToLeaf \
            (if dir[dir.count] == "\\" then (substring dir 1 (dir.count - 1)) else dir)

        local matFiles = _mnc_collectMatFiles dir
        totalMats += matFiles.count

        for matFP in matFiles do
        (
            format "[%/%] %\n" di totalDirs matFP

            local loadOK = true
            try
            (
                with quiet on ( loadMaterialLibrary matFP )
            )
            catch
            (
                loadOK = false
                local errMsg = try (getCurrentException()) catch ("unknown error")
                format "  ERROR loading: %\n" errMsg
                append mismatches #(matFP, parentDir, "<<load failed>>")
            )

            if loadOK do
            (
                for mat in currentMaterialLibrary do
                (
                    totalChecked += 1
                    local innerName = try (mat.name) catch ("<<no name>>")
                    -- Case-sensitive exact match
                    if stricmp innerName parentDir != 0 do
                        append mismatches #(matFP, parentDir, innerName)
                )
            )
        )
    )
    progressEnd()

    format "Done. Checked % materials in % .mat files across % directories.\n" totalChecked totalMats totalDirs
    format "Mismatches found: %\n" mismatches.count

    mismatches
)

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

fn _mnc_onSelectAll s e =
(
    if _mnc_dgv == undefined do return()
    _mnc_dgv.EndEdit()
    for ri = 0 to _mnc_dgv.Rows.Count - 1 do
        _mnc_dgv.Rows.Item[ri].Cells.Item[0].Value = dotNetObject "System.Boolean" true
    _mnc_dgv.RefreshEdit()
)

fn _mnc_onSelectNone s e =
(
    if _mnc_dgv == undefined do return()
    _mnc_dgv.EndEdit()
    for ri = 0 to _mnc_dgv.Rows.Count - 1 do
        _mnc_dgv.Rows.Item[ri].Cells.Item[0].Value = dotNetObject "System.Boolean" false
    _mnc_dgv.RefreshEdit()
)

fn _mnc_onExport s e =
(
    if _mnc_mismatches == undefined or _mnc_mismatches.count == 0 do
    (
        messageBox "Nothing to export." title:"Name Checker"
        return()
    )

    local outFile = getSaveFileName \
        caption:"Export mismatches" \
        types:"Text File (*.txt)|*.txt|All Files (*.*)|*.*|" \
        filename:("name_mismatches_" + (_mnc_getTimestamp()) + ".txt")
    if outFile == undefined do return()

    local f = createFile outFile
    if f == undefined do
    (
        messageBox ("Could not create file:\n" + outFile) title:"Name Checker"
        return()
    )

    local nl = "\n"
    format "Material Name Checker - Mismatches%"  nl to:f
    format "Generated: %%"  (_mnc_getTimestamp()) nl to:f
    format "Total mismatches: %%"  (_mnc_mismatches.count as string) nl to:f

    for item in _mnc_mismatches do
    (
        format "-----%"  nl to:f
        format "MAT: %%"  item[1] nl to:f
        format "EXP: %%"  item[2] nl to:f
        format "ACT: %%"  item[3] nl to:f
    )
    format "-----%"  nl to:f

    close f
    format "Exported to: %\n" outFile
    messageBox ("Exported " + (_mnc_mismatches.count as string) + " mismatches to:\n" + outFile) title:"Name Checker"
)

fn _mnc_onRename s e =
(
    if _mnc_dgv == undefined do return()
    _mnc_dgv.EndEdit()

    -- Collect checked rows
    local toRename = #()
    for ri = 0 to _mnc_dgv.Rows.Count - 1 do
    (
        local row = _mnc_dgv.Rows.Item[ri]
        if _mnc_isRowChecked row do
        (
            local matFP       = row.Cells.Item[1].Value
            local actualName  = row.Cells.Item[3].Value
            local newName     = row.Cells.Item[4].Value

            -- Skip load-failed rows
            if actualName == "<<load failed>>" do continue

            -- Skip if suggested name is empty
            if newName == undefined or newName == "" do continue

            append toRename #(matFP, actualName, newName)
        )
    )

    if toRename.count == 0 do
    (
        messageBox "No rows selected for renaming." title:"Name Checker"
        return()
    )

    local confirm = queryBox \
        ("Rename inner names for " + (toRename.count as string) + " material(s)?") \
        title:"Name Checker" beep:false
    if not confirm do return()

    -- Group by .mat file path
    local fileGroups = #()
    local fileGroupKeys = #()
    for item in toRename do
    (
        local idx = findItem fileGroupKeys item[1]
        if idx == 0 then
        (
            append fileGroupKeys item[1]
            append fileGroups #(item)
        )
        else
            append fileGroups[idx] item
    )

    local successCount = 0
    local failCount = 0

    for fi = 1 to fileGroupKeys.count do
    (
        local matFP = fileGroupKeys[fi]
        local items = fileGroups[fi]

        format "Processing: %\n" matFP

        -- Load the .mat file
        local loadOK = true
        try
        (
            with quiet on ( loadMaterialLibrary matFP )
        )
        catch
        (
            loadOK = false
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "  ERROR loading: %\n" errMsg
            failCount += items.count
        )

        if loadOK do
        (
            -- Rename materials
            local modified = false
            for item in items do
            (
                local oldName = item[2]
                local newName = item[3]
                local found = false

                for mat in currentMaterialLibrary do
                (
                    local matName = try (mat.name) catch ("")
                    if stricmp matName oldName == 0 do
                    (
                        try
                        (
                            mat.name = newName
                            format "  Renamed \"%\" -> \"%\"\n" oldName newName
                            modified = true
                            found = true
                            successCount += 1
                        )
                        catch
                        (
                            local errMsg = try (getCurrentException()) catch ("unknown error")
                            format "  ERROR renaming \"%\": %\n" oldName errMsg
                            failCount += 1
                        )
                        exit
                    )
                )

                if not found do
                (
                    format "  WARNING: material \"%\" not found in library\n" oldName
                    failCount += 1
                )
            )

            -- Save back
            if modified do
            (
                try
                (
                    with quiet on ( saveMaterialLibrary matFP )
                    format "  Saved: %\n" matFP
                )
                catch
                (
                    local errMsg = try (getCurrentException()) catch ("unknown error")
                    format "  ERROR saving: %\n" errMsg
                )
            )
        )
    )

    local msg = "Renamed: " + (successCount as string) + \
        (if failCount > 0 then ("\nFailed: " + (failCount as string)) else "")
    messageBox msg title:"Name Checker"
    format "%\n" msg
)

fn _mnc_onClose s e =
(
    if _mnc_form != undefined do _mnc_form.Close()
)

-- ============================================================================
-- RESULTS UI
-- ============================================================================

fn _mnc_makeBtn label x y w h parent =
(
    local b = dotNetObject "System.Windows.Forms.Button"
    b.Text = label
    b.Location = dotNetObject "System.Drawing.Point" x y
    b.Size     = dotNetObject "System.Drawing.Size" w h
    b.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").System
    parent.Controls.Add b
    b
)

fn _mnc_showResults mismatches =
(
    _mnc_mismatches = mismatches

    if mismatches.count == 0 do
    (
        messageBox "All material names match their parent directories." title:"Name Checker"
        return()
    )

    -- Form
    local form = dotNetObject "System.Windows.Forms.Form"
    _mnc_form = form
    form.Text = "Material Name Checker - " + (mismatches.count as string) + " mismatches"
    form.Width = 1100
    form.Height = 500
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
    form.MinimumSize = dotNetObject "System.Drawing.Size" 800 300

    -- Top panel (Select All / Deselect All)
    local topPanel = dotNetObject "System.Windows.Forms.Panel"
    topPanel.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Top
    topPanel.Height = 36

    local bTA = _mnc_makeBtn "Select all" 12 6 90 24 topPanel
    local bTN = _mnc_makeBtn "Deselect all" 108 6 90 24 topPanel

    -- Bottom panel
    local botPanel = dotNetObject "System.Windows.Forms.Panel"
    botPanel.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Bottom
    botPanel.Height = 80

    -- Bottom row 1: Select All / Deselect All
    local bBA = _mnc_makeBtn "Select all" 12 8 90 24 botPanel
    local bBN = _mnc_makeBtn "Deselect all" 108 8 90 24 botPanel

    -- Bottom row 2: Rename / Export / Close
    local bRename = _mnc_makeBtn "Rename selected" 12 40 120 28 botPanel
    local bExport = _mnc_makeBtn "Export log" 140 40 90 28 botPanel
    local bClose  = _mnc_makeBtn "Close" 238 40 80 28 botPanel

    -- DataGridView
    local dgv = dotNetObject "System.Windows.Forms.DataGridView"
    _mnc_dgv = dgv
    dgv.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Fill
    dgv.AllowUserToAddRows    = false
    dgv.AllowUserToDeleteRows = false
    dgv.AllowUserToResizeRows    = false
    dgv.AllowUserToResizeColumns = true
    dgv.RowHeadersVisible     = false
    dgv.SelectionMode = (dotNetClass "System.Windows.Forms.DataGridViewSelectionMode").FullRowSelect
    dgv.MultiSelect   = false
    dgv.BackgroundColor = (dotNetClass "System.Drawing.SystemColors").Window
    dgv.BorderStyle     = (dotNetClass "System.Windows.Forms.BorderStyle").None

    -- Column 0: Checkbox
    local c0 = dotNetObject "System.Windows.Forms.DataGridViewCheckBoxColumn"
    c0.HeaderText = ""
    c0.Width = 30
    dgv.Columns.Add c0

    -- Column 1: MAT file (read-only)
    local c1 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c1.HeaderText = "MAT file"
    c1.Width = 350
    c1.ReadOnly = true
    dgv.Columns.Add c1

    -- Column 2: Expected dir (read-only)
    local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c2.HeaderText = "Expected (dir)"
    c2.Width = 160
    c2.ReadOnly = true
    dgv.Columns.Add c2

    -- Column 3: Actual inner name (read-only)
    local c3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c3.HeaderText = "Actual (inner name)"
    c3.Width = 180
    c3.ReadOnly = true
    dgv.Columns.Add c3

    -- Column 4: Suggested name (editable)
    local c4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c4.HeaderText = "Suggested name"
    c4.Width = 180
    c4.ReadOnly = false
    dgv.Columns.Add c4

    -- Populate
    local clrWarnBg = (dotNetClass "System.Drawing.Color").FromArgb 255 245 210
    local clrErrBg  = (dotNetClass "System.Drawing.Color").FromArgb 255 230 230

    for item in mismatches do
    (
        local ri  = dgv.Rows.Add()
        local row = dgv.Rows.Item[ri]
        row.Cells.Item[0].Value = dotNetObject "System.Boolean" true
        row.Cells.Item[1].Value = item[1]
        row.Cells.Item[2].Value = item[2]
        row.Cells.Item[3].Value = item[3]
        row.Cells.Item[4].Value = item[2]   -- pre-fill suggested from expected dir

        if item[3] == "<<load failed>>" then
        (
            row.DefaultCellStyle.BackColor = clrErrBg
            row.Cells.Item[4].Value = ""
            row.Cells.Item[0].Value = dotNetObject "System.Boolean" false
        )
        else
            row.DefaultCellStyle.BackColor = clrWarnBg
    )

    -- Dock order: Fill first, then Bottom, then Top
    form.Controls.Add dgv
    form.Controls.Add botPanel
    form.Controls.Add topPanel

    -- Events
    dotNet.addEventHandler bTA "Click" _mnc_onSelectAll
    dotNet.addEventHandler bTN "Click" _mnc_onSelectNone
    dotNet.addEventHandler bBA "Click" _mnc_onSelectAll
    dotNet.addEventHandler bBN "Click" _mnc_onSelectNone
    dotNet.addEventHandler bRename "Click" _mnc_onRename
    dotNet.addEventHandler bExport "Click" _mnc_onExport
    dotNet.addEventHandler bClose  "Click" _mnc_onClose

    form.ShowDialog()
)

-- ============================================================================
-- MAIN
-- ============================================================================

fn runMatNameChecker =
(
    local rootDir = getSavePath caption:"Select mother directory containing material folders"
    if rootDir == undefined do
    (
        format "Cancelled.\n"
        return OK
    )

    local mismatches = _mnc_scanDirectory rootDir
    _mnc_showResults mismatches
)

runMatNameChecker()
