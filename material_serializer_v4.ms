/*
 * Material Library Serializer v4 — Diff-Only Idiomatic YAML
 *
 * Reads a .mat material library and serializes each top-level material
 * to an individual YAML file, writing ONLY properties that differ from
 * a default-constructed instance of each material/map class.
 *
 * A pool of default instances is built lazily as new classes are
 * encountered. Each material/map's properties are compared field-by-field
 * against the pool entry; only non-default values are emitted.
 * Nesting is preserved — sub-materials and texture maps are always
 * written when assigned (since defaults have undefined in those slots),
 * and their own properties are recursively diffed.
 *
 * Uses idiomatic YAML output:
 *   - Native types (int, float, bool, string) written as plain values
 *   - MaxScript-specific types use YAML local tags (!color, !point3, etc.)
 *   - Special floats use YAML .inf / .nan notation
 *
 * Pure MaxScript — no dotNet dependency. Works on any 3ds Max version.
 * Uses StringStream for output (avoids O(n^2) string concatenation).
 *
 * Usage:
 *   1. Set material_library and output_dir below
 *   2. Run script in 3ds Max (MAXScript > Run Script)
 *   3. Check output_dir for generated .yaml files
 *
 * YAML Tags Reference:
 *   !color [r, g, b, a]                          — RGBA color (0-255)
 *   !point2 [x, y]                               — 2D point
 *   !point3 [x, y, z]                            — 3D point/vector
 *   !point4 [x, y, z, w]                         — 4D point
 *   !matrix3 [[r1], [r2], [r3], [pos]]           — 3x4 transform matrix
 *   !bitarray [1, 3, 5]                           — Set bit indices
 *   !name "symbol"                                — MaxScript name/symbol
 *   !error "message"                              — Property read error
 *
 * Supports all material and map types including V-Ray.
 *
 * Known limitations:
 *   - Animation data (keyframes, controllers) not captured
 *   - Instance relationships between shared maps not preserved
 *   - Custom attributes not serialized
 *   - If a class cannot be default-constructed (e.g. renderer plugin not
 *     loaded), all its properties are written with a listener warning
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

struct MaterialSerializerV4 (
	maxDepth = 20,

	-- Default-instance pool (parallel arrays — MaxScript has no hash maps)
	defaultClassNames = #(),
	defaultInstances = #(),

	-- Write indentation (2 spaces per level) to a StringStream.
	fn writeIndent ss level = (
		for j = 1 to level do format "  " to:ss
	),

	-- Write a YAML double-quoted string with backslash escaping.
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

	-- Map a MaxScript special float to its YAML representation.
	-- Returns undefined for normal floats.
	fn yamlFloat val = (
		local s = val as string
		if findString s "#INF" != undefined then (
			if s[1] == "-" then "-.inf" else ".inf"
		) else if findString s "#IND" != undefined or findString s "#QNAN" != undefined then (
			".nan"
		) else (
			undefined
		)
	),

	-- Returns true if a value can be written inline (same line as its key).
	-- Materials, TextureMaps, and non-empty Arrays require block style.
	fn isInlinable val = (
		if isKindOf val Material then return false
		if isKindOf val TextureMap then return false
		if isKindOf val Array and val.count > 0 then return false
		true
	),

	-- Look up or create a default instance for a given class.
	-- Returns the default instance, or undefined if construction fails.
	fn getOrCreateDefault cls = (
		local clsName = cls as string
		local idx = findItem defaultClassNames clsName
		if idx > 0 then return defaultInstances[idx]

		local def = undefined
		try (
			def = cls()
			append defaultClassNames clsName
			append defaultInstances def
		) catch (
			format "  WARNING: Cannot create default for class: %\n" clsName
		)
		def
	),

	-- Compare two values for equality. Used to detect non-default properties.
	-- Materials and TextureMaps always return false (their presence in a slot
	-- where the default is undefined IS the diff; internals are diffed recursively).
	-- Arrays are compared element-wise.
	fn valuesEqual a b = (
		try (
			local aNone = (a == undefined or a == unsupplied)
			local bNone = (b == undefined or b == unsupplied)
			if aNone and bNone then return true
			if aNone or bNone then return false
			if isKindOf a Material or isKindOf a TextureMap then return false
			if isKindOf b Material or isKindOf b TextureMap then return false
			if isKindOf a Array and isKindOf b Array then (
				if a.count != b.count then return false
				for i = 1 to a.count do
					if not (valuesEqual a[i] b[i]) then return false
				return true
			)
			a == b
		) catch (
			false
		)
	),

	-- Write a value inline as idiomatic YAML.
	-- No leading indent, no trailing newline — caller handles those.
	fn writeInline val ss = (
		-- Undefined / unsupplied → null
		if val == undefined or val == unsupplied then (
			format "null" to:ss
			return OK
		)

		local cls = classOf val

		-- Integer — native YAML
		if cls == Integer then (
			format "%" val to:ss
			return OK
		)

		-- Float — native YAML (with .inf / .nan for specials)
		if cls == Float then (
			local special = yamlFloat val
			if special != undefined then
				format "%" special to:ss
			else
				format "%" val to:ss
			return OK
		)

		-- Boolean — native YAML
		if cls == BooleanClass then (
			format "%" (if val then "true" else "false") to:ss
			return OK
		)

		-- String — native YAML quoted scalar
		if cls == String then (
			writeQuoted ss val
			return OK
		)

		-- Name → !name "symbol"
		if cls == Name then (
			format "!name " to:ss
			writeQuoted ss (val as string)
			return OK
		)

		-- Color → !color [r, g, b, a]
		if cls == Color then (
			format "!color [%, %, %, %]" val.r val.g val.b val.a to:ss
			return OK
		)

		-- Point2 → !point2 [x, y]
		if cls == Point2 then (
			format "!point2 [%, %]" val.x val.y to:ss
			return OK
		)

		-- Point3 → !point3 [x, y, z]
		if cls == Point3 then (
			format "!point3 [%, %, %]" val.x val.y val.z to:ss
			return OK
		)

		-- Point4 → !point4 [x, y, z, w]
		if cls == Point4 then (
			format "!point4 [%, %, %, %]" val.x val.y val.z val.w to:ss
			return OK
		)

		-- Matrix3 → !matrix3 [[r1], [r2], [r3], [pos]]
		if cls == Matrix3 then (
			local r1 = val.row1; local r2 = val.row2
			local r3 = val.row3; local r4 = val.row4
			format "!matrix3 [" to:ss
			format "[%, %, %], " r1.x r1.y r1.z to:ss
			format "[%, %, %], " r2.x r2.y r2.z to:ss
			format "[%, %, %], " r3.x r3.y r3.z to:ss
			format "[%, %, %]]" r4.x r4.y r4.z to:ss
			return OK
		)

		-- BitArray → !bitarray [indices...]
		if cls == BitArray then (
			format "!bitarray [" to:ss
			local first = true
			for bit in val do (
				if not first then format ", " to:ss
				format "%" bit to:ss
				first = false
			)
			format "]" to:ss
			return OK
		)

		-- Empty array
		if isKindOf val Array then (
			format "[]" to:ss
			return OK
		)

		-- Other numeric types (Double, Integer64) via superclass
		if superClassOf val == Number then (
			format "%" val to:ss
			return OK
		)

		-- Fallback: unknown type → tagged quoted string
		local valStr = try (val as string) catch ("<<cannot convert>>")
		format "!unknown " to:ss
		writeQuoted ss ((cls as string) + ": " + valStr)
	),

	-- Write a value as block-style YAML (materials/maps and non-empty arrays).
	-- For materials/maps, only properties differing from the class default
	-- are written. Sub-materials and maps are always written when present
	-- (since default slots are undefined), with recursive diffing inside.
	fn writeBlock val depth ss = (
		-- Depth guard against circular references
		if depth > maxDepth then (
			writeIndent ss depth
			format "!max_depth null\n" to:ss
			return OK
		)

		-- Material or TextureMap — block mapping with class, name, diffed properties
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
				-- Get default instance for comparison
				local def = getOrCreateDefault (classOf val)

				-- Buffer properties into a temporary stream so we can detect
				-- the empty-diff case and emit "properties: {}" instead.
				local propSS = StringStream ""
				local diffCount = 0

				for i = 1 to props.count do (
					local pName = props[i] as string

					try (
						local pVal = getProperty val props[i]

						-- Check if this property matches the default
						local skip = false
						if def != undefined then (
							local dVal = try (getProperty def props[i]) catch (unsupplied)
							if dVal != unsupplied and valuesEqual pVal dVal then
								skip = true
						)

						if not skip then (
							diffCount += 1
							writeIndent propSS (depth + 1)

							if isInlinable pVal then (
								format "%: " pName to:propSS
								writeInline pVal propSS
								format "\n" to:propSS
							) else (
								format "%:\n" pName to:propSS
								writeBlock pVal (depth + 2) propSS
							)
						)
					) catch (
						-- Property read error on actual value — always write
						diffCount += 1
						local errMsg = try (getCurrentException()) catch ("unknown error")
						writeIndent propSS (depth + 1)
						format "%: !error " pName to:propSS
						writeQuoted propSS errMsg
						format "\n" to:propSS
					)
				)

				writeIndent ss depth
				if diffCount == 0 then (
					format "properties: {}\n" to:ss
				) else (
					format "properties:\n" to:ss
					format "%" (propSS as string) to:ss
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
					format "- " to:ss
					writeInline item ss
					format "\n" to:ss
				) else (
					format "-\n" to:ss
					writeBlock item (depth + 1) ss
				)
			)
			return OK
		)

		-- Fallback: write inline (shouldn't normally reach here)
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
	format "Material Library Serializer v4 (Diff YAML)\n"
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
		local serializer = MaterialSerializerV4()
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
		format "Default class pool: % entries\n" serializer.defaultClassNames.count
		format "========================================\n"
	)
)
