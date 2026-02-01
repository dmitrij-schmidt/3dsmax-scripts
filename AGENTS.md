# AGENTS.md — MaxScript Coding Patterns

Concrete patterns for writing production MaxScript. See CLAUDE.md for project philosophy.
Target: 3ds Max 2018+ with V-Ray 5.x/6.x. Language: MaxScript (.ms, .mcr).

---

## Production Reality

Scripts in this repo run against real production scenes. Assume the worst:

- **Scenes are large** — 10K+ objects, 500+ materials, deep modifier stacks. Every loop matters.
- **Paths are broken** — textures on drives that don't exist, UNC paths to offline servers, mixed `/` and `\`. Never trust a path without `doesFileExist`.
- **Materials are mixed** — V-Ray, Standard, Arch&Design, Mental Ray leftovers, Corona, all in one scene. Never assume all materials are VRayMtl.
- **Names are garbage** — duplicate names, Unicode, empty strings, names with `\/:*?"<>|`. Always sanitize before using in file paths.
- **Units are wrong** — scenes imported from other software may have centimeters when the project expects meters. Check `units.SystemType` when scale matters.
- **Scenes are legacy** — objects from 3ds Max 2012, deprecated modifiers, orphaned controllers. `getPropNames` and `getProperty` can throw on corrupted objects.
- **Artists will cancel mid-operation** — GUI dialogs return `undefined`. Long operations should be interruptible.
- **Nothing is guaranteed to exist** — selections can be empty, material libraries can have zero entries, render elements may not be assigned.

Design every script to survive all of this without crashing.

---

## MaxScript Language Traps

Things that will silently break your code if you don't know them:

```maxscript
-- Arrays are 1-indexed, not 0-indexed
local arr = #(10, 20, 30)
arr[1]  -- 10 (not arr[0])

-- Boolean class is BooleanClass, not Boolean
classOf true == BooleanClass  -- true
classOf true == Boolean        -- ERROR: unknown in scope

-- undefined vs unsupplied — different values, both falsy
val == undefined     -- property not set / object doesn't exist
val == unsupplied    -- optional parameter not passed by caller

-- OK is the default return value, not null/nil/void
fn doSomething = ( format "done\n" )
local result = doSomething()  -- result is OK, not undefined

-- String comparison is case-insensitive by default
"Hello" == "hello"  -- true
-- Use stricmp for case-sensitive: stricmp "Hello" "hello" != 0

-- classOf on undefined throws — check undefined BEFORE classOf
if val != undefined and classOf val == String then (...)  -- SAFE
if classOf val == String then (...)  -- THROWS if val is undefined

-- Semicolons are NOT line terminators — they separate statements on one line
-- Newlines are the actual statement separators

-- Variables default to global scope if not declared local
fn myFunc = (
    x = 42       -- GLOBAL! Leaks out of function. Use: local x = 42
    local y = 99  -- Correct: scoped to function
)

-- format "%" with no to: prints to MAXScript Listener (console)
-- format "%" with to:stream writes to a stream/file
format "debug: %\n" someVal         -- prints to console
format "debug: %\n" someVal to:ss   -- writes to StringStream

-- #() is a literal array, #{} is a literal BitArray
local arr = #(1, 2, 3)       -- Array
local bits = #{1, 3, 5..10}  -- BitArray (ranges supported)

-- Line continuation uses backslash at end of line
local result = longFunctionName \
    arg1 arg2 \
    keyword:value
```

---

## Scene Traversal Patterns

Common patterns for working with scene objects:

