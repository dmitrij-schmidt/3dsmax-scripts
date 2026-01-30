/*
 * Material Library Serializer v2 — dotNet Edition
 *
 * Reads a .mat material library and serializes each top-level material
 * to an individual JSON file with full property data, including
 * recursive serialization of sub-materials and texture maps.
 *
 * Uses .NET Framework's JavaScriptSerializer (System.Web.Extensions)
 * for JSON generation, eliminating manual string escaping. Builds
 * dotNet Dictionary/ArrayList object trees, serializes to compact JSON,
 * then pretty-prints via a StringStream-based formatter.
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
 *   - Requires .NET Framework 4.x (3ds Max 2018–2024)
 *   - 3ds Max 2025+ may use .NET 6+ where JavaScriptSerializer is unavailable
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
	_serializer = undefined,
	_assemblyLoaded = false,

	-- Create an ArrayList from a MaxScript array of values.
	fn makeList items = (
		local a = dotNetObject "System.Collections.ArrayList"
		for item in items do a.Add item
		a
	),

	-- Create a Dictionary[String,Object] from #(#("key",val), ...) pairs.
	-- Pairs where val is undefined use the indexer to store CLR null,
	-- since MaxScript cannot pass null directly to Dictionary.Add.
	fn makeDict pairs = (
		local d = dotNetObject "System.Collections.Generic.Dictionary`2[System.String,System.Object]"
		for pair in pairs do (
			if pair[2] == undefined then
				d.Item[pair[1]] = undefined
			else
				d.Add pair[1] pair[2]
		)
		d
	),

	-- Guard against non-finite float values (INF, NaN) that would cause
	-- JavaScriptSerializer to throw. Returns the raw float for normal values,
	-- or its string representation for special values.
	fn guardFloat val = (
		local s = val as string
		if findString s "#INF" != undefined \
			or findString s "#IND" != undefined \
			or findString s "#QNAN" != undefined then
			s
		else
			val
	),

	-- Load System.Web.Extensions and create the JavaScriptSerializer.
	-- Returns true on success, false on failure.
	fn ensureAssembly = (
		if _assemblyLoaded then return true
		try (
			dotNet.loadAssembly "System.Web.Extensions"
			_serializer = dotNetObject "System.Web.Script.Serialization.JavaScriptSerializer"
			_serializer.MaxJsonLength = 104857600  -- 100 MB
			_assemblyLoaded = true
			true
		) catch (
			format "FATAL: Could not load System.Web.Extensions assembly.\n"
			format "       Requires .NET Framework 4.x (3ds Max 2018-2024).\n"
			format "       Error: %\n" (try (getCurrentException()) catch ("unknown"))
			false
		)
	),

	-- Write indentation (2 spaces per level) to a StringStream.
	fn writeIndent stream level = (
		for j = 1 to level do format "  " to:stream
	),

	-- Pretty-print compact JSON into indented, readable format.
	-- Character-by-character state machine with StringStream output.
	fn prettyPrint jsonStr = (
		local out = StringStream ""
		local depth = 0
		local inStr = false
		local esc = false
		local skipNext = false

		for i = 1 to jsonStr.count do (
			if skipNext then (
				skipNext = false
			) else if esc then (
				format "%" jsonStr[i] to:out
				esc = false
			) else if inStr then (
				local c = jsonStr[i]
				format "%" c to:out
				if c == "\\" then esc = true
				else if c == "\"" then inStr = false
			) else (
				local c = jsonStr[i]
				local nextChar = if i < jsonStr.count then jsonStr[i + 1] else ""

				if c == "\"" then (
					format "\"" to:out
					inStr = true
				)
				else if c == "{" then (
					if nextChar == "}" then (
						format "{}" to:out
						skipNext = true
					) else (
						depth += 1
						format "{\n" to:out
						writeIndent out depth
					)
				)
				else if c == "}" then (
					depth -= 1
					format "\n" to:out
					writeIndent out depth
					format "}" to:out
				)
				else if c == "[" then (
					if nextChar == "]" then (
						format "[]" to:out
						skipNext = true
					) else (
						depth += 1
						format "[\n" to:out
						writeIndent out depth
					)
				)
				else if c == "]" then (
					depth -= 1
					format "\n" to:out
					writeIndent out depth
					format "]" to:out
				)
				else if c == "," then (
					format ",\n" to:out
					writeIndent out depth
				)
				else if c == ":" then (
					format ": " to:out
				)
				else (
					-- Skip whitespace outside strings
					if c != " " and c != "\n" and c != "\r" and c != "\t" then
						format "%" c to:out
				)
			)
		)
		out as string
	),

	-- Recursively convert a MaxScript value to a dotNet object tree
	-- (Dictionary, ArrayList, or boxed primitives) for JavaScriptSerializer.
	fn convertValue val depth = (
		-- Depth guard against circular references
		if depth > maxDepth then
			return (makeDict #(#("type", "max_depth"), #("value", undefined)))

		-- Undefined / unsupplied
		if val == undefined or val == unsupplied then
			return (makeDict #(#("type", "undefined"), #("value", undefined)))

		local cls = classOf val

		-- Integer
		if cls == Integer then
			return (makeDict #(#("type", "integer"), #("value", val)))

		-- Float (with INF/NaN guard)
		if cls == Float then
			return (makeDict #(#("type", "float"), #("value", guardFloat val)))

		-- Boolean
		if cls == BooleanClass then
			return (makeDict #(#("type", "boolean"), #("value", val)))

		-- String (escaping handled entirely by JavaScriptSerializer)
		if cls == String then
			return (makeDict #(#("type", "string"), #("value", val)))

		-- Name (#symbol → string)
		if cls == Name then
			return (makeDict #(#("type", "name"), #("value", val as string)))

		-- Color (RGBA, 0–255)
		if cls == Color then
			return (makeDict #(#("type", "color"), #("value", makeList #(val.r, val.g, val.b, val.a))))

		-- Point2
		if cls == Point2 then
			return (makeDict #(#("type", "point2"), #("value", makeList #(val.x, val.y))))

		-- Point3
		if cls == Point3 then
			return (makeDict #(#("type", "point3"), #("value", makeList #(val.x, val.y, val.z))))

		-- Point4
		if cls == Point4 then
			return (makeDict #(#("type", "point4"), #("value", makeList #(val.x, val.y, val.z, val.w))))

		-- Matrix3 (3 rotation rows + position row)
		if cls == Matrix3 then (
			local r1 = val.row1; local r2 = val.row2
			local r3 = val.row3; local r4 = val.row4
			return (makeDict #(#("type", "matrix3"), #("value", makeList #(
				makeList #(r1.x, r1.y, r1.z),
				makeList #(r2.x, r2.y, r2.z),
				makeList #(r3.x, r3.y, r3.z),
				makeList #(r4.x, r4.y, r4.z)
			))))
		)

		-- Material or TextureMap — full recursive property serialization
		if isKindOf val Material or isKindOf val TextureMap then (
			local matName = try (val.name) catch ("")
			local propsDict = dotNetObject "System.Collections.Generic.Dictionary`2[System.String,System.Object]"

			local props = #()
			try (props = getPropNames val) catch ()

			for i = 1 to props.count do (
				local pName = props[i] as string
				try (
					local pVal = getProperty val props[i]
					propsDict.Add pName (convertValue pVal (depth + 1))
				) catch (
					local errMsg = try (getCurrentException()) catch ("unknown error")
					propsDict.Add pName (makeDict #(#("type", "error"), #("value", errMsg)))
				)
			)

			return (makeDict #(
				#("class", classOf val as string),
				#("name", matName),
				#("properties", propsDict)
			))
		)

		-- Array / ArrayParameter
		if isKindOf val Array then (
			local arrList = dotNetObject "System.Collections.ArrayList"
			for item in val do
				arrList.Add (convertValue item (depth + 1))
			return arrList
		)

		-- BitArray
		if cls == BitArray then (
			local bitList = dotNetObject "System.Collections.ArrayList"
			for bit in val do bitList.Add bit
			return (makeDict #(#("type", "bitarray"), #("value", bitList)))
		)

		-- Other numeric types (Double, Integer64) via superclass
		if superClassOf val == Number then
			return (makeDict #(#("type", toLower (cls as string)), #("value", val)))

		-- Fallback: unknown type — store class name and string representation
		local valStr = try (val as string) catch ("<<cannot convert to string>>")
		makeDict #(#("type", "unknown"), #("class", cls as string), #("value", valStr))
	),

	-- Serialize a material to a pretty-printed JSON file on disk.
	fn serializeToFile mat filepath = (
		if not ensureAssembly() then return false

		try (
			local objTree = convertValue mat 0
			local compactJson = _serializer.Serialize objTree
			local prettyJson = prettyPrint compactJson

			local f = createFile filepath
			if f != undefined then (
				format "%" prettyJson to:f
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
	format "Material Library Serializer v2 (dotNet)\n"
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
