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
    "  READELF                    readelf binary (default: readelf)",
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

local function parse_int(s)
    if s == nil then return 0 end
    s = tostring(s)
    local sign = 1
    if s:sub(1, 1) == "-" then sign = -1; s = s:sub(2) end
    if s:match("^0x") or s:match("^0X") then return sign * tonumber(s) end
    if s:match("^[0-9a-fA-F]+$") and s:match("[a-fA-F]") then return sign * tonumber(s, 16) end
    return sign * (tonumber(s) or 0)
end

local function parse_reloc_addend(s)
    if s == nil then return 0 end
    s = tostring(s)
    local sign = 1
    if s:sub(1, 1) == "-" then sign = -1; s = s:sub(2) end
    if s:match("^0x") or s:match("^0X") then return sign * tonumber(s) end
    return sign * (tonumber(s, 16) or tonumber(s) or 0)
end

local function parse_sections(readelf_output)
    local by_index = {}
    local by_name = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local idx, name, typ, _addr, off, size, _es, flags, _link, _info, align =
            line:match("^%s*%[%s*(%d+)%]%s+(%S+)%s+(%S+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+)%s+(%S*)%s+(%d+)%s+(%d+)%s+(%d+)%s*$")
        if idx ~= nil and name ~= "" then
            local section = {
                index = tonumber(idx),
                name = name,
                typ = typ,
                offset = tonumber(off, 16) or 0,
                size = tonumber(size, 16) or 0,
                flags = flags or "",
                align = tonumber(align) or 1,
            }
            by_index[section.index] = section
            by_name[section.name] = section
        end
    end
    return by_index, by_name
end

