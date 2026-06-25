package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

local out_c = assert(arg[1], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")
local out_h = assert(arg[2], "usage: luajit tools/gen_lalin_mc_bank.lua OUT_C OUT_H")

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local LJ = T.LalinLuaJIT
local InternSet = require("lalin.copy_patch_mc_intern_set")(T)
local Bank = require("lalin.copy_patch_mc")(T)

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
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

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bytes_array(bytes)
    local out, line = {}, {}
    for i = 1, #bytes do
        line[#line + 1] = string.format("0x%02x", bytes:byte(i))
        if #line == 12 then
            out[#out + 1] = "  " .. table.concat(line, ", ") .. ","
            line = {}
        end
    end
    if #line > 0 then out[#out + 1] = "  " .. table.concat(line, ", ") .. "," end
    if #out == 0 then out[1] = "  0x00," end
    return table.concat(out, "\n")
end

local function c_string(s)
    if s == nil then return "NULL" end
    return string.format("%q", tostring(s))
end

local function patch_kind(kind)
    if kind == LJ.LJMCPatchAbs32 then return "abs32" end
    if kind == LJ.LJMCPatchAbs64 then return "abs64" end
    if kind == LJ.LJMCPatchSymbol32 then return "symbol32" end
    if kind == LJ.LJMCPatchSymbol64 then return "symbol64" end
    if kind == LJ.LJMCPatchPc32 then return "pc32" end
    if kind == LJ.LJMCPatchRel32 then return "rel32" end
    if kind == LJ.LJMCPatchLocalAbs32 then return "local_abs32" end
    if kind == LJ.LJMCPatchLocalAbs64 then return "local_abs64" end
    return tostring(kind)
end

local artifacts = InternSet.artifacts()
local mc_bank, err, source = Bank.build_mc_bank(artifacts, {
    stem = "lalin_embedded_mc_bank",
    dir = "target/lalin_binary/mc_bank_build",
    preamble = InternSet.preamble(),
})
if mc_bank == nil then error(tostring(err) .. "\n" .. tostring(source)) end

local h = {
    "#ifndef LALIN_EMBEDDED_MC_BANK_H",
    "#define LALIN_EMBEDDED_MC_BANK_H",
    "",
    "#include <stddef.h>",
    "#include \"lua.h\"",
    "",
    "typedef struct LalinEmbeddedMCPatch {",
    "  size_t offset;",
    "  const char *kind;",
    "  const char *reloc_type;",
    "  const char *symbol;",
    "  int ordinal;",
    "  long long addend;",
    "} LalinEmbeddedMCPatch;",
    "",
    "typedef struct LalinEmbeddedMCEntry {",
    "  const char *symbol;",
    "  const char *c_signature;",
    "  const unsigned char *data;",
    "  size_t size;",
    "  const LalinEmbeddedMCPatch *patches;",
    "  size_t patch_count;",
    "} LalinEmbeddedMCEntry;",
    "",
    "const LalinEmbeddedMCEntry *lalin_embedded_mc_bank(void);",
    "size_t lalin_embedded_mc_bank_count(void);",
    "int lalin_install_embedded_mc_bank(lua_State *L);",
    "",
    "#endif",
    "",
}

local c = {
    "#include <stddef.h>",
    "#include \"lua.h\"",
    "#include \"lalin_embedded_mc_bank.h\"",
    "",
}

for _, entry in ipairs(mc_bank.entries or {}) do
    local sym = "lalin_mc_" .. sanitize(entry.symbol)
    c[#c + 1] = "static const unsigned char " .. sym .. "_bytes[] = {"
    c[#c + 1] = bytes_array(entry.binary)
    c[#c + 1] = "};"
    c[#c + 1] = "static const LalinEmbeddedMCPatch " .. sym .. "_patches[] = {"
    for _, patch in ipairs(entry.patches or {}) do
        c[#c + 1] = string.format(
            "  { %d, %s, %s, %s, %d, %d },",
            tonumber(patch.offset) or 0,
            c_string(patch_kind(patch.kind)),
            c_string(patch.reloc_type),
            c_string(patch.symbol),
            tonumber(patch.ordinal) or -1,
            tonumber(patch.addend) or 0
        )
    end
    c[#c + 1] = "};"
    c[#c + 1] = ""
end

c[#c + 1] = "static const LalinEmbeddedMCEntry lalin_mc_entries[] = {"
for _, entry in ipairs(mc_bank.entries or {}) do
    local sym = "lalin_mc_" .. sanitize(entry.symbol)
    c[#c + 1] = string.format(
        "  { %s, %s, %s_bytes, sizeof(%s_bytes), %s_patches, sizeof(%s_patches) / sizeof(%s_patches[0]) },",
        c_string(entry.symbol),
        c_string(entry.c_signature),
        sym,
        sym,
        sym,
        sym,
        sym
    )
end
c[#c + 1] = "  { NULL, NULL, NULL, 0, NULL, 0 },"
c[#c + 1] = "};"
c[#c + 1] = ""
c[#c + 1] = "const LalinEmbeddedMCEntry *lalin_embedded_mc_bank(void) {"
c[#c + 1] = "  return lalin_mc_entries;"
c[#c + 1] = "}"
c[#c + 1] = ""
c[#c + 1] = "size_t lalin_embedded_mc_bank_count(void) {"
c[#c + 1] = "  return " .. tostring(#(mc_bank.entries or {})) .. ";"
c[#c + 1] = "}"
c[#c + 1] = ""
c[#c + 1] = "int lalin_install_embedded_mc_bank(lua_State *L) {"
c[#c + 1] = "  lua_pushinteger(L, (lua_Integer)lalin_embedded_mc_bank_count());"
c[#c + 1] = "  lua_setfield(L, LUA_REGISTRYINDEX, \"lalin.embedded_mc_bank.count\");"
c[#c + 1] = "  return 0;"
c[#c + 1] = "}"
c[#c + 1] = ""

write_file(out_h, table.concat(h, "\n"))
write_file(out_c, table.concat(c, "\n"))
io.stderr:write("embedded ", tostring(#(mc_bank.entries or {})), " Lalin MC bank entries\n")
