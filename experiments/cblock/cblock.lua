-- cblock.lua
--
-- Lua owns declaration names and namespaces. CBlock values are built with
-- ordinary calls and exported by returning a Lua table from C.compile.
-- Callable values receive immutable named parameter products. Functions and
-- regions curry a native result type in the result position; regions may
-- instead carry a named continuation protocol among their parameters, and
-- those plural bodies receive the second binder `c`.
--
-- Functions and externs curry their native result type after named parameters.
-- Regions inline by default; call(region) creates one private C seal. Blocks are
-- local goto targets, and pipelines fuse into scalar C loops for GCC to optimize.
local L = require("label")
local unpack = unpack or table.unpack

local M = {}

--====================================================================
-- types
--====================================================================

local function prim(n, c) return { kind = "prim", name = n, c = c } end
local i32  = prim("i32",  "int32_t")
local i8   = prim("i8",  "int8_t")
local i16  = prim("i16", "int16_t")
local i64  = prim("i64", "int64_t")
local u8   = prim("u8",  "uint8_t")
local u16  = prim("u16", "uint16_t")
local u32  = prim("u32", "uint32_t")
local u64  = prim("u64", "uint64_t")
local f32  = prim("f32", "float")
local f64  = prim("f64", "double")
local bool = prim("bool", "bool")
local usize = prim("usize", "size_t")
local isize = prim("isize", "ptrdiff_t")
local void = { kind = "void", name = "void", c = "void" }
local INTEGER = { i8 = true, i16 = true, i32 = true, i64 = true,
    u8 = true, u16 = true, u32 = true, u64 = true,
    usize = true, isize = true }
local function numeric(T) return INTEGER[T.name] or T == f32 or T == f64 end
local function integral(T) return INTEGER[T.name] == true end
local ptr_cache = setmetatable({}, { __mode = "k" })
local function ctype(T)
    if T.kind == "ptr" then return ctype(T.elem) .. " *" end
    if T.kind == "array" then return ctype(T.elem) .. " [" .. T.count .. "]" end
    if T.kind == "fnptr" then
        local ps = {}
        for i, P in ipairs(T.params) do ps[i] = ctype(P) end
        if #ps == 0 then ps[1] = "void" end
        return ("%s (*)(%s)"):format(ctype(T.result), table.concat(ps, ", "))
    end
    local c = rawget(T, "c")
    assert(type(c) == "string",
        "type " .. tostring(T and T.name) .. " has no exported C name")
    return c
end
local function ptr(T)
    local P = ptr_cache[T]
    if not P then
        P = { kind = "ptr", elem = T, name = "ptr(" .. T.name .. ")" }
        ptr_cache[T] = P
    end
    return P
end
local array_cache = setmetatable({}, { __mode = "k" })
local function array(T, N)
    assert(type(T) == "table" and T.kind and T.kind ~= "array",
        "array expects a base type")
    assert(type(N) == "number" and N >= 1 and N % 1 == 0,
        "array count must be a positive integer")
    local key = tostring(T) .. ":" .. N
    local A = array_cache[key]
    if not A then
        A = { kind = "array", elem = T, count = N,
              name = ("array(%s, %d)"):format(T.name, N) }
        array_cache[key] = A
    end
    return A
end
local function cont_value(exit_name, ...)
    assert(select("#", ...) <= 1, "cont carries zero or one value")
    return { kind = "cont", types = { ... }, name = "cont", exit_name = exit_name }
end
local cont
local ContDecl_mt = {}
ContDecl_mt.__call = function(_, ...) return cont_value(nil, ...) end
ContDecl_mt.__index = function(_, name)
    if type(name) ~= "string" or name:sub(1, 2) == "__" then return nil end
    return function(receiver, ...)
        if receiver ~= cont then
            error(("cont.%s(...) -- use colon syntax: cont: %s (...)")
                :format(name, name), 2)
        end
        return cont_value(name, ...)
    end
end
cont = setmetatable({}, ContDecl_mt)

--====================================================================
-- places : lvalues that auto-load in expression contexts
--====================================================================


--====================================================================
-- LAYER 1 : surface
--====================================================================