local function parse_symbols(readelf_output, sections)
    local by_name = {}
    local order = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local _num, value, size, typ, bind, _vis, ndx, name =
            line:match("^%s*(%d+):%s+([0-9a-fA-F]+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)%s*$")
        if name ~= nil and name ~= "" and ndx:match("^%d+$") then
            local section = sections[tonumber(ndx)]
            local sym = {
                name = name,
                value = tonumber(value, 16) or 0,
                size = tonumber(size) or 0,
                typ = typ,
                bind = bind,
                section_index = tonumber(ndx),
                section = section and section.name or nil,
                section_flags = section and section.flags or "",
                section_align = section and section.align or 1,
            }
            by_name[name] = sym
            order[#order + 1] = sym
        end
    end
    return by_name, order
end

local function parse_relocations(readelf_output)
    local current
    local by_section = {}
    for line in tostring(readelf_output or ""):gmatch("[^\n]+") do
        local sec = line:match("Relocation section '([^']+)'")
        if sec ~= nil then
            current = sec
            by_section[current] = by_section[current] or {}
        else
            local off, typ, rest = line:match("^%s*([0-9a-fA-F]+)%s+[%x]+%s+(R_%S+)%s*(.*)$")
            if current ~= nil and off ~= nil then
                local fields = {}
                for f in tostring(rest or ""):gmatch("%S+") do fields[#fields + 1] = f end
                local symbol, addend = nil, 0
                if fields[1] ~= nil and fields[1]:match("^[0-9a-fA-F]+$") and fields[2] ~= nil then
                    symbol = fields[2]
                    if fields[3] == "+" or fields[3] == "-" then
                        addend = (fields[3] == "-" and -1 or 1) * parse_reloc_addend(fields[4])
                    end
                elseif fields[1] ~= nil then
                    symbol = fields[1]
                    if fields[2] == "+" or fields[2] == "-" then
                        addend = (fields[2] == "-" and -1 or 1) * parse_reloc_addend(fields[3])
                    end
                end
                if symbol == "0" or symbol == "0000000000000000" then symbol = nil end
                by_section[current][#by_section[current] + 1] = {
                    offset = tonumber(off, 16) or 0,
                    reloc_type = typ,
                    symbol = symbol,
                    addend = addend or 0,
                    raw = line,
                }
            end
        end
    end
    return by_section
end

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Support = require("lalin.native_template_support")(T)

local function native_bank_id()
    return os.getenv("LALIN_NATIVE_BANK_ID") or "lalin.native.empty"
end

local function empty_request()
    return Native.NativeTemplateBankRequest(
        Native.NativeBankId(native_bank_id()),
        Support.host_target(),
        Support.empty_runtime(),
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

local function text_section_relocations(relocs_by_section, text_section)
    return relocs_by_section[".rela" .. text_section] or relocs_by_section[".rel" .. text_section] or {}
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

local function continuation_symbol_index(source)
    local by_name = {}
    for _, sym in ipairs(source.extraction:native_continuation_symbols()) do
        by_name[sym.name] = sym
        by_name[sym.id.text] = sym
    end
    return by_name
end

local function native_relocation_for(source, raw, text_section, symbols, sections_by_name, runtime_symbols, continuation_symbols)
    local sym_name = raw.symbol
    if sym_name == nil or sym_name == "" then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            raw.offset,
            raw.reloc_type,
            "relocation has no symbol"
        )
    end

    local sym = symbols[sym_name]
    if sym ~= nil and sym.section ~= nil and sym.section ~= text_section and sym.section ~= "UND" then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            raw.offset,
            raw.reloc_type,
            "local cross-section relocation to " .. tostring(sym.section) .. " is not supported"
        )
    end
    local section = sections_by_name[sym_name]
    if section ~= nil and section.name ~= text_section then
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            raw.offset,
            raw.reloc_type,
            "section relocation to " .. tostring(section.name) .. " is not supported"
        )
    end

    local continuation_symbol = continuation_symbols[sym_name]
    if continuation_symbol ~= nil then
        if raw.reloc_type == "R_X86_64_PC32" or raw.reloc_type == "R_X86_64_PLT32" then
            return Native.NativeRelocationContinuation(raw.offset, continuation_symbol, raw.addend or 0)
        end
        return nil, Native.NativeBuildRejectUnsupportedRelocation(
            source.id,
            raw.offset,
            raw.reloc_type,
            "continuation relocation must be PC-relative"
        )
    end

    local runtime_id = runtime_symbols[sym_name]
    if runtime_id ~= nil then
        return Native.NativeRelocationRuntimeSymbol(raw.offset, runtime_id, raw.addend or 0)
    end

    if sym == nil then
        return nil, Native.NativeBuildRejectUnexpectedSymbol(
            source.id,
            sym_name,
            "unresolved symbol is not a declared continuation or runtime symbol"
        )
    end

    if raw.reloc_type == "R_X86_64_PC32" or raw.reloc_type == "R_X86_64_PLT32" then
        return Native.NativeRelocationRel32(raw.offset, sym_name, raw.addend or 0)
    end
    if raw.reloc_type == "R_X86_64_64" then
        return Native.NativeRelocationAbs64(raw.offset, sym_name, raw.addend or 0)
    end

    return nil, Native.NativeBuildRejectUnsupportedRelocation(
        source.id,
        raw.offset,
        raw.reloc_type,
        "unsupported relocation type for NativeEmbeddedTemplateBank"
    )
end