```maxscript
-- Collect all scene objects into an array (do this ONCE, then iterate)
local allNodes = for obj in objects collect obj

-- Collect with filter
local meshes = for obj in objects where isKindOf obj GeometryClass collect obj
local lights = for obj in lights collect obj
local cameras = for obj in cameras collect obj

-- Selection (may be empty — always check)
if selection.count > 0 then (
    local sel = for obj in selection collect obj
    for node in sel do (...)
)

-- Walk hierarchy
fn getDescendants node = (
    local result = #()
    for child in node.children do (
        append result child
        join result (getDescendants child)
    )
    result
)

-- Materials: iterate scene materials (not just assigned ones)
local sceneMats = for obj in objects
    where obj.material != undefined
    collect obj.material

-- Unique materials (remove duplicates via name+class check or reference comparison)
local uniqueMats = #()
local seen = #()
for mat in sceneMats do (
    local key = (classOf mat as string) + ":" + mat.name
    if findItem seen key == 0 then (
        append seen key
        append uniqueMats mat
    )
)

-- Multi/Sub materials — iterate sub-materials
if classOf mat == Multimaterial then (
    for i = 1 to mat.numsubs do (
        local subMat = mat[i]
        if subMat != undefined then (...)
    )
)
```

---

## Undo, Redraw, and Evaluation Context

3ds Max has global state that affects script behavior:

```maxscript
-- Wrap destructive operations in undo blocks (one undo step for the user)
undo "Tool Name: description" on (
    -- all changes here become one undo step
    for node in nodes do node.wireColor = red
)

-- Disable viewport redraw during batch operations (massive speedup)
with redraw off (
    for i = 1 to 10000 do (
        -- operations that would trigger viewport updates
    )
)
-- Redraw automatically restored when block exits

-- Suppress 3ds Max dialogs during batch operations
with quiet on (
    -- file operations, imports, etc. won't show popup dialogs
    loadMaterialLibrary someFile
)

-- Disable scene redraw notifications for performance
disableSceneRedraw()
-- ...batch operations...
enableSceneRedraw()
completeRedraw()  -- force one final redraw

-- Garbage collection after processing many objects
gc light:true  -- lightweight GC (safe mid-operation)
gc()            -- full GC (use after large batch operations, not inside loops)
```

When to use what:
- **undo block**: any operation that modifies scene state (geometry, materials, transforms)
- **with redraw off**: batch operations touching >100 objects
- **with quiet on**: file I/O that might trigger "file not found" dialogs
- **Read-only scripts** (like the serializers in this repo): none of these needed — they only inspect, never modify

---

## Script Skeleton

Every new script follows this structure (extracted from the v5 serializer):

```maxscript
/*
 * [Script Name]
 *
 * [What it does — one paragraph]
 *
 * Usage:
 *   1. Run script in 3ds Max (MAXScript > Run Script)
 *   2. [Step 2]
 *
 * Known limitations:
 *   - [Limitation 1]
 *
 * Supported: 3ds Max 2018+
 * V-Ray: 5.x / 6.x
 */

-- ============================================================================
-- UTILITIES
-- ============================================================================

fn sanitizeFilename name = (
    local illegal = "\\/:*?\"<>|"
    local result = ""
    for i = 1 to name.count do (
        local c = name[i]
        if findString illegal c != undefined or c == " " then result += "_"
        else result += c
    )
    while findString result "__" != undefined do
        result = substituteString result "__" "_"
    if result.count > 200 then result = substring result 1 200
    if result.count == 0 then result = "_unnamed_"
    result
)

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

struct ToolName (
    maxDepth = 20,   -- always include depth guard for recursive functions

    fn helperMethod arg = (
        -- private helpers first
    ),

    fn run = (
        try (
            -- main logic
            true
        ) catch (
            local errMsg = try (getCurrentException()) catch ("unknown error")
            format "ERROR: %\n" errMsg
            false
        )
    )
)

-- ============================================================================
-- MAIN
-- ============================================================================

fn runToolName = (
    -- 1. Gather inputs via GUI dialogs
    -- 2. Validate inputs (early return on failure)
    -- 3. Instantiate struct
    -- 4. Execute and report results
)

runToolName()
```

---

## String Building — Use StringStream

