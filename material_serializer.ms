/*
 * Material Library Serializer
 *
 * Reads a .mat material library and serializes each top-level material
 * to an individual JSON file with full property data, including
 * recursive serialization of sub-materials and texture maps.
 *
 * Usage:
 *   1. Set material_library and output_dir below
 *   2. Run script in 3ds Max (MAXScript > Run Script)
 *   3. Check output_dir for generated .json files
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

struct MaterialSerializer (
	maxDepth = 20,

	-- Escape a string for safe inclusion in JSON.
	-- Handles backslashes (critical for file paths), quotes, and control chars.
	fn escapeJsonString str = (
		if str == undefined then return ""
		local s = str as string
		local result = ""
		for i = 1 to s.count do (
			local c = s[i]
			if c == "\\" then result += "\\\\"
			else if c == "\"" then result += "\\\""
			else if c == "\n" then result += "\\n"
			else if c == "\r" then result += "\\r"
			else if c == "\t" then result += "\\t"
			else result += c
		)
		result
	),

	-- Generate indentation string for given nesting level.
	fn makeIndent level = (
		local s = ""
		for i = 1 to level do s += "  "
		s
	),

	-- Wrap a string value in JSON-escaped double quotes.
	fn jsonQuote str = (
		"\"" + (escapeJsonString (str as string)) + "\""
	),

	-- Serialize any value to a JSON string representation.
	-- Dispatches based on classOf / superClassOf / isKindOf.
	-- Materials and TextureMaps are recursively serialized with full properties.
	fn serializeValue val depth = (
		-- Depth guard against circular references
		if depth > maxDepth then
			return "{\"type\": \"max_depth\", \"value\": null}"

		-- Undefined / unsupplied
		if val == undefined or val == unsupplied then
			return "{\"type\": \"undefined\", \"value\": null}"

		local cls = classOf val

		-- Integer
		if cls == Integer then
			return ("{\"type\": \"integer\", \"value\": " + (val as string) + "}")

		-- Float
		if cls == Float then
			return ("{\"type\": \"float\", \"value\": " + (val as string) + "}")

		-- Boolean
		if cls == BooleanClass then
			return ("{\"type\": \"boolean\", \"value\": " + (if val then "true" else "false") + "}")

		-- String
		if cls == String then
			return ("{\"type\": \"string\", \"value\": " + (jsonQuote val) + "}")

		-- Name (#symbol)
		if cls == Name then
			return ("{\"type\": \"name\", \"value\": " + (jsonQuote (val as string)) + "}")

		-- Color (RGBA, 0-255 range)
		if cls == Color then (
			local cv = "{\"type\": \"color\", \"value\": ["
			cv += (val.r as string) + ", " + (val.g as string) + ", "
			cv += (val.b as string) + ", " + (val.a as string) + "]}"
			return cv
		)

		-- Point2
		if cls == Point2 then
			return ("{\"type\": \"point2\", \"value\": [" + \
				(val.x as string) + ", " + (val.y as string) + "]}")

		-- Point3
		if cls == Point3 then
			return ("{\"type\": \"point3\", \"value\": [" + \
				(val.x as string) + ", " + (val.y as string) + ", " + \
				(val.z as string) + "]}")

		-- Point4
		if cls == Point4 then
			return ("{\"type\": \"point4\", \"value\": [" + \
				(val.x as string) + ", " + (val.y as string) + ", " + \
				(val.z as string) + ", " + (val.w as string) + "]}")

		-- Matrix3 (3 rotation rows + position row)
		if cls == Matrix3 then (
			local r1 = val.row1
			local r2 = val.row2
			local r3 = val.row3
			local r4 = val.row4
			local mv = "{\"type\": \"matrix3\", \"value\": ["
			mv += "[" + (r1.x as string) + ", " + (r1.y as string) + ", " + (r1.z as string) + "], "
			mv += "[" + (r2.x as string) + ", " + (r2.y as string) + ", " + (r2.z as string) + "], "
			mv += "[" + (r3.x as string) + ", " + (r3.y as string) + ", " + (r3.z as string) + "], "
			mv += "[" + (r4.x as string) + ", " + (r4.y as string) + ", " + (r4.z as string) + "]]}"
			return mv
		)

		-- Material or TextureMap — full recursive serialization
		if isKindOf val Material or isKindOf val TextureMap then (
			local ind1 = makeIndent depth
			local ind2 = makeIndent (depth + 1)
			local ind3 = makeIndent (depth + 2)

			local matName = try (val.name) catch ("")

			local result = "{\n"
			result += ind2 + "\"class\": " + (jsonQuote (classOf val as string)) + ",\n"
			result += ind2 + "\"name\": " + (jsonQuote matName) + ",\n"
			result += ind2 + "\"properties\": {"

			local props = #()
			try (props = getPropNames val) catch ()

			if props.count > 0 then (
				result += "\n"
				for i = 1 to props.count do (
					local pName = props[i] as string
					local pJson = ""
					try (
						local pVal = getProperty val props[i]
						pJson = serializeValue pVal (depth + 2)
					) catch (
						local errMsg = try (getCurrentException()) catch ("unknown error")
						pJson = "{\"type\": \"error\", \"value\": " + (jsonQuote errMsg) + "}"
					)
					result += ind3 + (jsonQuote pName) + ": " + pJson
					if i < props.count then result += ","
					result += "\n"
				)
				result += ind2 + "}"
			) else (
				result += "}"
			)

			result += "\n" + ind1 + "}"
			return result
		)

		-- Array / ArrayParameter
		if isKindOf val Array then (
			if val.count == 0 then return "[]"
			local innerInd = makeIndent (depth + 1)
			local outerInd = makeIndent depth
			local arrStr = "[\n"
			for i = 1 to val.count do (
				arrStr += innerInd + (serializeValue val[i] (depth + 1))
				if i < val.count then arrStr += ","
				arrStr += "\n"
			)
			arrStr += outerInd + "]"
			return arrStr
		)

		-- BitArray
		if cls == BitArray then (
			local bits = "["
			local first = true
			for bit in val do (
				if not first then bits += ", "
				bits += (bit as string)
				first = false
			)
			bits += "]"
			return ("{\"type\": \"bitarray\", \"value\": " + bits + "}")
		)

		-- Catch other numeric types (Double, Integer64) via superclass
		if superClassOf val == Number then
			return ("{\"type\": \"" + (toLower (cls as string)) + "\", \"value\": " + (val as string) + "}")

		-- Fallback: unknown type — store class name and string representation
		local valStr = try (val as string) catch ("<<cannot convert to string>>")
		"{\"type\": \"unknown\", \"class\": " + (jsonQuote (cls as string)) + ", \"value\": " + (jsonQuote valStr) + "}"
	),

	-- Serialize a material to a JSON file on disk.
	fn serializeToFile mat filepath = (
		try (
			local json = serializeValue mat 0
			local f = createFile filepath
			if f != undefined then (
				format "%" json to:f
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
	format "Material Library Serializer\n"
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
		local serializer = MaterialSerializer()
		local successCount = 0
		local failCount = 0

		for i = 1 to matCount do (
			local mat = lib[i]
			local safeName = sanitizeFilename mat.name
			local filepath = output_dir + safeName + ".json"
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