local function marker_bytes(marker, width)
    local s = tostring(marker or ""):gsub("[uUlL]+$", "")
    if s:match("^0x") or s:match("^0X") then
        local hex = s:gsub("^0[xX]", "")
        if #hex % 2 == 1 then hex = "0" .. hex end
        local bytes = {}
        for i = #hex - 1, 1, -2 do
            bytes[#bytes + 1] = string.char(tonumber(hex:sub(i, i + 1), 16) or 0)
        end
        while #bytes < width do bytes[#bytes + 1] = string.char(0) end
        if #bytes > width then
            local trimmed = {}
            for i = 1, width do trimmed[i] = bytes[i] end
            bytes = trimmed
        end
        return table.concat(bytes)
    end
    local n = tonumber(s)
    if n == nil then return nil end
    local out = {}
    for _ = 1, width do
        out[#out + 1] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(out)
end

local function find_unique_marker(text_bytes, marker, width)
    local needle = marker_bytes(marker, width)
    if needle == nil then return nil, 0 end
    local found
    local count = 0
    local start = 1
    while true do
        local i = text_bytes:find(needle, start, true)
        if i == nil then break end
        count = count + 1
        found = i - 1
        start = i + 1
    end
    return found, count
end

local function resolve_declared_holes(source, text_bytes)
    local holes = {}
    local rejects = {}
    for _, hole in ipairs(source.declared_holes or {}) do
        local offset = hole.offset
        if offset < 0 then
            local found, count = find_unique_marker(text_bytes, hole.symbol, hole.width)
            if count == 1 then
                offset = found
            elseif count == 0 then
                rejects[#rejects + 1] = Native.NativeBuildRejectMissingHole(source.id, hole.id, hole.symbol)
            else
                rejects[#rejects + 1] = Native.NativeBuildRejectRoleMismatch(
                    source.id,
                    "hole marker " .. tostring(hole.symbol) .. " appears " .. tostring(count) .. " times"
                )
            end
        end
        if offset >= 0 then
            if offset + hole.width > #text_bytes then
                rejects[#rejects + 1] = Native.NativeBuildRejectHoleOutOfRange(source.id, hole.id, offset, hole.width)
            else
                holes[#holes + 1] = Native.NativeHoleLayout(hole.id, hole.symbol, offset, hole.width, hole.hole)
            end
        end
    end
    return holes, rejects
end

local function compile_source(source, request, build_dir, index)
    local rejects = {}
    if source.c_text == "" then
        return nil, { Native.NativeBuildRejectEmptySource(source.id, "empty native template source") }
    end

    local stem = string.format("%03d_%s", index, c_identifier(source.id.text or source.entry_symbol))
    local source_path = build_dir .. "/" .. stem .. source_extension(source)
    local object_path = build_dir .. "/" .. stem .. ".o"
    write_file(source_path, source.c_text)

    local cc = os.getenv("CC") or "gcc"
    local cmd = table.concat({ shell_quote(cc), source_flags(source), shell_quote(source_path), "-o", shell_quote(object_path) }, " ")
    if not os_execute(cmd) then
        return nil, { Native.NativeBuildRejectCompileError(source.id, "native template object build failed: " .. cmd) }
    end

    local readelf = os.getenv("READELF") or "readelf"
    local section_out, section_err = capture(shell_quote(readelf) .. " -SW " .. shell_quote(object_path))
    if section_out == nil then
        return nil, { Native.NativeBuildRejectCompileError(source.id, "readelf sections failed: " .. tostring(section_err)) }
    end
    local sections, sections_by_name = parse_sections(section_out)

    local symbol_out, symbol_err = capture(shell_quote(readelf) .. " -Ws " .. shell_quote(object_path))
    if symbol_out == nil then
        return nil, { Native.NativeBuildRejectCompileError(source.id, "readelf symbols failed: " .. tostring(symbol_err)) }
    end
    local symbols, symbol_order = parse_symbols(symbol_out, sections)
    local entry_symbol = symbols[source.entry_symbol]
    if entry_symbol == nil or entry_symbol.section == nil or entry_symbol.section == "UND" then
        return nil, { Native.NativeBuildRejectMissingEntrySymbol(source.id, source.entry_symbol) }
    end

    local text_section = entry_symbol.section
    local text_meta = sections_by_name[text_section]
    if text_meta == nil then
        return nil, { Native.NativeBuildRejectMissingEntrySymbol(source.id, source.entry_symbol) }
    end

    local object_bytes = read_file(object_path)
    local text_bytes = object_bytes:sub(text_meta.offset + 1, text_meta.offset + text_meta.size)
    if #text_bytes == 0 then
        return nil, { Native.NativeBuildRejectEmptyText(source.id, "entry symbol text section is empty") }
    end

    local symbol_entries = {}
    for _, sym in ipairs(symbol_order) do
        if sym.section == text_section and sym.name ~= "" then
            symbol_entries[#symbol_entries + 1] = Native.NativeSymbol(sym.name, sym.value or 0, sym.size or 0)
        end
    end

    local reloc_out, reloc_err = capture(shell_quote(readelf) .. " -Wr " .. shell_quote(object_path))
    if reloc_out == nil then
        return nil, { Native.NativeBuildRejectCompileError(source.id, "readelf relocations failed: " .. tostring(reloc_err)) }
    end
    local raw_relocs = text_section_relocations(parse_relocations(reloc_out), text_section)
    local runtime_symbols = runtime_symbol_index(request.runtime)
    local continuation_symbols = continuation_symbol_index(source)
    local seen_continuations = {}
    local relocations = {}
    for _, raw in ipairs(raw_relocs) do
        local relocation, reject = native_relocation_for(source, raw, text_section, symbols, sections_by_name, runtime_symbols, continuation_symbols)
        if reject ~= nil then rejects[#rejects + 1] = reject
        else
            if asdl.isa(relocation, Native.NativeRelocationContinuation) then
                seen_continuations[relocation.symbol.name] = true
            end
            relocations[#relocations + 1] = relocation
        end
    end

    for _, cont in ipairs(source.extraction:native_continuation_symbols()) do
        if not seen_continuations[cont.name] then
            rejects[#rejects + 1] = Native.NativeBuildRejectUnexpectedSymbol(
                source.id,
                cont.name,
                "declared continuation symbol has no relocation in compiled object"
            )
        end
    end

    local holes, hole_rejects = resolve_declared_holes(source, text_bytes)
    for _, reject in ipairs(hole_rejects) do rejects[#rejects + 1] = reject end

    if #rejects > 0 then return nil, rejects end

    return Native.NativeEmbeddedTemplate(
        source.family,
        Native.NativeTextSection(Native.NativeTemplateBytes(text_bytes, #text_bytes), text_meta.align or 1),
        symbol_entries,
        relocations,
        holes
    ), nil
end

local function build_embedded_bank(request)
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
    return Native.NativeEmbeddedTemplateBank(request.id, request.target, entries), nil
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
    return relocation.symbol
end

local function relocation_kind_for_c(relocation)
    if asdl.isa(relocation, Native.NativeRelocationRel32) then return "rel32" end
    if asdl.isa(relocation, Native.NativeRelocationAbs64) then return "abs64" end
    if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then return "runtime_symbol" end
    if asdl.isa(relocation, Native.NativeRelocationContinuation) then return "continuation" end
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
        "  const unsigned char *text;",
        "  size_t text_size;",
        "  size_t text_alignment;",
        "  const LalinNativeEmbeddedSymbol *symbols;",
        "  size_t symbol_count;",
        "  const LalinNativeEmbeddedRelocation *relocations;",
        "  size_t relocation_count;",
        "  const LalinNativeEmbeddedPatchHole *holes;",
        "  size_t hole_count;",
        "} LalinNativeEmbeddedTemplate;",
        "",
        "typedef struct LalinNativeEmbeddedTemplateBank {",
        "  const char *bank_id;",
        "  const char *target_id;",
        "  const LalinNativeEmbeddedTemplate *entries;",
        "  size_t entry_count;",
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

local function emit_source(embedded)
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
            "  { %s, %s, %u, %u, %s, %u, %s, %u, %s, %u },",
            c_string(entry.family.id.text),
            m.text_name,
            entry.text.bytes.size,
            entry.text.alignment,
            m.sym_name,
            m.sym_count,
            m.reloc_name,
            m.reloc_count,
            m.hole_name,
            m.hole_count
        )
    end
    out[#out + 1] = "  { NULL, NULL, 0, 1, NULL, 0, NULL, 0, NULL, 0 },"
    out[#out + 1] = "};"
    out[#out + 1] = ""
    out[#out + 1] = "static const LalinNativeEmbeddedTemplateBank lalin_native_bank = {"
    out[#out + 1] = "  " .. c_string(embedded.id.text) .. ","
    out[#out + 1] = "  " .. c_string(embedded.target.id.text) .. ","
    out[#out + 1] = "  lalin_native_template_entries,"
    out[#out + 1] = "  " .. tostring(#embedded.entries)
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
write_file(out_c, emit_source(embedded))
write_file(out_lua, emit_lua_module(embedded))
io.stderr:write(
    "embedded native template bank ", embedded.id.text,
    " with ", tostring(#embedded.entries),
    " templates; Lua ASDL bridge ", out_lua,
    "\n"
)
