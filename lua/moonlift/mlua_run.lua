-- moonlift/mlua_run.lua — .mlua runner.  Single-path, uses parse.lua directly.
--
-- A .mlua file is Lua with MoonLift islands.  The lexer (parse.lua) tokenises
-- the whole source; antiquotes @{lua_expr} become TK.hole tokens.  Islands are
-- parsed with the unified parser, holes are filled from Lua closures, and the result
-- is compiled via the normal MoonLift pipeline.

local ffi       = require("ffi")
local pvm       = require("moonlift.pvm")
local A         = require("moonlift.asdl")
local Quote     = require("moonlift.quote")
local Session   = require("moonlift.host_session")
local HostValues= require("moonlift.host_values")
local Parse     = require("moonlift.parse")

local M = {}

---------------------------------------------------------------------------
-- Runtime
---------------------------------------------------------------------------

local Runtime = {}; Runtime.__index = Runtime

local ModuleValue = {}
local module_value_mt
local module_value_state = setmetatable({}, {__mode = "k"})

local CompiledModule = {}; CompiledModule.__index = CompiledModule
local CompiledFunction = {}; CompiledFunction.__index = CompiledFunction

local FuncValue = {}; FuncValue.__index = FuncValue

local runtime_stack = {}

local function push_runtime(runtime)
    runtime_stack[#runtime_stack + 1] = runtime
    return function()
        assert(runtime_stack[#runtime_stack] == runtime, "moonlift runtime stack imbalance")
        runtime_stack[#runtime_stack] = nil
    end
end

function M.current_runtime() return runtime_stack[#runtime_stack] end
function M._push_runtime(runtime) return push_runtime(runtime) end

local function new_context()
    local T = pvm.context(); A.Define(T); return T
end

---------------------------------------------------------------------------
-- C type helpers
---------------------------------------------------------------------------

local scalar_ctype = {
    BackBool = "bool",
    BackI8 = "int8_t", BackI16 = "int16_t", BackI32 = "int32_t", BackI64 = "int64_t",
    BackU8 = "uint8_t", BackU16 = "uint16_t", BackU32 = "uint32_t", BackU64 = "uint64_t",
    BackF32 = "float", BackF64 = "double",
    BackPtr = "void *", BackIndex = "intptr_t", BackVoid = "void",
}

local function back_scalar_name(scalar)
    return tostring(scalar):match("%.([%w_]+):") or tostring(scalar):match("(Back[%w_]+)") or tostring(scalar)
end

local function ctype_of_type(T, ty)
    local Ty = T.MoonType
    if pvm.classof(ty) == Ty.TPtr then return "void *" end
    local Back = require("moonlift.type_to_back_scalar").Define(T)
    local r = Back.result(ty)
    if pvm.classof(r) ~= Ty.TypeBackScalarKnown then return "void *" end
    return assert(scalar_ctype[back_scalar_name(r.scalar)], "unsupported C type: " .. tostring(r.scalar))
end

local function c_sig_of(T, func)
    local Ty = T.MoonType
    local args = {}
    local result_is_view = pvm.classof(func.result) == Ty.TView
    if result_is_view then args[#args + 1] = "void *" end
    for i = 1, #func.params do args[#args + 1] = ctype_of_type(T, func.params[i].ty) end
    local ret = result_is_view and "void" or ctype_of_type(T, func.result)
    return ret .. " (*)(" .. table.concat(args, ", ") .. ")"
end

local function module_funcs(T, module)
    local Tr = T.MoonTree
    local out = {}
    for i = 1, #module.items do
        local item = module.items[i]
        if pvm.classof(item) == Tr.ItemFunc then
            local cls = pvm.classof(item.func)
            if cls == Tr.FuncExport or cls == Tr.FuncLocal then
                out[item.func.name] = item.func
            end
        end
    end
    return out
end

local function module_name_of(T, module)
    local Tr = T.MoonTree
    local h = module and module.h
    local cls = h and pvm.classof(h)
    if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then return h.module_name end
    if cls == Tr.ModuleOpen and h.name ~= T.MoonOpen.ModuleNameOpen then return h.name.module_name end
    return ""
end

local function func_type(T, params, result)
    local tys = {}
    for i = 1, #(params or {}) do tys[i] = params[i].ty end
    return T.MoonType.TFunc(tys, result)
end

---------------------------------------------------------------------------
-- Module values (exported fields + compile)
---------------------------------------------------------------------------

local function exported_module_fields(runtime, module, extra)
    local T = runtime.T
    local C, B, Tr = T.MoonCore, T.MoonBind, T.MoonTree
    local api = runtime.session:api()
    local mod_name = module_name_of(T, module)
    local fields = {}
    for i = 1, #module.items do
        local item = module.items[i]
        local cls = pvm.classof(item)
        if cls == Tr.ItemType then
            local t = item.t
            local name = t.name or (t.sym and t.sym.name)
            if name then
                local extra = {}
                if pvm.classof(t) == Tr.TypeDeclTaggedUnionSugar then extra.protocol_variants = t.variants end
                fields[name] = api.type_from_asdl(T.MoonType.TNamed(T.MoonType.TypeRefGlobal(mod_name, name)),
                    (mod_name ~= "" and (mod_name .. ".") or "") .. name, extra)
            end
        elseif cls == Tr.ItemConst then
            local c = item.c
            local name = c.name or (c.sym and c.sym.name)
            if name then
                fields[name] = api.expr_from_asdl(c.value, api.type_from_asdl(c.ty, name),
                    (mod_name ~= "" and (mod_name .. ".") or "") .. name)
            end
        elseif cls == Tr.ItemFunc then
            local f = item.func
            local fcls = pvm.classof(f)
            if fcls == Tr.FuncExport or fcls == Tr.FuncExportContract then
                local ty = api.type_from_asdl(func_type(T, f.params, f.result), f.name)
                local binding = B.Binding(C.Id("func:" .. mod_name .. ":" .. f.name), f.name, ty.ty,
                    B.BindingClassGlobalFunc(mod_name, f.name))
                fields[f.name] = api.expr_ref(binding, ty,
                    (mod_name ~= "" and (mod_name .. ".") or "") .. f.name)
            end
        elseif cls == Tr.ItemExtern then
            local f = item.func
            local ty = api.type_from_asdl(func_type(T, f.params, f.result), f.name)
            local binding = B.Binding(C.Id("extern:" .. f.name), f.name, ty.ty, B.BindingClassExtern(f.symbol))
            fields[f.name] = api.expr_ref(binding, ty, f.name)
        end
    end
    for k, v in pairs(extra or {}) do fields[k] = v end
    return fields
end

local function current_dep_table(runtime)
    local stack = runtime.require_stack
    if stack and #stack > 0 then return stack[#stack].deps end
    runtime.root_deps = runtime.root_deps or {}
    return runtime.root_deps
end

local function new_module_value(runtime, module, extra_fields)
    local self = setmetatable({}, module_value_mt)
    module_value_state[self] = {
        kind = "module",
        moonlift_quote_kind = "module",
        name = module_name_of(runtime.T, module),
        module = module,
        exports = exported_module_fields(runtime, module, extra_fields),
        deps = current_dep_table(runtime),
        T = runtime.T,
        runtime = runtime,
    }
    return self
end

local function module_value_index(self, key)
    local method = ModuleValue[key]
    if method ~= nil then return method end
    local state = module_value_state[self]
    if not state then return nil end
    local exports = state.exports
    if exports and exports[key] ~= nil then return exports[key] end
    if key == "kind" or key == "moonlift_quote_kind" or key == "name" or key == "module" then
        return state[key]
    end
    return nil
end

module_value_mt = {
    __index = module_value_index,
    __newindex = function(self, key) error("Moonlift module tables are sealed; cannot assign " .. tostring(key), 2) end,
    __tostring = function(self) return ModuleValue.__tostring(self) end,
    __metatable = "Moonlift module table",
}

function ModuleValue:__tostring()
    local state = module_value_state[self]
    return "MoonModuleValue(" .. tostring((state and state.name) or "<anonymous>") .. ")"
end

local function module_with_required_deps(self)
    local state = assert(module_value_state[self], "invalid Moonlift module table")
    local deps = state.deps or {}
    if #deps == 0 then return state.module end
    local Tr = state.T.MoonTree
    local items, seen = {}, {}
    for _, dep in ipairs(deps) do
        local dep_state = module_value_state[dep]
        if dep_state and dep ~= self and dep_state.module and not seen[dep_state.module] then
            seen[dep_state.module] = true
            items[#items + 1] = Tr.ItemUseModule("require:" .. tostring(dep_state.name or #items + 1), dep_state.module, {})
        end
    end
    for i = 1, #state.module.items do items[#items + 1] = state.module.items[i] end
    return Tr.Module(state.module.h, items)
end

function ModuleValue:compile()
    local state = assert(module_value_state[self], "invalid Moonlift module table")
    local Typecheck = require("moonlift.tree_typecheck").Define(state.T)
    local Layout = require("moonlift.sem_layout_resolve").Define(state.T)
    local TreeToBack = require("moonlift.tree_to_back").Define(state.T)
    local Validate = require("moonlift.back_validate").Define(state.T)
    local J = require("moonlift.back_jit").Define(state.T)
    local expanded = module_with_required_deps(self)
    local checked = Typecheck.check_module(expanded)
    if #checked.issues ~= 0 then error("module typecheck failed: " .. tostring(checked.issues[1]), 2) end
    local resolved = Layout.module(checked.module)
    local program = TreeToBack.module(resolved)
    local report = Validate.validate(program)
    if #report.issues ~= 0 then error("module back validation failed: " .. tostring(report.issues[1]), 2) end
    local artifact = J.jit():compile(program)
    return setmetatable({
        module = self, artifact = artifact, T = state.T,
        exports = module_funcs(state.T, checked.module), functions = {},
    }, CompiledModule)
end

function CompiledModule:get(name)
    local cached = self.functions[name]
    if cached then return cached end
    local func = assert(self.exports[name], "compiled module has no exported function: " .. tostring(name))
    local c_sig = c_sig_of(self.T, func)
    local ptr = self.artifact:getpointer(self.T.MoonBack.BackFuncId(name))
    local wrapped = setmetatable({
        module = self, func = func, fn = ffi.cast(c_sig, ptr), c_sig = c_sig,
    }, CompiledFunction)
    self.functions[name] = wrapped
    return wrapped
end

function CompiledModule:free()
    if self.artifact then self.artifact:free(); self.artifact = nil end
end

function CompiledFunction:__call(...)
    if not self.module or not self.module.artifact then
        error("compiled Moonlift function called after artifact was freed", 2)
    end
    return self.fn(...)
end

function CompiledFunction:free()
    if self.module then self.module:free(); self.module = nil end
end

function CompiledFunction:__tostring()
    return "CompiledMoonFunction(" .. tostring(self.func.name) .. ": " .. tostring(self.c_sig) .. ")"
end

function FuncValue:compile()
    return self.module:compile():get(self.name)
end

---------------------------------------------------------------------------
-- eval_island — parse an island with the unified parser, fill holes, expand
---------------------------------------------------------------------------

local function adopt_splice_value(runtime, value)
    if type(value) ~= "table" then return end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind == "region_frag" and value.frag ~= nil then
        local n = value.name or (value.frag.name and value.frag.name.text)
        if n then runtime.region_frags[n] = value end
    elseif kind == "expr_frag" and value.frag ~= nil then
        local n = value.name or (value.frag.name and value.frag.name.text)
        if n then runtime.expr_frags[n] = value end
    end
end

function Runtime:eval_island(kind_word, island_src, closures)
    local T = self.T
    local ParseApi = Parse.Define(T)
    local Splice = require("moonlift.host_splice")
    local Expand = require("moonlift.open_expand").Define(T)

    -- 1. Evaluate Lua closures for splice values
    local luamap = {}
    for id, fn in pairs(closures or {}) do
        local ok, val = pcall(fn)
        if not ok then
            error("Moonlift splice eval failed at " .. id .. ": " .. tostring(val), 2)
        end
        luamap[id] = {present = true, value = val}
        adopt_splice_value(self, val)
        -- Qualified probes: x.y → register protocol_types etc
        if id:match("^qualified%.") and val ~= nil then
            local path = id:gsub("^qualified%.", "", 1)
            if type(val) == "table" and val.protocol_variants then
                self.protocol_types[path] = val.protocol_variants
            end
        end
    end

    -- 2. Parse island source → typed ASDL + splice_slots
    local parse_opts = {
        protocol_types = self.protocol_types,
    }
    local parsed = ParseApi.parse(kind_word, island_src, parse_opts)
    if #parsed.issues ~= 0 then
        error("Moonlift parse failed: " .. tostring(parsed.issues[1]), 2)
    end

    -- 3. Fill splice slots
    local bindings = {}
    for _, ss in ipairs(parsed.splice_slots) do
        local rec = luamap[ss.splice_id]
        if not rec or not rec.present then
            error("missing splice value for " .. ss.splice_id, 2)
        end
        bindings[#bindings + 1] = Splice.fill(self.session, ss.slot, rec.value, "splice " .. ss.splice_id)
    end

    -- 4. Expand + wrap
    local base_env = Expand.env_with_frags(self.region_frags, self.expr_frags)
    local env = Expand.env_with_fills(base_env, bindings)

    if kind_word == "region" then
        local expanded = Expand.expand_region_frag(parsed.value, env)
        local value = HostValues.region_frag_value(self.session, expanded, {})
        self.region_frags[value.name] = value
        return value
    elseif kind_word == "expr" then
        local expanded = Expand.expand_expr_frag(parsed.value, env)
        local value = HostValues.expr_frag_value(self.session, expanded)
        self.expr_frags[value.name] = value
        return value
    elseif kind_word == "func" then
        -- Wrap as module with one function item
        local Tr = T.MoonTree
        local items = { Tr.ItemFunc(parsed.value) }
        local mod = new_module_value(self,
            Tr.Module(Tr.ModuleSurface, items), {})
        for i = 1, #items do
            if pvm.classof(items[i]) == Tr.ItemFunc then
                return setmetatable({
                    kind = "func", name = items[i].func.name, func = items[i].func,
                    module = mod, T = T, runtime = self,
                }, FuncValue)
            end
        end
        error("func island did not produce a function", 2)
    elseif kind_word == "struct" then
        local Tr = T.MoonTree
        return new_module_value(self,
            Tr.Module(Tr.ModuleSurface, { Tr.ItemType(parsed.value) }), {})
    elseif kind_word == "type" then
        if parsed.protocol_types then
            for name, variants in pairs(parsed.protocol_types) do
                self.protocol_types[name] = variants
            end
        end
        local Tr = T.MoonTree
        return new_module_value(self,
            Tr.Module(Tr.ModuleSurface, {parsed.value}), {})
    elseif kind_word == "const" then
        local Tr = T.MoonTree
        return new_module_value(self,
            Tr.Module(Tr.ModuleSurface, {parsed.value}), {})
    elseif kind_word == "static" then
        local Tr = T.MoonTree
        return new_module_value(self,
            Tr.Module(Tr.ModuleSurface, {parsed.value}), {})
    elseif kind_word == "extern" then
        local Tr = T.MoonTree
        return new_module_value(self,
            Tr.Module(Tr.ModuleSurface, { Tr.ItemExtern(parsed.value) }), {})
    else
        error("unsupported island kind: " .. tostring(kind_word), 2)
    end
end

---------------------------------------------------------------------------
-- Source loading
---------------------------------------------------------------------------

local function module_path_candidates(runtime, name)
    local rel = tostring(name):gsub("%.", "/")
    local patterns = runtime.module_path_patterns or {"mlua/?.mlua", "mlua/?/init.mlua", "?.mlua", "?/init.mlua"}
    local out = {}
    for i = 1, #patterns do out[#out + 1] = (patterns[i]:gsub("%?", rel)) end
    return out
end

function Runtime:note_require_dep(value)
    if not module_value_state[value] then return end
    local deps = current_dep_table(self)
    for i = 1, #deps do if deps[i] == value then return end end
    deps[#deps + 1] = value
end

function Runtime:require(name)
    self.require_cache = self.require_cache or {}
    if self.require_cache[name] == false then error("circular moon.require for " .. tostring(name), 2) end
    if self.require_cache[name] ~= nil then
        local cached = self.require_cache[name]
        self:note_require_dep(cached)
        return cached
    end
    local tried = {}
    for _, path in ipairs(module_path_candidates(self, name)) do
        tried[#tried + 1] = path
        local f = io.open(path, "rb")
        if f then
            f:close()
            self.require_cache[name] = false
            local frame = {name = name, deps = {}}
            self.require_stack[#self.require_stack + 1] = frame
            local ok, loaded_or_err = pcall(function()
                local fn = assert(M.loadfile(path, {runtime = self}))
                return fn()
            end)
            self.require_stack[#self.require_stack] = nil
            if not ok then self.require_cache[name] = nil; error(loaded_or_err, 2) end
            local value = loaded_or_err
            local state = module_value_state[value]
            if state then state.deps = frame.deps end
            self.require_cache[name] = value
            self:note_require_dep(value)
            return value
        end
    end
    error("moon.require could not find " .. tostring(name) .. " (tried " .. table.concat(tried, ", ") .. ")", 2)
end

---------------------------------------------------------------------------
-- loadstring: compile .mlua source → Lua function
---------------------------------------------------------------------------

function M.loadstring(src, chunk_name, opts)
    opts = opts or {}
    local parent = opts.runtime
    local T = opts.T or (parent and parent.T) or new_context()
    local session = opts.session or (parent and parent.session)
        or Session.new({prefix = opts.prefix or "mlua", T = T})

    local runtime = setmetatable({
        T = T,
        session = session,
        region_frags = opts.region_frags or (parent and parent.region_frags) or {},
        expr_frags = opts.expr_frags or (parent and parent.expr_frags) or {},
        protocol_types = opts.protocol_types or (parent and parent.protocol_types) or {},
        require_cache = opts.require_cache or (parent and parent.require_cache) or {},
        require_stack = opts.require_stack or (parent and parent.require_stack) or {},
        root_deps = opts.root_deps or (parent and parent.root_deps) or {},
        module_path_patterns = opts.module_path_patterns or opts.module_paths
            or (parent and parent.module_path_patterns),
    }, Runtime)

    local scanned = Parse.scan_islands(src)
    local islands = scanned.islands
    local hole_map = scanned.splice_map

    local q = Quote()
    local rt = q:val(runtime, "runtime")
    q("return function(...)")
    q("local __moonlift_runtime = %s", rt)
    q("local moon = setmetatable({ require = function(name) return __moonlift_runtime:require(name) end }, { __index = __moonlift_runtime.session:api() })")

    local cursor = 1
    for _, isl in ipairs(islands) do
        -- Emit any Lua source between cursor and island start
        local lua_part = src:sub(cursor, isl.start - 1)
        if lua_part:match("%S") then
            q(lua_part)
        end

        -- Build closure table for this island's holes
        local entries = {}
        local seen = {}
        for _, hid in ipairs(isl.holes) do
            if not seen[hid] then
                seen[hid] = true
                local expr = hole_map[hid]
                if expr then
                    entries[#entries+1] = string.format("[%q] = function() return (%s) end", hid, expr)
                end
            end
        end

        -- Also add auto-qualified probes for dotted names in the island text
        local isl_text = src:sub(isl.start, isl.stop)
        for base, field in isl_text:gmatch("([_%a][_%w]*)%.([_%a][_%w]*)") do
            local path = base .. "." .. field
            local hid = "qualified." .. path
            if not seen[hid] then
                seen[hid] = true
                entries[#entries+1] = string.format(
                    "[%q] = function() local __v = %s; if type(__v) == 'table' or type(__v) == 'userdata' then return __v[%q] end; return nil end",
                    hid, base, field)
            end
        end

        -- Emit eval_island call
        local kind_word = isl.kind:gsub("_kw$", "")
        q(string.format("__moonlift_runtime:eval_island(%q, %q, {%s})",
            kind_word, isl_text, table.concat(entries, ",")))

        cursor = isl.stop + 1
    end

    -- Trailing Lua
    local tail = src:sub(cursor)
    if tail:match("%S") then q(tail) end

    q("end")
    local inner, lua_src = q:compile(chunk_name or "=(moonlift.mlua_run)")

    local function fn(...)
        local pop = push_runtime(runtime)
        local function pack(ok, ...)
            return { ok, n = select("#", ...) + 1, ... }
        end
        local results = pack(pcall(inner, ...))
        pop()
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2, results.n)
    end
    return fn, runtime, lua_src
end

function M.loadfile(path, opts)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path, opts)
end

function M.dofile(path, opts, ...)
    if type(opts) == "table" and (opts.runtime or opts.T or opts.session) then
        return assert(M.loadfile(path, opts))(...)
    end
    if not opts and path:match("%.mlua$") then
        local parent = M.current_runtime()
        if parent then
            return assert(M.loadfile(path, {runtime = parent}))(...)
        end
    end
    local fn = assert(M.loadfile(path))
    return fn(opts, ...)
end

function M.eval(src, chunk_name, ...)
    return assert(M.loadstring(src, chunk_name or "=(moonlift.eval)"))(...)
end

return M
