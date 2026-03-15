/*
 * MatLib Replace v3
 *
 * Find-and-replace path strings inside .mat material library files.
 * Supports two modes:
 *   1. Single file — select one .mat file, scan and replace paths
 *   2. Directory scan — select a directory, batch-process all .mat files
 *
 * Usage:
 *   1. Run script in 3ds Max (MAXScript > Run Script)
 *   2. Choose mode: Single file or Directory scan
 *   3. Browse for a .mat file or directory
 *   4. Enter Find and Replace strings
 *   5. Click Scan to preview matches
 *   6. Review results, select items, click Replace
 *
 * Known limitations:
 *   - findString matching is case-sensitive
 *   - Only the first occurrence per path is replaced
 *
 * Supported: 3ds Max 2018+
 */

clearListener()
try destroyDialog matLibReplace catch()

-- ============================================================
-- UTILITIES
-- ============================================================
fn _mlr_getTimestamp =
(
    local now = (dotNetClass "System.DateTime").Now
    (now.Year as string) + "-" +
    (formattedPrint now.Month  format:"02d") + "-" +
    (formattedPrint now.Day    format:"02d") + "_" +
    (formattedPrint now.Hour   format:"02d") + "-" +
    (formattedPrint now.Minute format:"02d") + "-" +
    (formattedPrint now.Second format:"02d")
)

fn _mlr_getMatFolder fp =
(
    local leaf = pathConfig.stripPathToLeaf fp
    substring fp 1 (fp.count - leaf.count)
)

fn _mlr_getMatBaseName fp =
(
    local leaf = pathConfig.stripPathToLeaf fp
    local dotPos = undefined
    for i = leaf.count to 1 by -1 do
        if leaf[i] == "." do (dotPos = i; exit)
    if dotPos != undefined then (substring leaf 1 (dotPos - 1)) else leaf
)

fn _mlr_collectSubDirsRecurse dir depth maxD result =
(
    if depth > maxD do return()
    local subDirs = getDirectories (dir + "*")
    for d in subDirs do
    (
        append result d
        _mlr_collectSubDirsRecurse d (depth + 1) maxD result
    )
)

fn _mlr_collectSubDirs rootDir recursive maxDepth:20 =
(
    -- Collect only subdirectories — skip rootDir itself so that
    -- .mat files sitting directly in the provided root are ignored
    local result = #()
    if not recursive then
    (
        -- One level deep only
        local subDirs = getDirectories (rootDir + "*")
        for d in subDirs do append result d
    )
    else
    (
        -- Recursive with depth guard
        _mlr_collectSubDirsRecurse rootDir 1 maxDepth result
    )
    result
)

fn _mlr_collectMatFiles dirs =
(
    local result = #()
    for dir in dirs do
    (
        local files = getFiles (dir + "*.mat")
        for f in files do append result f
    )
    result
)

