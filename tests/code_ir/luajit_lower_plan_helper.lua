package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local lalin = require("lalin")

local M = {}

local function is_lalin_parsed_decl(value)
    return type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") ~= nil
end

local function parsed_decls_from(value)
    if is_lalin_parsed_decl(value) then return { value } end
    if type(value) ~= "table" then return nil end
    local out = {}
    for i = 1, #value do
        if not is_lalin_parsed_decl(value[i]) then return nil end
        out[#out + 1] = value[i]
    end
    for k, v in pairs(value) do
        if type(k) ~= "number" and is_lalin_parsed_decl(v) then
            if type(k) == "string" and v.name == nil then
                v.public_name = v.public_name or k
                v.debug_name = v.debug_name or k
                v.name = k
            end
            out[#out + 1] = v
        end
    end
    if #out == 0 then return nil end
    return out
end

local function module_ast_from(value, name)
    local cls = asdl.classof(value)
    if cls and tostring(cls) == "Class(LalinTree.Module)" then return value end
    local parsed = parsed_decls_from(value)
    if parsed then return lalin.syntax.to_module(parsed, name) end
    if type(value) == "table" and type(value.ast) == "function" then
        local ast = value:ast()
        local ast_cls = asdl.classof(ast)
        if ast_cls and tostring(ast_cls) == "Class(LalinTree.Module)" then return ast end
        local unit = lalin.dsl.to_unit(name or "Unit", value)
        if type(unit.ast) == "function" then return unit:ast() end
        return unit
    end
    local projected = lalin.dsl.to_unit(name or "Unit", value)
    if type(projected.ast) == "function" then return projected:ast() end
    return projected
end

function M.plan(value, opts)
    opts = opts or {}
    local module_ast = module_ast_from(value, opts.name or "LowerOnly")
    local cls = asdl.classof(module_ast)
    local T = (cls and asdl.context_of(cls)) or asdl.context()
    if T.LalinCompiler == nil or T.LalinLuaJIT == nil or T.LalinStencil == nil then require("lalin.schema_projection")(T) end
    local Pipeline = require("lalin.frontend_pipeline")(T)
    local Backend = require("lalin.luajit_backend")(T)
    local checked = Pipeline.typecheck_module(module_ast, {
        context = T,
        site = "luajit_lower_plan_helper:typecheck",
        name = opts.name or "LowerOnly",
    })
    local code_result = Pipeline.checked_to_code_result(checked, {
        context = T,
        site = "luajit_lower_plan_helper:code",
        name = opts.name or "LowerOnly",
    })
    local lj_module, facts, artifacts, rejects = Backend.lower_module(code_result.module, {
        contracts = code_result.contracts,
        layout_env = code_result.layout_env,
        target_model = opts.target_model,
        target = opts.target,
        schedule = opts.schedule,
        schedule_plan = opts.schedule_plan,
        collect_rejects = opts.collect_rejects,
    })
    return {
        context = T,
        module_ast = module_ast,
        checked = checked,
        code_result = code_result,
        backend = Backend,
        lj_module = lj_module,
        facts = facts,
        artifacts = artifacts,
        rejects = rejects,
    }
end

return M
