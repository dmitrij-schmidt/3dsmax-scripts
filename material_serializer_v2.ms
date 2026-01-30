/*
 * Material Library Serializer v2 — YAML Edition
 *
 * Reads a .mat material library and serializes each top-level material
 * to an individual YAML file with full property data, including
 * recursive serialization of sub-materials and texture maps.
 *
 * Pure MaxScript — no dotNet dependency. Works on any 3ds Max version.
 * Uses StringStream for output (avoids O(n^2) string concatenation).
 *
 * Output format:
 *   - Simple properties are inline flow mappings: {type: float, value: 1.0}
 *   - Materials/maps are block mappings with class, name, properties
 *   - Arrays are block sequences with - prefix
 *
 * Usage:
 *   1. Set material_library and output_dir below
 *   2. Run script in 3ds Max (MAXScript > Run Script)
 *   3. Check output_dir for generated .yaml files
 *
 * Supports all material and map types including V-Ray.
 *
 * Known limitations:
 *   - Animation data (keyframes, controllers) not captured
 *   - Instance relationships between shared maps not preserved
 *   - Custom attributes not serialized
 *
 * Supported: 3ds Max 2018+
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
-- SERIALIZER
-- ============================================================================

struct MaterialSerializerV2 (
	maxDepth = 20,

	-- Write indentation (2 spaces per level) to a StringStream.
	fn writeIndent ss level = (
		for j = 1 to level do format "  " to:ss
	),

	-- Write a YAML double-quoted string with backslash escaping.
	-- Handles \, ", newlines, carriage returns, and tabs.
	fn writeQuoted ss str = (
		local s = str as string
		format "\"" to:ss
		for i = 1 to s.count do (
			local c = s[i]
			if c == "\\" then format "\\\\" to:ss
			else if c == "\"" then format "\\\"" to:ss
			else if c == "\n" then format "\\n" to:ss
			else if c == "\r" then format "\\r" to:ss
			else if c == "\t" then format "\\t" to:ss
			else format "%" c to:ss
		)
		format "\"" to:ss
	),

	-- Returns true if a float is non-finite (INF, NaN, IND).
	-- These need special handling since they aren't valid YAML numbers.
	fn isSpecialFloat val = (
		local s = val as string
		findString s "#INF" != undefined \
			or findString s "#IND" != undefined \
			or findString s "#QNAN" != undefined
	),

	-- Returns true if a value can be written as a single-line flow mapping.
	-- Materials, TextureMaps, and non-empty Arrays require block style.
	fn isInlinable val = (
		if isKindOf val Material then return false
		if isKindOf val TextureMap then return false
		if isKindOf val Array and val.count > 0 then return false
		true
	),

	-- Write a typed value as an inline YAML flow mapping: {type: X, value: Y}
	-- Does NOT write leading indentation or trailing newline — caller handles those.
	fn writeInline val ss = (
		-- Undefined / unsupplied
		if val == undefined or val == unsupplied then (
			format "{type: undefined, value: null}" to:ss
			return OK
		)

		local cls = classOf val

		-- Integer
		if cls == Integer then (
			format "{type: integer, value: %}" val to:ss
			return OK
		)

		-- Float
		if cls == Float then (
			if isSpecialFloat val then (
				-- Non-finite floats stored as quoted strings for valid YAML
				format "{type: float, value: " to:ss
				writeQuoted ss (val as string)
				format "}" to:ss
			) else (
				format "{type: float, value: %}" val to:ss
			)
			return OK
		)

		-- Boolean
		if cls == BooleanClass then (
			format "{type: boolean, value: %}" (if val then "true" else "false") to:ss
			return OK
		)

		-- String
		if cls == String then (
			format "{type: string, value: " to:ss
			writeQuoted ss val
			format "}" to:ss
			return OK
		)

		-- Name (#symbol → string)
		if cls == Name then (
			format "{type: name, value: " to:ss
			writeQuoted ss (val as string)
			format "}" to:ss
			return OK
		)

		-- Color (RGBA, 0–255)
		if cls == Color then (
			format "{type: color, value: [%, %, %, %]}" val.r val.g val.b val.a to:ss
			return OK
		)

		-- Point2
		if cls == Point2 then (
			format "{type: point2, value: [%, %]}" val.x val.y to:ss
			return OK
		)

		-- Point3
		if cls == Point3 then (
			format "{type: point3, value: [%, %, %]}" val.x val.y val.z to:ss
			return OK
		)

		-- Point4
		if cls == Point4 then (
			format "{type: point4, value: [%, %, %, %]}" val.x val.y val.z val.w to:ss
			return OK
		)

		-- Matrix3 (3 rotation rows + position row)
		if cls == Matrix3 then (
			local r1 = val.row1; local r2 = val.row2
			local r3 = val.row3; local r4 = val.row4
			format "{type: matrix3, value: [" to:ss
			format "[%, %, %], " r1.x r1.y r1.z to:ss
			format "[%, %, %], " r2.x r2.y r2.z to:ss
			format "[%, %, %], " r3.x r3.y r3.z to:ss
			format "[%, %, %]]}" r4.x r4.y r4.z to:ss
			return OK
		)

		-- BitArray
		if cls == BitArray then (
			format "{type: bitarray, value: [" to:ss
			local first = true
			for bit in val do (
				if not first then format ", " to:ss
				format "%" bit to:ss
				first = false
			)
			format "]}" to:ss
			return OK
		)

		-- Empty array (non-empty handled by writeBlock)
		if isKindOf val Array then (
			format "[]" to:ss
			return OK
		)

		-- Other numeric types (Double, Integer64) via superclass
		if superClassOf val == Number then (
			format "{type: %, value: %}" (toLower (cls as string)) val to:ss
			return OK
		)

		-- Fallback: unknown type
		local valStr = try (val as string) catch ("<<cannot convert to string>>")
		format "{type: unknown, class: " to:ss
		writeQuoted ss (cls as string)
		format ", value: " to:ss
		writeQuoted ss valStr
		format "}" to:ss
	),

	-- Write a value as block-style YAML (materials/maps and non-empty arrays).
	-- Each output line starts with indentation at the given depth.
	-- Self-recursive for nested materials and arrays.
	fn writeBlock val depth ss = (
		-- Depth guard against circular references
		if depth > maxDepth then (
			writeIndent ss depth
			format "{type: max_depth, value: null}\n" to:ss
			return OK
		)

		-- Material or TextureMap — block mapping with class, name, properties
		if isKindOf val Material or isKindOf val TextureMap then (
			local matName = try (val.name) catch ("")

			writeIndent ss depth
			format "class: " to:ss
			writeQuoted ss (classOf val as string)
			format "\n" to:ss

			writeIndent ss depth
			format "name: " to:ss
			writeQuoted ss matName
			format "\n" to:ss

			local props = #()
			try (props = getPropNames val) catch ()

			if props.count == 0 then (
				writeIndent ss depth
				format "properties: {}\n" to:ss
			) else (
				writeIndent ss depth
				format "properties:\n" to:ss

				for i = 1 to props.count do (
					local pName = props[i] as string
					writeIndent ss (depth + 1)

					try (
						local pVal = getProperty val props[i]

						if isInlinable pVal then (
							-- Inline: key + flow mapping on one line
							format "%: " pName to:ss
							writeInline pVal ss
							format "\n" to:ss
						) else (
							-- Block: key on its own line, content indented below
							format "%:\n" pName to:ss
							writeBlock pVal (depth + 2) ss
						)
					) catch (
						local errMsg = try (getCurrentException()) catch ("unknown error")
						format "%: {type: error, value: " pName to:ss
						writeQuoted ss errMsg
						format "}\n" to:ss
					)
				)
			)
			return OK
		)

		-- Array — block sequence with - prefix per item
		if isKindOf val Array then (
			for i = 1 to val.count do (
				local item = val[i]
				writeIndent ss depth

				if isInlinable item then (
					-- Inline item on same line as -
					format "- " to:ss
					writeInline item ss
					format "\n" to:ss
				) else (
					-- Block item: - on its own line, content indented below
					format "-\n" to:ss
					writeBlock item (depth + 1) ss
				)
			)
			return OK
		)

		-- Fallback: write inline anyway (shouldn't normally reach here)
		writeIndent ss depth
		writeInline val ss
		format "\n" to:ss
	),

	-- Serialize a material to a YAML file on disk.
	fn serializeToFile mat filepath = (
		try (
			local ss = StringStream ""
			format "---\n" to:ss
			writeBlock mat 0 ss

			local f = createFile filepath
			if f != undefined then (
				format "%" (ss as string) to:f
				close f
				true
			) else (
				format "  ERROR: Could not create file: %\n" filepath
				false
			)
		) catch (
			local errMsg = try (getCurrentException()) catch ("unknown error")
			format "  ERROR: % -- %\n" filepath errMsg
			false
		)
	)
)

-- ============================================================================
-- MAIN
-- ============================================================================

(
	format "\n========================================\n"
	format "Material Library Serializer v2 (YAML)\n"
	format "========================================\n"
	format "Library: %\n" material_library
	format "Output:  %\n" output_dir
	format "========================================\n\n"

	-- Warn if library file not found
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
		local serializer = MaterialSerializerV2()
		local successCount = 0
		local failCount = 0

		for i = 1 to matCount do (
			local mat = lib[i]
			local safeName = sanitizeFilename mat.name
			local filepath = output_dir + safeName + ".yaml"
			format "[%/%] \"%\"\n" i matCount mat.name

			if serializer.serializeToFile mat filepath then
				successCount += 1
			else
				failCount += 1
		)

		format "\n========================================\n"
		format "Complete: % succeeded, % failed\n" successCount failCount
		format "========================================\n"
	)
)
