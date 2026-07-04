package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local usage = table.concat({
    "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H [OUT_LUA] [MANIFEST]",
    "",
    "MANIFEST is a Lua file returning either a LalinNative.NativeTemplateBankRequest",
    "or function(T) -> NativeTemplateBankRequest.  The request sources are the",
    "offline NativeTemplateSource inputs.  If MANIFEST is omitted, a valid empty",
    "NativeEmbeddedTemplateBank is emitted for the host/default target.",
    "",
    "Environment:",
    "  LALIN_NATIVE_BANK_MANIFEST  manifest path when not supplied on CLI",
    "  LALIN_NATIVE_BANK_OUT_LUA   generated Lua ASDL bridge path",
    "  LALIN_NATIVE_BANK_ID        default bank id for empty generation",
    "  LALIN_NATIVE_BANK_BUILD_DIR offline object build directory",
    "  CC                         C compiler used by the offline stencil factory (default: gcc)",
    "  LALIN_NATIVE_BANK_CFLAGS    flags for NativeTemplateSource C compilation",
}, "\n")

local out_c = assert(arg[1], usage)
local out_h = assert(arg[2], usage)

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
    if path == nil or path == "" then return false end
    local f = io.open(path, "rb")
    if f == nil then return false end
    f:close()
    return true
end

local function derive_lua_path(path)
    local s = tostring(path)
    if s:match("%.c$") then return s:gsub("%.c$", ".lua") end
    return s .. ".lua"
end

local env_manifest = os.getenv("LALIN_NATIVE_BANK_MANIFEST")
local env_out_lua = os.getenv("LALIN_NATIVE_BANK_OUT_LUA")
local out_lua, manifest_path
if arg[4] ~= nil then
    out_lua = arg[3]
    manifest_path = arg[4]
elseif arg[3] ~= nil then
    out_lua = arg[3]
    manifest_path = env_manifest
else
    out_lua = env_out_lua or derive_lua_path(out_c)
    manifest_path = env_manifest
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function write_file(path, text)
    mkdir_parent(path)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function capture(cmd)
    local f = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = f:read("*a")
    local ok, _, code = f:close()
    if ok == true or ok == 0 then return out end
    return nil, out, code
end

