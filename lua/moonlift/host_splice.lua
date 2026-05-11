-- host_splice.lua — single coercion point for splice-hole filling.
--
-- Turns Lua host values into MoonOpen.SlotBinding given a parser-determined
-- slot role.  This is the ONLY place that decides what a Lua value means for
-- a particular slot kind.
--
-- Patterns used:
--   pvm.classof(node) == SomeConcreteClass   -- ASDL class check (standard)
--   pvm.classof(node) ~= false               -- "is any ASDL node?"
--   duck-typing on well-known Lua fields      -- for host value types

local pvm = require("moonlift.pvm")

local M = {}

-- ── Classification ────────────────────────────────────────────────────────────

-- Return a human-readable kind string for error messages.
function M.kind_of(value)
    local tv = type(value)
    if tv ~= "table" and tv ~= "userdata" then return tv end
    local kind = rawget(value, "moonlift_quote_kind") or rawget(value, "kind")
    if kind then return kind end
    if type(value.as_type_value) == "function" then return "type_value" end
    if type(value.as_expr_value) == "function" then return "expr_value" end
    local cls = pvm.classof(value)
    if cls and cls.kind then return cls.kind end
    return "table"
end

-- ── Protocol helper ───────────────────────────────────────────────────────────

-- Ask a host value to splice itself into the given role.
-- Returns the role-specific result, or nil if the value has no protocol.
local function protocol(value, role, session, site)
    if (type(value) == "table" or type(value) == "userdata")
        and type(value.moonlift_splice) == "function" then
        return value:moonlift_splice(role, session, site)
    end
    return nil
end

-- ── Top-level dispatch ────────────────────────────────────────────────────────

-- Fill a parser-produced Slot sum wrapper with a Lua value.
function M.fill(session, slot, value, site)
    local O = session.T.MoonOpen
    local cls = pvm.classof(slot)

    if cls == O.SlotType       then return M.fill_type(session, slot.slot, value, site) end
    if cls == O.SlotExpr       then return M.fill_expr(session, slot.slot, value, site) end
    if cls == O.SlotRegion     then return M.fill_region_body(session, slot.slot, value, site) end
    if cls == O.SlotRegionFrag then return M.fill_region_frag(session, slot.slot, value, site) end
    if cls == O.SlotExprFrag   then return M.fill_expr_frag(session, slot.slot, value, site) end
    if cls == O.SlotName       then return M.fill_name(session, slot.slot, value, site) end

    error((site or "splice") .. ": unsupported splice slot class " .. tostring(cls), 2)
end

-- ── Type slot ─────────────────────────────────────────────────────────────────

-- Accepted:  host TypeValue (as_type_value()), direct MoonType ASDL node.
-- Rejected:  bare string, number, boolean, nil, fragment values.
function M.fill_type(session, slot, value, site)
    local O = session.T.MoonOpen

    local ty = nil

    -- 1. Protocol method (TypeValue returns self.ty)
    local p = protocol(value, "type", session, site)
    if p ~= nil then ty = p end

    -- 2. Duck-typed: as_type_value()
    if not ty and type(value) == "table"
               and type(value.as_type_value) == "function" then
        ty = value:as_type_value().ty
    end

    -- 3. Raw ASDL type node passed directly (pvm.classof is non-false for ASDL nodes)
    if not ty and pvm.classof(value) ~= false then
        ty = value
    end

    if not ty then
        error((site or "splice") .. ": expected type value for @{} type splice, got " .. M.kind_of(value), 2)
    end

    local ok, binding = pcall(function()
        return O.SlotBinding(O.SlotType(slot), O.SlotValueType(ty))
    end)
    if ok then return binding end
    error((site or "splice") .. ": type value context mismatch; use the active session's moon.* API", 2)
end

-- ── Expression slot ───────────────────────────────────────────────────────────