The single biggest MaxScript performance pitfall. String concatenation is O(n^2).

```maxscript
-- BAD: O(n^2) — every += copies the entire string
local result = ""
result += "line 1\n"
result += "line 2\n"

-- GOOD: O(n) — StringStream appends in-place
local ss = StringStream ""
format "line 1\n" to:ss
format "line 2\n" to:ss
local output = ss as string
```

Use StringStream for any output over ~10 lines. Write to file at the end:

```maxscript
local f = createFile filepath
if f != undefined then (
    format "%" (ss as string) to:f
    close f
)
```

---

## Type Dispatch

Check exact types first with `classOf`, polymorphic types with `isKindOf`, superclass as fallback.

```maxscript
if val == undefined or val == unsupplied then (...)

local cls = classOf val

if cls == Integer then (...)
if cls == Float then (...)
if cls == BooleanClass then (...)       -- NOT Boolean — this is a MaxScript gotcha
if cls == String then (...)
if cls == Name then (...)               -- MaxScript #symbol values
if cls == Color then (...)              -- RGBA, components 0-255
if cls == Point2 then (...)
if cls == Point3 then (...)
if cls == Point4 then (...)
if cls == Matrix3 then (...)            -- .row1 .row2 .row3 .row4, each Point3
if cls == BitArray then (...)           -- iterate with: for bit in val do (...)

if isKindOf val Material then (...)     -- catches VRayMtl, Standard, all subtypes
if isKindOf val TextureMap then (...)   -- catches VRayBitmap, Noise, all subtypes
if isKindOf val Array then (...)        -- catches Array and ArrayParameter

if superClassOf val == Number then (...) -- fallback for Double, Integer64

-- Ultimate fallback — as string can throw
local valStr = try (val as string) catch ("<<cannot convert>>")
```

---

## Error Handling

Three levels. Use all three.

**1. Per-property isolation in loops** — never one giant try/catch around the loop:

```maxscript
for i = 1 to props.count do (
    try (
        local pVal = getProperty val props[i]
        -- process pVal
    ) catch (
        local errMsg = try (getCurrentException()) catch ("unknown error")
        format "ERROR reading %: %\n" (props[i] as string) errMsg
    )
)
```

**2. Safe property access** — for `.name` and similar:

```maxscript
local matName = try (val.name) catch ("")
```

**3. File operation safety** — `createFile` returns `undefined` on failure (not an exception):

```maxscript
local f = createFile filepath
if f != undefined then (
    format "%" content to:f
    close f
    true
) else (
    format "ERROR: Could not create file: %\n" filepath
    false
)
```

Key rules:
- `getCurrentException()` can itself fail — always double-wrap: `try (getCurrentException()) catch ("unknown error")`
- `getPropNames` can throw on some objects — wrap: `try (props = getPropNames val) catch ()`
- Always `close` file handles in all code paths
- Never let one bad property abort the entire loop

---

## File I/O and Path Handling

```maxscript
-- Create directory tree (all:true creates parent dirs)
makeDir outputDir all:true

-- Normalize trailing backslash — getSavePath does NOT add one
if outputDir.count > 0 \
    and outputDir[outputDir.count] != "\\" \
    and outputDir[outputDir.count] != "/" then
    outputDir += "\\"

-- Build full path
local filepath = outputDir + filename + ".yaml"

-- Check file existence before reads
if not doesFileExist filepath then
    format "WARNING: File not found: %\n" filepath

-- Use verbatim strings for hardcoded paths (no double-backslash escaping)
global somePath = @"C:\Users\artist\assets\"

-- Windows path limit is 260 chars — sanitizeFilename trims to 200
-- to leave room for directory prefix and extension
```

---

## GUI Dialogs (Artist-Facing Tools)

Always use dialogs instead of hardcoded paths for production-facing scripts.