local function os_execute(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function c_string(s)
    return string.format("%q", tostring(s or ""))
end

local function c_identifier(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function c_bytes(bytes)
    local out = {}
    for i = 1, #bytes do out[#out + 1] = string.format("0x%02x", bytes:byte(i)) end
    if #out == 0 then return "0" end
    return table.concat(out, ", ")
end

local function lua_string_expr(s)
    s = tostring(s or "")
    if #s == 0 then return "\"\"" end
    if #s < 96 and not s:find("%z") then return string.format("%q", s) end
    local out = {}
    local chunk = {}
    for i = 1, #s do
        chunk[#chunk + 1] = tostring(s:byte(i))
        if #chunk == 96 then
            out[#out + 1] = "string.char(" .. table.concat(chunk, ",") .. ")"
            chunk = {}
        end
    end
    if #chunk > 0 then out[#out + 1] = "string.char(" .. table.concat(chunk, ",") .. ")" end
    return table.concat(out, " .. ")
end

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Support = require("lalin.native_template_support")(T)
require("lalin.native_object")(T)

local function native_bank_id()
    return os.getenv("LALIN_NATIVE_BANK_ID") or "lalin.native.empty"
end

local function empty_request()
    local target = Support.host_target()
    local manifest = Support.template_source_manifest(
        Support.template_manifest_id("empty." .. native_bank_id()),
        Native.NativeTemplateSupportDomainId("native.template.support.empty"),
        {}
    )
    return Native.NativeTemplateBankRequest(
        Native.NativeBankId(native_bank_id()),
        target,
        Support.empty_runtime(),
        manifest,
        {}
    )
end

local function load_manifest(path)
    if path == nil or path == "" then return empty_request() end
    local chunk, err = loadfile(path)
    if chunk == nil then error("gen_lalin_mc_bank: cannot load manifest " .. tostring(path) .. ": " .. tostring(err), 2) end
    local value = chunk()
    if type(value) == "function" then value = value(T) end
    if not asdl.isa(value, Native.NativeTemplateBankRequest) then
        error("gen_lalin_mc_bank: manifest must return NativeTemplateBankRequest or function(T)->NativeTemplateBankRequest", 2)
    end
    return value
end

local function source_extension(_source)
    return ".c"
end

local function source_flags(_source)
    return os.getenv("LALIN_NATIVE_BANK_CFLAGS") or "-std=c99 -O3 -foptimize-sibling-calls -fno-builtin -ffunction-sections -fdata-sections -fno-pic -fno-jump-tables -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function runtime_symbol_index(runtime)
    local by_name = {}
    for _, sym in ipairs(runtime.symbols or {}) do
        by_name[sym.name] = sym.id
        by_name[sym.id.text] = sym.id
    end
    return by_name
end

function Native.NativeExtractStandaloneCallable:native_continuation_symbols()
    return {}
end

function Native.NativeExtractEntryCallable:native_continuation_symbols()
    return { self.first_continuation }
end

function Native.NativeExtractContinuationFragment:native_continuation_symbols()
    return self.successors or {}
end

function Native.NativeExtractTerminalContinuation:native_continuation_symbols()
    return {}
end

function Native.NativeExtractPublicAbiAdapter:native_continuation_symbols()
    return { self.first_continuation }
end

local function continuation_symbol_index(source)
    local by_name = {}
    for _, sym in ipairs(source.extraction:native_continuation_symbols()) do
        by_name[sym.name] = sym
        by_name[sym.id.text] = sym
    end
    return by_name
end

local function require_seen_continuations(source, symbols, seen_continuations)
    local rejects = {}
    for _, cont in ipairs(symbols or {}) do
        if not seen_continuations[cont.name] then
            rejects[#rejects + 1] = Native.NativeBuildRejectMissingContinuationRelocation(source.id, cont)
        end
    end
    return rejects
end

function Native.NativeExtractStandaloneCallable:verify_native_object_relocations(_source, _seen_continuations)
    return {}
end

function Native.NativeExtractEntryCallable:verify_native_object_relocations(source, seen_continuations)
    return require_seen_continuations(source, { self.first_continuation }, seen_continuations)
end

function Native.NativeExtractPublicAbiAdapter:verify_native_object_relocations(source, seen_continuations)
    return require_seen_continuations(source, { self.first_continuation }, seen_continuations)
end

function Native.NativeExtractContinuationFragment:verify_native_object_relocations(source, seen_continuations)
    return require_seen_continuations(source, self.successors or {}, seen_continuations)
end

function Native.NativeExtractTerminalContinuation:verify_native_object_relocations(_source, _seen_continuations)
    return {}
end

local function hole_ordinal_symbol_index(source)
    local by_name = {}
    for _, ordinal in ipairs(source.declared_hole_ordinals or {}) do
        by_name[ordinal.symbol] = ordinal
        by_name[ordinal.id.text] = ordinal
    end
    return by_name
end

function Native.NativeObjectRelocationKind:native_object_relocation_name()
    return asdl.class_basename(self)
end

function Native.NativeObjectRelocX64Pc32:native_object_relocation_name() return "R_X86_64_PC32" end
function Native.NativeObjectRelocX64Plt32:native_object_relocation_name() return "R_X86_64_PLT32" end
function Native.NativeObjectRelocX64Abs64:native_object_relocation_name() return "R_X86_64_64" end
function Native.NativeObjectRelocX64Abs32:native_object_relocation_name() return "R_X86_64_32" end
function Native.NativeObjectRelocX64Abs32S:native_object_relocation_name() return "R_X86_64_32S" end

function Native.NativeObjectRelocationKind:native_continuation_relocation(source, relocation, _symbol)
    return nil, Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        relocation.offset,
        self:native_object_relocation_name(),
        "continuation relocation must be PC-relative"
    )
end

function Native.NativeObjectRelocX64Pc32:native_continuation_relocation(_source, relocation, symbol)
    return Native.NativeRelocationContinuation(relocation.offset, symbol, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Plt32:native_continuation_relocation(_source, relocation, symbol)
    return Native.NativeRelocationContinuation(relocation.offset, symbol, relocation.addend or 0)
end

function Native.NativeObjectRelocationKind:native_hole_ordinal_relocation(source, relocation, _ordinal)
    return nil, Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        relocation.offset,
        self:native_object_relocation_name(),
        "hole ordinal relocation must be 32-bit, 64-bit, or PC-relative"
    )
end

function Native.NativeObjectRelocX64Abs32:native_hole_ordinal_relocation(_source, relocation, ordinal)
    return Native.NativeRelocationHoleOrdinal(relocation.offset, ordinal, Native.NativePatchSym32, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Abs32S:native_hole_ordinal_relocation(_source, relocation, ordinal)
    return Native.NativeRelocationHoleOrdinal(relocation.offset, ordinal, Native.NativePatchSym32, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Abs64:native_hole_ordinal_relocation(_source, relocation, ordinal)
    return Native.NativeRelocationHoleOrdinal(relocation.offset, ordinal, Native.NativePatchSym64, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Pc32:native_hole_ordinal_relocation(_source, relocation, ordinal)
    return Native.NativeRelocationHoleOrdinal(relocation.offset, ordinal, Native.NativePatchPcRel32, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Plt32:native_hole_ordinal_relocation(_source, relocation, ordinal)
    return Native.NativeRelocationHoleOrdinal(relocation.offset, ordinal, Native.NativePatchPcRel32, relocation.addend or 0)
end

function Native.NativeObjectRelocationKind:native_runtime_symbol_relocation(source, relocation, _runtime_id)
    return nil, Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        relocation.offset,
        self:native_object_relocation_name(),
        "runtime symbol relocation must be PC-relative until runtime relocations carry an explicit formula"
    )
end

function Native.NativeObjectRelocX64Pc32:native_runtime_symbol_relocation(_source, relocation, runtime_id)
    return Native.NativeRelocationRuntimeSymbol(relocation.offset, runtime_id, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Plt32:native_runtime_symbol_relocation(_source, relocation, runtime_id)
    return Native.NativeRelocationRuntimeSymbol(relocation.offset, runtime_id, relocation.addend or 0)
end

function Native.NativeObjectRelocationKind:native_constant_pool_relocation(source, relocation, _entry_id, _addend_bias)
    return nil, Native.NativeBuildRejectUnsupportedConstantPoolRelocation(
        source.id,
        relocation.offset,
        self:native_object_relocation_name(),
        "unsupported relocation formula for object constant-pool reference"
    )
end

function Native.NativeObjectRelocX64Pc32:native_constant_pool_relocation(_source, relocation, entry_id, addend_bias)
    return Native.NativeRelocationConstantPool(relocation.offset, entry_id, Native.NativePatchPcRel32, (relocation.addend or 0) + (addend_bias or 0))
end

function Native.NativeObjectRelocX64Plt32:native_constant_pool_relocation(_source, relocation, entry_id, addend_bias)
    return Native.NativeRelocationConstantPool(relocation.offset, entry_id, Native.NativePatchPcRel32, (relocation.addend or 0) + (addend_bias or 0))
end

function Native.NativeObjectRelocX64Abs64:native_constant_pool_relocation(_source, relocation, entry_id, addend_bias)
    return Native.NativeRelocationConstantPool(relocation.offset, entry_id, Native.NativePatchSym64, (relocation.addend or 0) + (addend_bias or 0))
end

function Native.NativeObjectRelocX64Abs32:native_constant_pool_relocation(_source, relocation, entry_id, addend_bias)
    return Native.NativeRelocationConstantPool(relocation.offset, entry_id, Native.NativePatchSym32, (relocation.addend or 0) + (addend_bias or 0))
end

function Native.NativeObjectRelocX64Abs32S:native_constant_pool_relocation(_source, relocation, entry_id, addend_bias)
    return Native.NativeRelocationConstantPool(relocation.offset, entry_id, Native.NativePatchSym32, (relocation.addend or 0) + (addend_bias or 0))
end

function Native.NativeObjectRelocationKind:native_local_symbol_relocation(source, relocation, _symbol_name)
    return nil, Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        relocation.offset,
        self:native_object_relocation_name(),
        "unsupported relocation type for NativeEmbeddedTemplateBank"
    )
end

function Native.NativeObjectRelocX64Pc32:native_local_symbol_relocation(_source, relocation, symbol_name)
    return Native.NativeRelocationRel32(relocation.offset, symbol_name, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Plt32:native_local_symbol_relocation(_source, relocation, symbol_name)
    return Native.NativeRelocationRel32(relocation.offset, symbol_name, relocation.addend or 0)
end

function Native.NativeObjectRelocX64Abs64:native_local_symbol_relocation(_source, relocation, symbol_name)
    return Native.NativeRelocationAbs64(relocation.offset, symbol_name, relocation.addend or 0)
end

local function native_relocation_for(source, object_relocation, text_section, symbols_by_id, symbols_by_name, sections_by_name, runtime_symbols, continuation_symbols, hole_symbols, constant_pool_symbols)
    local symbol = symbols_by_id[object_relocation.symbol.text]
    local sym_name = symbol and symbol.name or nil
    local reloc_name = object_relocation.kind:native_object_relocation_name()
    if sym_name == nil or sym_name == "" then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(source.id, object_relocation.offset, reloc_name, "relocation has no symbol")
    end

    local constant_pool_symbol = constant_pool_symbols[sym_name]
    if constant_pool_symbol ~= nil then
        return object_relocation.kind:native_constant_pool_relocation(source, object_relocation, constant_pool_symbol.entry.id, constant_pool_symbol.addend_bias)
    end

    local sym = symbols_by_name[sym_name]
    if sym ~= nil and sym.section ~= nil and sym.section ~= text_section and sym.section ~= "UND" then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            object_relocation.offset,
            reloc_name,
            "local cross-section relocation to " .. tostring(sym.section) .. " is not supported"
        )
    end
    local section = sections_by_name[sym_name]
    if section ~= nil and section.name ~= text_section then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            object_relocation.offset,
            reloc_name,
            "section relocation to " .. tostring(section.name) .. " is not supported"
        )
    end

    local continuation_symbol = continuation_symbols[sym_name]
    if continuation_symbol ~= nil then
        return object_relocation.kind:native_continuation_relocation(source, object_relocation, continuation_symbol)
    end

    local hole_ordinal = hole_symbols[sym_name]
    if hole_ordinal ~= nil then
        return object_relocation.kind:native_hole_ordinal_relocation(source, object_relocation, hole_ordinal)
    end

    local runtime_id = runtime_symbols[sym_name]
    if runtime_id ~= nil then
        return object_relocation.kind:native_runtime_symbol_relocation(source, object_relocation, runtime_id)
    end

    if sym == nil or sym.section == "UND" or asdl.isa(sym.binding, Native.NativeObjectSymbolExtern) then
        return nil, Native.NativeBuildRejectExtraUnresolvedSymbol(
            source.id,
            sym_name,
            "unresolved symbol is not a declared continuation, runtime symbol, hole ordinal, or local object symbol"
        )
    end

    return object_relocation.kind:native_local_symbol_relocation(source, object_relocation, sym_name)
end

local function resolve_declared_holes(source, text_bytes, hole_relocations)
    local holes = {}
    local rejects = {}
    local declarations_by_symbol = {}
    for _, hole in ipairs(source.declared_holes or {}) do
        declarations_by_symbol[hole.symbol] = hole
    end
    local seen = {}
    for _, relocation in ipairs(hole_relocations or {}) do
        local declared = declarations_by_symbol[relocation.ordinal.symbol]
        if declared == nil then
            rejects[#rejects + 1] = Native.NativeBuildRejectMissingHoleOrdinal(
                source.id,
                relocation.ordinal.ordinal,
                relocation.ordinal.symbol
            )
        else
            local width = declared.width
            if asdl.isa(relocation.formula, Native.NativePatchSym64) then width = 8 end
            if relocation.offset + width > #text_bytes then
                rejects[#rejects + 1] = Native.NativeBuildRejectHoleOutOfRange(source.id, declared.id, relocation.offset, width)
            else
                holes[#holes + 1] = Native.NativeHoleLayout(declared.id, declared.symbol, relocation.offset, width, declared.hole)
                seen[declared.symbol] = true
            end
        end
    end
    for _, hole in ipairs(source.declared_holes or {}) do
        if seen[hole.symbol] == nil then
            rejects[#rejects + 1] = Native.NativeBuildRejectMissingHole(source.id, hole.id, hole.symbol)
        end
    end
    return holes, rejects
end

local function object_indexes(object)
    local sections_by_id = {}
    local sections_by_name = {}
    for _, section in ipairs(object.sections or {}) do
        sections_by_id[section.id.text] = section
        sections_by_name[section.name] = section
    end

    local symbols_by_id = {}
    local symbols_by_name = {}
    local symbol_order = {}
    for _, symbol in ipairs(object.symbols or {}) do
        local section_name
        if symbol.section ~= nil then
            local section = sections_by_id[symbol.section.text]
            section_name = section and section.name or nil
        end
        local entry = {
            id = symbol.id,
            name = symbol.name,
            value = symbol.value,
            size = symbol.size,
            section = section_name,
            binding = symbol.binding,
            source = symbol,
        }
        symbols_by_id[symbol.id.text] = entry
        if symbol.name ~= "" then symbols_by_name[symbol.name] = entry end
        symbol_order[#symbol_order + 1] = entry
    end

    return sections_by_id, sections_by_name, symbols_by_id, symbols_by_name, symbol_order
end

local function object_text_relocations(object, text_section)
    local out = {}
    for _, relocation in ipairs(object.relocations or {}) do
        if relocation.section.text == text_section.id.text then out[#out + 1] = relocation end
    end
    return out
end

local function section_has_flag(section, flag)
    for _, present in ipairs(section.flags or {}) do
        if present == flag then return true end
    end
    return false
end

local function is_readonly_constant_section(section)
    if section == nil or section.bytes == nil or section.bytes.size == 0 then return false end
    if section_has_flag(section, Native.NativeObjectSectionExecutable) then return false end
    if section_has_flag(section, Native.NativeObjectSectionWritable) then return false end
    return tostring(section.name):match("^%.rodata") ~= nil
end

local function constant_pool_entry_id_for_section(source, section)
    return Native.NativeConstantPoolEntryId(source.id.text .. ".constant_pool.section." .. c_identifier(section.name))
end

local function object_constant_pool_layout(source, sections_by_id, symbol_order)
    local entries = {}
    local symbols = {}
    local max_align = 1
    for _, section in pairs(sections_by_id or {}) do
        if is_readonly_constant_section(section) then
            local entry = Native.NativeConstantPoolEntry(
                constant_pool_entry_id_for_section(source, section),
                section.bytes,
                section.align or 1,
                Native.NativeConstantPoolBytes(section.bytes.size, section.align or 1)
            )
            entries[#entries + 1] = Native.NativeConstantPoolLayoutEntry(entry, 0)
            if entry.alignment > max_align then max_align = entry.alignment end
            symbols[section.name] = { entry = entry, addend_bias = 0 }
            for _, sym in ipairs(symbol_order or {}) do
                if sym.section == section.name and sym.name ~= "" then
                    symbols[sym.name] = { entry = entry, addend_bias = sym.value or 0 }
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.entry.id.text < b.entry.id.text end)
    local offset = 0
    local laid_out = {}
    for _, layout_entry in ipairs(entries) do
        local alignment = layout_entry.entry.alignment or 1
        local rem = offset % alignment
        if rem ~= 0 then offset = offset + (alignment - rem) end
        laid_out[#laid_out + 1] = Native.NativeConstantPoolLayoutEntry(layout_entry.entry, offset)
        offset = offset + layout_entry.entry.bytes.size
    end
    return Native.NativeConstantPoolLayout(laid_out, offset, max_align), symbols
end

function Native.NativeTarget:reject_if_not_elf64_x64_object_target(source)
    if asdl.isa(self.arch, Native.NativeArchX64) and asdl.isa(self.endian, Native.NativeLittleEndian) and self.pointer_bits == 64 then
        return nil
    end
    return Native.NativeBuildRejectUnsupportedObjectFormat(
        source.id,
        "elf64-x64",
        "compiled ELF64/x64 stencil object does not match request target " .. self.id.text
    )
end

function Native.NativeRelocation:native_template_relocation_kind()
    return nil
end

function Native.NativeRelocationRel32:native_template_relocation_kind() return Native.NativeTemplateRelocationRel32 end
function Native.NativeRelocationAbs64:native_template_relocation_kind() return Native.NativeTemplateRelocationAbs64 end
function Native.NativeRelocationRuntimeSymbol:native_template_relocation_kind() return Native.NativeTemplateRelocationRuntimeSymbol end
function Native.NativeRelocationContinuation:native_template_relocation_kind() return Native.NativeTemplateRelocationContinuation end
function Native.NativeRelocationHoleOrdinal:native_template_relocation_kind() return Native.NativeTemplateRelocationHoleOrdinal end
function Native.NativeRelocationConstantPool:native_template_relocation_kind() return Native.NativeTemplateRelocationConstantPool end

local function template_relocation_kind_declared(source, kind)
    for _, declared in ipairs(source.declared_relocation_kinds or {}) do
        if declared == kind then return true end
    end
    return false
end

local function reject_undeclared_relocation_kind(source, relocation)
    local kind = relocation:native_template_relocation_kind()
    if kind == nil or template_relocation_kind_declared(source, kind) then return nil end
    return Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        relocation.offset,
        asdl.class_basename(kind),
        "object relocation kind is not declared by NativeTemplateSource manifest entry"
    )
end

local function declared_hole_ordinal_rejects(source)
    local rejects = {}
    local seen_symbol = {}
    local seen_number = {}
    for _, ordinal in ipairs(source.declared_hole_ordinals or {}) do
        if seen_symbol[ordinal.symbol] ~= nil or seen_number[ordinal.ordinal] ~= nil then
            rejects[#rejects + 1] = Native.NativeBuildRejectDuplicateHoleOrdinal(source.id, ordinal.ordinal, ordinal.symbol)
        end
        seen_symbol[ordinal.symbol] = true
        seen_number[ordinal.ordinal] = true
    end
    return rejects
end

local function compile_source(source, request, build_dir, index)
    local rejects = declared_hole_ordinal_rejects(source)
    if source.c_text == "" then
        rejects[#rejects + 1] = Native.NativeBuildRejectEmptySource(source.id, "empty native template source")
        return nil, rejects
    end
    if #rejects > 0 then return nil, rejects end

    local stem = string.format("%03d_%s", index, c_identifier(source.id.text or source.entry_symbol))
    local source_path = build_dir .. "/" .. stem .. source_extension(source)
    local object_path = build_dir .. "/" .. stem .. ".o"
    write_file(source_path, source.c_text)

    local cc = os.getenv("CC") or "gcc"
    local cmd = table.concat({ shell_quote(cc), source_flags(source), shell_quote(source_path), "-o", shell_quote(object_path) }, " ")
    if not os_execute(cmd) then
        return nil, { Native.NativeBuildRejectCompileError(source.id, "native template object build failed: " .. cmd) }
    end

    local target_reject = request.target:reject_if_not_elf64_x64_object_target(source)
    if target_reject ~= nil then return nil, { target_reject } end

    local object_bytes = read_file(object_path)
    local object, object_rejects = Native.NativeTemplateBytes(object_bytes, #object_bytes):parse_native_object(source.id, request.target)
    if object_rejects ~= nil then return nil, object_rejects end

    local sections_by_id, sections_by_name, symbols_by_id, symbols, symbol_order = object_indexes(object)
    local entry_symbol = symbols[source.entry_symbol]
    if entry_symbol == nil or entry_symbol.section == nil then
        return nil, { Native.NativeBuildRejectMissingEntrySymbol(source.id, source.entry_symbol) }
    end

    local text_section = entry_symbol.section
    local text_meta = sections_by_name[text_section]
    if text_meta == nil then
        return nil, { Native.NativeBuildRejectMissingEntrySymbol(source.id, source.entry_symbol) }
    end

    local text_bytes = text_meta.bytes.bytes
    if #text_bytes == 0 then
        return nil, { Native.NativeBuildRejectEmptyText(source.id, "entry symbol text section is empty") }
    end

    local symbol_entries = {}
    for _, sym in ipairs(symbol_order) do
        if sym.section == text_section and sym.name ~= "" then
            symbol_entries[#symbol_entries + 1] = Native.NativeSymbol(sym.name, sym.value or 0, sym.size or 0)
        end
    end

    local constant_pool_layout, constant_pool_symbols = object_constant_pool_layout(source, sections_by_id, symbol_order)
    local object_relocs = object_text_relocations(object, text_meta)
    local runtime_symbols = runtime_symbol_index(request.runtime)
    local continuation_symbols = continuation_symbol_index(source)
    local hole_symbols = hole_ordinal_symbol_index(source)
    local seen_continuations = {}
    local relocations = {}
    local hole_relocations = {}
    for _, object_relocation in ipairs(object_relocs) do
        local relocation, reject = native_relocation_for(source, object_relocation, text_section, symbols_by_id, symbols, sections_by_name, runtime_symbols, continuation_symbols, hole_symbols, constant_pool_symbols)
        if reject ~= nil then rejects[#rejects + 1] = reject
        else
            local declaration_reject = reject_undeclared_relocation_kind(source, relocation)
            if declaration_reject ~= nil then rejects[#rejects + 1] = declaration_reject end
            if asdl.isa(relocation, Native.NativeRelocationContinuation) then
                seen_continuations[relocation.symbol.name] = true
                relocations[#relocations + 1] = relocation
            elseif asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then
                hole_relocations[#hole_relocations + 1] = relocation
                relocations[#relocations + 1] = relocation
            else
                relocations[#relocations + 1] = relocation
            end
        end
    end

    for _, reject in ipairs(source.extraction:verify_native_object_relocations(source, seen_continuations)) do
        rejects[#rejects + 1] = reject
    end

    local holes, hole_rejects = resolve_declared_holes(source, text_bytes, hole_relocations)
    for _, reject in ipairs(hole_rejects) do rejects[#rejects + 1] = reject end

    if #rejects > 0 then return nil, rejects end

    return Native.NativeEmbeddedTemplate(
        source.family,
        source.extraction,
        source.signature,
        Native.NativeTextSection(Native.NativeTemplateBytes(text_bytes, #text_bytes), text_meta.align or 1),
        symbol_entries,
        relocations,
        holes,
        source.declared_hole_ordinals,
        source.declared_relocation_kinds,
        constant_pool_layout
    ), nil
end

local function asdl_list_equals(a, b)
    a = a or {}
    b = b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function request_manifest_rejects(request)
    local rejects = {}
    local manifest_source = Native.NativeTemplateId(request.id.text .. ".manifest")
    local entries = {}
    for _, group in ipairs((request.manifest and request.manifest.groups) or {}) do
        for _, entry in ipairs(group.entries or {}) do entries[#entries + 1] = entry end
    end
    if request.manifest.total_count ~= #entries then
        rejects[#rejects + 1] = Native.NativeBuildRejectRoleMismatch(
            manifest_source,
            "manifest total_count does not equal manifest entry count"
        )
    end
    if #entries ~= #(request.sources or {}) then
        rejects[#rejects + 1] = Native.NativeBuildRejectRoleMismatch(
            manifest_source,
            "manifest entry count does not equal source count"
        )
    end
    local entries_by_source = {}
    for _, entry in ipairs(entries) do entries_by_source[entry.source.text] = entry end
    for _, source in ipairs(request.sources or {}) do
        local entry = entries_by_source[source.id.text]
        if entry == nil then
            rejects[#rejects + 1] = Native.NativeBuildRejectRoleMismatch(source.id, "source is not declared by manifest")
        elseif source.family ~= entry.family
            or source.generator ~= entry.generator
            or source.configuration ~= entry.configuration
            or source.signature ~= entry.signature
            or source.extraction ~= entry.extraction
            or not asdl_list_equals(source.declared_hole_ordinals, entry.declared_hole_ordinals)
            or not asdl_list_equals(source.declared_continuation_ordinals, entry.declared_continuation_ordinals)
            or not asdl_list_equals(source.declared_relocation_kinds, entry.declared_relocation_kinds) then
            rejects[#rejects + 1] = Native.NativeBuildRejectRoleMismatch(source.id, "source facts do not match manifest entry")
        end
    end
    return rejects
end

local function build_embedded_bank(request)
    local manifest_rejects = request_manifest_rejects(request)
    if #manifest_rejects > 0 then return nil, Native.NativeTemplateBankBuildRejected(manifest_rejects) end

    local build_root = os.getenv("LALIN_NATIVE_BANK_BUILD_DIR") or "target/native_bank_build"
    os.execute("mkdir -p " .. shell_quote(build_root))
    local build_dir = build_root .. "/" .. tostring(os.time()) .. "_" .. c_identifier(tostring(os.clock()))
    os.execute("mkdir -p " .. shell_quote(build_dir))

    local entries = {}
    local rejects = {}
    for i, source in ipairs(request.sources or {}) do
        local entry, source_rejects = compile_source(source, request, build_dir, i)
        if source_rejects ~= nil then
            for _, reject in ipairs(source_rejects) do rejects[#rejects + 1] = reject end
        else
            entries[#entries + 1] = entry
        end
    end

    if #rejects > 0 then return nil, Native.NativeTemplateBankBuildRejected(rejects) end
    return Native.NativeEmbeddedTemplateBank(request.id, request.target, request.manifest, entries), nil
end

local function schema_local_for_class(class_name)
    local schema = tostring(class_name):match("^(Lalin[^%.]+)%.")
    if schema == "LalinNative" then return "Native" end
    if schema == "LalinCode" then return "Code" end
    if schema == "LalinCore" then return "Core" end
    if schema == "LalinValue" then return "Value" end
    if schema == "LalinStencil" then return "Stencil" end
    if schema == "LalinKernel" then return "Kernel" end
    if schema == "LalinEffect" then return "Effect" end
    if schema == "LalinFlow" then return "Flow" end
    if schema == "LalinSem" then return "Sem" end
    if schema == "LalinType" then return "Type" end
    if schema == "LalinC" then return "C" end
    return nil
end

local function value_to_lua(value)
    local tv = type(value)
    if tv == "nil" then return "nil" end
    if tv == "string" then return lua_string_expr(value) end
    if tv == "number" or tv == "boolean" then return tostring(value) end
    if tv ~= "table" then error("gen_lalin_mc_bank: cannot serialize " .. tv .. " value", 2) end

    local class_name = asdl.class_name(value)
    if class_name ~= nil then
        local local_name = schema_local_for_class(class_name)
        if local_name == nil then
            error("gen_lalin_mc_bank: cannot serialize ASDL value " .. tostring(class_name) .. " in native embedded bank", 2)
        end
        local base = asdl.class_basename(value)
        local fields = asdl.fields(value)
        if fields == nil or #fields == 0 then return local_name .. "." .. base end
        local args = {}
        for _, field in ipairs(fields) do
            args[#args + 1] = value_to_lua(value[field.name])
        end
        return local_name .. "." .. base .. "(" .. table.concat(args, ", ") .. ")"
    end

    local parts = {}
    for i = 1, #value do parts[#parts + 1] = value_to_lua(value[i]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function emit_lua_module(embedded)
    return table.concat({
        "-- Generated by tools/gen_lalin_mc_bank.lua.",
        "-- Returns a typed LalinNative.NativeEmbeddedTemplateBank ASDL value.",
        "return function(T)",
        "  local Native = T.LalinNative",
        "  local Code = T.LalinCode",
        "  local Core = T.LalinCore",
        "  local Value = T.LalinValue",
        "  local Stencil = T.LalinStencil",
        "  local Kernel = T.LalinKernel",
        "  local Effect = T.LalinEffect",
        "  local Flow = T.LalinFlow",
        "  local Sem = T.LalinSem",
        "  local Type = T.LalinType",
        "  local C = T.LalinC",
        "  return " .. value_to_lua(embedded),
        "end",
        "",
    }, "\n")
end

local function relocation_symbol_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then return relocation.symbol.text end
    if asdl.isa(relocation, Native.NativeRelocationContinuation) then return relocation.symbol.name end
    if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then return relocation.ordinal.symbol end
    if asdl.isa(relocation, Native.NativeRelocationConstantPool) then return relocation.entry.text end
    return relocation.symbol
end

local function relocation_kind_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationRel32) then return "rel32" end
    if asdl.isa(relocation, Native.NativeRelocationAbs64) then return "abs64" end
    if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then return "runtime_symbol" end
    if asdl.isa(relocation, Native.NativeRelocationContinuation) then return "continuation" end
    if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then return "hole_ordinal" end
    if asdl.isa(relocation, Native.NativeRelocationConstantPool) then return "constant_pool" end
    return asdl.class_basename(relocation)
end

local function emit_header()
    return table.concat({
        "#ifndef LALIN_EMBEDDED_NATIVE_BANK_H",
        "#define LALIN_EMBEDDED_NATIVE_BANK_H",
        "",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "",
        "/* Raw build/debug view of the embedded native bank.",
        "   The generated Lua ASDL bridge is the typed runtime import boundary. */",
        "typedef struct LalinNativeEmbeddedSymbol {",
        "  const char *name;",
        "  size_t offset;",
        "  size_t size;",
        "} LalinNativeEmbeddedSymbol;",
        "",
        "typedef struct LalinNativeEmbeddedRelocation {",
        "  const char *kind;",
        "  size_t offset;",
        "  const char *symbol;",
        "  long addend;",
        "} LalinNativeEmbeddedRelocation;",
        "",
        "typedef struct LalinNativeEmbeddedPatchHole {",
        "  const char *id;",
        "  const char *symbol;",
        "  size_t offset;",
        "  size_t width;",
        "  const char *hole_kind;",
        "} LalinNativeEmbeddedPatchHole;",
        "",
        "typedef struct LalinNativeEmbeddedTemplate {",
        "  const char *family_id;",
        "  const char *extraction_kind;",
        "  const char *signature_frame_scalar_kind;",
        "  const unsigned char *text;",
        "  size_t text_size;",
        "  size_t text_alignment;",
        "  const LalinNativeEmbeddedSymbol *symbols;",
        "  size_t symbol_count;",
        "  const LalinNativeEmbeddedRelocation *relocations;",
        "  size_t relocation_count;",
        "  const LalinNativeEmbeddedPatchHole *holes;",
        "  size_t hole_count;",
        "  size_t constant_pool_size;",
        "  size_t constant_pool_alignment;",
        "} LalinNativeEmbeddedTemplate;",
        "",
        "typedef struct LalinNativeEmbeddedTemplateBank {",
        "  const char *bank_id;",
        "  const char *target_id;",
        "  const LalinNativeEmbeddedTemplate *entries;",
        "  size_t entry_count;",
        "  size_t manifest_total_count;",
        "} LalinNativeEmbeddedTemplateBank;",
        "",
        "/* Raw C access for binary embedding/debugging only; not an ASDL import hook. */",
        "const LalinNativeEmbeddedTemplateBank *lalin_native_embedded_template_bank(void);",
        "",
        "#endif",
        "",
    }, "\n")
end

local function emit_symbol_array(entry, index)
    if #(entry.symbols or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_symbols_" .. tostring(index)
    local out = { "static const LalinNativeEmbeddedSymbol " .. name .. "[] = {" }
    for _, sym in ipairs(entry.symbols) do
        out[#out + 1] = string.format("  { %s, %u, %u },", c_string(sym.name), sym.offset, sym.size)
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #entry.symbols
end

local function emit_relocation_array(entry, index)
    if #(entry.relocations or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_relocations_" .. tostring(index)
    local out = { "static const LalinNativeEmbeddedRelocation " .. name .. "[] = {" }
    for _, reloc in ipairs(entry.relocations) do
        out[#out + 1] = string.format(
            "  { %s, %u, %s, %d },",
            c_string(relocation_kind_for_c(reloc)),
            reloc.offset,
            c_string(relocation_symbol_for_c(reloc)),
            reloc.addend or 0
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #entry.relocations
end

local function emit_hole_array(entry, index)
    if #(entry.holes or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_holes_" .. tostring(index)
    local out = { "static const LalinNativeEmbeddedPatchHole " .. name .. "[] = {" }
    for _, hole in ipairs(entry.holes) do
        out[#out + 1] = string.format(
            "  { %s, %s, %u, %u, %s },",
            c_string(hole.id.text),
            c_string(hole.symbol),
            hole.offset,
            hole.width,
            c_string(asdl.class_basename(hole.hole))
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #entry.holes
end

local function emit_entry_arrays(entry, index)
    local out = {}
    local text_name = "lalin_native_template_text_" .. tostring(index)
    out[#out + 1] = string.format("static const unsigned char %s[] = { %s };", text_name, c_bytes(entry.text.bytes.bytes))
    local sym_src, sym_name, sym_count = emit_symbol_array(entry, index)
    if sym_src ~= nil then out[#out + 1] = sym_src end
    local reloc_src, reloc_name, reloc_count = emit_relocation_array(entry, index)
    if reloc_src ~= nil then out[#out + 1] = reloc_src end
    local hole_src, hole_name, hole_count = emit_hole_array(entry, index)
    if hole_src ~= nil then out[#out + 1] = hole_src end
    return table.concat(out, "\n"), {
        text_name = text_name,
        sym_name = sym_name,
        sym_count = sym_count,
        reloc_name = reloc_name,
        reloc_count = reloc_count,
        hole_name = hole_name,
        hole_count = hole_count,
    }
end

local function emit_source(embedded, request)
    local out = {
        "#include <stddef.h>",
        "#include <stdint.h>",
        "#include \"" .. tostring(out_h):match("([^/]+)$") .. "\"",
        "",
        "/* This C file embeds raw template bytes/metadata for native binaries.",
        "   Runtime ASDL import uses the generated Lua bridge, not these structs. */",
    }

    local meta = {}
    for i, entry in ipairs(embedded.entries) do
        local src, m = emit_entry_arrays(entry, i)
        out[#out + 1] = src
        out[#out + 1] = ""
        meta[i] = m
    end

    out[#out + 1] = "static const LalinNativeEmbeddedTemplate lalin_native_template_entries[] = {"
    for i, entry in ipairs(embedded.entries) do
        local m = meta[i]
        out[#out + 1] = string.format(
            "  { %s, %s, %s, %s, %u, %u, %s, %u, %s, %u, %s, %u, %u, %u },",
            c_string(entry.family.id.text),
            c_string(asdl.class_basename(entry.extraction)),
            c_string(asdl.class_basename(entry.signature.frame_param.scalar)),
            m.text_name,
            entry.text.bytes.size,
            entry.text.alignment,
            m.sym_name,
            m.sym_count,
            m.reloc_name,
            m.reloc_count,
            m.hole_name,
            m.hole_count,
            entry.constant_pool_layout.size,
            entry.constant_pool_layout.alignment
        )
    end
    out[#out + 1] = "  { NULL, NULL, NULL, NULL, 0, 1, NULL, 0, NULL, 0, NULL, 0, 0, 1 },"
    out[#out + 1] = "};"
    out[#out + 1] = ""
    out[#out + 1] = "static const LalinNativeEmbeddedTemplateBank lalin_native_bank = {"
    out[#out + 1] = "  " .. c_string(embedded.id.text) .. ","
    out[#out + 1] = "  " .. c_string(embedded.target.id.text) .. ","
    out[#out + 1] = "  lalin_native_template_entries,"
    out[#out + 1] = "  " .. tostring(#embedded.entries) .. ","
    out[#out + 1] = "  " .. tostring(request.manifest.total_count)
    out[#out + 1] = "};"
    out[#out + 1] = ""
    out[#out + 1] = "const LalinNativeEmbeddedTemplateBank *lalin_native_embedded_template_bank(void) {"
    out[#out + 1] = "  return &lalin_native_bank;"
    out[#out + 1] = "}"
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

local request = load_manifest(manifest_path)
local embedded, build_rejected = build_embedded_bank(request)
if build_rejected ~= nil then
    io.stderr:write("native template bank build rejected\n")
    for _, reject in ipairs(build_rejected.rejects or {}) do
        io.stderr:write("  ", tostring(reject), "\n")
    end
    os.exit(1)
end

write_file(out_h, emit_header())
write_file(out_c, emit_source(embedded, request))
write_file(out_lua, emit_lua_module(embedded))
io.stderr:write(
    "embedded native template bank ", embedded.id.text,
    " with ", tostring(#embedded.entries),
    " templates; Lua ASDL bridge ", out_lua,
    "\n"
)