-- ============================================================
-- WALKER
-- Returns array of #(node, propName, pathValue)
-- ============================================================
fn _mlr_walkMat node visited:#() depth:0 maxDepth:20 =
(
    if node == undefined do return #()
    if depth > maxDepth do return #()
    if findItem visited node != 0 do return #()
    append visited node

    local results = #()
    local props = try (getPropNames node) catch (#())
    if props == undefined do props = #()
    for prop in props do
    (
        -- Skip #bitmap to avoid triggering file dialogs / slow texture loading
        if prop == #bitmap do continue
        local val = undefined
        try (val = getProperty node prop) catch()
        if val != undefined and classOf val == String and val != "" and \
               (findString val "\\" != undefined or findString val ":" != undefined) do
                append results #(node, prop, val)
    )

    local nSubs = try (node.numSubs) catch (0)
    if nSubs == undefined do nSubs = 0
    for i = 1 to nSubs do
        join results (_mlr_walkMat (getSubAnim node i) visited:visited depth:(depth + 1) maxDepth:maxDepth)

    results
)

-- ============================================================
-- COLLECT MATCHES
-- item: #(matName, node, prop, oldPath, newPath, fileExists)
-- ============================================================
fn _mlr_collectAllMatches needle replacement =
(
    local results = #()
    local total = currentMaterialLibrary.count
    progressStart "Scanning materials..."
    local i = 0
    for mat in currentMaterialLibrary do
    (
        i += 1
        if total > 0 do
        (
            local cancelled = not (progressUpdate (100.0 * i / total))
            if cancelled do
            (
                progressEnd()
                return results
            )
        )
        local visited = #()
        local allProps = _mlr_walkMat mat visited:visited
        for item in allProps do
        (
            local oldPath = item[3]
            local sPos = findString oldPath needle
            if sPos != undefined do
            (
                local newPath = replace oldPath sPos needle.count replacement
                local exists = doesFileExist newPath
                append results #(mat.name, item[1], item[2], oldPath, newPath, exists)
            )
        )
    )
    progressEnd()
    results
)

fn _mlr_scanAllMatFiles matFiles needle replacement =
(
    local fileMatches = #()
    local failedFiles = #()
    local totalFiles = matFiles.count

    progressStart "Scanning .mat files..."
    for fi = 1 to totalFiles do
    (
        local cancelled = not (progressUpdate (100.0 * fi / totalFiles))
        if cancelled do
        (
            progressEnd()
            return #(fileMatches, failedFiles)
        )

        local matFP = matFiles[fi]
        format "Scanning [%/%] %\n" fi totalFiles matFP

        local loadOK = true
        try
        (
            with quiet on ( loadMaterialLibrary matFP )
        )
        catch
        (
            loadOK = false
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "ERROR loading %: %\n" matFP errMsg
            append failedFiles matFP
        )

        if loadOK do
        (
            local matches = _mlr_collectAllMatches needle replacement
            if matches.count > 0 do
            (
                -- Discard live node references, keep string-only data
                -- Output tuple: #(matName, propName, oldPath, newPath, fileExists)
                local strMatches = #()
                for item in matches do
                (
                    append strMatches #(item[1], (item[3] as string), item[4], item[5], item[6])
                )
                append fileMatches #(matFP, strMatches)
            )
        )
    )
    progressEnd()

    #(fileMatches, failedFiles)
)

-- ============================================================
-- RESULTS WINDOW — globals for dotNet event handlers
-- ============================================================
global _mlr_dgv
global _mlr_matches = #()
global _mlr_matFP = ""
global _mlr_form
global _mlr_chkBackup
global _mlr_chkLog
global _mlr_rootDir = ""
global _mlr_headerRows = #()

fn _mlr_isHeaderRow rowIndex =
(
    findItem _mlr_headerRows rowIndex != 0
)

fn _mlr_isChecked row rowIndex =
(
    if _mlr_isHeaderRow rowIndex do return false
    local v = row.Cells.Item[0].Value
    if v == undefined or v == false do return false
    if v == true do return true
    try (v.ToString() == "True") catch false
)

fn _mlr_selectByStatus statusFilter =
(
    if _mlr_dgv == undefined do return()
    _mlr_dgv.EndEdit()
    for i = 0 to _mlr_dgv.Rows.Count - 1 do
    (
        if _mlr_isHeaderRow (i + 1) do continue
        local row = _mlr_dgv.Rows.Item[i]
        local target = row.Cells.Item[4].Value
        local val = case statusFilter of
        (
            "all":   true
            "none":  false
            "ok":    (target == "OK")
            "error": (target == "ERROR")
        )
        row.Cells.Item[0].Value = dotNetObject "System.Boolean" val
    )
    _mlr_dgv.RefreshEdit()
)

fn _mlr_getSelectedItems =
(
    local selected = #()
    if _mlr_dgv == undefined do return selected
    _mlr_dgv.EndEdit()
    for i = 0 to _mlr_dgv.Rows.Count - 1 do
    (
        if _mlr_isHeaderRow (i + 1) do continue
        if _mlr_isChecked (_mlr_dgv.Rows.Item[i]) (i + 1) do
            append selected _mlr_matches[i + 1]
    )
    selected
)

fn _mlr_onSelectAll   s e = _mlr_selectByStatus "all"
fn _mlr_onSelectNone  s e = _mlr_selectByStatus "none"
fn _mlr_onSelectOK    s e = _mlr_selectByStatus "ok"
fn _mlr_onSelectError s e = _mlr_selectByStatus "error"

fn _mlr_groupByMatFile items =
(
    -- Groups items by .mat file path (6th tuple element).
    -- Returns array of #(matFilePath, itemsArray)
    local fileGroups = #()
    local fileGroupPaths = #()
    for item in items do
    (
        local matFP = item[6]
        local idx = findItem fileGroupPaths matFP
        if idx == 0 then
        (
            append fileGroupPaths matFP
            append fileGroups #(matFP, #(item))
        )
        else
        (
            append fileGroups[idx][2] item
        )
    )
    fileGroups
)

fn _mlr_onReplace s e =
(
    local selected = _mlr_getSelectedItems()
    if selected.count == 0 do (messageBox "No items selected."; return())

    local okItems  = for item in selected where item[6] == true collect item
    local errCount = selected.count - okItems.count

    if errCount > 0 do
    (
        local msg = (errCount as string) + " selected item(s) have ERROR status and will be skipped.\n\n" + \
                    "Proceed with " + (okItems.count as string) + " OK item(s)?"
        if not (queryBox msg title:"Confirm Replace") do return()
    )
    if okItems.count == 0 do (messageBox "No valid items to replace."; return())

    local ts       = _mlr_getTimestamp()
    local folder   = _mlr_getMatFolder _mlr_matFP
    local baseName = _mlr_getMatBaseName _mlr_matFP

    -- Backup
    if _mlr_chkBackup != undefined and _mlr_chkBackup.Checked do
    (
        local bakFP = folder + baseName + "_" + ts + ".mat.bak"
        try
        (
            copyFile _mlr_matFP bakFP
            format "Backup: %\n" bakFP
        )
        catch
        (
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "WARNING: backup failed for %: %\n" _mlr_matFP errMsg
        )
    )

    -- Apply replacements
    local replaceCount = 0
    progressStart "Replacing..."
    for i = 1 to okItems.count do
    (
        local cancelled = not (progressUpdate (100.0 * i / okItems.count))
        if cancelled do exit
        try
        (
            setProperty okItems[i][2] okItems[i][3] okItems[i][5]
            replaceCount += 1
        )
        catch
        (
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "ERROR replacing % in %: %\n" (okItems[i][3] as string) okItems[i][1] errMsg
        )
    )
    progressEnd()

    local saveOK = true
    try ( fileSaveMatLib quiet:true ) catch
    (
        saveOK = false
        local errMsg = try (getCurrentException()) catch ("unknown error")
        format "ERROR saving material library: %\n" errMsg
    )

    -- Execution log
    if _mlr_chkLog != undefined and _mlr_chkLog.Checked do
    (
        local logFP = folder + baseName + "_log_" + ts + ".txt"
        local f = openFile logFP mode:"w"
        if f != undefined then
        (
            local curMat = ""
            for item in okItems do
            (
                if item[1] != curMat do
                (
                    if curMat != "" do format "\n" to:f
                    format "== % ==\n" item[1] to:f
                    curMat = item[1]
                )
                format "  [%]\n"     (item[3] as string) to:f
                format "  OLD: %\n"   item[4] to:f
                format "  NEW: %\n\n" item[5] to:f
            )
            close f
            format "Log: %\n" logFP
        )
        else
        (
            messageBox "Cannot create log file." title:"MatLib Replace"
        )
    )

    local savedMsg = if saveOK then " and saved" else " (WARNING: save failed!)"
    messageBox ((replaceCount as string) + " of " + (okItems.count as string) + " path(s) replaced" + savedMsg + ".") title:"Done"
    format "% of % path(s) replaced.\n" replaceCount okItems.count
    _mlr_form.Close()
)

fn _mlr_onExport s e =
(
    local selected = _mlr_getSelectedItems()
    if selected.count == 0 do (messageBox "No items selected."; return())

    local ts       = _mlr_getTimestamp()
    local folder   = _mlr_getMatFolder _mlr_matFP
    local baseName = _mlr_getMatBaseName _mlr_matFP
    local logFP    = folder + baseName + "_log_" + ts + ".txt"

    local f = openFile logFP mode:"w"
    if f == undefined do (messageBox "Cannot create log file."; return())

    local curMat = ""
    for item in selected do
    (
        if item[1] != curMat do
        (
            if curMat != "" do format "\n" to:f
            format "== % ==\n" item[1] to:f
            curMat = item[1]
        )
        local tag = if item[6] then "OK" else "ERROR"
        format "  [%] [%]\n"  (item[3] as string) tag to:f
        format "  OLD: %\n"   item[4] to:f
        format "  NEW: %\n\n" item[5] to:f
    )
    close f
    messageBox ("Log exported to:\n" + logFP) title:"Export Complete"
    format "Log: %\n" logFP
)

fn _mlr_reWalkAndReplace items =
(
    -- items: array of #(matName, propName, oldPath, newPath, fileExists, matFilePath)
    -- Re-walk the loaded library to find matching nodes
    -- Returns #(succeededItems, failedItems)
    --   failedItems entries: #(item, errMsg)
    local succeeded = #()
    local failed = #()
    for mat in currentMaterialLibrary do
    (
        local visited = #()
        local allProps = _mlr_walkMat mat visited:visited
        for item in items do
        (
            if item[1] != mat.name do continue
            for wp in allProps do
            (
                -- wp is #(node, prop, pathValue)
                if (wp[2] as string) == item[2] and wp[3] == item[3] do
                (
                    try
                    (
                        setProperty wp[1] wp[2] item[4]
                        append succeeded item
                    )
                    catch
                    (
                        local errMsg = try (getCurrentException()) catch ("unknown error")
                        format "ERROR replacing % in %: %\n" (wp[2] as string) item[1] errMsg
                        append failed #(item, errMsg)
                    )
                )
            )
        )
    )
    #(succeeded, failed)
)

fn _mlr_onReplaceMulti s e =
(
    local selected = _mlr_getSelectedItems()
    if selected.count == 0 do (messageBox "No items selected."; return())

    local okItems = for item in selected where item[5] == true collect item
    local errCount = selected.count - okItems.count

    if errCount > 0 do
    (
        local msg = (errCount as string) + " selected item(s) have ERROR status and will be skipped." + \
                    "\n\nProceed with " + (okItems.count as string) + " OK item(s)?"
        if not (queryBox msg title:"Confirm Replace") do return()
    )
    if okItems.count == 0 do (messageBox "No valid items to replace."; return())

    local ts = _mlr_getTimestamp()

    local fileGroups = _mlr_groupByMatFile okItems

    -- Process each .mat file
    local allSucceeded = #()
    local allFailed = #()
    local totalFiles = fileGroups.count
    progressStart "Replacing..."
    for fi = 1 to totalFiles do
    (
        local cancelled = not (progressUpdate (100.0 * fi / totalFiles))
        if cancelled do exit
        local matFP = fileGroups[fi][1]
        local items = fileGroups[fi][2]

        -- Backup
        if _mlr_chkBackup != undefined and _mlr_chkBackup.Checked do
        (
            local folder = _mlr_getMatFolder matFP
            local baseName = _mlr_getMatBaseName matFP
            local bakFP = folder + baseName + "_" + ts + ".mat.bak"
            try
            (
                copyFile matFP bakFP
                format "Backup: %\n" bakFP
            )
            catch
            (
                local errMsg = try (getCurrentException()) catch ("unknown error")
                format "WARNING: backup failed for %: %\n" matFP errMsg
            )
        )

        -- Load and replace
        local loadOK = true
        try
        (
            with quiet on ( loadMaterialLibrary matFP )
        )
        catch
        (
            loadOK = false
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "ERROR loading % for replace: %\n" matFP errMsg
        )

        if loadOK do
        (
            local result = _mlr_reWalkAndReplace items
            local succeeded = result[1]
            local failed = result[2]
            join allSucceeded succeeded
            join allFailed failed

            local saveOK = true
            try ( fileSaveMatLib quiet:true ) catch
            (
                saveOK = false
                local errMsg = try (getCurrentException()) catch ("unknown error")
                format "ERROR saving %: %\n" matFP errMsg
            )
            local saveTag = if saveOK then "" else " (SAVE FAILED)"
            format "Replaced % path(s), % failed in %%\n" succeeded.count failed.count matFP saveTag
        )
    )
    progressEnd()

    -- Write combined log
    if _mlr_chkLog != undefined and _mlr_chkLog.Checked do
    (
        local logFP = _mlr_rootDir + "relink_log_" + ts + ".txt"
        local f = openFile logFP mode:"w"
        if f != undefined then
        (
            -- Succeeded section
            if allSucceeded.count > 0 do
            (
                local fileGroups2 = _mlr_groupByMatFile allSucceeded
                for fi = 1 to fileGroups2.count do
                (
                    local matFP = fileGroups2[fi][1]
                    local items = fileGroups2[fi][2]
                    format "== % ==\n\n" matFP to:f
                    local curMat = ""
                    for item in items do
                    (
                        if item[1] != curMat do
                        (
                            if curMat != "" do format "\n" to:f
                            format "  == % ==\n" item[1] to:f
                            curMat = item[1]
                        )
                        format "    [%]\n"     item[2] to:f
                        format "    OLD: %\n"  item[3] to:f
                        format "    NEW: %\n\n" item[4] to:f
                    )
                    format "\n" to:f
                )
            )

            -- Errors section
            if allFailed.count > 0 do
            (
                format "== ERRORS ==\n\n" to:f
                for entry in allFailed do
                (
                    local item = entry[1]
                    local errMsg = entry[2]
                    format "  [%] %  %\n" item[2] item[1] to:f
                    format "    OLD: %\n" item[3] to:f
                    format "    NEW: %\n" item[4] to:f
                    format "    ERROR: %\n\n" errMsg to:f
                )
            )
            close f
            format "Log: %\n" logFP
        )
        else
        (
            messageBox "Cannot create log file." title:"MatLib Replace"
        )
    )

    local msg = (allSucceeded.count as string) + " path(s) replaced"
    if allFailed.count > 0 do
        msg += ", " + (allFailed.count as string) + " failed"
    msg += " across " + (totalFiles as string) + " file(s)."
    messageBox msg title:"Done"
    _mlr_form.Close()
)
fn _mlr_onExportMulti s e =
(
    local selected = _mlr_getSelectedItems()
    if selected.count == 0 do (messageBox "No items selected."; return())

    local ts = _mlr_getTimestamp()
    local logFP = _mlr_rootDir + "relink_export_" + ts + ".txt"

    local f = openFile logFP mode:"w"
    if f == undefined do (messageBox "Cannot create log file."; return())

    local fileGroups = _mlr_groupByMatFile selected

    for fi = 1 to fileGroups.count do
    (
        local matFP = fileGroups[fi][1]
        local items = fileGroups[fi][2]
        format "== % ==\n\n" matFP to:f
        local curMat = ""
        for item in items do
        (
            if item[1] != curMat do
            (
                if curMat != "" do format "\n" to:f
                format "  == % ==\n" item[1] to:f
                curMat = item[1]
            )
            local tag = if item[5] then "OK" else "ERROR"
            format "    [%] [%]\n"  item[2] tag to:f
            format "    OLD: %\n"   item[3] to:f
            format "    NEW: %\n\n" item[4] to:f
        )
        format "\n" to:f
    )
    close f
    messageBox ("Log exported to:" + "\n" + logFP) title:"Export Complete"
    format "Log: %\n" logFP
)

-- ============================================================
-- SHARED UI HELPERS
-- ============================================================
fn _mlr_makeBtn label x y w h parent =
(
    local b = dotNetObject "System.Windows.Forms.Button"
    b.Text = label
    b.Location = dotNetObject "System.Drawing.Point" x y
    b.Size     = dotNetObject "System.Drawing.Size" w h
    b.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").System
    parent.Controls.Add b
    b
)

fn _mlr_createDGV =
(
    local dgv = dotNetObject "System.Windows.Forms.DataGridView"
    _mlr_dgv = dgv
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
    dgv.DefaultCellStyle.WrapMode = (dotNetClass "System.Windows.Forms.DataGridViewTriState").True

    local c1 = dotNetObject "System.Windows.Forms.DataGridViewCheckBoxColumn"
    c1.HeaderText = ""
    c1.Width = 30
    dgv.Columns.Add c1

    local c2 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c2.HeaderText = "Material"
    c2.Width    = 150
    c2.ReadOnly = true
    dgv.Columns.Add c2

    local c3 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c3.HeaderText = "Property"
    c3.Width    = 80
    c3.ReadOnly = true
    dgv.Columns.Add c3

    local c4 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c4.HeaderText  = "Path"
    c4.Width = 500
    c4.ReadOnly    = true
    dgv.Columns.Add c4

    local c5 = dotNetObject "System.Windows.Forms.DataGridViewTextBoxColumn"
    c5.HeaderText = "Target file"
    c5.Width    = 70
    c5.ReadOnly = true
    dgv.Columns.Add c5

    dgv
)

-- ============================================================
-- SHOW RESULTS WINDOW
-- ============================================================
fn _mlr_showResultsWindow matches matFP =
(
    _mlr_matches  = matches
    _mlr_matFP    = matFP
    _mlr_headerRows = #()

    local nl   = (dotNetClass "System.Environment").NewLine
    local okN  = (for m in matches where m[6] collect m).count
    local errN = matches.count - okN

    -- ── Form ───────────────────────────────────────────────
    local form = dotNetObject "System.Windows.Forms.Form"
    _mlr_form = form
    form.Text = "MatLib Replace - Results"
    form.Width = 900
    form.Height = 600
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
    form.MinimumSize   = dotNetObject "System.Drawing.Size" 700 400

    -- ── Top panel ──────────────────────────────────────────
    local topPanel = dotNetObject "System.Windows.Forms.Panel"
    topPanel.Dock   = (dotNetClass "System.Windows.Forms.DockStyle").Top
    topPanel.Height = 40

    local bTA = _mlr_makeBtn "Select All"    10  8  90 26 topPanel
    local bTN = _mlr_makeBtn "Deselect All" 105 8 100 26 topPanel
    local bTO = _mlr_makeBtn "Select OK"    210 8  90 26 topPanel
    local bTE = _mlr_makeBtn "Select ERROR" 305 8 110 26 topPanel

    -- ── Bottom panel ───────────────────────────────────────
    local botPanel = dotNetObject "System.Windows.Forms.Panel"
    botPanel.Dock   = (dotNetClass "System.Windows.Forms.DockStyle").Bottom
    botPanel.Height = 185

    local bBA = _mlr_makeBtn "Select All"    10  8  90 26 botPanel
    local bBN = _mlr_makeBtn "Deselect All" 105 8 100 26 botPanel
    local bBO = _mlr_makeBtn "Select OK"    210 8  90 26 botPanel
    local bBE = _mlr_makeBtn "Select ERROR" 305 8 110 26 botPanel

    -- Summary label
    local lbl = dotNetObject "System.Windows.Forms.Label"
    lbl.Text     = (matches.count as string) + " paths found  -  " + \
                   (okN as string) + " OK,  " + (errN as string) + " ERROR"
    lbl.Location = dotNetObject "System.Drawing.Point" 12 42
    lbl.AutoSize = true
    botPanel.Controls.Add lbl

    -- Line 1: Export
    local bExport = _mlr_makeBtn "Export selected to log" 10 66 180 30 botPanel

    -- Line 2: Replace + checkboxes
    local bReplace = _mlr_makeBtn "Replace selected" 10 100 150 30 botPanel

    local chkBackup = dotNetObject "System.Windows.Forms.CheckBox"
    chkBackup.Text     = "Backup .mat file"
    chkBackup.Location = dotNetObject "System.Drawing.Point" 170 104
    chkBackup.AutoSize = true
    chkBackup.Checked  = true
    botPanel.Controls.Add chkBackup
    _mlr_chkBackup = chkBackup

    local chkLog = dotNetObject "System.Windows.Forms.CheckBox"
    chkLog.Text     = "Store execution log"
    chkLog.Location = dotNetObject "System.Drawing.Point" 320 104
    chkLog.AutoSize = true
    chkLog.Checked  = true
    botPanel.Controls.Add chkLog
    _mlr_chkLog = chkLog

    -- Line 3: Hint
    local hint = dotNetObject "System.Windows.Forms.Label"
    hint.Text      = "Backup and log files will be stored next to the source .mat file." + nl + \
                     "Note: matching is case-sensitive. Only the first occurrence per path is replaced."
    hint.Location  = dotNetObject "System.Drawing.Point" 12 134
    hint.AutoSize  = true
    hint.ForeColor = (dotNetClass "System.Drawing.SystemColors").GrayText
    botPanel.Controls.Add hint

    -- ── DataGridView ───────────────────────────────────────
    local dgv = _mlr_createDGV()

    -- Populate rows
    local clrErrBg  = (dotNetClass "System.Drawing.Color").FromArgb 255 230 230
    local clrErrFg  = (dotNetClass "System.Drawing.Color").FromArgb 180 0 0

    for item in matches do
    (
        local pathStr = "OLD: " + item[4] + nl + "NEW: " + item[5]
        local tag     = if item[6] then "OK" else "ERROR"

        local ri  = dgv.Rows.Add()
        local row = dgv.Rows.Item[ri]
        row.Cells.Item[0].Value = dotNetObject "System.Boolean" item[6]
        row.Cells.Item[1].Value = item[1]
        row.Cells.Item[2].Value = (item[3] as string)
        row.Cells.Item[3].Value = pathStr
        row.Cells.Item[4].Value = tag
        row.Height = 42

        if not item[6] do
        (
            row.DefaultCellStyle.BackColor = clrErrBg
            row.DefaultCellStyle.ForeColor = clrErrFg
        )
    )

    -- ── Wire events ────────────────────────────────────────
    dotNet.addEventHandler bTA "Click" _mlr_onSelectAll
    dotNet.addEventHandler bTN "Click" _mlr_onSelectNone
    dotNet.addEventHandler bTO "Click" _mlr_onSelectOK
    dotNet.addEventHandler bTE "Click" _mlr_onSelectError
    dotNet.addEventHandler bBA "Click" _mlr_onSelectAll
    dotNet.addEventHandler bBN "Click" _mlr_onSelectNone
    dotNet.addEventHandler bBO "Click" _mlr_onSelectOK
    dotNet.addEventHandler bBE "Click" _mlr_onSelectError
    dotNet.addEventHandler bReplace "Click" _mlr_onReplace
    dotNet.addEventHandler bExport  "Click" _mlr_onExport

    -- Add controls (reverse order for correct docking)
    form.Controls.Add dgv
    form.Controls.Add botPanel
    form.Controls.Add topPanel

    form.ShowDialog()
)

fn _mlr_showResultsWindowMulti fileMatches rootDir =
(
    -- Flatten matches and build _mlr_matches with 6th element (matFilePath)
    _mlr_matches = #()
    _mlr_headerRows = #()
    _mlr_rootDir = rootDir

    -- We'll track which _mlr_matches indices are headers
    -- Header entry: #("__HEADER__", "", "", "", false, matFilePath)
    -- Data entry:   #(matName, propName, oldPath, newPath, fileExists, matFilePath)
    local rowMap = #()  -- parallel to _mlr_matches: "header" or "data"

    for fm in fileMatches do
    (
        local matFP = fm[1]
        local matches = fm[2]
        -- Add header placeholder
        append _mlr_matches #("__HEADER__", "", "", "", false, matFP)
        append rowMap "header"
        -- Add data rows
        for item in matches do
        (
            append _mlr_matches #(item[1], item[2], item[3], item[4], item[5], matFP)
            append rowMap "data"
        )
    )

    -- Record header row indices (1-based)
    for i = 1 to rowMap.count do
        if rowMap[i] == "header" do append _mlr_headerRows i

    -- Count stats
    local totalMatches = 0
    local totalFiles = fileMatches.count
    local okN = 0
    for i = 1 to _mlr_matches.count do
    (
        if _mlr_isHeaderRow i do continue
        totalMatches += 1
        if _mlr_matches[i][5] == true do okN += 1
    )
    local errN = totalMatches - okN

    local nl = (dotNetClass "System.Environment").NewLine

    -- Form
    local form = dotNetObject "System.Windows.Forms.Form"
    _mlr_form = form
    form.Text = "MatLib Replace - Results"
    form.Width = 900
    form.Height = 600
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
    form.MinimumSize = dotNetObject "System.Drawing.Size" 700 400

    -- Top panel
    local topPanel = dotNetObject "System.Windows.Forms.Panel"
    topPanel.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Top
    topPanel.Height = 40

    local bTA = _mlr_makeBtn "Select All"    10  8  90 26 topPanel
    local bTN = _mlr_makeBtn "Deselect All" 105 8 100 26 topPanel
    local bTO = _mlr_makeBtn "Select OK"    210 8  90 26 topPanel
    local bTE = _mlr_makeBtn "Select ERROR" 305 8 110 26 topPanel

    -- Bottom panel
    local botPanel = dotNetObject "System.Windows.Forms.Panel"
    botPanel.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Bottom
    botPanel.Height = 215

    local bBA = _mlr_makeBtn "Select All"    10  8  90 26 botPanel
    local bBN = _mlr_makeBtn "Deselect All" 105 8 100 26 botPanel
    local bBO = _mlr_makeBtn "Select OK"    210 8  90 26 botPanel
    local bBE = _mlr_makeBtn "Select ERROR" 305 8 110 26 botPanel

    -- Summary label
    local lbl = dotNetObject "System.Windows.Forms.Label"
    lbl.Text = (totalMatches as string) + " paths found across " + \
               (totalFiles as string) + " files  -  " + \
               (okN as string) + " OK,  " + (errN as string) + " ERROR"
    lbl.Location = dotNetObject "System.Drawing.Point" 12 42
    lbl.AutoSize = true
    botPanel.Controls.Add lbl

    -- Export button
    local bExport = _mlr_makeBtn "Export selected to log" 10 66 180 30 botPanel

    -- Replace button + checkboxes
    local bReplace = _mlr_makeBtn "Replace selected" 10 100 150 30 botPanel

    local chkBackup = dotNetObject "System.Windows.Forms.CheckBox"
    chkBackup.Text = "Backup .mat files (next to each original)"
    chkBackup.Location = dotNetObject "System.Drawing.Point" 170 104
    chkBackup.AutoSize = true
    chkBackup.Checked = true
    botPanel.Controls.Add chkBackup
    _mlr_chkBackup = chkBackup

    local chkLog = dotNetObject "System.Windows.Forms.CheckBox"
    chkLog.Text = "Store execution log"
    chkLog.Location = dotNetObject "System.Drawing.Point" 170 124
    chkLog.AutoSize = true
    chkLog.Checked = true
    botPanel.Controls.Add chkLog
    _mlr_chkLog = chkLog

    -- Hint labels
    local hint1 = dotNetObject "System.Windows.Forms.Label"
    hint1.Text = "Backup creates one .bak file per .mat file next to each original - may produce many files."
    hint1.Location = dotNetObject "System.Drawing.Point" 12 148
    hint1.AutoSize = true
    hint1.ForeColor = (dotNetClass "System.Drawing.SystemColors").GrayText
    botPanel.Controls.Add hint1

    local hint2 = dotNetObject "System.Windows.Forms.Label"
    hint2.Text = "Log will be stored in: " + rootDir + nl + \
                 "Matching is case-sensitive. Only the first occurrence per path is replaced."
    hint2.Location = dotNetObject "System.Drawing.Point" 12 164
    hint2.AutoSize = true
    hint2.ForeColor = (dotNetClass "System.Drawing.SystemColors").GrayText
    botPanel.Controls.Add hint2

    -- DataGridView
    local dgv = _mlr_createDGV()

    -- Color definitions
    local clrErrBg  = (dotNetClass "System.Drawing.Color").FromArgb 255 230 230
    local clrErrFg  = (dotNetClass "System.Drawing.Color").FromArgb 180 0 0
    local clrHeaderBg = (dotNetClass "System.Drawing.Color").FromArgb 230 230 230
    local clrHeaderFg = (dotNetClass "System.Drawing.Color").FromArgb 60 60 60
    local boldFont = dotNetObject "System.Drawing.Font" dgv.Font (dotNetClass "System.Drawing.FontStyle").Bold

    -- Populate rows
    for i = 1 to _mlr_matches.count do
    (
        local item = _mlr_matches[i]
        local ri = dgv.Rows.Add()
        local row = dgv.Rows.Item[ri]

        if _mlr_isHeaderRow i then
        (
            -- Header row: show .mat file path
            local matFP = item[6]
            -- Count matches for this file
            local matchCount = 0
            local j = i + 1
            while j <= _mlr_matches.count and not (_mlr_isHeaderRow j) do
            (
                matchCount += 1
                j += 1
            )
            row.Cells.Item[0].Value = dotNetObject "System.Boolean" false
            row.Cells.Item[1].Value = matFP + " (" + (matchCount as string) + " paths)"
            row.Cells.Item[2].Value = ""
            row.Cells.Item[3].Value = ""
            row.Cells.Item[4].Value = ""
            row.DefaultCellStyle.BackColor = clrHeaderBg
            row.DefaultCellStyle.ForeColor = clrHeaderFg
            row.DefaultCellStyle.Font = boldFont
            row.ReadOnly = true
            row.Height = 26
        )
        else
        (
            -- Data row (same as v2 logic)
            local pathStr = "OLD: " + item[3] + nl + "NEW: " + item[4]
            local tag = if item[5] then "OK" else "ERROR"

            row.Cells.Item[0].Value = dotNetObject "System.Boolean" item[5]
            row.Cells.Item[1].Value = item[1]
            row.Cells.Item[2].Value = item[2]
            row.Cells.Item[3].Value = pathStr
            row.Cells.Item[4].Value = tag
            row.Height = 42

            if not item[5] do
            (
                row.DefaultCellStyle.BackColor = clrErrBg
                row.DefaultCellStyle.ForeColor = clrErrFg
            )
        )
    )

    -- Wire events (same handlers as v2 - they already skip headers via updated functions)
    dotNet.addEventHandler bTA "Click" _mlr_onSelectAll
    dotNet.addEventHandler bTN "Click" _mlr_onSelectNone
    dotNet.addEventHandler bTO "Click" _mlr_onSelectOK
    dotNet.addEventHandler bTE "Click" _mlr_onSelectError
    dotNet.addEventHandler bBA "Click" _mlr_onSelectAll
    dotNet.addEventHandler bBN "Click" _mlr_onSelectNone
    dotNet.addEventHandler bBO "Click" _mlr_onSelectOK
    dotNet.addEventHandler bBE "Click" _mlr_onSelectError
    dotNet.addEventHandler bReplace "Click" _mlr_onReplaceMulti
    dotNet.addEventHandler bExport  "Click" _mlr_onExportMulti

    -- Add controls (reverse order for correct docking)
    form.Controls.Add dgv
    form.Controls.Add botPanel
    form.Controls.Add topPanel

    form.ShowDialog()
)

-- ============================================================
-- MAIN
-- ============================================================
fn _mlr_runTool matFP needle replacement =
(
    try
    (
        with quiet on ( loadMaterialLibrary matFP )
    )
    catch
    (
        local errMsg = try (getCurrentException()) catch ("unknown error")
        messageBox ("Failed to load material library:\n" + errMsg) title:"MatLib Replace"
        return()
    )
    local matches = _mlr_collectAllMatches needle replacement

    if matches.count == 0 do
    (
        messageBox "No matching paths found." title:"MatLib Replace"
        return()
    )

    _mlr_showResultsWindow matches matFP
)

fn _mlr_runToolDir rootDir needle replacement recursive =
(
    -- Step 1: Collect directories
    local dirs = _mlr_collectSubDirs rootDir recursive
    format "Directories to scan: %\n" dirs.count

    -- Step 2: Collect .mat files
    local matFiles = _mlr_collectMatFiles dirs
    format "Mat files found: %\n" matFiles.count

    if matFiles.count == 0 do
    (
        messageBox "No .mat files found." title:"MatLib Replace"
        return()
    )

    -- Step 3: Scan all .mat files
    local scanResult = _mlr_scanAllMatFiles matFiles needle replacement
    local fileMatches = scanResult[1]
    local failedFiles = scanResult[2]

    -- Report failed files
    if failedFiles.count > 0 do
    (
        local msg = (failedFiles.count as string) + " of " + (matFiles.count as string) + \
                    " files could not be loaded and were skipped."
        messageBox msg title:"MatLib Replace"
    )

    -- Check for matches
    local totalMatches = 0
    for fm in fileMatches do totalMatches += fm[2].count

    if totalMatches == 0 do
    (
        messageBox "No matching paths found." title:"MatLib Replace"
        return()
    )

    -- Step 4: Show results
    _mlr_showResultsWindowMulti fileMatches rootDir
)

-- ============================================================
-- DIALOG
-- ============================================================
rollout matLibReplace "MatLib Replace" width:440 height:190
(
    radiobuttons _mode labels:#("Single file", "Directory scan") default:1 pos:[10,10]

    button   _browseBtn  "Browse..."        pos:[10,36]  width:80  height:22
    label    _matLabel   "No file selected"  pos:[100,40] width:330 align:#left

    edittext _findText    "Find:"    pos:[10,72]  width:420 fieldWidth:345
    edittext _replaceText "Replace:" pos:[10,98]  width:420 fieldWidth:345

    checkbox _recursiveChk "Deep recursive search" pos:[10,128] checked:false enabled:false

    button _runBtn "Scan" pos:[10,152] width:420 height:26

    local matFP = undefined
    local rootDir = undefined

    on _mode changed val do
    (
        matFP = undefined
        rootDir = undefined
        _recursiveChk.checked = false

        if val == 1 then
        (
            _matLabel.text = "No file selected"
            _recursiveChk.enabled = false
        )
        else
        (
            _matLabel.text = "No directory selected"
            _recursiveChk.enabled = true
        )
    )

    on _browseBtn pressed do
    (
        if _mode.state == 1 then
        (
            -- Single file mode
            local fp = getOpenFileName \
                caption:"Select material library" \
                filename:(getDir #matlib + @"\") \
                types:"Material libraries(*.mat)"
            if fp != undefined do
            (
                matFP = fp
                rootDir = undefined
                _matLabel.text = pathConfig.stripPathToLeaf fp
            )
        )
        else
        (
            -- Directory mode
            local dp = getSavePath caption:"Select root directory"
            if dp != undefined do
            (
                -- Normalize trailing backslash
                if dp.count > 0 and dp[dp.count] != "\\" and dp[dp.count] != "/" do
                    dp += "\\"
                rootDir = dp
                matFP = undefined
                _matLabel.text = dp
            )
        )
    )

    on _runBtn pressed do
    (
        if _findText.text == "" do (messageBox "Find field cannot be empty."; return())
        if _replaceText.text == "" do (messageBox "Replace field cannot be empty."; return())

        if _mode.state == 1 then
        (
            -- Single file mode (unchanged from v2)
            if matFP == undefined do (messageBox "Select a .mat file first."; return())

            _runBtn.enabled = false
            _mlr_runTool matFP _findText.text _replaceText.text
            _runBtn.enabled = true
        )
        else
        (
            -- Directory mode
            if rootDir == undefined do (messageBox "Select a directory first."; return())

            -- Verify directory is still accessible
            if not (doesFileExist rootDir) do
            (
                messageBox "Directory is not accessible. It may have been disconnected."
                return()
            )

            _runBtn.enabled = false
            _mlr_runToolDir rootDir _findText.text _replaceText.text _recursiveChk.checked
            _runBtn.enabled = true
        )
    )
)

createDialog matLibReplace style:#(#style_toolwindow, #style_sysmenu)