```maxscript
-- Yes/No decision (always use beep:false and title:)
local proceed = queryBox "Your question here" \
    title:"Tool Name" beep:false

-- File picker (returns undefined if user cancels)
local matFile = getOpenFileName \
    caption:"Select Material Library (.mat)" \
    types:"Material Library (*.mat)|*.mat|All Files (*.*)|*.*|"
if matFile == undefined then (
    format "Cancelled.\n"
    return OK
)

-- Directory picker (returns undefined if cancelled)
local outputDir = getSavePath caption:"Select Output Directory"
if outputDir == undefined then (
    format "Cancelled.\n"
    return OK
)

-- Error/info display
messageBox "No materials found." title:"Tool Name"

-- Confirmation before slow or destructive operations
local confirm = queryBox \
    ("About to process " + count as string + " items.\nContinue?") \
    title:"Tool Name" beep:false
if not confirm then return OK
```

Rules:
- Always check `undefined` return (user cancelled)
- Use early `return OK` for cancellation — don't nest in if/else
- `beep:false` on `queryBox` — don't annoy artists
- Always provide `title:` parameter

---

## V-Ray Class Reference

Actual identifiers the scripts will encounter. Use `classOf` for exact match, `isKindOf` for polymorphic.

**Materials:**

| Class | Purpose |
|---|---|
| `VRayMtl` | Standard PBR material |
| `VRayBlendMtl` | Layered material blend (up to 10 coats) |
| `VRay2SidedMtl` | Translucent thin-wall material |
| `VRayLightMtl` | Self-illuminated / emissive |
| `VRayOverrideMtl` | GI/shadow/reflection overrides |
| `VRayFastSSS2` | Subsurface scattering |
| `VRayMtlWrapper` | Matte/shadow catcher properties |

**Maps:**

| Class | Purpose |
|---|---|
| `VRayBitmap` | File-based texture |
| `VRayHDRI` | HDR environment map |
| `VRayColor` | Procedural solid color |
| `VRayDirt` | Ambient occlusion / curvature |
| `VRayEdgesTex` | Wireframe overlay |
| `VRayCompTex` | Layer compositing |
| `VRayTriplanarTex` | Triplanar projection |

**Lights:**

| Class | Purpose |
|---|---|
| `VRayLight` | Area light (rect, sphere, dome, mesh) |
| `VRaySun` | Physical sun |
| `VRaySky` | Physical sky (pairs with VRaySun) |
| `VRayIES` | Photometric IES profile |

**Render elements:**
`VRayDiffuseFilter`, `VRayReflection`, `VRayRefraction`, `VRaySpecular`, `VRaySelfIllumination`, `VRayLightSelect`, `VRayCryptomatte`

**Common VRayMtl properties:**
```maxscript
mat.texmap_diffuse          -- diffuse texture slot (TextureMap or undefined)
mat.texmap_reflection       -- reflection texture slot
mat.texmap_refraction       -- refraction texture slot
mat.texmap_bump             -- bump map slot
mat.reflection_glossiness   -- float 0.0-1.0
mat.refraction_ior          -- index of refraction
mat.diffuse                 -- Color value
mat.reflection              -- Color value
```

---

## Property Introspection

Standard pattern for reading any object's properties generically:

```maxscript
-- Get all property names as array of Name values
local props = #()
try (props = getPropNames someObject) catch ()

-- Read a property by name
local val = getProperty someObject #diffuse_color

-- Set a property by name
setProperty someObject #reflection_glossiness 0.85

-- Safe enumeration with per-property error isolation
for i = 1 to props.count do (
    local pName = props[i] as string
    try (
        local pVal = getProperty someObject props[i]
        -- process pVal
    ) catch (
        -- some properties throw when read (animated, locked, etc.)
    )
)
```

---

## Performance Rules

1. **StringStream** for any multi-line string output (see section above)
2. **Depth guards** on all recursive functions — default `maxDepth = 20`:
   ```maxscript
   if depth > maxDepth then (
       -- emit placeholder and return
       return OK
   )
   ```