local Expr_mt, Cont_mt, Func_mt, Block_mt, Region_mt, InlineCont_mt,
      ParamBinder_mt, ExitBinder_mt, BoundExit_mt, Producer_mt, Stream_mt, Zip_mt,
      Struct_mt, StructExpr_mt, Place_mt =
      {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

-- exact kind checks by metatable identity, never by field-name sniffing
local function expr_value(v)
    local mt = type(v) == "table" and getmetatable(v)
    return mt == Expr_mt or mt == StructExpr_mt
end
local function E(k, t)
    t = t or {} t.kind = k
    local agg = t.type and (t.type.kind == "struct" or t.type.kind == "union")
    return setmetatable(t, agg and StructExpr_mt or Expr_mt)
end
local function lift(v)
    if type(v) == "number" then return E("const", { value = v }) end
    if type(v) == "boolean" then return E("const", { value = v }) end
    if getmetatable(v) == Place_mt then
        return E("load", { place = v, type = v.type })
    end
    return v
end
local function zero_value(T)
    if T == f64 then return E("const", { value = "0.0", type = T }) end
    if T == f32 then return E("const", { value = "0.0f", type = T }) end
    return E("const", { value = 0, type = T })
end
local function place_load(p)
    return E("load", { place = p, type = p.type })
end
local function place_store(p, value)
    return { stmt = "store_place", place = p, value = lift(value) }
end
local function place_address(p)
    local t = p.type and (p.type.kind == "array" and ptr(p.type.elem) or ptr(p.type)) or nil
    return E("address", { place = p, type = t })
end
local function place_at(base, index)
    local array_lvalue = getmetatable(base) == Place_mt
        and base.type and base.type.kind == "array"
    if not array_lvalue then base = lift(base) end
    local T = type(base) == "table" and base.type or nil
    local elem = T and (T.kind == "ptr" and T.elem or T.kind == "array" and T.elem) or nil
    return setmetatable({ place = "at", ptr = base, index = lift(index), type = elem }, Place_mt)
end
local function place_deref(ptr_expr)
    local T = type(ptr_expr) == "table" and ptr_expr.type or nil
    return setmetatable({ place = "deref", ptr = lift(ptr_expr),
        type = T and T.kind == "ptr" and T.elem or nil }, Place_mt)
end
local function place_arith(op)
    return function(a, b)
        return E("binop", { op = op, a = place_load(a), b = lift(b) })
    end
end
Place_mt.__add, Place_mt.__sub = place_arith("add"), place_arith("sub")
Place_mt.__mul, Place_mt.__div = place_arith("mul"), place_arith("div")
Place_mt.__mod = place_arith("mod")
Place_mt.__unm = function(a) return E("binop", { op = "sub", a = lift(0), b = place_load(a) }) end
Place_mt.__lt = function(a, b) return E("binop", { op = "lt", a = place_load(a), b = lift(b) }) end
Place_mt.__le = function(a, b) return E("binop", { op = "le", a = place_load(a), b = lift(b) }) end
Place_mt.__eq = function(a, b) return E("binop", { op = "eq", a = place_load(a), b = lift(b) }) end
Place_mt.__index = function(p, name)
    local T = rawget(p, "type")
    local field = T and T.kind == "struct" and T.by_name[name]
    if field then return setmetatable({ place = "member", object = p, name = name,
        type = field.type }, Place_mt) end
    -- method sugar: places read and write as builders too
    if name == "load" then return function() return place_load(p) end end
    if name == "store" then return function(_, value) return place_store(p, value) end end
    if name == "address" then return function() return place_address(p) end end
    if name == "at" then return function(_, index) return place_at(p, index) end end
    if name == "deref" then return function() return place_deref(p) end end
    return nil
end

local function arith(op)
    return function(a, b) return E("binop", { op = op, a = lift(a), b = lift(b) }) end
end
Expr_mt.__add, Expr_mt.__sub = arith("add"), arith("sub")
Expr_mt.__mul, Expr_mt.__div = arith("mul"), arith("div")
Expr_mt.__mod = arith("mod")
Expr_mt.__unm = function(a) return E("binop", { op = "sub", a = lift(0), b = a }) end
local function compare(op, swap)
    return function(a, b)
        if swap then a, b = b, a end
        return E("binop", { op = op, a = lift(a), b = lift(b) })
    end
end

Expr_mt.__index = function(e, name)
    if name == "at" then return function(_, index) return place_at(e, index) end end
    if name == "deref" then return function() return place_deref(e) end end
    return nil
end

for key, value in pairs(Expr_mt) do
    if key ~= "__index" then StructExpr_mt[key] = value end
end
StructExpr_mt.__index = function(e, key)
    local T = rawget(e, "type")
    local method = T and T.methods[key]
    if method then return function(_, ...) return method(e, ...) end end
    local field = T and T.by_name[key]
    if field then return E("field_get", { object = e, field = field, type = field.type }) end
    return StructExpr_mt[key]
end

Struct_mt.__index = function(T, key)
    local member = T.methods[key] or Struct_mt[key]
    if member then return member end
    local declare_region = rawget(T, "declare_region")
    if declare_region then
        return function(receiver, ...)
            assert(receiver == T, "owned region receiver mismatch")
            return declare_region(key, ...)
        end
    end
end
Struct_mt.__newindex = function(T, key, value)
    local mt = type(value) == "table" and getmetatable(value)
    if type(value) ~= "function" and mt ~= Region_mt and mt ~= Func_mt then
        error("struct members must be Lua methods, funcs, or regions", 2)
    end
    if mt == Region_mt then
        local first = value.params[1]
        local ok = first == T or (first and first.kind == "ptr" and first.elem == T)
        assert(ok,
            "struct region " .. key .. " must take its owner or ptr(owner) first")
    end
    T.methods[key] = value
end
Struct_mt.__call = function(T, values)
    local host_runtime = rawget(T, "host_runtime")
    if host_runtime then return host_runtime:construct(T, values) end
    assert(type(values) == "table", "struct construction expects a field table")
    local init = {}
    if T.kind == "union" then
        -- a union is constructed by naming its one active member
        local n = 0
        local active
        for key in pairs(values) do n = n + 1 active = key end
        assert(n == 1, "union construction needs exactly one active field")
        local field = T.by_name[active]
        assert(field, "unknown union field: " .. tostring(active))
        init[1] = { field = field, value = lift(values[active]) }
    else
        for _, field in ipairs(T.fields) do
            local value = values[field.name]
            assert(value ~= nil, "missing struct field: " .. field.name)
            init[#init + 1] = { field = field, value = lift(value) }
        end
        for key in pairs(values) do
            assert(T.by_name[key], "unknown struct field: " .. tostring(key))
        end
    end
    return E("struct_init", { struct = T, fields = init, type = T })
end

Cont_mt.__call = function(k, ...)
    local a = {} for i = 1, select("#", ...) do a[i] = lift((select(i, ...))) end
    return { stmt = "go", dest = k, args = a }
end

Block_mt.__call = function(b, ...)
    local a = {} for i = 1, select("#", ...) do a[i] = lift((select(i, ...))) end
    assert(#a == #b.ptypes,
        ("block %s takes %d operand(s), got %d"):format(b.name, #b.ptypes, #a))
    return { stmt = "jump", target = b, args = a }
end

local function as_block(x, where)
    if type(x) == "table" and x.kind == "block" then
        assert(#x.ptypes == 0, ("%s: block %s takes operands"):format(where, x.name))
        return { stmt = "jump", target = x, args = {} }
    end
    if type(x) == "table" and x.stmt then return x end
    error(("%s must be a block value, got %s"):format(where, type(x)), 3)
    error(("%s must be a block value, got %s"):format(where, type(x)), 3)
end

local function is_stmt_value(x)
    return type(x) == "table" and x.stmt ~= nil
end

-- A body is a statement list: its return values are the statements,
-- the last one terminates. A lone value is the direct result.
local function as_block_list(list, where)
    if #list == 0 then
        error(("%s must produce at least one statement (the last one terminates)")
            :format(where), 3)
    end
    if #list == 1 then return as_block(list[1], where) end
    for i = 1, #list do
        if not is_stmt_value(list[i]) then
            error(("%s: statement %d must be a block value, got %s")
                :format(where, i, type(list[i])), 3)
        end
    end
    return { stmt = "seq", list = list }
end

local function callable(x)
    if type(x) == "function" then return true end
    local mt = type(x) == "table" and getmetatable(x)
    return mt and mt.__call ~= nil
end

local function continuation_value(x)
    local mt = type(x) == "table" and getmetatable(x)
    return mt == Cont_mt or mt == InlineCont_mt or mt == BoundExit_mt
end

local param_binder_data = setmetatable({}, { __mode = "k" })
local exit_binder_data = setmetatable({}, { __mode = "k" })
local bound_exit_data = setmetatable({}, { __mode = "k" })

ParamBinder_mt.__index = function(binder, name)
    local data = param_binder_data[binder]
    local value = data.values[name]
    if value ~= nil then return value end
    error(("%s has no parameter named %s"):format(data.where, tostring(name)), 2)
end
ParamBinder_mt.__newindex = function()
    error("parameter binders are immutable", 2)
end

local function param_binder(owner, values, where)
    local binder = setmetatable({}, ParamBinder_mt)
    local data = { values = {}, where = where }
    param_binder_data[binder] = data
    for i, name in ipairs(owner.param_names) do data.values[name] = values[i] end
    return binder
end

local function region_arguments(owner, ...)
    local n = select("#", ...)
    if n == 1 then
        local supplied = select(1, ...)
        if type(supplied) == "table" and getmetatable(supplied) == nil then
            local args, expected = {}, {}
            for i, name in ipairs(owner.param_names) do
                expected[name] = true
                local value = supplied[name]
                if value == nil then
                    error(("%s is missing parameter %s")
                        :format(owner.name, name), 3)
                end
                args[i] = value
            end
            for name in pairs(supplied) do
                if not expected[name] then
                    error(("%s has no parameter named %s")
                        :format(owner.name, tostring(name)), 3)
                end
            end
            return args
        end
    end
    if n ~= #owner.params then
        error(("%s takes %d operand(s), got %d")
            :format(owner.name, #owner.params, n), 3)
    end
    return { ... }
end
BoundExit_mt.__call = function(exit, ...)
    local data = bound_exit_data[exit]
    local n = select("#", ...)
    if n > 0 and select(1, ...) == data.owner then
        return data.dest(select(2, ...))
    end
    return data.dest(...)
end
BoundExit_mt.__tostring = function(exit)
    return "exit<" .. bound_exit_data[exit].name .. ">"
end
BoundExit_mt.__newindex = function()
    error("bound exits are immutable", 2)
end

ExitBinder_mt.__index = function(binder, name)
    local data = exit_binder_data[binder]
    local exit = data.exits[name]
    if exit then return exit end
    error(("%s has no exit named %s"):format(data.where, tostring(name)), 2)
end
ExitBinder_mt.__newindex = function()
    error("exit binders are immutable", 2)
end

local function exit_binder(conts, dests, where)
    local binder = setmetatable({}, ExitBinder_mt)
    local data = { exits = {}, where = where }
    exit_binder_data[binder] = data
    for j, c in ipairs(conts) do
        local exit = setmetatable({}, BoundExit_mt)
        bound_exit_data[exit] = {
            owner = binder, dest = dests[j], name = c.name, types = c.types,
        }
        data.exits[c.name] = exit
    end
    return binder
end

local function named_handlers(owner, supplied, where)
    if type(supplied) ~= "table" or getmetatable(supplied) ~= nil then
        error(where .. " expects one plain named-handler table", 3)
    end
    local expected, handlers = {}, {}
    for j, c in ipairs(owner.conts) do
        expected[c.name] = true
        local handler = supplied[c.name]
        if handler == nil then
            error(("%s is missing handler %s"):format(where, c.name), 3)
        end
        handlers[j] = handler
    end
    for name in pairs(supplied) do
        if not expected[name] then
            error(("%s has no exit named %s"):format(where, tostring(name)), 3)
        end
    end
    return handlers
end

local function zero_handler(handler, where)
    if continuation_value(handler) then
        return as_block(handler(), where)
    end
    if callable(handler) then
        return as_block(handler(), where)
    end
    return as_block(handler, where)
end

InlineCont_mt.__call = function(k, ...)
    local got, want = select("#", ...), #k.types
    if got ~= want then
        error(("%s takes %d value(s), got %d"):format(k.where, want, got), 2)
    end
    if want == 0 then return zero_handler(k.handler, k.where) end
    if not callable(k.handler) then error(k.where .. " must bind its result", 2) end
    return as_block(k.handler(lift((select(1, ...)))), k.where .. " body")
end

Region_mt.__call = function(r, ...)
    return r.emit(r, ...)
end

Producer_mt.__index, Stream_mt.__index, Zip_mt.__index =
    Producer_mt, Stream_mt, Zip_mt

local function range(first, last)
    return setmetatable({ kind = "producer", first = lift(first), last = lift(last) },
        Producer_mt)
end

function Producer_mt:load(source)
    local T = source and source.type
    assert(T and T.kind == "ptr", "producer:load expects a typed pointer")
    local value = E("pload", { producer = self, ptr = source, type = T.elem })
    return setmetatable({ kind = "stream", producer = self, value = value }, Stream_mt)
end

local function mapped(producer, fn, values)
    M._map_depth = (M._map_depth or 0) + 1
    local value = lift(fn(unpack(values)))
    M._map_depth = M._map_depth - 1
    assert(type(value) == "table" and value.kind,
        "map function must produce one scalar expression")
    assert(not value.stmt, "map function cannot produce control")
    return setmetatable({ kind = "stream", producer = producer, value = value }, Stream_mt)
end
function Stream_mt:map(fn) return mapped(self.producer, fn, { self.value }) end

local function zip(...)
    local streams, n = { ... }, select("#", ...)
    assert(n > 0, "zip needs at least one stream")
    local producer, values = streams[1].producer, {}
    for i = 1, n do
        assert(getmetatable(streams[i]) == Stream_mt, "zip expects streams")
        assert(streams[i].producer == producer,
            "zip streams must have the same producer")
        values[i] = streams[i].value
    end
    return setmetatable({ kind = "zip", producer = producer, values = values }, Zip_mt)
end

function Zip_mt:map(fn) return mapped(self.producer, fn, self.values) end

local function stream_type(e)
    if e.type then return e.type end
    if e.kind == "binop" then return stream_type(e.a) or stream_type(e.b) end
end

function Stream_mt:store(dst)
    return { stmt = "pipeline_store", producer = self.producer,
        value = self.value, dst = dst }
end

function Stream_mt:reduce(reducer, init)
    assert(reducer and reducer.kind == "reducer", "reduce expects add or mul")
    local T = assert(stream_type(self.value), "cannot infer reduced stream type")
    return E("pipeline_reduce", { producer = self.producer, value = self.value,
        reducer = reducer, init = lift(init), type = T })
end

-- Chained conditional: if_(cond):then_(block):else_(block).
-- then/else are Lua keywords, so the methods carry an underscore.
local if_  -- forward declaration for the chain builders
local IfThen_mt = {}
local IfCond_mt = {}
IfCond_mt.__index = IfCond_mt
function IfCond_mt:then_(t)
    return setmetatable({ cond = self.cond, t = t }, IfThen_mt)
end
IfThen_mt.__index = IfThen_mt
function IfThen_mt:else_(f)
    return if_(self.cond, self.t, f)
end

if_ = function(c, t, f)
    if t == nil and f == nil then
        return setmetatable({ cond = c }, IfCond_mt)
    end
    assert(t ~= nil and f ~= nil, "if_ (condition, value, value | block, block)")
    local tv, fv = lift(t), lift(f)
    if expr_value(tv) and expr_value(fv) then
        local T = tv.type and tv.type == fv.type and tv.type or nil
        return E("select", { cond = c, t = tv, f = fv, type = T })
    end
    return { stmt = "if_", cond = c,
             t = as_block(t, "if_ then operand"),
             f = as_block(f, "if_ else operand") }
end

M.nres = 0
Func_mt.__call = function(f, ...)
    local args, n
    if f.named_params then
        args, n = region_arguments(f, ...), #f.params
    else
        args, n = { ... }, select("#", ...)
    end
    local host_runtime = rawget(f, "host_runtime")
    if host_runtime then return host_runtime:invoke(f, unpack(args, 1, n)) end
    if f.direct then
        if n ~= #f.params then
            error(("%s takes %d operand(s), got %d"):format(
                f.name, #f.params, n), 2)
        end
        for i = 1, n do args[i] = lift(args[i]) end
        if f.result == void then
            return { stmt = "dcall", callee = f, args = args }
        end
        return E("fcall", { callee = f, args = args, type = f.result })
    end

    local nval = #f.params
    if n ~= nval then
        error(("%s takes %d operand(s), got %d")
            :format(f.name, nval, n), 2)
    end
    for i = 1, n do args[i] = lift(args[i]) end
    return function(...)
        local got = select("#", ...)
        if got ~= 1 then
            error(("%s call expects one named-handler table, got %d values")
                :format(f.name, got), 2)
        end
        local handlers = named_handlers(f, select(1, ...), f.name .. " call")
        local ks = {}
        for j, c in ipairs(f.conts) do
            local types, bind = c.types, nil
            local where = ("%s exit %s handler"):format(f.name, c.name)
            local body
            if #types == 0 then
                body = zero_handler(handlers[j], where)
            else
                M.nres = M.nres + 1
                bind = E("result", { id = M.nres, type = types[1] })
                local handler = handlers[j]
                if not callable(handler) then
                    error(where .. " must bind its result", 2)
                end
                body = as_block(handler(bind), where .. " body")
            end
            ks[j] = { name = c.name, bind = bind, body = body }
        end
        return { stmt = "call", callee = f, args = args, ks = ks }
    end
end

local function source_env(parent)
    local env = L.new_env(parent)
    env.i8, env.i16, env.i32, env.i64 = i8, i16, i32, i64
    env.u8, env.u16, env.u32, env.u64 = u8, u16, u32, u64
    env.f32, env.f64, env.bool = f32, f64, bool
    env.usize, env.isize = usize, isize
    env.ptr, env.cont, env.void, env.lit, env.if_ = ptr, cont, void, lift, if_
    env.field = L.keyword {
        name = "field", env = env, binds = false,
        identity = function(name) return { kind = "field", name = name } end,
        build = function(member, T)
            assert(type(T) == "table" and T.kind, "field type must be a CBlock type")
            member.type = T
            return member
        end,
    }
    env.param = L.keyword {
        name = "param", env = env, binds = false,
        identity = function(name) return { kind = "param", name = name } end,
        build = function(member, T)
            assert(type(T) == "table" and T.kind, "parameter type must be a CBlock type")
            member.type = T
            return member
        end,
    }
    local functions, externs, structs, globals, current = {}, {}, {}, {}, nil
    local serial, complete_func = 0, nil

    local function aggregate(kind, fields, what)
        assert(type(fields) == "table", what .. " expects a field table")
        local T = setmetatable({ kind = kind,
            name = "anonymous " .. kind, fields = {}, by_name = {},
            methods = {} }, Struct_mt)
        rawset(T, "declare_region", function(member_name, ...)
            assert(not T.methods[member_name],
                "duplicate struct member: " .. member_name)
            local stage = env.region({ kind = "param", name = "self", type = T }, ...)
            return function(second)
                if type(second) == "function" then
                    local owned = stage(second)
                    T.methods[member_name] = owned
                    return owned
                end
                return function(body)
                    local owned = stage(second)(body)
                    T.methods[member_name] = owned
                    return owned
                end
            end
        end)
        -- The explicit ordered field list is the physical C layout order,
        -- written in source and preserved exactly. Lua table iteration is
        -- never an ordering contract.
        for i, field in ipairs(fields) do
            assert(field.kind == "field",
                what .. " entries must be field: name (type)")
            assert(not T.by_name[field.name],
                "duplicate " .. kind .. " field: " .. field.name)
            T.fields[i], T.by_name[field.name] = field, field
        end
        return T
    end
    env.struct = function(fields) return aggregate("struct", fields, "struct") end
    env.union  = function(fields) return aggregate("union", fields, "union") end

    -- fixed C array type (struct fields only; arrays are not call values)
    env.array = array

    -- bounded view: a (ptr, length) pair type, composed from existing structs
    local view_cache = setmetatable({}, { __mode = "k" })
    env.view = function(T)
        assert(type(T) == "table" and T.kind and T.kind ~= "array",
            "view expects a base type")
        local V = view_cache[T]
        if not V then
            serial = serial + 1
            local name = ("cblock_view_%d"):format(serial)
            V = aggregate("struct", {
                { kind = "field", name = "ptr", type = ptr(T) },
                { kind = "field", name = "length", type = i64 },
            }, "view")
            rawset(V, "name", name)
            rawset(V, "c", name)
            structs[#structs + 1] = V
            view_cache[T] = V
        end
        return V
    end

    -- opaque external type: incomplete C struct, usable through pointers
    local opaque_serial = 0
    env.opaque = function(name)
        opaque_serial = opaque_serial + 1
        local tag = name or ("cblock_opaque_%d"):format(opaque_serial)
        return { kind = "opaque", name = tag, c = ("struct %s"):format(tag) }
    end

    -- globals: file-scope static storage with a Lua-built initializer.
    -- init is a number, a string literal, or a table of numbers.
    env.global = function(T, init)
        assert(type(T) == "table" and T.kind, "global expects a type")
        local g = { place = "global", id = #globals + 1,
            name = ("cblock_global_%d"):format(#globals + 1),
            type = T, init = init }
        globals[g.id] = g
        return setmetatable(g, Place_mt)
    end

    -- cstring: a static NUL-terminated byte array, usable as ptr(u8).
    env.cstring = function(text)
        assert(type(text) == "string", "cstring expects a string")
        local g = { place = "global", id = #globals + 1,
            name = ("cblock_str_%d"):format(#globals + 1),
            type = array(u8, #text + 1), init = text }
        globals[g.id] = g
        return E("address", { place = g, type = ptr(u8) })
    end

    -- function pointer type and address-of-func value (cached by shape)
    local fnptr_cache = setmetatable({}, { __mode = "k" })
    env.fnptr = function(result, ...)
        assert(type(result) == "table" and result.kind,
            "fnptr expects a result type")
        local params = {}
        for i, P in ipairs({ ... }) do
            assert(type(P) == "table" and P.kind, "fnptr params must be types")
            params[i] = P
        end
        local parts = {}
        for i, P in ipairs(params) do parts[i] = tostring(P) end
        local key = tostring(result) .. "(" .. table.concat(parts, ",") .. ")"
        local F = fnptr_cache[key]
        if not F then
            F = { kind = "fnptr", result = result, params = params,
                name = ("fnptr(%s, ...)"):format(result.name) }
            fnptr_cache[key] = F
        end
        return F
    end
    env.range, env.zip = range, zip
    env.add = { kind = "reducer", op = "add", name = "add" }
    env.mul = { kind = "reducer", op = "mul", name = "mul" }
    env.lt = compare("lt")  env.gt = compare("lt", true)
    env.le = compare("le")  env.ge = compare("le", true)
    env.eq = compare("eq")  env.ne = compare("ne")
    env.bit_and, env.bit_or, env.bit_xor = arith("and"), arith("or"), arith("xor")
    env.shift_left, env.shift_right = arith("shl"), arith("shr")
    env.and_ = function(a, b) return E("binop", { op = "land", a = lift(a), b = lift(b) }) end
    env.or_  = function(a, b) return E("binop", { op = "lor", a = lift(a), b = lift(b) }) end

    -- switch_(value):case_(k):then_(block):default(block)
    -- Integer keys dispatch to named blocks; a default arm is required.
    local Switch_mt = {}
    Switch_mt.__index = Switch_mt
    function Switch_mt:case_(k)
        self.pending = lift(k)
        return self
    end
    function Switch_mt:then_(b)
        assert(self.pending ~= nil, "switch: case_(key) before then_(block)")
        self.cases[#self.cases + 1] = { key = self.pending, block = b }
        self.pending = nil
        return self
    end
    function Switch_mt:default(b)
        assert(#self.cases > 0, "switch: at least one case_ before default")
        assert(type(b) == "table" and b.kind == "block",
            "switch default must be a block")
        return { stmt = "switch", cond = self.cond,
                 cases = self.cases, default = b }
    end
    env.switch_ = function(cond)
        return setmetatable({ cond = lift(cond), cases = {}, pending = nil },
            Switch_mt)
    end

    -- enum: named integer constants, usable as switch keys and expressions.
    env.enum = function(entries)
        assert(type(entries) == "table", "enum expects a name/value table")
        local e = {}
        for name, value in pairs(entries) do
            assert(type(name) == "string", "enum names must be strings")
            assert(type(value) == "number",
                ("enum %s value must be a number"):format(name))
            e[name] = value
        end
        return e
    end

    env.__functions, env.__externs, env.__structs, env.__globals =
        functions, externs, structs, globals

    local place_id = 0
    local place_id = 0
    local function fresh_place()
        place_id = place_id + 1
        return place_id
    end
    local function place_type_of(value)
        return type(value) == "table" and value.type or nil
    end

    env.let = function(value)
        local v = lift(value)
        return E("let", { id = fresh_place(), value = v,
            type = place_type_of(v) })
    end
    env.var = function(T, init)
        assert(type(T) == "table" and T.kind, "var expects a type")
        assert(current, "var declared outside any func")
        init = init == nil and zero_value(T) or lift(init)
        local v = setmetatable({ place = "var", id = fresh_place(), type = T, init = init }, Place_mt)
        current.vars[#current.vars + 1] = v
        return v
    end
    env.at = function(ptr_expr, index_expr)
        return place_at(ptr_expr, index_expr)
    end
    env.member = function(object, name)
        assert(type(object) == "table" and object.place, "member expects a place")
        local T = object.type
        local field = T and T.kind == "struct" and T.by_name[name]
        return setmetatable({ place = "member", object = object, name = name,
            type = field and field.type or nil }, Place_mt)
    end
    env.deref = function(ptr_expr)
        return place_deref(ptr_expr)
    end
    env.load = function(place)
        assert(type(place) == "table" and place.place, "load expects a place")
        return E("load", { place = place, type = place.type })
    end
    env.store = function(place, value)
        assert(type(place) == "table" and place.place, "store expects a place")
        return place_store(place, value)
    end
    env.address = function(target)
        if type(target) == "table" and getmetatable(target) == Func_mt then
            -- address of a func: a callable function pointer value
            return E("fnaddress", { func = target,
                type = env.fnptr(target.result, unpack(target.params)) })
        end
        assert(type(target) == "table" and target.place, "address expects a place")
        return place_address(target)
    end
    env.cast = function(T, value)
        return E("cast", { type = T, value = lift(value) })
    end
    env.sizeof = function(T)
        assert(type(T) == "table" and T.kind, "sizeof expects a type")
        return E("sizeof", { type = usize, of = T })
    end
    env.seq = function(...)
        local list = { ... }
        assert(#list >= 1, "seq needs a final block value")
        return { stmt = "seq", list = list }
    end
    env.void_call = function(f, ...)
        assert(f.direct and f.result == void, "void_call expects a void func")
        local args = region_arguments(f, ...)
        local n = #f.params
        for i = 1, n do args[i] = lift(args[i]) end
        return { stmt = "call_void", callee = f, args = args }
    end

    
    
    env.__functions, env.__externs, env.__structs = functions, externs, structs
    
    local function generated(kind)
        serial = serial + 1
        return ("cblock_%s_%d"):format(kind, serial)
    end
    
    local function set_signature(owner, ...)
        local signature, first = { ... }, nil
        for i, entry in ipairs(signature) do
            assert(type(entry) == "table" and entry.kind,
                owner.name .. ": signature entries must be declarations or types")
            if entry.kind == "cont" or entry.kind == "ret" then
                first = first or i
            elseif first then
                error(owner.name .. ": outcomes must follow the operands", 2)
            end
        end
        assert(first, owner.name .. ": signature needs a trailing outcome")
        owner.params, owner.param_names, owner.param_by_name, owner.conts = {}, {}, {}, {}
        for i = 1, first - 1 do
            local entry, T = signature[i]
            assert(entry.kind == "param",
                owner.name .. ": operands must be named with param: name (type)")
            assert(not owner.param_by_name[entry.name],
                owner.name .. ": duplicate parameter name " .. entry.name)
            T = entry.type
            owner.param_names[i] = entry.name
            owner.param_by_name[entry.name] = i
            assert(type(T) == "table" and T.kind,
                owner.name .. ": operand entries must contain CBlock types")
            assert(T.kind ~= "array" and T.kind ~= "opaque",
                owner.name .. ": " .. T.kind .. "s cannot cross a call boundary; use ptr()")
            owner.params[i] = T
        end
        owner.named_params = true
        local outcomes = {}
        for j = 0, #signature - first do outcomes[j + 1] = signature[first + j] end

        if owner.kind == "func" then
            assert(#outcomes == 1 and outcomes[1].kind == "ret",
                owner.name .. ": func has exactly one curried result type")
            owner.named_exits = false
        else
            if #outcomes == 1 and outcomes[1].kind == "ret" then
                owner.named_exits = false
            else
                local names = {}
                for _, o in ipairs(outcomes) do
                    assert(o.kind == "cont" and o.exit_name,
                        owner.name .. ": continuations must be named with cont: name (...) ")
                    assert(not names[o.exit_name],
                        owner.name .. ": duplicate exit name " .. o.exit_name)
                    names[o.exit_name] = true
                end
                assert(#outcomes >= 2,
                    owner.name .. ": a single continuation is not a protocol; "
                    .. "direct regions curry their result type instead")
                owner.named_exits = true
            end
        end

        if #outcomes == 1 then
            owner.direct = true
            owner.result = outcomes[1].types[1] or void
            if owner.kind == "func" then
                owner.conts[1] = { index = #owner.params + 1, ord = 1,
                    types = outcomes[1].types }
            end
        else
            owner.direct, owner.result = false, nil
            for j, o in ipairs(outcomes) do
                owner.conts[j] = { index = #owner.params + j, ord = j,
                    name = o.exit_name, types = o.types }
            end
        end
    end
    
    local function parameter_refs(owner)
        local refs, dests, values = {}, {}, {}
        for j, c in ipairs(owner.conts) do
            dests[j] = setmetatable({
                kind = "contref", index = c.index, ord = c.ord, types = c.types,
            }, Cont_mt)
        end
        for i, T in ipairs(owner.params) do
            values[i] = E("param", { index = i, type = T })
        end
        if owner.named_params then
            refs[1] = param_binder(owner, values, owner.name .. " parameters")
            if owner.named_exits then
                refs[2] = exit_binder(owner.conts, dests, owner.name .. " body")
            elseif owner.kind == "func" and dests[1] then
                refs[2] = dests[1]
            end
        elseif owner.named_exits then
            refs[1] = exit_binder(owner.conts, dests, owner.name .. " body")
            for i, value in ipairs(values) do refs[i + 1] = value end
        else
            for i, value in ipairs(values) do refs[i] = value end
            for j, dest in ipairs(dests) do refs[#owner.params + j] = dest end
        end
        return refs
    end
    
    complete_func = function(f)
        if f.complete then return f end
        assert(f.body_builder, f.name .. ": function has no body")
        f.complete = true
        local prev = current
        current = f
        local ok, err = pcall(function()
            local built = { f.body_builder(unpack(parameter_refs(f))) }
            if f.direct and f.result ~= void and #built == 1
               and not is_stmt_value(built[1])
               and not (type(built[1]) == "table" and built[1].kind == "block") then
                f.body = { stmt = "return_value", value = lift(built[1]) }
            else
                f.body = as_block_list(built, f.name .. " body")
            end
            local i = 1
            while i <= #f.blocks do
                local b = f.blocks[i]
                assert(b.body_builder, b.name .. ": block has no body")
                local refs = {}
                for j, T in ipairs(b.ptypes) do
                    refs[j] = E("bparam", { block = b, index = j, type = T })
                end
                b.body = as_block_list({ b.body_builder(unpack(refs)) },
                    "block " .. b.name .. " body")
                i = i + 1
            end
        end)
        current = prev
        if not ok then f.complete = nil error(err, 0) end
        return f
    end
    
    local function emit_region(r, ...)
        assert(current, "region " .. r.name .. " emitted outside any func")
        local args = region_arguments(r, ...)
        local nval = #r.params
        for i = 1, nval do args[i] = lift(args[i]) end
        local p = param_binder(r, args, "region " .. r.name .. " parameters")

        if r.direct then
            if r.emitting then
                error("region " .. r.name ..
                    " recursively emits itself; use call(region)", 2)
            end
            r.emitting = true
            local ok, vals = pcall(function()
                return { r.body_builder(p) }
            end)
            r.emitting = false
            if not ok then error(vals, 0) end
            if r.result == void then
                return as_block_list(vals, "region " .. r.name .. " body")
            end
            if #vals == 1 and not is_stmt_value(vals[1])
               and not (type(vals[1]) == "table" and vals[1].kind == "block") then
                return lift(vals[1])
            end
            return as_block_list(vals, "region " .. r.name .. " body")
        end

        return function(...)
            local got = select("#", ...)
            if got ~= 1 then
                error(("region %s expects one named-handler table, got %d values")
                    :format(r.name, got), 2)
            end
            local handlers = named_handlers(r, select(1, ...), "region " .. r.name)
            if r.emitting then
                error("region " .. r.name ..
                    " recursively emits itself; use call(region)", 2)
            end
            local dests = {}
            for j, c in ipairs(r.conts) do
                dests[j] = setmetatable({
                    types = c.types, handler = handlers[j],
                    where = ("region %s exit %s"):format(r.name, c.name),
                }, InlineCont_mt)
            end
            local c = exit_binder(r.conts, dests, "region " .. r.name .. " body")
            r.emitting = true
            local ok, vals = pcall(function()
                return { r.body_builder(p, c) }
            end)
            r.emitting = false
            if not ok then error(vals, 0) end
            return as_block_list(vals, "region " .. r.name .. " body")
        end
    end
    
    local function seal_region(r)
        if r.sealed then return r.sealed end
        local f = setmetatable({
            kind = "func", name = generated("region"), source_name = r.name,
            internal = true, params = r.params, param_names = r.param_names,
            param_by_name = r.param_by_name, named_params = true, conts = r.conts,
            direct = r.direct, result = r.result, named_exits = r.named_exits,
            blocks = {}, vars = {}, body_builder = r.body_builder,
        }, Func_mt)
        r.sealed = f
        functions[#functions + 1] = f
        local ok, sealed = pcall(complete_func, f)
        if not ok then r.sealed = nil error(sealed, 0) end
        return sealed
    end
    
    env.call = function(r, ...)
        assert(select("#", ...) == 0, "call(region)")
        assert(getmetatable(r) == Region_mt, "call expects a region")
        return seal_region(r)
    end
    
    local function return_decl(T, where)
        assert(type(T) == "table" and T.kind and T.kind ~= "param"
            and T.kind ~= "cont" and T.kind ~= "ret",
            where .. ": result position expects one CBlock type")
        assert(T.kind ~= "array" and T.kind ~= "opaque",
            where .. ": " .. T.kind .. "s cannot be returned by value")
        return { kind = "ret", types = T == void and {} or { T } }
    end

    env.region = function(...)
        assert(not current, "region declared inside a func")
        local parameters = { ... }
        local has_conts = false
        for _, entry in ipairs(parameters) do
            if type(entry) == "table" and entry.kind == "cont" then
                has_conts = true
                break
            end
        end
        local r = setmetatable({
            kind = "region", name = generated("region"), emit = emit_region,
            vars = {},
        }, Region_mt)
        if has_conts then
            set_signature(r, unpack(parameters))
            return function(body)
                assert(type(body) == "function", "region body must be a function")
                r.body_builder = body
                return r
            end
        end
        return function(result)
            local signature = {}
            for i, entry in ipairs(parameters) do signature[i] = entry end
            signature[#signature + 1] = return_decl(result, "region")
            set_signature(r, unpack(signature))
            return function(body)
                assert(type(body) == "function", "region body must be a function")
                r.body_builder = body
                return r
            end
        end
    end
    

    env.extern = function(...)
        assert(not current, "extern declared inside a func")
        local parameters = { ... }
        return function(result)
            local f = setmetatable({
                kind = "func", external = true, name = generated("extern"),
                params = {}, conts = {}, blocks = {}, vars = {},
            }, Func_mt)
            local signature = {}
            for i, entry in ipairs(parameters) do signature[i] = entry end
            signature[#signature + 1] = return_decl(result, "extern")
            set_signature(f, unpack(signature))
            f.nparams = #f.params
            externs[#externs + 1] = f
            return f
        end
    end
    
    env.block = function(...)
        assert(current, "block declared outside a func")
        local b = setmetatable({
            kind = "block", name = generated("block"), ptypes = { ... },
            vars = {},
        }, Block_mt)
        for _, T in ipairs(b.ptypes) do
            assert(T.kind ~= "cont", "block operands cannot be outcomes")
        end
        current.blocks[#current.blocks + 1] = b
        return function(body)
            assert(type(body) == "function", "block body must be a function")
            b.body_builder = body
            return b
        end
    end
    
    env.func = function(...)
        assert(not current, "func declared inside a func")
        local parameters = { ... }
        return function(result)
            local f = setmetatable({
                kind = "func", name = generated("func"), internal = true,
                params = {}, conts = {}, blocks = {}, vars = {},
            }, Func_mt)
            local signature = {}
            for i, entry in ipairs(parameters) do signature[i] = entry end
            signature[#signature + 1] = return_decl(result, "func")
            set_signature(f, unpack(signature))
            functions[#functions + 1] = f
            return function(body)
                assert(type(body) == "function", "func body must be a function")
                f.body_builder = body
                return f
            end
        end
    end
    
    local function export_namespace(root)
        assert(type(root) == "table" and getmetatable(root) == nil,
            "C.compile body must return a Lua namespace table")
        local seen_tables, names, owners = {}, {}, {}
        local function walk(value, path)
            local mt = type(value) == "table" and getmetatable(value) or nil
            if mt == Struct_mt then
                local name = table.concat(path, "_")
                assert(name ~= "", "a struct needs a namespace field")
                local old = owners[value]
                assert(not old or old == name,
                    ("declaration has two namespace owners: %s and %s"):format(old, name))
                assert(not names[name] or names[name] == value,
                    "duplicate C namespace name: " .. name)
                owners[value], names[name] = name, value
                rawset(value, "name", name)
                rawset(value, "c", name)
                rawset(value, "export_name", name)
                structs[#structs + 1] = value
                return
            end
            if mt == Func_mt or mt == Region_mt then
                local name = table.concat(path, "_")
                assert(name ~= "", "a declaration needs a namespace field")
                local old = owners[value]
                assert(not old or old == name,
                    ("declaration has two namespace owners: %s and %s"):format(old, name))
                assert(not names[name] or names[name] == value,
                    "duplicate C namespace name: " .. name)
                owners[value], names[name] = name, value
                value.name, value.export_name = name, name
                if mt == Func_mt then value.internal = false end
                return
            end
            if type(value) ~= "table" or value.kind ~= nil or seen_tables[value] then
                return
            end
            seen_tables[value] = true
            for key, child in pairs(value) do
                assert(type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$"),
                    "namespace keys must be C identifiers")
                local next_path = {}
                for i = 1, #path do next_path[i] = path[i] end
                next_path[#next_path + 1] = key
                walk(child, next_path)
            end
        end
        walk(root, {})
        for _, f in ipairs(externs) do
            assert(f.export_name, "extern must belong to the returned namespace")
        end
    end
    
    env.__finish = function(root)
        export_namespace(root)
        local i = 1
        while i <= #functions do complete_func(functions[i]) i = i + 1 end
    end
    return env
end

--====================================================================
-- LAYER 2 : check
--====================================================================

local function check_machine()
    local m = { methods = {} } m.mt = { __index = m.methods }
    local benv = L.new_env(_G)
    benv.i32, benv.i64, benv.bool, benv.numeric, benv.integral =
        i32, i64, bool, numeric, integral
    benv.def_check = L.keyword {
        name = "def_check", env = benv, binds = true, body = true,
        identity = function(n) return { kind = "clabel", name = n } end,
        bind = function(s, body) m.methods[s.name] = body return s end,
    }
    local function T(op, ty, t) t = t or {} t.op = op t.type = ty return t end
    benv.T = T
    L.run(benv, function()

        def_check: expr (expr, type) (function(self, e, want)
            if type(e.kind) ~= "string" then
                error("expr dispatch on kind=" .. tostring(e.kind), 0)
            end
            return self [e.kind] (self, e, want) end)
        def_check: stmt (stmt) (function(self, s) return self [s.stmt] (self, s) end)

        local function is_terminator(t)
            local op = t.op
            if op == "if_" then
                return is_terminator(t.t) and is_terminator(t.f)
            end
            if op == "call" then
                for _, k in ipairs(t.ks) do
                    if not is_terminator(k.body) then return false end
                end
                return true
            end
            if op == "seq" then return is_terminator(t.list[#t.list]) end
            return op == "jump" or op == "gok" or op == "tail"
                or op == "dcall" or op == "return_value"
                or op == "switch" or op == "pipeline_store"
        end
        def_check: const  (expr, type) (function(self, e, want)
            return T("const", want or i32, { value = e.value }) end)
        def_check: param  (expr, type) (function(self, e)
            return T("param", e.type, { index = e.index }) end)
        def_check: bparam (expr, type) (function(self, e)
            return T("bparam", e.type, { block = e.block, index = e.index }) end)
        def_check: result (expr, type) (function(self, e)
            return T("result", e.type, { id = e.id }) end)
        def_check: pload (expr, type) (function(self, e)
            local p = self: expr (e.ptr)
            if not p.type or p.type.kind ~= "ptr" then
                return self: bad ("pipeline load expects a pointer")
            end
            return T("pload", p.type.elem, { ptr = p, producer = e.producer })
            end)
        def_check: fcall (expr, type) (function(self, e)
            local args = {}
            for i, a in ipairs(e.args) do
                args[i] = self: expr (a, e.callee.params[i])
                if args[i].type ~= e.callee.params[i] then
                    self: bad (("%s operand %d: expected %s, got %s"):format(
                        e.callee.name, i, e.callee.params[i].name, args[i].type.name))
                end
            end
            return T("fcall", e.callee.result, { callee = e.callee, args = args })
            end)
        def_check: field_get (expr, type) (function(self, e)
            local object = self: expr (e.object, e.object.type)
            return T("field_get", e.field.type, { object = object, field = e.field })
            end)
        def_check: struct_init (expr, type) (function(self, e)
            local fields = {}
            for i, init in ipairs(e.fields) do
                local value = self: expr (init.value, init.field.type)
                if value.type ~= init.field.type then
                    self: bad(("struct field %s wants %s, got %s"):format(
                        init.field.name, init.field.type.name, value.type.name))
                end
                fields[i] = { field = init.field, value = value }
            end
            return T("struct_init", e.struct, { struct = e.struct, fields = fields })
            end)

        def_check: let (expr, type) (function(self, e, want)
            local value = self: expr (e.value, want)
            return T("let", value.type, { id = e.id, value = value })
            end)
        def_check: load (expr, type) (function(self, e)
            local p = self: place (e.place)
            assert(p.type.kind ~= "array",
                "load of an array is not a value; use at(array, index)")
            return T("load", p.type, { place = p })
            end)
        def_check: address (expr, type) (function(self, e)
            local p = self: place (e.place)
            local t = p.type.kind == "array" and ptr(p.type.elem) or ptr(p.type)
            return T("address", t, { place = p })
            end)
        def_check: fnaddress (expr, type) (function(self, e)
            return T("fnaddress", e.type, { func = e.func })
            end)
        def_check: fncall (expr, type) (function(self, e)
            local callee = self: expr (e.callee)
            if not callee.type or callee.type.kind ~= "fnptr" then
                self: bad ("fncall expects a function pointer value")
            end
            local args = {}
            for i, a in ipairs(e.args) do
                args[i] = self: expr (a, callee.type.params[i])
                if args[i].type ~= callee.type.params[i] then
                    self: bad (("fncall operand %d: expected %s, got %s"):format(
                        i, callee.type.params[i].name, args[i].type.name))
                end
            end
            return T("fncall", callee.type.result, { callee = callee, args = args })
            end)
        def_check: cast (expr, type) (function(self, e)
            local value = self: expr (e.value, e.type)
            return T("cast", e.type, { value = value })
            end)
        def_check: sizeof (expr, type) (function(self, e)
            return T("sizeof", usize, { of = e.of })
            end)

        def_check: place (place) (function(self, p)
            local method = ({ var = "place_var", at = "place_at",
                member = "place_member", deref = "place_deref",
                global = "place_global" })[p.place]
            assert(method, "unknown place tag: " .. tostring(p and p.place))
            if p.checked then return p end
            local checked = self [method] (self, p)
            p.checked = true
            return checked end)
        def_check: place_global (place) (function(self, p)
            return p
            end)
        def_check: place_var (place) (function(self, p)
            local init = self: expr (p.init, p.type)
            if init.type ~= p.type then
                return self: bad (("var wants %s, got %s"):format(
                    p.type.name, init.type.name))
            end
            p.init = init
            return p
            end)
        def_check: place_at (place) (function(self, p)
            local array_base = type(p.ptr) == "table" and p.ptr.place
                and not p.ptr.kind
            local base
            if array_base then
                base = self: place (p.ptr)
                if base.type.kind ~= "array" then
                    return self: bad ("at with an lvalue base expects an array")
                end
            else
                base = self: expr (p.ptr)
                if not base.type or base.type.kind ~= "ptr" then
                    return self: bad ("at expects a pointer base")
                end
            end
            local index = self: expr (p.index)
            if not integral(index.type) then
                return self: bad ("at index must be an integer")
            end
            p.ptr, p.index, p.type = base, index,
                base.type.kind == "array" and base.type.elem or base.type.elem
            p.array_base = array_base
            return p
            end)
        def_check: place_member (place) (function(self, p)
            local object = self: place (p.object)
            if not object.type or object.type.kind ~= "struct" then
                return self: bad ("member expects a struct place")
            end
            local field = object.type.by_name[p.name]
            if not field then return self: bad ("struct has no field " .. p.name) end
            p.object, p.field, p.type = object, field, field.type
            return p
            end)
        def_check: place_deref (place) (function(self, p)
            local ptr = self: expr (p.ptr)
            if not ptr.type or ptr.type.kind ~= "ptr" then
                return self: bad ("deref expects a pointer")
            end
            p.ptr, p.type = ptr, ptr.type.elem
            return p
            end)
        def_check: binop (expr, type) (function(self, e, want)
            local cmp = e.op=="lt" or e.op=="le" or e.op=="eq" or e.op=="ne"
            local bitwise = e.op=="and" or e.op=="or" or e.op=="xor"
            local shift = e.op=="shl" or e.op=="shr"
            local a, b
            if e.a.kind == "const" and e.b.kind ~= "const" then
                b = self: expr (e.b, cmp and nil or want)
                a = self: expr (e.a, b.type)
            else
                a = self: expr (e.a, cmp and nil or want)
                b = self: expr (e.b, a.type)
            end
            if shift then
                if not integral(a.type) or not integral(b.type) then
                    return self: bad (("'%s' wants integer operands, got %s and %s")
                        :format(e.op, a.type.name, b.type.name))
                end
                return T(e.op, a.type, { a = a, b = b })
            end
            if bitwise then
                if not integral(a.type) or a.type ~= b.type then
                    return self: bad (("'%s' wants one integer type, got %s and %s")
                        :format(e.op, a.type.name, b.type.name))
                end
                return T(e.op, a.type, { a = a, b = b })
            end
            if e.op == "land" or e.op == "lor" then
                if a.type ~= bool or b.type ~= bool then
                    return self: bad (("'%s' wants bool operands, got %s and %s")
                        :format(e.op, a.type.name, b.type.name))
                end
                return T(e.op, bool, { a = a, b = b })
            end
            if not numeric(a.type) or a.type ~= b.type then
                return self: bad (("'%s' wants one numeric type, got %s and %s")
                    :format(e.op, a.type.name, b.type.name))
            end
            return T(e.op, cmp and bool or a.type, { a = a, b = b })
            end)
        def_check: select (expr, type) (function(self, e, want)
            local c = self: expr (e.cond, bool)
            local t = self: expr (e.t, want)
            local f = self: expr (e.f, t.type)
            if c.type ~= bool or t.type ~= f.type then
                return self: bad ("if_ value branches need one type")
            end
            return T("select", t.type, { cond = c, t = t, f = f })
            end)
        def_check: pipeline_reduce (expr, type) (function(self, e)
            local producer = self: producer (e.producer)
            local value = self: expr (e.value)
            local init = self: expr (e.init, value.type)
            if not numeric(value.type) or init.type ~= value.type then
                self: bad ("reduce value and initial value need one numeric type")
            end
            return T("pipeline_reduce", value.type, { producer = producer,
                value = value, init = init, reducer = e.reducer })
            end)

        def_check: if_ (stmt) (function(self, s)
            local c = self: expr (s.cond, bool)
            if c.type ~= bool then
                self: bad ("if_ condition must be bool, got " .. c.type.name)
            end
            return { op = "if_", cond = c, t = self: stmt (s.t),
                     f = self: stmt (s.f) }
            end)

        def_check: jump (stmt) (function(self, s)
            local b, vs = s.target, {}
            for i, a in ipairs(s.args) do
                vs[i] = self: expr (a, b.ptypes[i])
                if b.ptypes[i] and vs[i].type ~= b.ptypes[i] then
                    self: bad (("block %s operand %d: expected %s, got %s")
                        :format(b.name, i, b.ptypes[i].name, vs[i].type.name))
                end
            end
            return { op = "jump", target = b, args = vs }
            end)

        def_check: go (stmt) (function(self, s)
            local d = s.dest
            if d.kind == "contref" then
                if #s.args ~= #d.types then
                    self: bad (("exit takes %d value(s), got %d")
                        :format(#d.types, #s.args))
                end
                local vs = {}
                for i, a in ipairs(s.args) do
                    vs[i] = self: expr (a, d.types[i])
                    if d.types[i] and vs[i].type ~= d.types[i] then
                        self: bad (("exit wants %s, got %s")
                            :format(d.types[i].name, vs[i].type.name))
                    end
                end
                return { op = "gok", ord = d.ord, args = vs }
            end
            local vs = {}
            for i, a in ipairs(s.args) do
                if type(a) == "table" and a.kind == "contref" then
                    vs[i] = { op = "contarg" }
                else
                    vs[i] = self: expr (a, d.params[i])
                    if d.params[i] and vs[i].type ~= d.params[i] then
                        self: bad (("%s operand %d: expected %s, got %s"):format(
                            d.name, i, d.params[i].name, vs[i].type.name))
                    end
                end
            end
            return { op = "tail", callee = d, args = vs }
            end)

        def_check: call (stmt) (function(self, s)
            local callee, args = s.callee, {}
            for i, a in ipairs(s.args) do
                args[i] = self: expr (a, callee.params[i])
                local want = callee.params[i]
                if want and want.kind ~= "cont" and args[i].type ~= want then
                    self: bad (("%s operand %d: expected %s, got %s"):format(
                        callee.name, i, want.name, args[i].type.name))
                end
            end
            local ks = {}
            for j, k in ipairs(s.ks) do
                ks[j] = { bind = k.bind and k.bind.id or nil,
                          btype = k.bind and k.bind.type or nil,
                          body = self: stmt (k.body) }
            end
            return { op = "call", callee = callee, args = args, ks = ks }
            end)
        def_check: dcall (stmt) (function(self, s)
            local args = {}
            for i, a in ipairs(s.args) do
                args[i] = self: expr (a, s.callee.params[i])
                if args[i].type ~= s.callee.params[i] then
                    self: bad (("%s operand %d has wrong type"):format(
                        s.callee.name, i))
                end
            end
            return { op = "dcall", callee = s.callee, args = args }
            end)
        def_check: return_value (stmt) (function(self, s)
            local value = self: expr (s.value, self.result_type)
            if value.type ~= self.result_type then
                self: bad (("return wants %s, got %s"):format(
                    self.result_type.name, value.type.name))
            end
            return { op = "return_value", value = value }
            end)
        def_check: store_place (stmt) (function(self, s)
            local p = self: place (s.place)
            local value = self: expr (s.value, p.type)
            if value.type ~= p.type then
                self: bad (("store wants %s, got %s"):format(
                    p.type.name, value.type.name))
            end
            return { op = "store_place", place = p, value = value }
            end)
        def_check: call_void (stmt) (function(self, s)
            local args = {}
            for i, a in ipairs(s.args) do
                args[i] = self: expr (a, s.callee.params[i])
                if args[i].type ~= s.callee.params[i] then
                    self: bad (("%s operand %d has wrong type"):format(
                        s.callee.name, i))
                end
            end
            return { op = "call_void", callee = s.callee, args = args }
            end)
        def_check: seq (stmt) (function(self, s)
            local list = {}
            for i, item in ipairs(s.list) do
                local checked = self: stmt (item)
                if i < #s.list then
                    local op = checked.op
                    if op ~= "store_place" and op ~= "call_void" then
                        self: bad (("seq item %d must be a store or void call"):format(i))
                    end
                end
                list[i] = checked
            end
            if #list > 0 and not is_terminator(list[#list]) then
                self: bad ("the last seq item must terminate the block")
            end
            return { op = "seq", list = list }
            end)
        def_check: switch (stmt) (function(self, s)
            local cond = self: expr (s.cond)
            if not (integral(cond.type) or cond.type == bool) then
                self: bad ("switch wants an integer or bool, got " .. cond.type.name)
            end
            local cases, seen = {}, {}
            for i, c in ipairs(s.cases) do
                local key = self: expr (c.key)
                if key.op ~= "const" or not integral(key.type) then
                    self: bad (("switch case %d must be an integer constant"):format(i))
                end
                if seen[key.value] then
                    self: bad ("duplicate switch case: " .. tostring(key.value))
                end
                seen[key.value] = true
                assert(c.block.kind == "block", "switch case must target a block")
                cases[i] = { key = key, target = c.block }
            end
            assert(s.default.kind == "block", "switch default must target a block")
            return { op = "switch", cond = cond, cases = cases,
                     default_target = s.default }
            end)

        def_check: producer (producer) (function(self, p)
            local first, last
            if p.first.kind == "const" and p.last.kind ~= "const" then
                last = self: expr (p.last)
                first = self: expr (p.first, last.type)
            else
                first = self: expr (p.first)
                last = self: expr (p.last, first.type)
            end
            if first.type ~= last.type or not integral(first.type) then
                self: bad ("range bounds must have one integer type")
            end
            return { source = p, first = first, last = last, type = first.type }
            end)

        def_check: pipeline_store (stmt) (function(self, s)
            local producer = self: producer (s.producer)
            local dst = self: expr (s.dst)
            local want = dst.type and dst.type.kind == "ptr" and dst.type.elem or nil
            if not want then self: bad ("store expects a pointer destination") end
            local value = self: expr (s.value, want)
            if want and value.type ~= want then
                self: bad (("store wants %s, got %s"):format(
                    want.name, value.type.name))
            end
            return { op = "pipeline_store", producer = producer, dst = dst,
                value = value }
            end)


        def_check: bad (string) (function(self, msg)
            self.errors[#self.errors + 1] = self.where .. ": " .. msg
            return T("poison", i32) end)

        def_check: func (func) (function(self, f)
            self.where, self.result_type = "in " .. f.name, f.result
            local blocks, vars = {}, {}
            for i, b in ipairs(f.blocks) do
                local checked = self: stmt (b.body)
                if not is_terminator(checked) then
                    self: bad ("block " .. b.name .. " must terminate")
                end
                blocks[i] = { src = b, body = checked }
            end
            for i, v in ipairs(f.vars) do vars[i] = self: place (v) end
            local body = self: stmt (f.body)
            if not is_terminator(body) then
                self: bad ("function body must terminate")
            end
            return { name = f.name, internal = f.internal, direct = f.direct,
                     result = f.result, params = f.params, conts = f.conts,
                     vars = vars, blocks = blocks, body = body }
            end)

    end)
    function m.new() return setmetatable({ errors = {} }, m.mt) end
    return m
end

--====================================================================
-- LAYER 3 : lowering
--====================================================================

local function lower_machine()
    local m = { methods = {} } m.mt = { __index = m.methods }
    local benv = L.new_env(_G)
    benv.i32 = i32
    benv.def_lower = L.keyword {
        name = "def_lower", env = benv, binds = true, body = true,
        identity = function(n) return { kind = "llabel", name = n } end,
        bind = function(s, body) m.methods[s.name] = body return s end,
    }

    L.run(benv, function()

        def_lower: newblock () (function(self)
            local b = { id = #self.blocks + 1, code = {} }
            self.blocks[b.id] = b return b end)
        def_lower: newreg (type) (function(self, T)
            self.nreg = self.nreg + 1 self.rt[self.nreg] = T return self.nreg end)
        def_lower: emit (opcode) (function(self, ...)
            local c = self.cur.code c[#c + 1] = { ... } end)

        def_lower: value (typed) (function(self, t)
            assert(self [t.op], "VALUE no method for op " .. tostring(t and t.op))
            return self [t.op] (self, t) end)
        def_lower: stmt  (typed) (function(self, s) return self [s.op] (self, s) end)

        def_lower: const (typed) (function(self, t)
            local d = self: newreg (t.type) self: emit ("const", d, t.value)
            return d end)
        def_lower: poison (typed) (function(self, t)
            local d = self: newreg (t.type) self: emit ("const", d, 0)
            return d end)
        def_lower: param  (typed) (function(self, t) return t.index end)
        def_lower: bparam (typed) (function(self, t)
            return self.bregs[t.block][t.index] end)
        def_lower: result (typed) (function(self, t) return self.rreg[t.id] end)
        def_lower: pload (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("load", d, self: value (t.ptr), self.pindex[t.producer])
            return d end)
        def_lower: fcall (typed) (function(self, t)
            local args = {}
            for i, a in ipairs(t.args) do args[i] = self: value (a) end
            local d = self: newreg (t.type)
            self: emit ("fcall", d, t.callee.name, args)
            return d end)
        def_lower: field_get (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("field_get", d, self: value(t.object), t.field.name)
            return d end)
        def_lower: struct_init (typed) (function(self, t)
            local d = self: newreg (t.type)
            local fields = {}
            for i, init in ipairs(t.fields) do
                fields[i] = { name = init.field.name, value = self: value(init.value) }
            end
            self: emit ("struct_init", d, t.struct, fields)
            return d end)

        def_lower: let (typed) (function(self, t)
            local reg = self.letregs[t.id]
            if not reg then
                reg = self: newreg (t.type)
                self: emit ("mov", reg, self: value (t.value))
                self.letregs[t.id] = reg
            end
            return reg end)
        def_lower: load (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("load_place", d, self: place (t.place))
            return d end)
        def_lower: address (typed) (function(self, t)
            local d = self: newreg (t.type)
            if t.place.type and t.place.type.kind == "array" then
                -- arrays decay: the lvalue name is already the pointer
                self: emit ("address_decay", d, self: place (t.place))
            else
                self: emit ("address_place", d, self: place (t.place))
            end
            return d end)
        def_lower: cast (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("cast", d, t.type, self: value (t.value))
            return d end)
        def_lower: sizeof (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("sizeof", d, t.of)
            return d end)
        def_lower: fnaddress (typed) (function(self, t)
            local d = self: newreg (t.type)
            self: emit ("fnaddress", d, t.func.name)
            return d end)
        def_lower: fncall (typed) (function(self, t)
            local args = {}
            for i, a in ipairs(t.args) do args[i] = self: value (a) end
            local d = self: newreg (t.type)
            self: emit ("fncall", d, self: value (t.callee), args)
            return d end)

        def_lower: place (place) (function(self, p)
            local method = ({ var = "place_var", at = "place_at",
                member = "place_member", deref = "place_deref",
                global = "place_global" })[p.place]
            assert(method, "unknown place tag: " .. tostring(p.place))
            return self [method] (self, p) end)
        def_lower: place_var (place) (function(self, p)
            return { lval = "reg", reg = self.pregs[p.id] } end)
        def_lower: place_global (place) (function(self, p)
            return { lval = "name", name = p.name } end)
        def_lower: place_at (place) (function(self, p)
            local base
            if p.array_base then
                base = self: place (p.ptr)
            else
                base = self: value (p.ptr)
            end
            local index = self: value (p.index)
            return { lval = "index", base = base, index = index } end)
        def_lower: place_member (place) (function(self, p)
            return { lval = "member", base = self: place (p.object), name = p.field.name } end)
        def_lower: place_deref (place) (function(self, p)
            return { lval = "deref", ptr = self: value (p.ptr) } end)

        def_lower: store_place (typed) (function(self, s)
            local value = self: value (s.value)
            self: emit ("store_place", self: place (s.place), value) end)
        def_lower: call_void (typed) (function(self, s)
            local args = {}
            for i, a in ipairs(s.args) do args[i] = self: value (a) end
            self: emit ("dcall", s.callee.name, args) end)
        def_lower: seq (typed) (function(self, s)
            for i, item in ipairs(s.list) do self: stmt (item) end end)
        def_lower: switch (typed) (function(self, s)
            local cond = self: value (s.cond)
            local cases = {}
            for i, c in ipairs(s.cases) do
                cases[i] = { value = c.key.value, target = self.bid[c.target] }
            end
            self.cur.term = { "switch", cond, cases, self.bid[s.default_target] }
            end)
        for _, op in ipairs { "add","sub","mul","div","mod","lt","le","eq","ne",
                             "and","or","xor","shl","shr","land","lor" } do
            def_lower [op] (def_lower, "typed") (function(self, t)
                local a, b = self: value (t.a), self: value (t.b)
                local d = self: newreg (t.type)
                self: emit (t.op, d, a, b)
                return d
                end)
        end
        def_lower: select (typed) (function(self, t)
            local c = self: value (t.cond)
            local bt, bf, join = self: newblock (), self: newblock (), self: newblock ()
            local d = self: newreg (t.type)
            self.cur.term = { "brc", c, bt.id, bf.id }
            self.cur = bt
            self: emit ("mov", d, self: value (t.t))
            self.cur.term = { "br", join.id }
            self.cur = bf
            self: emit ("mov", d, self: value (t.f))
            self.cur.term = { "br", join.id }
            self.cur = join
            return d end)

        def_lower: if_ (typed) (function(self, s)
            local c = self: value (s.cond)
            local bt, bf = self: newblock (), self: newblock ()
            self.cur.term = { "brc", c, bt.id, bf.id }
            self.cur = bt self: stmt (s.t)
            self.cur = bf self: stmt (s.f)
            end)

        -- compute every operand into a temporary FIRST, then assign the
        -- block's registers, then goto. That is what makes
        -- `loop(i - 1, acc + i)` safe.
        def_lower: jump (typed) (function(self, s)
            local vs = {}
            for i, a in ipairs(s.args) do vs[i] = self: value (a) end
            local regs = self.bregs[s.target]
            for i, v in ipairs(vs) do self: emit ("mov", regs[i], v) end
            self.cur.term = { "br", self.bid[s.target] }
            end)

        def_lower: gok (typed) (function(self, s)
            local v = s.args[1] and self: value (s.args[1]) or false
            if self.ncont == 1 then self.cur.term = { "ret", v }
            else self.cur.term = { "retn", s.ord, v } end
            end)

        def_lower: tail (typed) (function(self, s)
            local args = {}
            for _, a in ipairs(s.args) do
                if a.op ~= "contarg" then args[#args + 1] = self: value (a) end
            end
            self.cur.term = { "tail", s.callee.name, args }
            end)

        def_lower: call (typed) (function(self, s)
            local args = {}
            for i, a in ipairs(s.args) do args[i] = self: value (a) end
            local dtag = self: newreg (i32)
            local dsts, blocks = {}, {}
            for j, k in ipairs(s.ks) do
                dsts[j]   = k.bind and self: newreg (k.btype) or false
                blocks[j] = self: newblock ()
                if k.bind then self.rreg[k.bind] = dsts[j] end
            end
            self.cur.term = { "calln", dtag, dsts, s.callee.name, args, blocks }
            for j, k in ipairs(s.ks) do
                self.cur = blocks[j] self: stmt (k.body)
            end
            end)
        def_lower: dcall (typed) (function(self, s)
            local args = {}
            for i, a in ipairs(s.args) do args[i] = self: value (a) end
            self: emit ("dcall", s.callee.name, args)
            self.cur.term = { "ret", false }
            end)
        def_lower: return_value (typed) (function(self, s)
            local value = self: value (s.value)
            self.cur.term = { "ret", value }
            end)

        def_lower: pipeline_store (typed) (function(self, s)
            local first = self: value (s.producer.first)
            local last = self: value (s.producer.last)
            local dst = self: value (s.dst)
            local index = self: newreg (s.producer.type)
            self: emit ("mov", index, first)
            local test, body, finish = self: newblock (), self: newblock (), self: newblock ()
            self.cur.term = { "br", test.id }
            self.cur = test
            local condition = self: newreg (bool)
            self: emit ("lt", condition, index, last)
            self.cur.term = { "brc", condition, body.id, finish.id }
            self.cur = body
            self.pindex[s.producer.source] = index
            local value = self: value (s.value)
            self: emit ("store", dst, index, value)
            local one = self: newreg (s.producer.type)
            local next_index = self: newreg (s.producer.type)
            self: emit ("const", one, 1)
            self: emit ("add", next_index, index, one)
            self: emit ("mov", index, next_index)
            self.cur.term = { "br", test.id }
            self.pindex[s.producer.source] = nil
            self.cur = finish
            self.cur.term = { "ret", false }
            end)

        def_lower: pipeline_reduce (typed) (function(self, s)
            local first = self: value (s.producer.first)
            local last = self: value (s.producer.last)
            local init = self: value (s.init)
            local index = self: newreg (s.producer.type)
            local acc = self: newreg (s.type)
            self: emit ("mov", index, first)
            self: emit ("mov", acc, init)
            local test, body, finish = self: newblock (), self: newblock (), self: newblock ()
            self.cur.term = { "br", test.id }
            self.cur = test
            local condition = self: newreg (bool)
            self: emit ("lt", condition, index, last)
            self.cur.term = { "brc", condition, body.id, finish.id }
            self.cur = body
            self.pindex[s.producer.source] = index
            local value = self: value (s.value)
            local next_acc = self: newreg (s.type)
            self: emit (s.reducer.op, next_acc, acc, value)
            self: emit ("mov", acc, next_acc)
            local one = self: newreg (s.producer.type)
            local next_index = self: newreg (s.producer.type)
            self: emit ("const", one, 1)
            self: emit ("add", next_index, index, one)
            self: emit ("mov", index, next_index)
            self.cur.term = { "br", test.id }
            self.pindex[s.producer.source] = nil
            self.cur = finish
            return acc
            end)

        def_lower: func (checked_func) (function(self, cf)
            local nval = #cf.params
            self.blocks, self.rreg, self.rt, self.pindex = {}, {}, {}, {}
            self.bregs, self.bid = {}, {}
            self.pregs, self.letregs = {}, {}
            self.nreg, self.ncont = nval, #cf.conts
            for i = 1, nval do self.rt[i] = cf.params[i] end

            local entry = self: newblock ()
            for _, b in ipairs(cf.blocks) do
                local regs = {}
                for i, T in ipairs(b.src.ptypes) do regs[i] = self: newreg (T) end
                self.bregs[b.src] = regs
                self.bid[b.src]   = self: newblock ().id
            end

            self.cur = entry
            for _, v in ipairs(cf.vars) do
                local reg = self: newreg (v.type)
                self.pregs[v.id] = reg
                self: emit ("mov", reg, self: value (v.init))
            end
            self: stmt (cf.body)
            for _, b in ipairs(cf.blocks) do
                self.cur = self.blocks[self.bid[b.src]]
                self: stmt (b.body)
            end
            return { name = cf.name, internal = cf.internal, direct = cf.direct,
                     result = cf.result, nparams = nval, frame = self.nreg,
                     conts = cf.conts, params = cf.params, rt = self.rt,
                     entry = entry.id, blocks = self.blocks }
            end)

    end)
    function m.new() return setmetatable({ blocks = {}, nreg = 0 }, m.mt) end
    return m
end

--====================================================================
-- LAYER 4 : C
--====================================================================

local BINOP = { add="+", sub="-", mul="*", div="/", mod="%",
                lt="<", le="<=", eq="==", ne="!=",
                ["and"]="&", ["or"]="|", xor="^", shl="<<", shr=">>",
                land="&&", lor="||" }
local function LV(x)
    if x.lval == "reg" then return ("r%d"):format(x.reg)
    elseif x.lval == "index" then
        local b = type(x.base) == "number" and ("r%d"):format(x.base) or LV(x.base)
        return b .. "[r" .. x.index .. "]"
    elseif x.lval == "member" then
        local base = x.base
        if base.lval == "deref" then return ("r%d->%s"):format(base.ptr, x.name) end
        return LV(base) .. "." .. x.name
    elseif x.lval == "deref" then return "*r" .. x.ptr
    elseif x.lval == "name" then return x.name end
end

local function field_ctype(T, name)
    if T.kind == "array" then
        return ("%s %s[%d]"):format(ctype(T.elem), name, T.count)
    end
    if T.kind == "fnptr" then
        local ps = {}
        for i, P in ipairs(T.params) do ps[i] = ctype(P) end
        if #ps == 0 then ps[1] = "void" end
        return ("%s (*%s)(%s)"):format(ctype(T.result), name, table.concat(ps, ", "))
    end
    return ctype(T) .. " " .. name
end

local function sig(f)
    local ps = {}
    for i = 1, f.nparams do ps[#ps+1] = field_ctype(f.params[i], "r" .. i) end
    local ret
    if f.direct then
        assert(f.result.kind ~= "fnptr", f.name .. ": cannot return a function pointer")
        ret = ctype(f.result)
    else
        ret = "int"
        for _, c in ipairs(f.conts) do
            if c.types[1] then
                ps[#ps+1] = ("%s *k%d_out"):format(ctype(c.types[1]), c.ord)
            end
        end
    end
    if #ps == 0 then ps[1] = "void" end
    return ("%s%s %s(%s)"):format(f.internal and "static " or "",
        ret, f.name, table.concat(ps, ", "))
end

local function init_c(init)
    if type(init) == "number" then return tostring(init) end
    if type(init) == "string" then
        local escaped = init:gsub("\\", "\\\\"):gsub('"', '\\"')
        return '"' .. escaped .. '"'
    end
    if type(init) == "table" then
        local parts = {}
        for i, v in ipairs(init) do parts[i] = tostring(v) end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    error("global initializer must be a number, string, or table", 3)
end

local function codegen(funcs, externs, structs, globals)
    local out = {}
    local function w(fmt, ...) out[#out+1] = select("#", ...) > 0
        and fmt:format(...) or fmt end
    local function R(x) return ("r%d"):format(x) end

    w("#include <stdint.h>") w("#include <stdbool.h>") w("#include <stddef.h>") w("")
    for _, T in ipairs(structs) do w("typedef %s %s %s;", T.kind, T.c, T.c) end
    if #structs > 0 then w("") end
    local emitted, emitting = {}, {}
    local function nested_structs(T)
        if T.kind == "ptr" then return nested_structs(T.elem) end
        if T.kind == "array" then return nested_structs(T.elem) end
        if T.kind == "struct" or T.kind == "union" then return T end
    end
    local function emit_aggregate(T)
        if emitted[T] then return end
        assert(not emitting[T], "recursive value layout: " .. T.c)
        emitting[T] = true
        for _, field in ipairs(T.fields) do
            local nested = nested_structs(field.type)
            if nested then emit_aggregate(nested) end
        end
        w("%s %s {", T.kind, T.c)
        for _, field in ipairs(T.fields) do
            w("  %s;", field_ctype(field.type, field.name))
        end
        w("};") w("")
        emitting[T], emitted[T] = nil, true
    end
    for _, T in ipairs(structs) do emit_aggregate(T) end
    local opaque_tags = {}
    local function note_type(T)
        if type(T) ~= "table" then return end
        if T.kind == "ptr" then note_type(T.elem) end
        if T.kind == "opaque" then opaque_tags[T.c] = true end
    end
    for _, f in ipairs(externs) do
        for i = 1, #f.params do note_type(f.params[i]) end
        if f.result then note_type(f.result) end
    end
    for _, f in ipairs(funcs) do
        for i = 1, #f.params do note_type(f.params[i]) end
        if f.result then note_type(f.result) end
        for _, c in ipairs(f.conts) do
            for _, t in ipairs(c.types) do note_type(t) end
        end
    end
    for tag in pairs(opaque_tags) do w("%s;", tag) end
    if next(opaque_tags) then w("") end
    for _, g in ipairs(globals or {}) do
        w("static %s = %s;", field_ctype(g.type, g.name), init_c(g.init))
    end
    if #(globals or {}) > 0 then w("") end
    for _, f in ipairs(externs) do w("%s;", sig(f)) end
    if #externs > 0 then w("") end
    for _, f in ipairs(funcs) do w("%s;", sig(f)) end
    w("")

    for _, f in ipairs(funcs) do
        w("%s {", sig(f))
        for i = f.nparams + 1, f.frame do
            if f.rt[i] then w("  %s;", field_ctype(f.rt[i], "r" .. i)) end
        end
        for id, b in ipairs(f.blocks) do
            w("B%d: ;", id)
            for _, i in ipairs(b.code) do
                if i[1] == "const"   then w("  r%d = %s;", i[2], tostring(i[3]))
                elseif i[1] == "mov" then w("  r%d = r%d;", i[2], i[3])
                elseif i[1] == "load" then w("  r%d = r%d[r%d];", i[2], i[3], i[4])
                elseif i[1] == "store" then w("  r%d[r%d] = r%d;", i[2], i[3], i[4])
                elseif i[1] == "load_place" then w("  r%d = %s;", i[2], LV(i[3]))
                elseif i[1] == "store_place" then w("  %s = r%d;", LV(i[2]), i[3])
                elseif i[1] == "address_place" then w("  r%d = &%s;", i[2], LV(i[3]))
                elseif i[1] == "address_decay" then w("  r%d = %s;", i[2], LV(i[3]))
                elseif i[1] == "cast" then w("  r%d = (%s)r%d;", i[2], ctype(i[3]), i[4])
                elseif i[1] == "sizeof" then w("  r%d = sizeof(%s);", i[2], ctype(i[3]))
                elseif i[1] == "fnaddress" then w("  r%d = &%s;", i[2], i[3])
                elseif i[1] == "fncall" then
                    local as = {} for j, a in ipairs(i[4]) do as[j] = R(a) end
                    w("  r%d = %s(%s);", i[2], R(i[3]), table.concat(as, ", "))
                elseif i[1] == "fcall" then
                    local as = {} for j, a in ipairs(i[4]) do as[j] = R(a) end
                    w("  r%d = %s(%s);", i[2], i[3], table.concat(as, ", "))
                elseif i[1] == "dcall" then
                    local as = {} for j, a in ipairs(i[3]) do as[j] = R(a) end
                    w("  %s(%s);", i[2], table.concat(as, ", "))
                elseif i[1] == "field_get" then
                    w("  r%d = r%d.%s;", i[2], i[3], i[4])
                elseif i[1] == "struct_init" then
                    local fs = {}
                    for j, field in ipairs(i[4]) do
                        fs[j] = (".%s = %s"):format(field.name, R(field.value))
                    end
                    w("  r%d = (%s){ %s };", i[2], ctype(i[3]), table.concat(fs, ", "))
                else w("  r%d = r%d %s r%d;", i[2], i[3], BINOP[i[1]], i[4]) end
            end
            local t = b.term
            if not t then w("  ;")
            elseif t[1] == "br"  then w("  goto B%d;", t[2])
            elseif t[1] == "brc" then
                w("  if (%s) goto B%d; else goto B%d;", R(t[2]), t[3], t[4])
            elseif t[1] == "switch" then
                w("  switch (%s) {", R(t[2]))
                for _, c in ipairs(t[3]) do
                    w("  case %s: goto B%d;", tostring(c.value), c.target)
                end
                w("  default: goto B%d;", t[4])
                w("  }")
            elseif t[1] == "ret" then
                w(t[2] and ("  return " .. R(t[2]) .. ";") or "  return;")
            elseif t[1] == "retn" then
                if t[3] then w("  *k%d_out = %s;", t[2], R(t[3])) end
                w("  return %d;", t[2])
            elseif t[1] == "tail" then
                local as = {} for i, a in ipairs(t[3]) do as[i] = R(a) end
                local c = ("%s(%s)"):format(t[2], table.concat(as, ", "))
                w(#f.conts == 1 and f.conts[1].types[1]
                  and ("  return %s;"):format(c) or ("  %s; return;"):format(c))
            elseif t[1] == "call" then
                local as = {} for i, a in ipairs(t[4]) do as[i] = R(a) end
                local c = ("%s(%s)"):format(t[3], table.concat(as, ", "))
                w(t[2] and ("  r%d = %s;"):format(t[2], c) or ("  %s;"):format(c))
                w("  goto B%d;", t[5])
            elseif t[1] == "calln" then
                local as = {} for i, a in ipairs(t[5]) do as[i] = R(a) end
                for _, d in ipairs(t[3]) do if d then as[#as+1] = "&" .. R(d) end end
                w("  r%d = %s(%s);", t[2], t[4], table.concat(as, ", "))
                for j, blk in ipairs(t[6]) do
                    w("  %s (r%d == %d) goto B%d;",
                      j == 1 and "if" or "else if", t[2], j, blk.id)
                end
            end
        end
        w("}") w("")
    end
    return table.concat(out, "\n")
end

--====================================================================
-- Lazy host execution through libtcc
--====================================================================

local Runtime = {}
Runtime.__index = Runtime
local runtime_serial = 0

function Runtime:field_decl(T, name)
    if T.kind == "array" then
        return ("%s %s[%d]"):format(self:type_name(T.elem), name, T.count)
    end
    return self:type_name(T) .. " " .. name
end

function Runtime:type_name(T)
    if T.kind == "ptr" then return self:type_name(T.elem) .. " *" end
    if T.kind == "array" then return self:type_name(T.elem) .. " [" .. T.count .. "]" end
    if T.kind == "opaque" then return T.c end
    if T.kind == "fnptr" then
        local ps = {}
        for i, P in ipairs(T.params) do ps[i] = self:type_name(P) end
        if #ps == 0 then ps[1] = "void" end
        return ("%s (*)(%s)"):format(self:type_name(T.result), table.concat(ps, ", "))
    end
    local name
    if T.kind == "struct" or T.kind == "union" then
        name = self.struct_names[T]
        assert(name, "aggregate is not exported: " .. T.name)
    else
        name = T.c
        assert(name, "type has no host ABI representation: " .. tostring(T.name))
    end
    return name
end

function Runtime:ensure_ffi()
    if self.ffi then return self.ffi end
    assert(not self.freed, "CBlock JIT module is freed")
    local ffi = require("ffi")
    self.ffi = ffi
    self.struct_names = {}
    local prefix = ("CBlockJit%d_"):format(self.id)
    local declarations = {}
    for i, T in ipairs(self.structs) do
        local name = prefix .. i
        self.struct_names[T] = name
        declarations[#declarations + 1] =
            ("typedef %s %s %s;"):format(T.kind, name, name)
    end
    local emitted, emitting = {}, {}
    local function nested(T)
        if T.kind == "ptr" then return nested(T.elem) end
        if T.kind == "array" then return nested(T.elem) end
        if T.kind == "struct" or T.kind == "union" then return T end
    end
    local function emit_aggregate(T)
        if emitted[T] then return end
        assert(not emitting[T], "recursive value layout: " .. T.name)
        emitting[T] = true
        for _, field in ipairs(T.fields) do
            local n = nested(field.type)
            if n then emit_aggregate(n) end
        end
        local name = self.struct_names[T]
        declarations[#declarations + 1] = ("%s %s {"):format(T.kind, name)
        for _, field in ipairs(T.fields) do
            declarations[#declarations + 1] = ("  %s;"):format(
                self:field_decl(field.type, field.name))
        end
        declarations[#declarations + 1] = "};"
        emitting[T], emitted[T] = nil, true
    end
    for _, T in ipairs(self.structs) do emit_aggregate(T) end
    if #declarations > 0 then ffi.cdef(table.concat(declarations, "\n")) end
    return ffi
end

function Runtime:construct(T, values)
    assert(type(values) == "table",
        "host aggregate construction expects a field table")
    local ffi = self:ensure_ffi()
    local value = ffi.new(self:type_name(T))
    if T.kind == "union" then
        local n = 0
        local active
        for key in pairs(values) do n = n + 1 active = key end
        assert(n == 1, "union construction needs exactly one active field")
        local field = T.by_name[active]
        assert(field, "unknown union field: " .. tostring(active))
        value[active] = values[active]
    else
        for _, field in ipairs(T.fields) do
            local field_value = values[field.name]
            assert(field_value ~= nil, "missing struct field: " .. field.name)
            value[field.name] = field_value
        end
        for key in pairs(values) do
            assert(T.by_name[key], "unknown struct field: " .. tostring(key))
        end
    end
    return value
end

function Runtime:function_type(f)
    local parameters = {}
    for _, T in ipairs(f.params) do
        parameters[#parameters + 1] = self:type_name(T)
    end
    local result
    if f.direct then
        result = self:type_name(f.result)
    else
        result = "int"
        for _, exit in ipairs(f.conts) do
            if exit.types[1] then
                parameters[#parameters + 1] = self:type_name(exit.types[1]) .. " *"
            end
        end
    end
    if #parameters == 0 then parameters[1] = "void" end
    return ("%s (*)(%s)"):format(result, table.concat(parameters, ", "))
end

function Runtime:ensure_native()
    assert(not self.freed, "CBlock JIT module is freed")
    if self.session then return self.session end
    self:ensure_ffi()
    local session, err = require("cblock_tcc").compile(self.source, self.options)
    assert(session, err)
    self.session = session
    return session
end

function Runtime:function_pointer(f)
    local pointer = self.function_pointers[f]
    if pointer then return pointer end
    local session = self:ensure_native()
    local err
    pointer, err = session:symbol(f.name, self:function_type(f))
    assert(pointer, err)
    self.function_pointers[f] = pointer
    return pointer
end

function Runtime:invoke(f, ...)
    local got, expected = select("#", ...), #f.params
    if got ~= expected then
        error(("%s takes %d host operand(s), got %d"):format(
            f.name, expected, got), 2)
    end
    local arguments = { ... }
    for i, T in ipairs(f.params) do
        if T.kind == "struct" and type(arguments[i]) == "table" then
            arguments[i] = self:construct(T, arguments[i])
        end
    end
    local pointer = self:function_pointer(f)
    if f.direct then return pointer(unpack(arguments, 1, got)) end

    local ffi = self:ensure_ffi()
    local outputs = {}
    for ordinal, exit in ipairs(f.conts) do
        if exit.types[1] then
            local output = ffi.new(self:type_name(exit.types[1]) .. "[1]")
            outputs[ordinal] = output
            arguments[#arguments + 1] = output
        end
    end
    local ordinal = tonumber(pointer(unpack(arguments, 1, #arguments)))
    local exit = assert(f.conts[ordinal], "native function returned an invalid exit ordinal")
    local output = outputs[ordinal]
    if output then return exit.name, output[0] end
    return exit.name
end

function Runtime:attach(root)
    local seen = {}
    local function visit(value)
        local mt = type(value) == "table" and getmetatable(value) or nil
        if mt == Func_mt then
            rawset(value, "host_runtime", self)
            return
        end
        if mt == Struct_mt then
            rawset(value, "host_runtime", self)
            return
        end
        if type(value) ~= "table" or value.kind ~= nil or seen[value] then return end
        seen[value] = true
        for _, child in pairs(value) do visit(child) end
    end
    visit(root)
end

function Runtime:free()
    if self.freed then return end
    if self.session then self.session:free() self.session = nil end
    self.function_pointers = {}
    self.freed = true
end

local function collect_private_structs(list, functions)
    local serial = 0
    local function reg(T)
        if type(T) ~= "table" then return end
        if T.kind == "ptr" or T.kind == "array" then reg(T.elem) return end
        if (T.kind ~= "struct" and T.kind ~= "union") or rawget(T, "c") then
            return
        end
        serial = serial + 1
        local name = ("cblock_s%d"):format(serial)
        rawset(T, "name", name)
        rawset(T, "c", name)
        list[#list + 1] = T
        for _, field in ipairs(T.fields) do reg(field.type) end
    end
    for _, f in ipairs(functions) do
        for _, T in ipairs(f.params) do reg(T) end
        if f.result then reg(f.result) end
        for _, c in ipairs(f.conts) do
            for _, t in ipairs(c.types) do reg(t) end
        end
        for _, b in ipairs(f.blocks) do
            for _, T in ipairs(b.ptypes) do reg(T) end
        end
        for _, v in ipairs(f.vars) do reg(v.type) end
    end
end

local function compile_program(build)
    local env = source_env(_G)
    local root = L.run(env, build)
    env.__finish(root)
    collect_private_structs(env.__structs, env.__functions)
    local checker = check_machine().new()
    local checked = {}
    for i, f in ipairs(env.__functions) do checked[i] = checker: func (f) end
    if #checker.errors > 0 then return nil, checker.errors end
    local lm, lowered = lower_machine(), {}
    for i, cf in ipairs(checked) do lowered[i] = lm.new(): func (cf) end
    local source = codegen(lowered, env.__externs, env.__structs, env.__globals)
    return source, lowered, {
        root = root, functions = env.__functions, externs = env.__externs,
        structs = env.__structs, globals = env.__globals,
    }
end

function M.compile(build)
    return compile_program(build)
end

function M.jit(build, options)
    local source, lowered_or_errors, program = compile_program(build)
    if not source then return nil, lowered_or_errors end
    runtime_serial = runtime_serial + 1
    local runtime = setmetatable({
        id = runtime_serial, source = source, options = options or {},
        structs = program.structs, function_pointers = {},
    }, Runtime)
    runtime:attach(program.root)
    local module_methods = {
        free = function() return runtime:free() end,
        source = source,
    }
    setmetatable(program.root, { __index = module_methods })
    return program.root, runtime
end

return M
