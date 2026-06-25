package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
    package.path,
}, ";")

local out_c = assert(arg[1], "usage: luajit tools/gen_lalin_module_bank.lua OUT_C OUT_H [lua-root]")
local out_h = assert(arg[2], "usage: luajit tools/gen_lalin_module_bank.lua OUT_C OUT_H [lua-root]")
local root = arg[3] or "lua"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, text)
    mkdir_parent(path)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function sanitize(s)
    s = tostring(s):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function module_name(path)
    local rel = path:gsub("^" .. root:gsub("([^%w])", "%%%1") .. "/", ""):gsub("%.lua$", "")
    rel = rel:gsub("/init$", "")
    return rel:gsub("/", ".")
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
    return table.concat(out, "\n")
end

local function list_lua_files()
    local p = assert(io.popen("find " .. shell_quote(root) .. " -name '*.lua' | sort", "r"))
    local files = {}
    for line in p:lines() do
        files[#files + 1] = line
    end
    assert(p:close())
    return files
end

local modules = {}
for _, path in ipairs(list_lua_files()) do
    local name = module_name(path)
    local src = read_file(path)
    local chunk, err = loadstring(src, "@" .. name)
    if chunk == nil then error(path .. ": " .. tostring(err)) end
    modules[#modules + 1] = {
        name = name,
        symbol = "lalin_module_" .. sanitize(name),
        bytecode = string.dump(chunk),
    }
end

local h = {
    "#ifndef LALIN_EMBEDDED_BC_BANK_H",
    "#define LALIN_EMBEDDED_BC_BANK_H",
    "",
    "#include \"lua.h\"",
    "",
    "int lalin_install_embedded_bc_bank(lua_State *L);",
    "",
    "#endif",
    "",
}

local c = {
    "#include <stddef.h>",
    "#include \"lua.h\"",
    "#include \"lauxlib.h\"",
    "#include \"lalin_embedded_bc_bank.h\"",
    "",
    "typedef struct LalinEmbeddedBCEntry {",
    "  const char *name;",
    "  const unsigned char *data;",
    "  size_t size;",
    "} LalinEmbeddedBCEntry;",
    "",
}

for _, m in ipairs(modules) do
    c[#c + 1] = "static const unsigned char " .. m.symbol .. "[] = {"
    c[#c + 1] = bytes_array(m.bytecode)
    c[#c + 1] = "};"
    c[#c + 1] = ""
end

c[#c + 1] = "static const LalinEmbeddedBCEntry lalin_embedded_bc_bank[] = {"
for _, m in ipairs(modules) do
    c[#c + 1] = string.format("  { %q, %s, sizeof(%s) },", m.name, m.symbol, m.symbol)
end
c[#c + 1] = "  { NULL, NULL, 0 },"
c[#c + 1] = "};"
c[#c + 1] = ""
c[#c + 1] = "int lalin_install_embedded_bc_bank(lua_State *L) {"
c[#c + 1] = "  const LalinEmbeddedBCEntry *m;"
c[#c + 1] = "  lua_getglobal(L, \"package\");"
c[#c + 1] = "  lua_getfield(L, -1, \"preload\");"
c[#c + 1] = "  for (m = lalin_embedded_bc_bank; m->name != NULL; ++m) {"
c[#c + 1] = "    if (luaL_loadbuffer(L, (const char *)m->data, m->size, m->name) != 0) return lua_error(L);"
c[#c + 1] = "    lua_setfield(L, -2, m->name);"
c[#c + 1] = "  }"
c[#c + 1] = "  lua_pop(L, 2);"
c[#c + 1] = "  return 0;"
c[#c + 1] = "}"
c[#c + 1] = ""

write_file(out_h, table.concat(h, "\n"))
write_file(out_c, table.concat(c, "\n"))
io.stderr:write("embedded ", tostring(#modules), " Lalin Lua modules\n")