-- Accepted:  number (int/float lit), boolean (bool lit), nil (nil lit),
--            string (string literal), host ExprValue (as_expr_value()),
--            direct Expr ASDL node.
function M.fill_expr(session, slot, value, site)
    local T  = session.T
    local C, Tr, O = T.MoonCore, T.MoonTree, T.MoonOpen

    local expr = nil

    -- 1. Protocol method
    local p = protocol(value, "expr", session, site)
    if p ~= nil then
        -- protocol may return an Expr ASDL node directly
        if pvm.classof(p) ~= false then
            expr = p
        else
            expr = p  -- let the SlotValueExpr constructor validate it
        end
    end

    -- 2. Primitive Lua values → literal ASDL nodes
    if not expr then
        local tv = type(value)
        if tv == "number" then
            if value == math.floor(value) and value >= -2^31 and value < 2^31 then
                expr = Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(math.floor(value))))
            else
                expr = Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(value)))
            end
        elseif tv == "boolean" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitBool(value))
        elseif tv == "nil" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitNil)
        elseif tv == "string" then
            expr = Tr.ExprLit(Tr.ExprSurface, C.LitString(value))
        end
    end

    -- 3. Host ExprValue or direct ASDL Expr node.
    if not expr and type(value) == "table" then
        if type(value.as_expr_value) == "function" then
            expr = value:as_expr_value().expr
        elseif pvm.classof(value) ~= false then
            expr = value
        end
    end

    if not expr then
        error((site or "splice") .. ": expected expression value for @{} expr splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExpr(slot), O.SlotValueExpr(expr))
end

-- ── Region body slot (inline statement list) ──────────────────────────────────

function M.fill_region_body(session, slot, value, site)
    local O = session.T.MoonOpen

    local stmts = nil

    local p = protocol(value, "region_body", session, site)
    if p ~= nil then stmts = p end

    if not stmts and type(value) == "table" then
        stmts = value
    end

    if not stmts then
        error((site or "splice") .. ": expected statement list for region_body splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotRegion(slot), O.SlotValueRegion(stmts))
end

-- ── Region fragment slot (emit @{frag}(...) target) ───────────────────────────

-- Accepted:  canonical RegionFragValue, direct MoonOpen.RegionFrag ASDL node.
function M.fill_region_frag(session, slot, value, site)
    local O = session.T.MoonOpen

    local frag = nil

    local p = protocol(value, "region_frag", session, site)
    if p ~= nil then frag = p end

    if not frag and type(value) == "table" then
        if pvm.classof(value) == O.RegionFrag then
            frag = value
        elseif rawget(value, "moonlift_quote_kind") == "region_frag"
            or rawget(value, "kind") == "region_frag" then
            frag = value.frag
        end
    end

    if not frag then
        error((site or "splice") .. ": expected region fragment for emit target splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotRegionFrag(slot), O.SlotValueRegionFrag(frag))
end

-- ── Expression fragment slot (emit expr @{frag}(...) target) ─────────────────

-- Accepted:  canonical ExprFragValue, direct MoonOpen.ExprFrag ASDL node.
function M.fill_expr_frag(session, slot, value, site)
    local O = session.T.MoonOpen

    local frag = nil

    local p = protocol(value, "expr_frag", session, site)
    if p ~= nil then frag = p end

    if not frag and type(value) == "table" then
        if pvm.classof(value) == O.ExprFrag then
            frag = value
        elseif rawget(value, "moonlift_quote_kind") == "expr_frag"
            or rawget(value, "kind") == "expr_frag" then
            frag = value.frag
        end
    end

    if not frag then
        error((site or "splice") .. ": expected expression fragment for emit-expr target splice, got " .. M.kind_of(value), 2)
    end

    return O.SlotBinding(O.SlotExprFrag(slot), O.SlotValueExprFrag(frag))
end

-- ── Name slot (identifier splice) ─────────────────────────────────────────────

local ident_pat = "^[_%a][_%w]*$"

-- Accepted:  plain Lua string that is a valid Moonlift identifier.
function M.fill_name(session, slot, value, site)
    local O = session.T.MoonOpen

    local name = nil

    local p = protocol(value, "name", session, site)
    if p ~= nil then name = tostring(p) end

    if not name and type(value) == "string" then name = value end

    if not name then
        error((site or "splice") .. ": expected identifier string for name splice, got " .. M.kind_of(value), 2)
    end
    if not name:match(ident_pat) then
        error((site or "splice") .. ": invalid Moonlift identifier: " .. string.format("%q", name), 2)
    end

    return O.SlotBinding(O.SlotName(slot), O.SlotValueName(name))
end

return M
