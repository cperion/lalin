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
    "C-owned NativeBankArtifact descriptor and generated C bank are emitted for",
    "the host/default target.",
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

function Native.NativeExtractFallthroughFragment:native_continuation_symbols()
    return {}
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

function Native.NativeExtractFallthroughFragment:verify_native_object_relocations(_source, _seen_continuations)
    return {}
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
        "unsupported relocation type for C-owned native bank artifact"
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

    return Native.NativeCompiledTemplate(
        source.id,
        source.family,
        request.target,
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

local function build_native_bank(request)
    local manifest_rejects = request_manifest_rejects(request)
    if #manifest_rejects > 0 then return nil, Native.NativeTemplateBankBuildRejected(manifest_rejects) end

    local build_root = os.getenv("LALIN_NATIVE_BANK_BUILD_DIR") or "target/native_bank_build"
    os.execute("mkdir -p " .. shell_quote(build_root))
    local build_dir = build_root .. "/" .. tostring(os.time()) .. "_" .. c_identifier(tostring(os.clock()))
    os.execute("mkdir -p " .. shell_quote(build_dir))

    local templates = {}
    local rejects = {}
    for i, source in ipairs(request.sources or {}) do
        local template, source_rejects = compile_source(source, request, build_dir, i)
        if source_rejects ~= nil then
            for _, reject in ipairs(source_rejects) do rejects[#rejects + 1] = reject end
        else
            templates[#templates + 1] = template
        end
    end

    if #rejects > 0 then return nil, Native.NativeTemplateBankBuildRejected(rejects) end
    local artifact = Native.NativeBankArtifact(
        request.id,
        request.target,
        request.manifest,
        #templates,
        "lalin_native_bank_artifact",
        "lalin_native_bank_select",
        "lalin_native_bank_install"
    )
    return {
        id = request.id,
        target = request.target,
        manifest = request.manifest,
        templates = templates,
        artifact = artifact,
    }, nil
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

local LUA_FULL_MANIFEST_ENTRY_LIMIT = tonumber(os.getenv("LALIN_NATIVE_BANK_LUA_FULL_MANIFEST_ENTRY_LIMIT") or "2048") or 2048

local function lua_artifact_descriptor(artifact)
    local manifest = artifact.manifest
    if manifest ~= nil and manifest.total_count > LUA_FULL_MANIFEST_ENTRY_LIMIT then
        manifest = Native.NativeTemplateSourceManifest(manifest.id, manifest.support_domain, {}, manifest.total_count)
        return Native.NativeBankArtifact(
            artifact.id,
            artifact.target,
            manifest,
            artifact.template_count,
            artifact.api_symbol,
            artifact.selector_symbol,
            artifact.installer_symbol
        )
    end
    return artifact
end

local function emit_lua_module(bank)
    local artifact = lua_artifact_descriptor(bank.artifact)
    local lines = {
        "-- Generated by tools/gen_lalin_mc_bank.lua.",
        "-- Returns a typed LalinNative.NativeBankArtifact descriptor.",
        "-- Template bytes, selector tables, relocation metadata, and install ABI data",
        "-- live in the generated C artifact, not in Lua ASDL template constructors.",
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
        "  return " .. value_to_lua(artifact),
        "end",
        "",
    }
    return table.concat(lines, "\n")
end

local function relocation_symbol_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then return relocation.symbol.text end
    if asdl.isa(relocation, Native.NativeRelocationContinuation) then return relocation.symbol.name end
    if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then return relocation.ordinal.symbol end
    if asdl.isa(relocation, Native.NativeRelocationConstantPool) then return relocation.entry.text end
    return relocation.symbol
end

local function relocation_kind_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationRel32) then return "LALIN_NATIVE_RELOC_REL32" end
    if asdl.isa(relocation, Native.NativeRelocationAbs64) then return "LALIN_NATIVE_RELOC_ABS64" end
    if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then return "LALIN_NATIVE_RELOC_RUNTIME_SYMBOL" end
    if asdl.isa(relocation, Native.NativeRelocationContinuation) then return "LALIN_NATIVE_RELOC_CONTINUATION" end
    if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then return "LALIN_NATIVE_RELOC_HOLE_ORDINAL" end
    if asdl.isa(relocation, Native.NativeRelocationConstantPool) then return "LALIN_NATIVE_RELOC_CONSTANT_POOL" end
    return "LALIN_NATIVE_RELOC_UNKNOWN"
end

local function patch_formula_for_c(formula)
    if asdl.isa(formula, Native.NativePatchSym32) then return "LALIN_NATIVE_PATCH_FORMULA_SYM32" end
    if asdl.isa(formula, Native.NativePatchSym64) then return "LALIN_NATIVE_PATCH_FORMULA_SYM64" end
    if asdl.isa(formula, Native.NativePatchPcRel32) then return "LALIN_NATIVE_PATCH_FORMULA_PCREL32" end
    return "LALIN_NATIVE_PATCH_FORMULA_NONE"
end

local function relocation_formula_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then return patch_formula_for_c(relocation.formula) end
    if asdl.isa(relocation, Native.NativeRelocationConstantPool) then return patch_formula_for_c(relocation.formula) end
    return "LALIN_NATIVE_PATCH_FORMULA_NONE"
end

local function patch_hole_kind_for_c(hole)
    if asdl.isa(hole, Native.NativePatchImm32) then return "LALIN_NATIVE_PATCH_HOLE_IMM32" end
    if asdl.isa(hole, Native.NativePatchImm64) then return "LALIN_NATIVE_PATCH_HOLE_IMM64" end
    if asdl.isa(hole, Native.NativePatchPtr64) then return "LALIN_NATIVE_PATCH_HOLE_PTR64" end
    if asdl.isa(hole, Native.NativePatchRel32) then return "LALIN_NATIVE_PATCH_HOLE_REL32" end
    if asdl.isa(hole, Native.NativePatchBranchRel32) then return "LALIN_NATIVE_PATCH_HOLE_BRANCH_REL32" end
    if asdl.isa(hole, Native.NativePatchCallRel32) then return "LALIN_NATIVE_PATCH_HOLE_CALL_REL32" end
    if asdl.isa(hole, Native.NativePatchFieldOffset32) then return "LALIN_NATIVE_PATCH_HOLE_FIELD_OFFSET32" end
    if asdl.isa(hole, Native.NativePatchComponentIndex32) then return "LALIN_NATIVE_PATCH_HOLE_COMPONENT_INDEX32" end
    if asdl.isa(hole, Native.NativePatchStride32) then return "LALIN_NATIVE_PATCH_HOLE_STRIDE32" end
    if asdl.isa(hole, Native.NativePatchFrameOffset32) then return "LALIN_NATIVE_PATCH_HOLE_FRAME_OFFSET32" end
    if asdl.isa(hole, Native.NativePatchFrameSize32) then return "LALIN_NATIVE_PATCH_HOLE_FRAME_SIZE32" end
    return "LALIN_NATIVE_PATCH_HOLE_UNKNOWN"
end

local function constant_pool_kind_for_c(entry)
    return c_string(asdl.class_basename(entry.kind))
end

local function signature_frame_scalar_for_c(template)
    if template.signature ~= nil and template.signature.frame_param ~= nil and template.signature.frame_param.scalar ~= nil then
        return asdl.class_basename(template.signature.frame_param.scalar)
    end
    return ""
end

local function emit_header()
    return table.concat({
        "#ifndef LALIN_NATIVE_TEMPLATE_BANK_H",
        "#define LALIN_NATIVE_TEMPLATE_BANK_H",
        "",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "",
        "/* Generated C-owned native template bank artifact.",
        "   The C artifact owns template bytes, relocation metadata, selector tables,",
        "   and the install ABI payload vocabulary. Lua receives only a",
        "   LalinNative.NativeBankArtifact descriptor. */",
        "",
        "typedef enum LalinNativeRelocationKind {",
        "  LALIN_NATIVE_RELOC_UNKNOWN = 0,",
        "  LALIN_NATIVE_RELOC_REL32 = 1,",
        "  LALIN_NATIVE_RELOC_ABS64 = 2,",
        "  LALIN_NATIVE_RELOC_RUNTIME_SYMBOL = 3,",
        "  LALIN_NATIVE_RELOC_CONTINUATION = 4,",
        "  LALIN_NATIVE_RELOC_HOLE_ORDINAL = 5,",
        "  LALIN_NATIVE_RELOC_CONSTANT_POOL = 6",
        "} LalinNativeRelocationKind;",
        "",
        "typedef enum LalinNativePatchFormulaKind {",
        "  LALIN_NATIVE_PATCH_FORMULA_NONE = 0,",
        "  LALIN_NATIVE_PATCH_FORMULA_SYM32 = 1,",
        "  LALIN_NATIVE_PATCH_FORMULA_SYM64 = 2,",
        "  LALIN_NATIVE_PATCH_FORMULA_PCREL32 = 3",
        "} LalinNativePatchFormulaKind;",
        "",
        "typedef enum LalinNativePatchHoleKind {",
        "  LALIN_NATIVE_PATCH_HOLE_UNKNOWN = 0,",
        "  LALIN_NATIVE_PATCH_HOLE_IMM32 = 1,",
        "  LALIN_NATIVE_PATCH_HOLE_IMM64 = 2,",
        "  LALIN_NATIVE_PATCH_HOLE_PTR64 = 3,",
        "  LALIN_NATIVE_PATCH_HOLE_REL32 = 4,",
        "  LALIN_NATIVE_PATCH_HOLE_BRANCH_REL32 = 5,",
        "  LALIN_NATIVE_PATCH_HOLE_CALL_REL32 = 6,",
        "  LALIN_NATIVE_PATCH_HOLE_FIELD_OFFSET32 = 7,",
        "  LALIN_NATIVE_PATCH_HOLE_COMPONENT_INDEX32 = 8,",
        "  LALIN_NATIVE_PATCH_HOLE_STRIDE32 = 9,",
        "  LALIN_NATIVE_PATCH_HOLE_FRAME_OFFSET32 = 10,",
        "  LALIN_NATIVE_PATCH_HOLE_FRAME_SIZE32 = 11",
        "} LalinNativePatchHoleKind;",
        "",
        "typedef enum LalinNativePatchCoordinateKind {",
        "  LALIN_NATIVE_COORD_NONE = 0,",
        "  LALIN_NATIVE_COORD_IMMEDIATE_I32 = 1,",
        "  LALIN_NATIVE_COORD_IMMEDIATE_I64 = 2,",
        "  LALIN_NATIVE_COORD_POINTER64 = 3,",
        "  LALIN_NATIVE_COORD_FIELD_OFFSET = 4,",
        "  LALIN_NATIVE_COORD_COMPONENT_INDEX = 5,",
        "  LALIN_NATIVE_COORD_STRIDE = 6,",
        "  LALIN_NATIVE_COORD_AFFINE_COEFF = 7,",
        "  LALIN_NATIVE_COORD_AFFINE_OFFSET = 8,",
        "  LALIN_NATIVE_COORD_WINDOW_OFFSET = 9,",
        "  LALIN_NATIVE_COORD_BRANCH_TARGET = 10,",
        "  LALIN_NATIVE_COORD_CALL_TARGET = 11,",
        "  LALIN_NATIVE_COORD_CODE_DATA_ADDRESS = 12,",
        "  LALIN_NATIVE_COORD_CODE_GLOBAL_ADDRESS = 13,",
        "  LALIN_NATIVE_COORD_CODE_FUNC_ADDRESS = 14,",
        "  LALIN_NATIVE_COORD_CODE_EXTERN_ADDRESS = 15,",
        "  LALIN_NATIVE_COORD_MODULE_ADDRESS = 20,",
        "  LALIN_NATIVE_COORD_FRAME_OFFSET = 16,",
        "  LALIN_NATIVE_COORD_FRAME_SIZE = 17,",
        "  LALIN_NATIVE_COORD_SCALAR_CONST = 18,",
        "  LALIN_NATIVE_COORD_CONSTANT_POOL_ENTRY = 19",
        "} LalinNativePatchCoordinateKind;",
        "",
        "typedef enum LalinNativeSelectionStatus {",
        "  LALIN_NATIVE_SELECT_OK = 0,",
        "  LALIN_NATIVE_SELECT_INVALID = 1,",
        "  LALIN_NATIVE_SELECT_TARGET_MISMATCH = 2,",
        "  LALIN_NATIVE_SELECT_MISSING = 3,",
        "  LALIN_NATIVE_SELECT_AMBIGUOUS = 4",
        "} LalinNativeSelectionStatus;",
        "",
        "typedef enum LalinNativeInstallStatus {",
        "  LALIN_NATIVE_INSTALL_OK = 0,",
        "  LALIN_NATIVE_INSTALL_REJECTED = 1,",
        "  LALIN_NATIVE_INSTALL_ALLOCATION_FAILED = 2",
        "} LalinNativeInstallStatus;",
        "",
        "typedef struct LalinNativeSymbol {",
        "  const char *name;",
        "  size_t offset;",
        "  size_t size;",
        "} LalinNativeSymbol;",
        "",
        "typedef struct LalinNativeRelocation {",
        "  LalinNativeRelocationKind kind;",
        "  LalinNativePatchFormulaKind formula;",
        "  size_t offset;",
        "  const char *symbol;",
        "  int64_t addend;",
        "} LalinNativeRelocation;",
        "",
        "typedef struct LalinNativeHoleOrdinal {",
        "  const char *id;",
        "  uint32_t ordinal;",
        "  const char *symbol;",
        "  LalinNativePatchHoleKind hole_kind;",
        "} LalinNativeHoleOrdinal;",
        "",
        "typedef struct LalinNativePatchHole {",
        "  const char *id;",
        "  const char *symbol;",
        "  size_t offset;",
        "  size_t width;",
        "  LalinNativePatchHoleKind hole_kind;",
        "} LalinNativePatchHole;",
        "",
        "typedef struct LalinNativeConstantPoolEntry {",
        "  const char *id;",
        "  const unsigned char *bytes;",
        "  size_t size;",
        "  size_t alignment;",
        "  size_t offset;",
        "  const char *kind;",
        "} LalinNativeConstantPoolEntry;",
        "",
        "typedef struct LalinNativeTemplate {",
        "  size_t ordinal;",
        "  const char *template_id;",
        "  const char *family_id;",
        "  const char *extraction_kind;",
        "  const char *signature_frame_scalar_kind;",
        "  const unsigned char *text;",
        "  size_t text_size;",
        "  size_t text_alignment;",
        "  const LalinNativeSymbol *symbols;",
        "  size_t symbol_count;",
        "  const LalinNativeRelocation *relocations;",
        "  size_t relocation_count;",
        "  const LalinNativePatchHole *holes;",
        "  size_t hole_count;",
        "  const LalinNativeHoleOrdinal *hole_ordinals;",
        "  size_t hole_ordinal_count;",
        "  const LalinNativeConstantPoolEntry *constant_pool_entries;",
        "  size_t constant_pool_entry_count;",
        "  size_t constant_pool_size;",
        "  size_t constant_pool_alignment;",
        "} LalinNativeTemplate;",
        "",
        "typedef struct LalinNativeTemplateSelectorEntry {",
        "  const char *target_id;",
        "  const char *family_id;",
        "  size_t template_ordinal;",
        "} LalinNativeTemplateSelectorEntry;",
        "",
        "typedef struct LalinNativeBankArtifact {",
        "  const char *bank_id;",
        "  const char *target_id;",
        "  const char *api_symbol;",
        "  const char *selector_symbol;",
        "  const char *installer_symbol;",
        "  const LalinNativeTemplate *templates;",
        "  size_t template_count;",
        "  const LalinNativeTemplateSelectorEntry *selectors;",
        "  size_t selector_count;",
        "  size_t manifest_total_count;",
        "} LalinNativeBankArtifact;",
        "",
        "typedef struct LalinNativeTemplateSelectorKey {",
        "  const char *target_id;",
        "  const char *family_id;",
        "} LalinNativeTemplateSelectorKey;",
        "",
        "typedef struct LalinNativeTemplateHandle {",
        "  const LalinNativeBankArtifact *bank;",
        "  const LalinNativeTemplate *template_entry;",
        "  size_t ordinal;",
        "} LalinNativeTemplateHandle;",
        "",
        "typedef struct LalinNativeTemplateSelection {",
        "  LalinNativeSelectionStatus status;",
        "  LalinNativeTemplateHandle handle;",
        "  const LalinNativeTemplateSelectorEntry *matches;",
        "  size_t match_count;",
        "} LalinNativeTemplateSelection;",
        "",
        "typedef struct LalinNativePatchCoordinate {",
        "  LalinNativePatchCoordinateKind kind;",
        "  int64_t signed_value;",
        "  uint64_t unsigned_value;",
        "  const char *primary_id;",
        "  const char *secondary_id;",
        "  size_t index;",
        "  const unsigned char *bytes;",
        "  size_t byte_size;",
        "  size_t byte_alignment;",
        "} LalinNativePatchCoordinate;",
        "",
        "typedef struct LalinNativeInstallBinding {",
        "  const char *node_id;",
        "  const char *instance_id;",
        "  const char *hole_id;",
        "  const char *hole_ordinal_id;",
        "  int has_hole_ordinal_index;",
        "  size_t hole_ordinal_index;",
        "  LalinNativePatchCoordinate coordinate;",
        "} LalinNativeInstallBinding;",
        "",
        "typedef struct LalinNativeInstallNode {",
        "  const char *node_id;",
        "  const char *instance_id;",
        "  const char *key_target_id;",
        "  const char *family_id;",
        "  const LalinNativeInstallBinding *bindings;",
        "  size_t binding_count;",
        "} LalinNativeInstallNode;",
        "",
        "typedef enum LalinNativeInstallControlEdgeKind {",
        "  LALIN_NATIVE_INSTALL_EDGE_FALLTHROUGH = 1,",
        "  LALIN_NATIVE_INSTALL_EDGE_CONDITIONAL_BRANCH = 2,",
        "  LALIN_NATIVE_INSTALL_EDGE_LOOP_BACKEDGE = 3,",
        "  LALIN_NATIVE_INSTALL_EDGE_EXIT = 4,",
        "  LALIN_NATIVE_INSTALL_EDGE_CONTINUATION = 5,",
        "  LALIN_NATIVE_INSTALL_EDGE_RUNTIME_CALL_RETURN = 6,",
        "  LALIN_NATIVE_INSTALL_EDGE_SWITCH_STEP = 7",
        "} LalinNativeInstallControlEdgeKind;",
        "",
        "typedef struct LalinNativeInstallControlEdge {",
        "  LalinNativeInstallControlEdgeKind kind;",
        "  const char *from_node_id;",
        "  const char *to_node_id;",
        "  const char *then_node_id;",
        "  const char *then_symbol;",
        "  const char *else_node_id;",
        "  const char *else_symbol;",
        "  const char *symbol;",
        "  const char *runtime_symbol_id;",
        "  const char *return_symbol;",
        "} LalinNativeInstallControlEdge;",
        "",
        "typedef struct LalinNativeRuntimeSymbolAddress {",
        "  const char *symbol_id;",
        "  uint64_t address;",
        "} LalinNativeRuntimeSymbolAddress;",
        "",
        "typedef enum LalinNativeModuleAddressKind {",
        "  LALIN_NATIVE_MODULE_ADDRESS_DATA = 1,",
        "  LALIN_NATIVE_MODULE_ADDRESS_GLOBAL = 2,",
        "  LALIN_NATIVE_MODULE_ADDRESS_FUNC = 3,",
        "  LALIN_NATIVE_MODULE_ADDRESS_EXTERN = 4",
        "} LalinNativeModuleAddressKind;",
        "",
        "typedef struct LalinNativeModuleAddress {",
        "  LalinNativeModuleAddressKind kind;",
        "  const char *id;",
        "  uint64_t address;",
        "} LalinNativeModuleAddress;",
        "",
        "typedef void *(*LalinNativeExecutableAllocFn)(size_t size, size_t alignment, void *userdata);",
        "",
        "typedef struct LalinNativeInstallRequest {",
        "  const char *target_id;",
        "  const LalinNativeInstallNode *nodes;",
        "  size_t node_count;",
        "  const LalinNativeInstallControlEdge *control_edges;",
        "  size_t control_edge_count;",
        "  const LalinNativeRuntimeSymbolAddress *runtime_symbols;",
        "  size_t runtime_symbol_count;",
        "  const LalinNativeModuleAddress *module_addresses;",
        "  size_t module_address_count;",
        "  const char *entry_node_id;",
        "  LalinNativeExecutableAllocFn allocate_executable;",
        "  void *allocator_userdata;",
        "} LalinNativeInstallRequest;",
        "",
        "typedef enum LalinNativeInstallRejectKind {",
        "  LALIN_NATIVE_INSTALL_REJECT_GENERIC = 0,",
        "  LALIN_NATIVE_INSTALL_REJECT_FALLTHROUGH_LAYOUT = 1",
        "} LalinNativeInstallRejectKind;",
        "",
        "typedef struct LalinNativeInstallReject {",
        "  LalinNativeInstallRejectKind kind;",
        "  const char *node_id;",
        "  const char *to_node_id;",
        "  const char *hole_id;",
        "  const char *reason;",
        "} LalinNativeInstallReject;",
        "",
        "typedef struct LalinNativeInstallResult {",
        "  LalinNativeInstallStatus status;",
        "  void *base_address;",
        "  void *entry_address;",
        "  size_t size;",
        "  const LalinNativeInstallReject *rejects;",
        "  size_t reject_count;",
        "} LalinNativeInstallResult;",
        "",
        "const LalinNativeBankArtifact *lalin_native_bank_artifact(void);",
        "const LalinNativeTemplate *lalin_native_bank_template(const LalinNativeBankArtifact *bank, size_t ordinal);",
        "LalinNativeSelectionStatus lalin_native_bank_select(const LalinNativeBankArtifact *bank, const LalinNativeTemplateSelectorKey *key, LalinNativeTemplateSelection *out);",
        "LalinNativeInstallResult lalin_native_bank_install(const LalinNativeBankArtifact *bank, const LalinNativeInstallRequest *request);",
        "",
        "#endif",
        "",
    }, "\n")
end

local function emit_symbol_array(template, index)
    if #(template.symbols or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_symbols_" .. tostring(index)
    local out = { "static const LalinNativeSymbol " .. name .. "[] = {" }
    for _, sym in ipairs(template.symbols) do
        out[#out + 1] = string.format("  { %s, %u, %u },", c_string(sym.name), sym.offset, sym.size)
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #template.symbols
end

local function emit_relocation_array(template, index)
    if #(template.relocations or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_relocations_" .. tostring(index)
    local out = { "static const LalinNativeRelocation " .. name .. "[] = {" }
    for _, reloc in ipairs(template.relocations) do
        out[#out + 1] = string.format(
            "  { %s, %s, %u, %s, %d },",
            relocation_kind_for_c(reloc),
            relocation_formula_for_c(reloc),
            reloc.offset,
            c_string(relocation_symbol_for_c(reloc)),
            reloc.addend or 0
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #template.relocations
end

local function emit_hole_array(template, index)
    if #(template.holes or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_holes_" .. tostring(index)
    local out = { "static const LalinNativePatchHole " .. name .. "[] = {" }
    for _, hole in ipairs(template.holes) do
        out[#out + 1] = string.format(
            "  { %s, %s, %u, %u, %s },",
            c_string(hole.id.text),
            c_string(hole.symbol),
            hole.offset,
            hole.width,
            patch_hole_kind_for_c(hole.hole)
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #template.holes
end

local function emit_hole_ordinal_array(template, index)
    if #(template.hole_ordinals or {}) == 0 then return nil, "NULL", 0 end
    local name = "lalin_native_template_hole_ordinals_" .. tostring(index)
    local out = { "static const LalinNativeHoleOrdinal " .. name .. "[] = {" }
    for _, ordinal in ipairs(template.hole_ordinals) do
        out[#out + 1] = string.format(
            "  { %s, %u, %s, %s },",
            c_string(ordinal.id.text),
            ordinal.ordinal,
            c_string(ordinal.symbol),
            patch_hole_kind_for_c(ordinal.hole)
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), name, #template.hole_ordinals
end

local function emit_constant_pool_array(template, index)
    local entries = (template.constant_pool_layout and template.constant_pool_layout.entries) or {}
    if #entries == 0 then return nil, "NULL", 0 end
    local out = {}
    local meta_name = "lalin_native_template_constant_pool_" .. tostring(index)
    local item_names = {}
    for j, layout_entry in ipairs(entries) do
        local bytes_name = "lalin_native_template_constant_pool_bytes_" .. tostring(index) .. "_" .. tostring(j)
        out[#out + 1] = string.format("static const unsigned char %s[] = { %s };", bytes_name, c_bytes(layout_entry.entry.bytes.bytes))
        item_names[j] = bytes_name
    end
    out[#out + 1] = "static const LalinNativeConstantPoolEntry " .. meta_name .. "[] = {"
    for j, layout_entry in ipairs(entries) do
        out[#out + 1] = string.format(
            "  { %s, %s, %u, %u, %u, %s },",
            c_string(layout_entry.entry.id.text),
            item_names[j],
            layout_entry.entry.bytes.size,
            layout_entry.entry.alignment,
            layout_entry.offset,
            constant_pool_kind_for_c(layout_entry.entry)
        )
    end
    out[#out + 1] = "};"
    return table.concat(out, "\n"), meta_name, #entries
end

local function emit_template_arrays(template, index)
    local out = {}
    local text_name = "lalin_native_template_text_" .. tostring(index)
    out[#out + 1] = string.format("static const unsigned char %s[] = { %s };", text_name, c_bytes(template.text.bytes.bytes))
    local sym_src, sym_name, sym_count = emit_symbol_array(template, index)
    if sym_src ~= nil then out[#out + 1] = sym_src end
    local reloc_src, reloc_name, reloc_count = emit_relocation_array(template, index)
    if reloc_src ~= nil then out[#out + 1] = reloc_src end
    local hole_src, hole_name, hole_count = emit_hole_array(template, index)
    if hole_src ~= nil then out[#out + 1] = hole_src end
    local ordinal_src, ordinal_name, ordinal_count = emit_hole_ordinal_array(template, index)
    if ordinal_src ~= nil then out[#out + 1] = ordinal_src end
    local pool_src, pool_name, pool_count = emit_constant_pool_array(template, index)
    if pool_src ~= nil then out[#out + 1] = pool_src end
    return table.concat(out, "\n"), {
        text_name = text_name,
        sym_name = sym_name,
        sym_count = sym_count,
        reloc_name = reloc_name,
        reloc_count = reloc_count,
        hole_name = hole_name,
        hole_count = hole_count,
        ordinal_name = ordinal_name,
        ordinal_count = ordinal_count,
        pool_name = pool_name,
        pool_count = pool_count,
    }
end

local function sorted_selector_rows(bank)
    local rows = {}
    for i, template in ipairs(bank.templates or {}) do
        rows[#rows + 1] = {
            target_id = bank.target.id.text,
            family_id = template.family.id.text,
            ordinal = i - 1,
        }
    end
    table.sort(rows, function(a, b)
        if a.target_id ~= b.target_id then return a.target_id < b.target_id end
        if a.family_id ~= b.family_id then return a.family_id < b.family_id end
        return a.ordinal < b.ordinal
    end)
    return rows
end

local function emit_source(bank, request)
    local out = {
        "#include <stddef.h>",
        "#include <stdint.h>",
        "#include <stdlib.h>",
        "#include <string.h>",
        "#include \"" .. tostring(out_h):match("([^/]+)$") .. "\"",
        "",
        "/* Generated C-owned native template bank. */",
    }

    local meta = {}
    for i, template in ipairs(bank.templates) do
        local src, m = emit_template_arrays(template, i)
        out[#out + 1] = src
        out[#out + 1] = ""
        meta[i] = m
    end

    local template_array_name = "NULL"
    if #bank.templates > 0 then
        template_array_name = "lalin_native_templates"
        out[#out + 1] = "static const LalinNativeTemplate lalin_native_templates[] = {"
        for i, template in ipairs(bank.templates) do
            local m = meta[i]
            out[#out + 1] = string.format(
                "  { %u, %s, %s, %s, %s, %s, %u, %u, %s, %u, %s, %u, %s, %u, %s, %u, %s, %u, %u, %u },",
                i - 1,
                c_string(template.id.text),
                c_string(template.family.id.text),
                c_string(asdl.class_basename(template.extraction)),
                c_string(signature_frame_scalar_for_c(template)),
                m.text_name,
                template.text.bytes.size,
                template.text.alignment,
                m.sym_name,
                m.sym_count,
                m.reloc_name,
                m.reloc_count,
                m.hole_name,
                m.hole_count,
                m.ordinal_name,
                m.ordinal_count,
                m.pool_name,
                m.pool_count,
                template.constant_pool_layout.size,
                template.constant_pool_layout.alignment
            )
        end
        out[#out + 1] = "};"
        out[#out + 1] = ""
    end

    local selector_rows = sorted_selector_rows(bank)
    local selector_array_name = "NULL"
    if #selector_rows > 0 then
        selector_array_name = "lalin_native_template_selectors"
        out[#out + 1] = "static const LalinNativeTemplateSelectorEntry lalin_native_template_selectors[] = {"
        for _, row in ipairs(selector_rows) do
            out[#out + 1] = string.format(
                "  { %s, %s, %u },",
                c_string(row.target_id),
                c_string(row.family_id),
                row.ordinal
            )
        end
        out[#out + 1] = "};"
        out[#out + 1] = ""
    end

    out[#out + 1] = "static const LalinNativeBankArtifact lalin_native_bank = {"
    out[#out + 1] = "  " .. c_string(bank.id.text) .. ","
    out[#out + 1] = "  " .. c_string(bank.target.id.text) .. ","
    out[#out + 1] = "  " .. c_string(bank.artifact.api_symbol) .. ","
    out[#out + 1] = "  " .. c_string(bank.artifact.selector_symbol) .. ","
    out[#out + 1] = "  " .. c_string(bank.artifact.installer_symbol) .. ","
    out[#out + 1] = "  " .. template_array_name .. ","
    out[#out + 1] = "  " .. tostring(#bank.templates) .. ","
    out[#out + 1] = "  " .. selector_array_name .. ","
    out[#out + 1] = "  " .. tostring(#selector_rows) .. ","
    out[#out + 1] = "  " .. tostring(request.manifest.total_count)
    out[#out + 1] = "};"
    out[#out + 1] = ""
    out[#out + 1] = [[const LalinNativeBankArtifact *lalin_native_bank_artifact(void) {
  return &lalin_native_bank;
}

const LalinNativeTemplate *lalin_native_bank_template(const LalinNativeBankArtifact *bank, size_t ordinal) {
  const LalinNativeBankArtifact *selected = bank ? bank : &lalin_native_bank;
  if (ordinal >= selected->template_count) return NULL;
  return &selected->templates[ordinal];
}

static int lalin_native_cstr_cmp(const char *a, const char *b) {
  if (a == NULL) a = "";
  if (b == NULL) b = "";
  return strcmp(a, b);
}

LalinNativeSelectionStatus lalin_native_bank_select(const LalinNativeBankArtifact *bank, const LalinNativeTemplateSelectorKey *key, LalinNativeTemplateSelection *out) {
  const LalinNativeBankArtifact *selected = bank ? bank : &lalin_native_bank;
  size_t lo = 0;
  size_t hi;
  size_t first;
  size_t count = 0;
  const char *family;
  if (out != NULL) memset(out, 0, sizeof(*out));
  if (selected == NULL || key == NULL || key->family_id == NULL) {
    if (out != NULL) out->status = LALIN_NATIVE_SELECT_INVALID;
    return LALIN_NATIVE_SELECT_INVALID;
  }
  if (key->target_id != NULL && lalin_native_cstr_cmp(key->target_id, selected->target_id) != 0) {
    if (out != NULL) out->status = LALIN_NATIVE_SELECT_TARGET_MISMATCH;
    return LALIN_NATIVE_SELECT_TARGET_MISMATCH;
  }
  family = key->family_id;
  hi = selected->selector_count;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    int cmp = lalin_native_cstr_cmp(selected->selectors[mid].family_id, family);
    if (cmp < 0) lo = mid + 1;
    else hi = mid;
  }
  first = lo;
  while (lo < selected->selector_count && lalin_native_cstr_cmp(selected->selectors[lo].family_id, family) == 0) {
    count++;
    lo++;
  }
  if (count == 0) {
    if (out != NULL) out->status = LALIN_NATIVE_SELECT_MISSING;
    return LALIN_NATIVE_SELECT_MISSING;
  }
  if (out != NULL) {
    out->matches = &selected->selectors[first];
    out->match_count = count;
  }
  if (count != 1) {
    if (out != NULL) out->status = LALIN_NATIVE_SELECT_AMBIGUOUS;
    return LALIN_NATIVE_SELECT_AMBIGUOUS;
  }
  if (out != NULL) {
    size_t ordinal = selected->selectors[first].template_ordinal;
    out->status = LALIN_NATIVE_SELECT_OK;
    out->handle.bank = selected;
    out->handle.ordinal = ordinal;
    out->handle.template_entry = lalin_native_bank_template(selected, ordinal);
  }
  return LALIN_NATIVE_SELECT_OK;
}

typedef struct LalinNativeInstallNodeLayout {
  const LalinNativeInstallNode *node;
  const LalinNativeTemplate *template_entry;
  size_t code_offset;
} LalinNativeInstallNodeLayout;

typedef struct LalinNativeInstallPoolLayout {
  const LalinNativeInstallNode *node;
  const LalinNativeConstantPoolEntry *entry;
  size_t offset;
} LalinNativeInstallPoolLayout;

static LalinNativeInstallReject lalin_native_install_last_reject;

static LalinNativeInstallResult lalin_native_install_result_reject(LalinNativeInstallStatus status, const char *node_id, const char *hole_id, const char *reason) {
  LalinNativeInstallResult result;
  memset(&result, 0, sizeof(result));
  lalin_native_install_last_reject.kind = LALIN_NATIVE_INSTALL_REJECT_GENERIC;
  lalin_native_install_last_reject.node_id = node_id;
  lalin_native_install_last_reject.to_node_id = NULL;
  lalin_native_install_last_reject.hole_id = hole_id;
  lalin_native_install_last_reject.reason = reason;
  result.status = status;
  result.rejects = &lalin_native_install_last_reject;
  result.reject_count = 1;
  return result;
}

static LalinNativeInstallResult lalin_native_install_result_fallthrough_reject(const char *from_node_id, const char *to_node_id, const char *reason) {
  LalinNativeInstallResult result;
  memset(&result, 0, sizeof(result));
  lalin_native_install_last_reject.kind = LALIN_NATIVE_INSTALL_REJECT_FALLTHROUGH_LAYOUT;
  lalin_native_install_last_reject.node_id = from_node_id;
  lalin_native_install_last_reject.to_node_id = to_node_id;
  lalin_native_install_last_reject.hole_id = NULL;
  lalin_native_install_last_reject.reason = reason;
  result.status = LALIN_NATIVE_INSTALL_REJECTED;
  result.rejects = &lalin_native_install_last_reject;
  result.reject_count = 1;
  return result;
}

static LalinNativeInstallResult lalin_native_install_result_ok(void *base_address, void *entry_address, size_t size) {
  LalinNativeInstallResult result;
  memset(&result, 0, sizeof(result));
  result.status = LALIN_NATIVE_INSTALL_OK;
  result.base_address = base_address;
  result.entry_address = entry_address;
  result.size = size;
  return result;
}

static size_t lalin_native_align_up(size_t offset, size_t alignment) {
  size_t rem;
  if (alignment <= 1) return offset;
  rem = offset % alignment;
  if (rem == 0) return offset;
  return offset + (alignment - rem);
}

static void lalin_native_write_u32(void *address, uint32_t value) {
  unsigned char *p = (unsigned char *)address;
  p[0] = (unsigned char)(value & 0xffu);
  p[1] = (unsigned char)((value >> 8) & 0xffu);
  p[2] = (unsigned char)((value >> 16) & 0xffu);
  p[3] = (unsigned char)((value >> 24) & 0xffu);
}

static void lalin_native_write_u64(void *address, uint64_t value) {
  unsigned char *p = (unsigned char *)address;
  p[0] = (unsigned char)(value & 0xffu);
  p[1] = (unsigned char)((value >> 8) & 0xffu);
  p[2] = (unsigned char)((value >> 16) & 0xffu);
  p[3] = (unsigned char)((value >> 24) & 0xffu);
  p[4] = (unsigned char)((value >> 32) & 0xffu);
  p[5] = (unsigned char)((value >> 40) & 0xffu);
  p[6] = (unsigned char)((value >> 48) & 0xffu);
  p[7] = (unsigned char)((value >> 56) & 0xffu);
}

static int lalin_native_apply_rel32(uint64_t patch_address, uint64_t target_address, int64_t addend) {
  int64_t delta = (int64_t)target_address + addend - (int64_t)patch_address;
  if (delta < (int64_t)-2147483648LL || delta > (int64_t)2147483647LL) return 0;
  lalin_native_write_u32((void *)(uintptr_t)patch_address, (uint32_t)(int32_t)delta);
  return 1;
}

static const LalinNativeSymbol *lalin_native_find_symbol(const LalinNativeTemplate *template_entry, const char *name) {
  size_t i;
  if (template_entry == NULL || name == NULL) return NULL;
  for (i = 0; i < template_entry->symbol_count; i++) {
    if (lalin_native_cstr_cmp(template_entry->symbols[i].name, name) == 0) return &template_entry->symbols[i];
  }
  return NULL;
}

static const LalinNativeHoleOrdinal *lalin_native_find_ordinal_by_symbol(const LalinNativeTemplate *template_entry, const char *symbol) {
  size_t i;
  if (template_entry == NULL || symbol == NULL) return NULL;
  for (i = 0; i < template_entry->hole_ordinal_count; i++) {
    if (lalin_native_cstr_cmp(template_entry->hole_ordinals[i].symbol, symbol) == 0) return &template_entry->hole_ordinals[i];
  }
  return NULL;
}

static const LalinNativePatchHole *lalin_native_find_hole_by_symbol(const LalinNativeTemplate *template_entry, const char *symbol) {
  size_t i;
  if (template_entry == NULL || symbol == NULL) return NULL;
  for (i = 0; i < template_entry->hole_count; i++) {
    if (lalin_native_cstr_cmp(template_entry->holes[i].symbol, symbol) == 0) return &template_entry->holes[i];
  }
  return NULL;
}

static const LalinNativeInstallNodeLayout *lalin_native_find_layout(const LalinNativeInstallNodeLayout *layouts, size_t count, const char *node_id) {
  size_t i;
  if (node_id == NULL) return NULL;
  for (i = 0; i < count; i++) {
    if (layouts[i].node != NULL && lalin_native_cstr_cmp(layouts[i].node->node_id, node_id) == 0) return &layouts[i];
  }
  return NULL;
}

static const LalinNativeInstallPoolLayout *lalin_native_find_pool_layout(const LalinNativeInstallPoolLayout *pools, size_t count, const LalinNativeInstallNode *node, const char *entry_id) {
  size_t i;
  if (node == NULL || entry_id == NULL) return NULL;
  for (i = 0; i < count; i++) {
    if (pools[i].node == node && pools[i].entry != NULL && lalin_native_cstr_cmp(pools[i].entry->id, entry_id) == 0) return &pools[i];
  }
  return NULL;
}

static uint64_t lalin_native_runtime_symbol_address(const LalinNativeInstallRequest *request, const char *symbol_id, int *ok) {
  size_t i;
  if (ok != NULL) *ok = 0;
  if (request == NULL || symbol_id == NULL) return 0;
  for (i = 0; i < request->runtime_symbol_count; i++) {
    if (lalin_native_cstr_cmp(request->runtime_symbols[i].symbol_id, symbol_id) == 0) {
      if (ok != NULL) *ok = 1;
      return request->runtime_symbols[i].address;
    }
  }
  return 0;
}

static uint64_t lalin_native_module_address(const LalinNativeInstallRequest *request, const char *id, int *ok) {
  size_t i;
  if (ok != NULL) *ok = 0;
  if (request == NULL || id == NULL) return 0;
  for (i = 0; i < request->module_address_count; i++) {
    if (lalin_native_cstr_cmp(request->module_addresses[i].id, id) == 0) {
      if (ok != NULL) *ok = 1;
      return request->module_addresses[i].address;
    }
  }
  return 0;
}

static const char *lalin_native_continuation_target(const LalinNativeInstallRequest *request, const char *from_node_id, const char *symbol) {
  size_t i;
  if (request == NULL || from_node_id == NULL || symbol == NULL) return NULL;
  for (i = 0; i < request->control_edge_count; i++) {
    const LalinNativeInstallControlEdge *edge = &request->control_edges[i];
    if (lalin_native_cstr_cmp(edge->from_node_id, from_node_id) != 0) continue;
    switch (edge->kind) {
      case LALIN_NATIVE_INSTALL_EDGE_LOOP_BACKEDGE:
      case LALIN_NATIVE_INSTALL_EDGE_CONTINUATION:
        if (lalin_native_cstr_cmp(edge->symbol, symbol) == 0) return edge->to_node_id;
        break;
      case LALIN_NATIVE_INSTALL_EDGE_CONDITIONAL_BRANCH:
      case LALIN_NATIVE_INSTALL_EDGE_SWITCH_STEP:
        if (lalin_native_cstr_cmp(edge->then_symbol, symbol) == 0) return edge->then_node_id;
        if (lalin_native_cstr_cmp(edge->else_symbol, symbol) == 0) return edge->else_node_id;
        break;
      case LALIN_NATIVE_INSTALL_EDGE_RUNTIME_CALL_RETURN:
        if (lalin_native_cstr_cmp(edge->return_symbol, symbol) == 0) return edge->to_node_id;
        break;
      default:
        break;
    }
  }
  return NULL;
}

static int lalin_native_binding_matches(const LalinNativeInstallBinding *binding, const LalinNativeInstallNode *node, const LalinNativePatchHole *hole, const LalinNativeHoleOrdinal *ordinal) {
  if (binding == NULL || node == NULL || hole == NULL) return 0;
  if (lalin_native_cstr_cmp(binding->node_id, node->node_id) != 0) return 0;
  if (binding->instance_id != NULL && node->instance_id != NULL && lalin_native_cstr_cmp(binding->instance_id, node->instance_id) != 0) return 0;
  if (binding->hole_id != NULL && lalin_native_cstr_cmp(binding->hole_id, hole->id) == 0) return 1;
  if (ordinal != NULL && binding->hole_ordinal_id != NULL && lalin_native_cstr_cmp(binding->hole_ordinal_id, ordinal->id) == 0) return 1;
  if (ordinal != NULL && binding->has_hole_ordinal_index && binding->hole_ordinal_index == ordinal->ordinal) return 1;
  return 0;
}

static const LalinNativeInstallBinding *lalin_native_find_binding(const LalinNativeInstallNode *node, const LalinNativeTemplate *template_entry, const LalinNativePatchHole *hole) {
  const LalinNativeHoleOrdinal *ordinal;
  const LalinNativeInstallBinding *found = NULL;
  size_t i;
  if (node == NULL || template_entry == NULL || hole == NULL) return NULL;
  ordinal = lalin_native_find_ordinal_by_symbol(template_entry, hole->symbol);
  for (i = 0; i < node->binding_count; i++) {
    if (lalin_native_binding_matches(&node->bindings[i], node, hole, ordinal)) {
      if (found != NULL) return NULL;
      found = &node->bindings[i];
    }
  }
  return found;
}

static size_t lalin_native_count_bindings(const LalinNativeInstallNode *node, const LalinNativeTemplate *template_entry, const LalinNativePatchHole *hole) {
  const LalinNativeHoleOrdinal *ordinal;
  size_t count = 0;
  size_t i;
  if (node == NULL || template_entry == NULL || hole == NULL) return 0;
  ordinal = lalin_native_find_ordinal_by_symbol(template_entry, hole->symbol);
  for (i = 0; i < node->binding_count; i++) {
    if (lalin_native_binding_matches(&node->bindings[i], node, hole, ordinal)) count++;
  }
  return count;
}

static int lalin_native_coordinate_i64(const LalinNativePatchCoordinate *coordinate, int64_t *out) {
  if (coordinate == NULL || out == NULL) return 0;
  switch (coordinate->kind) {
    case LALIN_NATIVE_COORD_IMMEDIATE_I32:
    case LALIN_NATIVE_COORD_IMMEDIATE_I64:
    case LALIN_NATIVE_COORD_FIELD_OFFSET:
    case LALIN_NATIVE_COORD_COMPONENT_INDEX:
    case LALIN_NATIVE_COORD_STRIDE:
    case LALIN_NATIVE_COORD_WINDOW_OFFSET:
    case LALIN_NATIVE_COORD_FRAME_OFFSET:
    case LALIN_NATIVE_COORD_FRAME_SIZE:
      *out = coordinate->signed_value;
      return 1;
    case LALIN_NATIVE_COORD_POINTER64:
      *out = (int64_t)coordinate->unsigned_value;
      return 1;
    case LALIN_NATIVE_COORD_SCALAR_CONST:
      if (coordinate->bytes == NULL || coordinate->byte_size == 0 || coordinate->byte_size > 8) return 0;
      *out = 0;
      {
        size_t i;
        for (i = 0; i < coordinate->byte_size; i++) *out |= ((int64_t)coordinate->bytes[i]) << (8 * i);
      }
      return 1;
    default:
      return 0;
  }
}

static int lalin_native_coordinate_address(const LalinNativePatchCoordinate *coordinate, const LalinNativeInstallRequest *request, const LalinNativeInstallNodeLayout *layouts, size_t layout_count, const LalinNativeInstallPoolLayout *pools, size_t pool_count, const LalinNativeInstallNode *node, uint64_t base, uint64_t *out) {
  const LalinNativeInstallNodeLayout *target_layout;
  const LalinNativeInstallPoolLayout *pool_layout;
  int ok = 0;
  if (coordinate == NULL || out == NULL) return 0;
  switch (coordinate->kind) {
    case LALIN_NATIVE_COORD_POINTER64:
      *out = coordinate->unsigned_value;
      return 1;
    case LALIN_NATIVE_COORD_BRANCH_TARGET:
      target_layout = lalin_native_find_layout(layouts, layout_count, coordinate->primary_id);
      if (target_layout == NULL) return 0;
      *out = base + target_layout->code_offset;
      return 1;
    case LALIN_NATIVE_COORD_CALL_TARGET:
      *out = lalin_native_runtime_symbol_address(request, coordinate->primary_id, &ok);
      return ok;
    case LALIN_NATIVE_COORD_CODE_DATA_ADDRESS:
    case LALIN_NATIVE_COORD_CODE_GLOBAL_ADDRESS:
    case LALIN_NATIVE_COORD_CODE_FUNC_ADDRESS:
    case LALIN_NATIVE_COORD_CODE_EXTERN_ADDRESS:
    case LALIN_NATIVE_COORD_MODULE_ADDRESS:
      *out = lalin_native_module_address(request, coordinate->primary_id, &ok);
      return ok;
    case LALIN_NATIVE_COORD_CONSTANT_POOL_ENTRY:
      pool_layout = lalin_native_find_pool_layout(pools, pool_count, node, coordinate->primary_id);
      if (pool_layout == NULL) return 0;
      *out = base + pool_layout->offset;
      return 1;
    default:
      return 0;
  }
}

static const char *lalin_native_apply_coordinate_patch(uint64_t patch_address, LalinNativePatchFormulaKind formula, LalinNativePatchHoleKind hole_kind, const LalinNativePatchCoordinate *coordinate, const LalinNativeInstallRequest *request, const LalinNativeInstallNodeLayout *layouts, size_t layout_count, const LalinNativeInstallPoolLayout *pools, size_t pool_count, const LalinNativeInstallNode *node, uint64_t base, int64_t addend) {
  uint64_t address_value = 0;
  int64_t scalar_value = 0;
  if (formula == LALIN_NATIVE_PATCH_FORMULA_PCREL32) {
    if (!lalin_native_coordinate_address(coordinate, request, layouts, layout_count, pools, pool_count, node, base, &address_value)) return "coordinate does not resolve to a relative target address";
    if (!lalin_native_apply_rel32(patch_address, address_value, addend)) return "relative patch target is out of range";
    return NULL;
  }
  if (formula == LALIN_NATIVE_PATCH_FORMULA_SYM64) {
    if (!lalin_native_coordinate_address(coordinate, request, layouts, layout_count, pools, pool_count, node, base, &address_value)) {
      if (!lalin_native_coordinate_i64(coordinate, &scalar_value)) return "coordinate does not resolve to a 64-bit value";
      address_value = (uint64_t)(scalar_value + addend);
    } else {
      address_value = (uint64_t)((int64_t)address_value + addend);
    }
    lalin_native_write_u64((void *)(uintptr_t)patch_address, address_value);
    return NULL;
  }
  if (formula == LALIN_NATIVE_PATCH_FORMULA_SYM32) {
    if (!lalin_native_coordinate_address(coordinate, request, layouts, layout_count, pools, pool_count, node, base, &address_value)) {
      if (!lalin_native_coordinate_i64(coordinate, &scalar_value)) return "coordinate does not resolve to a 32-bit value";
      address_value = (uint64_t)(scalar_value + addend);
    } else {
      address_value = (uint64_t)((int64_t)address_value + addend);
    }
    if (address_value > 4294967295ULL) return "32-bit patch value is out of range";
    lalin_native_write_u32((void *)(uintptr_t)patch_address, (uint32_t)address_value);
    return NULL;
  }

  switch (hole_kind) {
    case LALIN_NATIVE_PATCH_HOLE_IMM32:
    case LALIN_NATIVE_PATCH_HOLE_FIELD_OFFSET32:
    case LALIN_NATIVE_PATCH_HOLE_COMPONENT_INDEX32:
    case LALIN_NATIVE_PATCH_HOLE_STRIDE32:
    case LALIN_NATIVE_PATCH_HOLE_FRAME_OFFSET32:
    case LALIN_NATIVE_PATCH_HOLE_FRAME_SIZE32:
      if (!lalin_native_coordinate_i64(coordinate, &scalar_value)) return "coordinate does not resolve to a signed 32-bit patch value";
      scalar_value += addend;
      if (scalar_value < (int64_t)-2147483648LL || scalar_value > (int64_t)2147483647LL) return "signed 32-bit patch value is out of range";
      lalin_native_write_u32((void *)(uintptr_t)patch_address, (uint32_t)(int32_t)scalar_value);
      return NULL;
    case LALIN_NATIVE_PATCH_HOLE_IMM64:
      if (!lalin_native_coordinate_i64(coordinate, &scalar_value)) return "coordinate does not resolve to a signed 64-bit patch value";
      lalin_native_write_u64((void *)(uintptr_t)patch_address, (uint64_t)(scalar_value + addend));
      return NULL;
    case LALIN_NATIVE_PATCH_HOLE_PTR64:
      if (!lalin_native_coordinate_address(coordinate, request, layouts, layout_count, pools, pool_count, node, base, &address_value)) return "coordinate does not resolve to a pointer patch value";
      lalin_native_write_u64((void *)(uintptr_t)patch_address, (uint64_t)((int64_t)address_value + addend));
      return NULL;
    case LALIN_NATIVE_PATCH_HOLE_REL32:
    case LALIN_NATIVE_PATCH_HOLE_BRANCH_REL32:
    case LALIN_NATIVE_PATCH_HOLE_CALL_REL32:
      if (!lalin_native_coordinate_address(coordinate, request, layouts, layout_count, pools, pool_count, node, base, &address_value)) return "coordinate does not resolve to a relative patch target";
      if (!lalin_native_apply_rel32(patch_address, address_value, addend)) return "relative patch target is out of range";
      return NULL;
    default:
      return "unsupported patch hole kind";
  }
}

static LalinNativeInstallResult lalin_native_validate_fallthrough_layout(const LalinNativeInstallRequest *request, const LalinNativeInstallNodeLayout *layouts, size_t layout_count) {
  size_t i;
  if (request == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "invalid fallthrough validation request");
  for (i = 0; i < request->control_edge_count; i++) {
    const LalinNativeInstallControlEdge *edge = &request->control_edges[i];
    const LalinNativeInstallNodeLayout *from_layout;
    const LalinNativeInstallNodeLayout *to_layout;
    size_t expected;
    if (edge->kind != LALIN_NATIVE_INSTALL_EDGE_FALLTHROUGH) continue;
    from_layout = lalin_native_find_layout(layouts, layout_count, edge->from_node_id);
    to_layout = lalin_native_find_layout(layouts, layout_count, edge->to_node_id);
    if (from_layout == NULL || to_layout == NULL) return lalin_native_install_result_fallthrough_reject(edge->from_node_id, edge->to_node_id, "fallthrough endpoint is missing");
    if (lalin_native_cstr_cmp(from_layout->template_entry->extraction_kind, "NativeExtractFallthroughFragment") != 0) return lalin_native_install_result_fallthrough_reject(edge->from_node_id, edge->to_node_id, "fallthrough source template is not fallthrough-extractable");
    expected = from_layout->code_offset + from_layout->template_entry->text_size;
    if (to_layout->code_offset != expected) return lalin_native_install_result_fallthrough_reject(edge->from_node_id, edge->to_node_id, "fallthrough successor is not adjacent in executable layout");
  }
  return lalin_native_install_result_ok(NULL, NULL, 0);
}

static LalinNativeInstallResult lalin_native_apply_relocation(const LalinNativeInstallRequest *request, const LalinNativeInstallNodeLayout *layouts, size_t layout_count, const LalinNativeInstallPoolLayout *pools, size_t pool_count, const LalinNativeInstallNodeLayout *layout, const LalinNativeRelocation *relocation, uint64_t base) {
  const LalinNativeSymbol *symbol;
  const LalinNativeInstallNodeLayout *target_layout;
  const LalinNativeInstallPoolLayout *pool_layout;
  const LalinNativePatchHole *hole;
  const LalinNativeHoleOrdinal *ordinal;
  const LalinNativeInstallBinding *binding;
  const char *target_node_id;
  const char *patch_error;
  uint64_t patch_address;
  uint64_t target_address;
  int ok = 0;
  if (layout == NULL || layout->template_entry == NULL || relocation == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "invalid relocation input");
  patch_address = base + layout->code_offset + relocation->offset;
  switch (relocation->kind) {
    case LALIN_NATIVE_RELOC_CONTINUATION:
      if (relocation->offset + 4 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "continuation relocation is out of node text range");
      target_node_id = lalin_native_continuation_target(request, layout->node->node_id, relocation->symbol);
      target_layout = lalin_native_find_layout(layouts, layout_count, target_node_id);
      if (target_layout == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "missing continuation target");
      if (!lalin_native_apply_rel32(patch_address, base + target_layout->code_offset, relocation->addend)) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "continuation target is out of range");
      return lalin_native_install_result_ok(NULL, NULL, 0);
    case LALIN_NATIVE_RELOC_REL32:
      if (relocation->offset + 4 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "rel32 relocation is out of node text range");
      symbol = lalin_native_find_symbol(layout->template_entry, relocation->symbol);
      if (symbol == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "missing local rel32 symbol");
      if (!lalin_native_apply_rel32(patch_address, base + layout->code_offset + symbol->offset, relocation->addend)) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "local rel32 target is out of range");
      return lalin_native_install_result_ok(NULL, NULL, 0);
    case LALIN_NATIVE_RELOC_ABS64:
      if (relocation->offset + 8 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "abs64 relocation is out of node text range");
      symbol = lalin_native_find_symbol(layout->template_entry, relocation->symbol);
      if (symbol == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "missing local abs64 symbol");
      lalin_native_write_u64((void *)(uintptr_t)patch_address, base + layout->code_offset + symbol->offset + (uint64_t)relocation->addend);
      return lalin_native_install_result_ok(NULL, NULL, 0);
    case LALIN_NATIVE_RELOC_RUNTIME_SYMBOL:
      if (relocation->offset + 4 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "runtime-symbol relocation is out of node text range");
      target_address = lalin_native_runtime_symbol_address(request, relocation->symbol, &ok);
      if (!ok) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "runtime symbol address is missing");
      if (!lalin_native_apply_rel32(patch_address, target_address, relocation->addend)) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "runtime symbol target is out of range");
      return lalin_native_install_result_ok(NULL, NULL, 0);
    case LALIN_NATIVE_RELOC_CONSTANT_POOL:
      pool_layout = lalin_native_find_pool_layout(pools, pool_count, layout->node, relocation->symbol);
      if (pool_layout == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "missing constant-pool entry");
      if (relocation->formula == LALIN_NATIVE_PATCH_FORMULA_SYM64) {
        if (relocation->offset + 8 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "constant-pool relocation is out of node text range");
        lalin_native_write_u64((void *)(uintptr_t)patch_address, base + pool_layout->offset + (uint64_t)relocation->addend);
      } else if (relocation->formula == LALIN_NATIVE_PATCH_FORMULA_SYM32) {
        target_address = base + pool_layout->offset + (uint64_t)relocation->addend;
        if (relocation->offset + 4 > layout->template_entry->text_size || target_address > 4294967295ULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "constant-pool 32-bit relocation is out of range");
        lalin_native_write_u32((void *)(uintptr_t)patch_address, (uint32_t)target_address);
      } else if (relocation->formula == LALIN_NATIVE_PATCH_FORMULA_PCREL32) {
        if (relocation->offset + 4 > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "constant-pool relocation is out of node text range");
        if (!lalin_native_apply_rel32(patch_address, base + pool_layout->offset, relocation->addend)) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "constant-pool rel32 target is out of range");
      } else {
        return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "unsupported constant-pool relocation formula");
      }
      return lalin_native_install_result_ok(NULL, NULL, 0);
    case LALIN_NATIVE_RELOC_HOLE_ORDINAL:
      ordinal = lalin_native_find_ordinal_by_symbol(layout->template_entry, relocation->symbol);
      hole = lalin_native_find_hole_by_symbol(layout->template_entry, relocation->symbol);
      if (ordinal == NULL || hole == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "missing hole ordinal layout");
      if (relocation->offset + hole->width > layout->template_entry->text_size) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, hole->id, "hole ordinal relocation is out of node text range");
      binding = lalin_native_find_binding(layout->node, layout->template_entry, hole);
      if (binding == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, hole->id, "missing or duplicate binding");
      patch_error = lalin_native_apply_coordinate_patch(patch_address, relocation->formula, hole->hole_kind, &binding->coordinate, request, layouts, layout_count, pools, pool_count, layout->node, base, relocation->addend);
      if (patch_error != NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, hole->id, patch_error);
      return lalin_native_install_result_ok(NULL, NULL, 0);
    default:
      return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layout->node->node_id, NULL, "unsupported relocation kind");
  }
}

LalinNativeInstallResult lalin_native_bank_install(const LalinNativeBankArtifact *bank, const LalinNativeInstallRequest *request) {
  const LalinNativeBankArtifact *selected = bank ? bank : &lalin_native_bank;
  LalinNativeInstallNodeLayout *layouts = NULL;
  LalinNativeInstallPoolLayout *pools = NULL;
  LalinNativeTemplateSelection selection;
  LalinNativeTemplateSelectorKey key;
  const LalinNativeInstallNodeLayout *entry_layout;
  LalinNativeInstallResult step;
  unsigned char *base;
  size_t i;
  size_t j;
  size_t pool_count = 0;
  size_t pool_index = 0;
  size_t offset = 0;
  size_t alignment = 1;
  size_t code_size;
  const char *target_id;

  if (request == NULL || request->allocate_executable == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "invalid install request");
  if (selected == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "missing bank artifact");
  target_id = request->target_id ? request->target_id : selected->target_id;
  if (lalin_native_cstr_cmp(target_id, selected->target_id) != 0) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "install target does not match bank target");
  if (request->node_count == 0) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "install plan has no nodes");

  layouts = (LalinNativeInstallNodeLayout *)calloc(request->node_count, sizeof(*layouts));
  if (layouts == NULL) return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_ALLOCATION_FAILED, NULL, NULL, "layout allocation failed");

  for (i = 0; i < request->node_count; i++) {
    const LalinNativeInstallNode *node = &request->nodes[i];
    key.target_id = node->key_target_id ? node->key_target_id : target_id;
    key.family_id = node->family_id;
    if (lalin_native_bank_select(selected, &key, &selection) != LALIN_NATIVE_SELECT_OK || selection.handle.template_entry == NULL) {
      LalinNativeInstallResult reject = lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, node->node_id, NULL, "template selection failed");
      free(layouts);
      return reject;
    }
    offset = lalin_native_align_up(offset, selection.handle.template_entry->text_alignment);
    if (selection.handle.template_entry->text_alignment > alignment) alignment = selection.handle.template_entry->text_alignment;
    layouts[i].node = node;
    layouts[i].template_entry = selection.handle.template_entry;
    layouts[i].code_offset = offset;
    offset += selection.handle.template_entry->text_size;
    pool_count += selection.handle.template_entry->constant_pool_entry_count;
  }

  step = lalin_native_validate_fallthrough_layout(request, layouts, request->node_count);
  if (step.status != LALIN_NATIVE_INSTALL_OK) {
    free(layouts);
    return step;
  }

  code_size = offset;
  if (pool_count > 0) {
    pools = (LalinNativeInstallPoolLayout *)calloc(pool_count, sizeof(*pools));
    if (pools == NULL) {
      free(layouts);
      return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_ALLOCATION_FAILED, NULL, NULL, "constant-pool layout allocation failed");
    }
  }

  for (i = 0; i < request->node_count; i++) {
    const LalinNativeTemplate *template_entry = layouts[i].template_entry;
    for (j = 0; j < template_entry->constant_pool_entry_count; j++) {
      const LalinNativeConstantPoolEntry *entry = &template_entry->constant_pool_entries[j];
      offset = lalin_native_align_up(offset, entry->alignment);
      if (entry->alignment > alignment) alignment = entry->alignment;
      pools[pool_index].node = layouts[i].node;
      pools[pool_index].entry = entry;
      pools[pool_index].offset = offset;
      pool_index++;
      offset += entry->size;
    }
  }

  for (i = 0; i < request->node_count; i++) {
    const LalinNativeTemplate *template_entry = layouts[i].template_entry;
    for (j = 0; j < template_entry->hole_count; j++) {
      size_t binding_count = lalin_native_count_bindings(layouts[i].node, template_entry, &template_entry->holes[j]);
      if (binding_count == 0) {
        LalinNativeInstallResult reject = lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layouts[i].node->node_id, template_entry->holes[j].id, "missing binding");
        free(pools);
        free(layouts);
        return reject;
      }
      if (binding_count > 1) {
        LalinNativeInstallResult reject = lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layouts[i].node->node_id, template_entry->holes[j].id, "duplicate binding");
        free(pools);
        free(layouts);
        return reject;
      }
      if (layouts[i].code_offset + template_entry->holes[j].offset + template_entry->holes[j].width > code_size) {
        LalinNativeInstallResult reject = lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layouts[i].node->node_id, template_entry->holes[j].id, "patch hole is out of code range");
        free(pools);
        free(layouts);
        return reject;
      }
    }
  }

  base = (unsigned char *)request->allocate_executable(offset, alignment, request->allocator_userdata);
  if (base == NULL) {
    free(pools);
    free(layouts);
    return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_ALLOCATION_FAILED, NULL, NULL, "executable allocation failed");
  }

  for (i = 0; i < request->node_count; i++) {
    memcpy(base + layouts[i].code_offset, layouts[i].template_entry->text, layouts[i].template_entry->text_size);
  }

  for (i = 0; i < request->node_count; i++) {
    for (j = 0; j < layouts[i].template_entry->relocation_count; j++) {
      step = lalin_native_apply_relocation(request, layouts, request->node_count, pools, pool_count, &layouts[i], &layouts[i].template_entry->relocations[j], (uint64_t)(uintptr_t)base);
      if (step.status != LALIN_NATIVE_INSTALL_OK) {
        free(pools);
        free(layouts);
        return step;
      }
    }
  }

  for (i = 0; i < pool_count; i++) {
    memcpy(base + pools[i].offset, pools[i].entry->bytes, pools[i].entry->size);
  }

  for (i = 0; i < request->node_count; i++) {
    const LalinNativeTemplate *template_entry = layouts[i].template_entry;
    for (j = 0; j < template_entry->hole_count; j++) {
      const LalinNativePatchHole *hole = &template_entry->holes[j];
      const LalinNativeInstallBinding *binding = lalin_native_find_binding(layouts[i].node, template_entry, hole);
      const char *patch_error = lalin_native_apply_coordinate_patch((uint64_t)(uintptr_t)(base + layouts[i].code_offset + hole->offset), LALIN_NATIVE_PATCH_FORMULA_NONE, hole->hole_kind, &binding->coordinate, request, layouts, request->node_count, pools, pool_count, layouts[i].node, (uint64_t)(uintptr_t)base, 0);
      if (patch_error != NULL) {
        LalinNativeInstallResult reject = lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, layouts[i].node->node_id, hole->id, patch_error);
        free(pools);
        free(layouts);
        return reject;
      }
    }
  }

  entry_layout = lalin_native_find_layout(layouts, request->node_count, request->entry_node_id ? request->entry_node_id : request->nodes[0].node_id);
  if (entry_layout == NULL) {
    free(pools);
    free(layouts);
    return lalin_native_install_result_reject(LALIN_NATIVE_INSTALL_REJECTED, NULL, NULL, "entry node is missing");
  }

  step = lalin_native_install_result_ok(base, base + entry_layout->code_offset, offset);
  free(pools);
  free(layouts);
  return step;
}
]]
    return table.concat(out, "\n")
end

local request = load_manifest(manifest_path)
local bank, build_rejected = build_native_bank(request)
if build_rejected ~= nil then
    io.stderr:write("native template bank build rejected\n")
    for _, reject in ipairs(build_rejected.rejects or {}) do
        io.stderr:write("  ", tostring(reject), "\n")
    end
    os.exit(1)
end

write_file(out_h, emit_header())
write_file(out_c, emit_source(bank, request))
write_file(out_lua, emit_lua_module(bank))
io.stderr:write(
    "C-owned native template bank ", bank.id.text,
    " with ", tostring(#bank.templates),
    " templates; Lua artifact descriptor ", out_lua,
    "\n"
)
