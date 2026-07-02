local asdl = require("lalin.asdl")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_backend ~= nil then return T._lalin_api_cache.luajit_backend end

    local Stencil = T.LalinStencil
    local LJ = T.LalinLuaJIT
    local Lower = require("lalin.luajit_lower")(T)
    local Emit = require("lalin.luajit_emit")(T)
    local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
    local BytecodeTrace = require("lalin.residual_luatrace")(T)
    local ExecPlan = require("lalin.exec_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local BackTargetModel = require("lalin.back_target_model")(T)

    local api = {}

    local function default_target_model()
        local Back = T.LalinBack
        local native = BackTargetModel.default_native()
        return Back.BackTargetModel(Back.BackTargetDynasmJit, native.facts)
    end

    local function target_model(opts)
        return opts.target_model or opts.back_target_model or default_target_model()
    end

    local function host_target(opts)
        opts = opts or {}
        if opts.target ~= nil then return opts.target end
        return BackTargetModel.host_target(target_model(opts))
    end

    local function schedule_index(schedule_plan)
        local Schedule = T.LalinSchedule
        local by_kernel = {}
        for _, sched in ipairs(schedule_plan and schedule_plan.schedules or {}) do
            if asdl.classof(sched) == Schedule.SchedulePlanned then by_kernel[sched.kernel.text] = sched end
        end
        return by_kernel
    end

    local function attach_schedule(descriptor, kernel_plan, schedules)
        local sched = kernel_plan and schedules[kernel_plan.id.text] or nil
        if sched ~= nil then
            return asdl.with(descriptor, { kernel_schedule = sched, schedule = sched.form })
        end
        return descriptor
    end

    local function artifact_for(kind, op, reduction, plan, descriptor)
        if kind == "scatter_reduce" then return StencilArtifactPlan.scatter_reduce_n_artifact(reduction, plan, descriptor) end
        if kind == "store_n" then return StencilArtifactPlan.store_n_artifact(descriptor) end
        if kind == "scan" then return StencilArtifactPlan.scan_array_artifact(reduction, plan, descriptor) end
        if kind == "find" then return StencilArtifactPlan.find_array_artifact(op, descriptor) end
        if kind == "partition" then return StencilArtifactPlan.partition_array_artifact(op, descriptor) end
        if kind == "reduce" then return StencilArtifactPlan.reduce_array_artifact(reduction, plan, descriptor) end
        if kind == "reduce_n" then return StencilArtifactPlan.reduce_n_artifact(reduction, plan, descriptor) end
        if kind == "count" then return StencilArtifactPlan.count_array_artifact(op, descriptor) end
        error("luajit_backend: unsupported selected stencil kind " .. tostring(kind), 3)
    end

    local function bytecode_mode(opts)
        return opts and opts.bytecode == true
    end

    local function artifact_with_provider(artifact, opts)
        if bytecode_mode(opts) then
            return BytecodeTrace.bc_artifact(artifact)
        end
        return artifact
    end

    local function collect_artifact(artifacts, selections, vocab, op, reduction, plan, descriptor, opts)
        descriptor = descriptor or {}
        local artifact = artifact_with_provider(artifact_for(vocab, op, reduction, plan, descriptor), opts)
        artifacts[#artifacts + 1] = artifact
        selections[#selections + 1] = Stencil.StencilPlanEntry(
            plan.id,
            Stencil.StencilSelected(
                artifact.instance,
                StencilArtifactPlan.selection_provenance_for_artifact(artifact)
            )
        )
        return artifact
    end

    function api.lower_module(module, opts)
        opts = opts or {}
        local artifacts = {}
        local selections = {}
        local rejects = opts.collect_rejects or {}
        local target = host_target(opts)
        local graph, flow, value, mem, effect, kernel = Lower.build_kernel(module, opts)
        local schedule_plan = opts.schedule_plan or opts.schedule or CodeSchedulePlan.plan(module, kernel, flow, value, mem, effect, target_model(opts))
        local schedules = schedule_index(schedule_plan)
        local stencil_machines = Lower.plan_stencil_machines(module, {
            contracts = opts.contracts,
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
            layout_env = opts.layout_env,
            target = target,
            stencil_store_artifact_for = function(_func, vocab, op, plan, descriptor)
                return collect_artifact(artifacts, selections, vocab, op, nil, plan, attach_schedule(descriptor, plan, schedules), opts)
            end,
            stencil_reduce_artifact_for = function(_func, vocab, op, reduction, plan, descriptor)
                return collect_artifact(artifacts, selections, vocab, op, reduction, plan, attach_schedule(descriptor, plan, schedules), opts)
            end,
            stencil_skeleton_artifact_for = function(_func, vocab, op, reduction, plan, descriptor)
                return collect_artifact(artifacts, selections, vocab, op, reduction, plan, attach_schedule(descriptor, plan, schedules), opts)
            end,
        })
        for _, reject in ipairs(stencil_machines.rejects or {}) do rejects[#rejects + 1] = reject end
        local lj_module, facts = Lower.lower_module(module, {
            contracts = opts.contracts,
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
            stencil_machines_by_func = stencil_machines.machines_by_func,
            layout_env = opts.layout_env,
            target = target,
        })
        facts.schedule = schedule_plan
        facts.schedule_plan = schedule_plan
        facts.stencil = Stencil.StencilModulePlan(module.id, facts.kernel, selections)
        facts.stencil_plan = facts.stencil
        facts.luajit_stencil_machines = LJ.LJStencilMachineModulePlan(module.id, facts.stencil, stencil_machines.machine_plans or {})
        facts.exec = ExecPlan.plan(module, {
            graph = facts.graph,
            flow = facts.flow,
            value = facts.value,
            mem = facts.mem,
            effect = facts.effect,
            kernels = facts.kernel,
            stencil = facts.stencil,
            artifacts = artifacts,
            contracts = opts.contracts,
        })
        facts.exec_plan = facts.exec
        return lj_module, facts, artifacts, rejects
    end

    local function native_boundary_error(operation)
        return "luajit_backend: " .. operation .. " only supports explicit LuaJIT bytecode stencil artifacts; native copy-patch uses lalin.native_backend / LalinNative"
    end

    function api.realize_artifacts(artifacts, opts)
        opts = opts or {}
        if not bytecode_mode(opts) then
            return nil, native_boundary_error("artifact realization")
        end
        return BytecodeTrace.realize_bc_artifacts(artifacts, {
            bank = opts.bc_bank,
            stem = opts.stem,
            id = opts.bc_bank_id,
            target = opts.bc_target,
            env = opts.bc_env,
        })
    end

    function api.build_bc_bank(artifacts, opts)
        return BytecodeTrace.build_bc_bank(artifacts or {}, opts or {})
    end

    function api.compile_lj_module(lj_module, artifacts, opts)
        opts = opts or {}
        local stencil_symbols = {}
        local realized = nil
        if bytecode_mode(opts) then
            local realize_err, realize_source
            realized, realize_err, realize_source = api.realize_artifacts(artifacts or {}, opts)
            if realized == nil then return nil, realize_err, realize_source end
            stencil_symbols = realized.symbols
        elseif #(artifacts or {}) > 0 then
            return nil, native_boundary_error("module compilation")
        end
        local compiled, emit_err, source = Emit.compile_module(lj_module, {
            chunk_name = opts.chunk_name or "lalin_luajit_backend",
            stencil_symbols = stencil_symbols,
        })
        if compiled == nil then return nil, emit_err, source end
        return {
            module = compiled,
            lj_module = lj_module,
            realization = realized,
            source = source,
        }
    end

    function api.emit_lua_artifact(lj_module, artifacts, opts)
        opts = opts or {}
        local stencil_source
        local bc_bank
        if bytecode_mode(opts) then
            bc_bank = opts.bc_bank
            if bc_bank == nil then
                local bank_err
                bc_bank, bank_err = api.build_bc_bank(artifacts or {}, {
                    stem = opts.stem,
                    id = opts.bc_bank_id,
                    target = opts.bc_target,
                })
                if bc_bank == nil then return nil, bank_err end
            end
            stencil_source = BytecodeTrace.emit_bc_bank_source(bc_bank, opts)
        else
            if #(artifacts or {}) > 0 then
                return nil, native_boundary_error("source artifact emission")
            end
            stencil_source = "local __lalin_luajit_stencil_symbols = {}\n"
        end
        local module_source = Emit.emit_module(lj_module, {
            chunk_name = opts.chunk_name or "lalin_luajit_artifact",
        })
        local source = table.concat({
            bytecode_mode(opts)
                and "-- Generated Lalin LuaJIT bytecode artifact.\n"
                or "-- Generated Lalin LuaJIT artifact.\n",
            bytecode_mode(opts)
                and "-- Stencil descriptors are emitted below as LuaJIT bytecode stencils.\n"
                or "-- No stencil bytecode bank is embedded in this LuaJIT artifact.\n",
            stencil_source,
            module_source,
        })
        if opts.path ~= nil then
            mkdir_parent(opts.path)
            local f = assert(io.open(opts.path, "wb"))
            f:write(source)
            f:close()
        end
        return source, nil, {
            selected_bc_bank = bc_bank,
        }
    end

    function api.emit_module_artifact(module, opts)
        opts = opts or {}
        local lj_module, facts, artifacts, rejects = api.lower_module(module, opts)
        if opts.reject_on_stencil_rejects ~= false and rejects and #rejects > 0 then
            return nil, rejects[1] and rejects[1].reason or "LuaJIT backend rejected module"
        end
        local source, err = api.emit_lua_artifact(lj_module, artifacts, opts)
        if source == nil then return nil, err end
        return {
            kind = "LuaJITSourceArtifact",
            source = source,
            lj_module = lj_module,
            facts = facts,
            stencil_plan = facts.stencil,
            luajit_stencil_machines = facts.luajit_stencil_machines,
            exec_plan = facts.exec,
            artifacts = artifacts,
            rejects = rejects,
        }
    end

    function api.compile_module(module, opts)
        opts = opts or {}
        local lj_module, facts, artifacts, rejects = api.lower_module(module, opts)
        if opts.reject_on_stencil_rejects ~= false and rejects and #rejects > 0 then
            return nil, rejects[1] and rejects[1].reason or "LuaJIT backend rejected module"
        end
        local result, err, source = api.compile_lj_module(lj_module, artifacts, opts)
        if result == nil then return nil, err, source end
        result.facts = facts
        result.stencil_plan = facts.stencil
        result.luajit_stencil_machines = facts.luajit_stencil_machines
        result.exec_plan = facts.exec
        result.artifacts = artifacts
        result.rejects = rejects
        return result
    end

    api.artifact_for = artifact_for

    T._lalin_api_cache.luajit_backend = api
    return api
end

return bind_context
