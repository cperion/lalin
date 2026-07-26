-- lalin/frontend_pipeline.lua
-- Compilation pipeline: typechecks, lowers, and validates a LalinTree module.
-- The DSL produces closed LalinTree directly; no parse/open-module phase is part
-- of the normal compiler path.

local asdl = require("lalin.asdl")
local llbl = require("llbl")

local function progress(ctx, name, payload)
    if not ctx then return end
    payload = payload or {}
    payload.name = name
    ctx. phase (payload)
end

local function assert_no_c_phase_unreachable(root, site)
    local Coverage = require("lalin.emit_c_coverage")
    local phase_unreachable = {}
    for _, table_ in pairs(Coverage.all_tables()) do
        for variant, c in pairs(table_) do
            if c.status == "phase_unreachable" then phase_unreachable[variant] = c.reason end
        end
    end

    local seen = {}
    local found = {}
    local function walk(node)
        if type(node) ~= "table" or seen[node] then return end
        seen[node] = true
        local cls = asdl.classof(node)
        if cls then
            local kind = asdl.class_basename(node)
            if kind ~= nil and phase_unreachable[kind] then
                found[#found + 1] = tostring(kind) .. ": " .. phase_unreachable[kind]
            end
            local fields = asdl.fields(cls) or {}
            for i = 1, #fields do walk(node[fields[i].name]) end
        else
            for _, value in pairs(node) do walk(value) end
        end
    end
    walk(root)
    if #found > 0 then
        table.sort(found)
        error((site or "C frontend") .. " phase boundary failed before tree_lower/code_to_c; phase_unreachable construct(s) remain:\n" .. table.concat(found, "\n"), 3)
    end
end

local function bind_context(T)
    local Layout = require("lalin.layout_resolve")(T)
    local TreeToCode = T.LalinCompiler.CompilerImplementationOwner():compiler_implementation_registry().tree_code
    local CodeType = require("lalin.code_type")(T)
    local BackTarget = require("lalin.backend_target_model")(T)
    local CompilerAbi = require("lalin.compiler_abi")(T)
    local Errors = require("lalin.error")
    local function typecheck_host_target(opts)
        if opts.target ~= nil then return opts.target:host_target_model() end
        if opts.c_target ~= nil then return CodeType.normalize_target(opts.c_target):host_target_model() end
        if opts.target_model ~= nil then return opts.target_model:host_target_model() end
        if opts.backend_target_model ~= nil then return opts.backend_target_model:host_target_model() end
        return BackTarget.default_native():host_target_model()
    end
    local function checked_to_code_result(checked, opts)
        opts = opts or {}
        local process_ctx = opts.process_ctx
        local is_c = opts.root == "emit_c" or opts.codegen == "c" or opts.backend == "c" or opts.c_target ~= nil or opts.target ~= nil
        local host_target = typecheck_host_target(opts)
        local target = is_c and CodeType.normalize_target(opts.c_target or opts.target or opts) or host_target
        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )
        local layout_env = opts.layout_env
        do
            local ModuleType = require("lalin.tree_module_type")(T)
            local generated_env = ModuleType.env(checked.module, host_target)
            if layout_env == nil then
                layout_env = T.LalinSem.LayoutEnv(generated_env.layouts)
            else
                local merged, seen = {}, {}
                local function key(layout)
                    local cls = asdl.classof(layout)
                    if cls == T.LalinSem.LayoutNamed then return "named\0" .. tostring(layout.module_name) .. "\0" .. tostring(layout.type_name) end
                    if cls == T.LalinSem.LayoutLocal then return "local\0" .. tostring(layout.sym and layout.sym.name or layout) end
                    return tostring(layout)
                end
                for _, layout in ipairs(layout_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                for _, layout in ipairs(generated_env.layouts or {}) do local k = key(layout); if not seen[k] then seen[k] = true; merged[#merged + 1] = layout end end
                layout_env = T.LalinSem.LayoutEnv(merged)
            end
        end
        progress(process_ctx, "layout_env", { layout_env = layout_env, target = is_c and "c" or "back" })
        local resolved = Layout.module(checked.module, layout_env, host_target)
        progress(process_ctx, "layout_resolve", { module = resolved, target = is_c and "c" or "back" })
        if is_c then assert_no_c_phase_unreachable(resolved, opts.site or "C frontend") end
        local lowering = TreeToCode:module_result(resolved, { layout_env = layout_env, target = target, module_id = opts.module_id })
        local code_module = lowering.code_module
        local code_contract_set = lowering.contracts
        progress(process_ctx, "tree_lower", { code_module = code_module, code_contracts = code_contract_set.facts, code_contract_set = code_contract_set, target = is_c and "c" or "back" })
        local code_issues = TreeToCode:code_validation_issues(code_module, collector)
        progress(process_ctx, "code_validate", { issues = code_issues, target = is_c and "c" or "back" })
        return T.LalinCompiler.CodeResult(code_module, code_contract_set, layout_env)
    end

    local function code_result_to_c(code_result, opts)
        opts = opts or {}
        local process_ctx = opts.process_ctx
        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )
        CompilerAbi.assert_valid_code_result(code_result, { collector = collector })
        local target = CodeType.normalize_target(opts.c_target or opts.target or opts)
        if T.LalinCompiler.CompilerCCodegenRequest then
            return TreeToCode:code_result_to_c(
                T.LalinCompiler.CompilerCCodegenRequest(
                    code_result, target, T.LalinStencil.StencilCompilerPolicy(
                        T.LalinStencil.StencilCompilerGcc,
                        T.LalinStencil.StencilOptO3,
                        T.LalinStencil.StencilMachineNative, {})))
        end
        opts.c_target = target
        opts.target = target
        return TreeToCode:code_result_to_c(code_result, opts)
    end

    local function typecheck_module(module, opts)
        opts = opts or {}
        local process_ctx = opts.process_ctx
        local analysis_ctx = opts.analysis_ctx or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS,
            analysis_ctx,
            Errors.Catalog,
            Errors.Terminal.render
        )
        local surfaced = TreeToCode:surface_resolve(module)
        progress(process_ctx, "surface_resolve", { module = surfaced })
        local host_target = typecheck_host_target(opts)
        local closed = TreeToCode:closure_convert(surfaced, T.LalinSem.ClosureModuleInput(host_target))
        progress(process_ctx, "closure_convert", { module = closed })
        local checked = TreeToCode:typecheck_module(closed, { collector = collector, layout_env = opts.layout_env, target = host_target })
        progress(process_ctx, "typecheck", { result = checked, module = checked and checked.module })
        return checked
    end

    local function process_event_sink(ctx, events)
        return setmetatable({}, {
            __index = function(_, key)
                return function(payload)
                    events[#events + 1] = ctx:make_event(key, payload)
                end
            end,
        })
    end

    local function typecheck_module_process_body(ctx, module, opts)
        opts = opts or {}
        local events = {}
        local run_opts = {}
        for k, v in pairs(opts) do run_opts[k] = v end
        run_opts.process_ctx = process_event_sink(ctx, events)
        events[#events + 1] = ctx:make_event("start", { target = "checked", site = run_opts.site or "frontend" })
        local ok, result = pcall(typecheck_module, module, run_opts)
        if not ok then
            local ev = ctx:diagnostic_event { severity = "error", code = "E_LALIN_TYPECHECK", message = tostring(result), target = "checked" }
            ev.target = "checked"
            events[#events + 1] = ev
            return llbl.gps.raw(llbl.gps.from.array(events))
        end
        events[#events + 1] = ctx:make_event("done", { target = "checked", result = result })
        events[#events + 1] = ctx:make_event("result", { result = result })
        return llbl.gps.raw(llbl.gps.from.array(events))
    end
    local typecheck_module_process = llbl.process. lalin_typecheck_module { "module", "opts" } (typecheck_module_process_body)

    local function checked_to_code_process_body(ctx, checked, opts)
        opts = opts or {}
        local events = {}
        local run_opts = {}
        for k, v in pairs(opts) do run_opts[k] = v end
        run_opts.process_ctx = process_event_sink(ctx, events)
        local target = run_opts.root == "emit_c" and "c_code" or "back_code"
        events[#events + 1] = ctx:make_event("start", { target = target, site = run_opts.site or "frontend" })
        local ok, result = pcall(checked_to_code_result, checked, run_opts)
        if not ok then
            local ev = ctx:diagnostic_event { severity = "error", code = "E_LALIN_CHECKED_TO_CODE", message = tostring(result), target = target }
            ev.target = target
            events[#events + 1] = ev
            return llbl.gps.raw(llbl.gps.from.array(events))
        end
        events[#events + 1] = ctx:make_event("done", { target = target, result = result })
        events[#events + 1] = ctx:make_event("result", { result = result })
        return llbl.gps.raw(llbl.gps.from.array(events))
    end
    local checked_to_code_process = llbl.process. lalin_checked_to_code { "checked", "opts" } (checked_to_code_process_body)

    local function code_to_c_process_body(ctx, code_result, opts)
        opts = opts or {}
        local events = {}
        local run_opts = {}
        for k, v in pairs(opts) do run_opts[k] = v end
        run_opts.process_ctx = process_event_sink(ctx, events)
        events[#events + 1] = ctx:make_event("start", { target = "c", site = run_opts.site or "C frontend" })
        local ok, result = pcall(code_result_to_c, code_result, run_opts)
        if not ok then
            local ev = ctx:diagnostic_event { severity = "error", code = "E_LALIN_CODE_TO_C", message = tostring(result), target = "c" }
            ev.target = "c"
            events[#events + 1] = ev
            return llbl.gps.raw(llbl.gps.from.array(events))
        end
        events[#events + 1] = ctx:make_event("done", { target = "c", result = result })
        events[#events + 1] = ctx:make_event("result", { result = result })
        return llbl.gps.raw(llbl.gps.from.array(events))
    end
    local code_to_c_process = llbl.process. lalin_code_to_c { "code_result", "opts" } (code_to_c_process_body)


    return {
        typecheck_module = typecheck_module,
        checked_to_code_result = checked_to_code_result,
        code_result_to_c = code_result_to_c,
        typecheck_module_process = typecheck_module_process,
        checked_to_code_process = checked_to_code_process,
        code_to_c_process = code_to_c_process,
        assert_no_c_phase_unreachable = assert_no_c_phase_unreachable,
    }
end

return bind_context
