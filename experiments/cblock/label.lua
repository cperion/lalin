-- label.lua -- keyword: name (operands) (function(...) end)
-- Lua 5.1 / LuaJIT.
local unpack = unpack or table.unpack

--------------------------------------------------------------------
-- 1. Environments
--------------------------------------------------------------------
-- An env is an ordinary table whose __index chains to a parent.
-- Named forms rawset into it; bare names resolve through it.

local function new_env(parent)
    return setmetatable({}, {
        __index = parent,
        __name  = "env",
    })
end

--------------------------------------------------------------------
-- 2. Registry
--------------------------------------------------------------------
-- Keyword internals live OUTSIDE the keyword table, because
-- Keyword.__index is a function: any self-access from inside it
-- (kw.spec, kw.labels, ...) re-enters the metamethod. Keeping the
-- keyword table completely empty means every field access on it is
-- unambiguously a label lookup.

local kwdata = setmetatable({}, { __mode = "k" })

local Label_mt, Binder_mt = {}, {}

--------------------------------------------------------------------
-- 3. Keyword
--------------------------------------------------------------------

local Keyword_mt = {}

local function make_label(kw, d, name)
    local label = setmetatable({
        kw     = kw,
        name   = name,
        sealed = false,
    }, Label_mt)

    -- Fresh keywords (`param`, `field`) mint a new identity on every
    -- use: they exist to attach a name to a value, not to create a
    -- referenceable entity. Only stable keywords publish and seal.
    if d.fresh then return label end

    -- PHASE 1: publish identity.
    -- Runs during `kw.name` lookup, i.e. BEFORE the operands are
    -- evaluated. That is what lets `struct: node { field: next (ptr(node)) }`
    -- resolve `node` inside its own definition.
    label.identity = d.identity(name, d)

    if d.binds then
        rawset(d.env, name, label.identity)
    end

    return label
end

function Keyword_mt.__index(kw, name)
    if type(name) ~= "string" then return nil end
    if name:sub(1, 2) == "__" then return nil end   -- keep introspection sane

    local d = kwdata[kw]
    local label = d.labels[name]
    if label == nil then
        label = make_label(kw, d, name)
        d.labels[name] = label
    end
    return label
end

function Keyword_mt.__newindex()
    error("keywords are read-only", 2)
end

function Keyword_mt.__tostring(kw)
    return "keyword<" .. kwdata[kw].name .. ">"
end

-- spec = {
--   name     = string
--   env      = table      -- where named results bind
--   binds    = bool       -- false for carrier keywords like `field`
--   body     = bool       -- true if the form takes a (function ... end) body
--   identity = f(name, d) -> stub          (phase 1)
--   build    = f(stub, ...) -> value       (phase 2, bodyless)
--   bind     = f(stub, body, ...) -> value (phase 2, body-bearing)
-- }
local function keyword(spec)
    local kw = setmetatable({}, Keyword_mt)
    spec.labels = {}
    spec.identity = spec.identity or function(name) return { name = name } end
    if spec.fresh == nil then spec.fresh = not spec.binds end
    kwdata[kw] = spec
    return kw
end

--------------------------------------------------------------------
-- 4. Label  --  keyword: name (operands)
--------------------------------------------------------------------

function Label_mt.__call(label, receiver, ...)
    local d = kwdata[label.kw]

    -- colon syntax passes the keyword as receiver; dot syntax does not.
    if receiver ~= label.kw then
        error(("%s.%s(...) -- use colon syntax: %s: %s (...)")
            :format(d.name, label.name, d.name, label.name), 2)
    end

    if label.sealed then
        error(("redefinition of %s: %s"):format(d.name, label.name), 2)
    end

    local identity = d.fresh and d.identity(label.name, d) or label.identity

    if d.body then
        return setmetatable({ label = label, identity = identity,
                              n = select("#", ...), ... }, Binder_mt)
    end

    if not d.fresh then label.sealed = true end
    -- PHASE 2: complete the identity.
    local value = d.build(identity, ...)
    -- Aliases return a DIFFERENT object than the published stub, so
    -- rebind. Anything that captured the stub mid-construction still
    -- sees the stub -- which is why recursive forms must complete
    -- their identity in place rather than returning a new value.
    if value ~= identity and d.binds then
        rawset(d.env, label.name, value)
    end
    return value
end

function Label_mt.__tostring(label)
    return kwdata[label.kw].name .. ":" .. label.name
end

--------------------------------------------------------------------
-- 5. Binder  --  the (function ... end) half
--------------------------------------------------------------------


function Binder_mt.__call(binder, body)
    local label    = binder.label
    local d        = kwdata[label.kw]
    local identity = binder.identity
    if not d.fresh then label.sealed = true end
    local value = d.bind(identity, body, unpack(binder, 1, binder.n))
    if value ~= identity and d.binds and not d.fresh then
        rawset(d.env, label.name, value)
    end
    return value
end

function Binder_mt.__tostring(b)
    return "pending<" .. tostring(b.label) .. ">"
end

--------------------------------------------------------------------
-- 6. Forward declaration
--------------------------------------------------------------------
-- `struct.node` alone is not a valid Lua statement, so mutual
-- recursion needs a way to force the __index that publishes the stub.
-- declare() is a no-op whose *arguments* do the work.

local function declare(...)
    for i = 1, select("#", ...) do
        local label = select(i, ...)
        assert(getmetatable(label) == Label_mt, "declare expects keyword.name")
    end
end

--------------------------------------------------------------------
-- 7. Running a DSL chunk under an environment
--------------------------------------------------------------------

local setfenv = setfenv
if not setfenv then                       -- 5.2+ shim
    setfenv = function(f, env)
        local i = 1
        while true do
            local n = debug.getupvalue(f, i)
            if not n then break end
            if n == "_ENV" then
                debug.upvaluejoin(f, i, function() return env end, 1)
                break
            end
            i = i + 1
        end
        return f
    end
end

local function run(env, chunk)
    setfenv(chunk, env)
    return chunk()
end

return {
    new_env = new_env,
    keyword = keyword,
    declare = declare,
    run     = run,
    is_label = function(x) return getmetatable(x) == Label_mt end,
}
