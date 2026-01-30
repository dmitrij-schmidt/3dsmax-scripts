/*
 * Material Library Serializer (exprForMAXObject version)
 *
 * Reads a .mat material library and serializes each top-level material
 * to an individual .ms file using MaxScript's native exprForMAXObject.
 *
 * Each output file contains a valid MaxScript expression that recreates
 * the material when executed:
 *     local mat = fileIn @"C:\output\My_Material.ms"
 *
 * Usage:
 *   1. Set material_library and output_dir below
 *   2. Run script in 3ds Max (MAXScript > Run Script)
 *   3. Check output_dir for generated .ms files
 *
 * Supported: 3ds Max 2018+
 *
 * Known limitations:
 *   - exprForMAXObject may omit properties that a plugin does not
 *     expose through its serialization interface
 *   - Animation data (controllers, keyframes) not captured
 *   - Instance relationships between shared maps not preserved
 */

-- ============================================================================
-- CONFIGURATION — Edit these paths before running
-- ============================================================================

global material_library = @"C:\path\to\your\library.mat"
global output_dir = @"C:\path\to\output\"

-- ============================================================================
-- UTILITIES
-- ============================================================================

fn sanitizeFilename name = (
	local illegal = "\\/:*?\"<>|"
	local result = ""
	for i = 1 to name.count do (
		local c = name[i]
		if findString illegal c != undefined or c == " " then
			result += "_"
		else
			result += c
	)
	-- Collapse consecutive underscores
	while findString result "__" != undefined do
		result = substituteString result "__" "_"
	-- Trim to reasonable length for Windows path limits
	if result.count > 200 then
		result = substring result 1 200
	if result.count == 0 then result = "_unnamed_"
	result
)

-- ============================================================================
-- MAIN
-- ============================================================================

(
	format "\n========================================\n"
	format "Material Library Serializer (expr)\n"
	format "========================================\n"
	format "Library: %\n" material_library
	format "Output:  %\n" output_dir
	format "========================================\n\n"

	-- Warn if library file not found (may still work for preloaded libraries or UNC paths)
	if not doesFileExist material_library then
		format "WARNING: Library file not found at specified path.\n         Attempting to load anyway...\n\n"

	-- Ensure output directory exists
	makeDir output_dir all:true

	-- Normalize path separator
	if output_dir.count > 0 and output_dir[output_dir.count] != "\\" and output_dir[output_dir.count] != "/" then
		output_dir += "\\"

	-- Load material library
	format "Loading material library...\n"
	loadMaterialLibrary material_library

	local lib = currentMaterialLibrary
	local matCount = lib.count
	format "Found % top-level material(s)\n\n" matCount

	if matCount == 0 then (
		format "No materials to process.\n"
	) else (
		local successCount = 0
		local failCount = 0

		for i = 1 to matCount do (
			local mat = lib[i]
			local safeName = sanitizeFilename mat.name
			local filepath = output_dir + safeName + ".ms"
			format "[%/%] \"%\"\n" i matCount mat.name

			try (
				local expr = exprForMAXObject mat
				local f = createFile filepath
				if f != undefined then (
					-- Header comment for context
					format "-- Material: %\n" mat.name to:f
					format "-- Class: %\n" (classOf mat as string) to:f
					format "-- Restore with: local mat = fileIn @\"%\"\n" filepath to:f
					format "--\n" to:f

					format "%" expr to:f
					format "\n" to:f
					close f
					format "  -> %\n" filepath
					successCount += 1
				) else (
					format "  ERROR: Could not create file: %\n" filepath
					failCount += 1
				)
			) catch (
				local errMsg = try (getCurrentException()) catch ("unknown error")
				format "  ERROR: % -- %\n" mat.name errMsg
				failCount += 1
			)
		)

		format "\n========================================\n"
		format "Complete: % succeeded, % failed\n" successCount failCount
		format "========================================\n"
	)
)