3. **Collect nodes once**, iterate the array — don't re-query inside loops:
   ```maxscript
   -- GOOD
   local allNodes = for obj in objects collect obj
   for node in allNodes do (...)

   -- BAD: re-evaluates 'objects' each iteration
   for i = 1 to objects.count do (local node = objects[i]; ...)
   ```
4. **Avoid `execute` and `fileIn` inside loops** — extremely slow
5. **Progress reporting** for operations over collections:
   ```maxscript
   format "[%/%] \"%\"\n" i totalCount itemName
   ```

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Files | `snake_case.ms` | `material_serializer_v5.ms` |
| Structs | `PascalCase` | `MaterialSerializerV5` |
| Functions | `camelCase` | `serializeToFile`, `sanitizeFilename` |
| Parameters | `camelCase` | `maxDepth`, `filepath` |
| Local variables | `camelCase` | `matCount`, `successCount` |
| Globals (config only) | `snake_case` | `material_library`, `output_dir` |
| Section separators | `-- ===...===` | `-- UTILITIES`, `-- CORE LOGIC`, `-- MAIN` |

---

## Debugging Approach

When a script fails in production, diagnose systematically:

1. **Isolate** — does it fail on all objects or one specific object? Narrow down with:
   ```maxscript
   for obj in objects do (
       try (
           -- the operation
       ) catch (
           format "FAILED on: % (class: %)\n" obj.name (classOf obj)
       )
   )
   ```
2. **Inspect** — check the actual state, don't assume:
   ```maxscript
   format "classOf: %\n" (classOf obj)
   format "superClassOf: %\n" (superClassOf obj)
   format "properties: %\n" (getPropNames obj)
   format "material: %\n" obj.material
   format "renderer: %\n" (classOf renderers.current)
   ```
3. **Root cause categories**:
   - **Script logic** — wrong classOf check, missing undefined guard, scope leak
   - **Scene corruption** — orphaned references, deleted-but-referenced objects
   - **Renderer mismatch** — V-Ray properties accessed when scene uses Scanline/ART
   - **User misuse** — nothing selected, wrong file type, cancelled dialog

---

## Anti-Patterns

1. Do NOT use string concatenation for multi-line output. Use StringStream.
2. Do NOT check `Boolean` — the class is `BooleanClass`.
3. Do NOT wrap an entire loop in one `try/catch`. Isolate per-item.
4. Do NOT use `execute` to build MaxScript strings at runtime unless absolutely necessary.
5. Do NOT assume `getPropNames` or `getProperty` succeed — always `try/catch`.
6. Do NOT skip checking `createFile` return value — it returns `undefined` on failure.
7. Do NOT hardcode paths in artist-facing scripts. Use GUI dialogs.
8. Do NOT use `format` with untrusted strings without escaping — `%` is a substitution token.
9. Do NOT leave file handles open. Always `close f` in both success and error paths.
10. Do NOT omit depth guards in recursive functions. Material trees can be circular.

---

## Self-Review Checklist

Before emitting any script, verify:

- [ ] Block-comment header with purpose, usage, limitations, supported versions
- [ ] Struct-based architecture (not loose top-level functions)
- [ ] StringStream for any multi-line string output
- [ ] Per-item `try/catch` in loops (not one giant wrapper)
- [ ] `getCurrentException()` double-wrapped in its own `try/catch`
- [ ] Depth guard on every recursive function
- [ ] `createFile` return value checked for `undefined`
- [ ] All file handles closed in every code path
- [ ] Trailing backslash normalized on directory paths
- [ ] `makeDir outputDir all:true` before writing files
- [ ] GUI dialogs for user-facing inputs (not hardcoded globals)
- [ ] Progress reporting with `format "[%/%]" i total`
- [ ] `sanitizeFilename` applied to any user-provided names used in file paths
