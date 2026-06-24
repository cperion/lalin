local pvm = require("moonlift.pvm")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function mkdir_parent(path)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir ~= nil and dir ~= "" then os.execute("mkdir -p " .. shell_quote(dir)) end
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_backend ~= nil then return T._moonlift_api_cache.luajit_backend end

    local Stencil = T.MoonStencil
    local Lower = require("moonlift.luajit_lower")(T)
    local Emit = require("moonlift.luajit_emit")(T)
    local StencilC = require("moonlift.stencil_c")(T)
    local StencilBank = require("moonlift.stencil_bank")(T)

    local api = {}

    local function artifact_for(vocab, op, reduction, plan, info)
        if vocab == Stencil.StencilCopy then return StencilC.copy_array_artifact(info) end
        if vocab == Stencil.StencilFill then return StencilC.fill_array_artifact(info) end
        if vocab == Stencil.StencilMap then return StencilC.map_array_artifact(op, info) end
        if vocab == Stencil.StencilZipMap then return StencilC.zip_map_array_artifact(op, info) end
        if vocab == Stencil.StencilCast then return StencilC.cast_array_artifact(op, info) end
        if vocab == Stencil.StencilCompare then return StencilC.compare_array_artifact(op, info) end
        if vocab == Stencil.StencilZipCompare then return StencilC.zip_compare_array_artifact(op, info) end
        if vocab == Stencil.StencilGather then return StencilC.gather_array_artifact(info) end
        if vocab == Stencil.StencilScatter then return StencilC.scatter_array_artifact(info) end
        if vocab == Stencil.StencilInPlaceMap then return StencilC.in_place_map_array_artifact(op, info) end
        if vocab == Stencil.StencilScan then return StencilC.scan_array_artifact(reduction, plan, info) end
        if vocab == Stencil.StencilFind then return StencilC.find_array_artifact(op, info) end
        if vocab == Stencil.StencilPartition then return StencilC.partition_array_artifact(op, info) end
        if vocab == Stencil.StencilReduce then return StencilC.reduce_array_artifact(reduction, plan, info) end
        if vocab == Stencil.StencilCount then return StencilC.count_array_artifact(op, info) end
        if vocab == Stencil.StencilMapReduce then return StencilC.map_reduce_array_artifact(op, reduction, plan, info) end
        if vocab == Stencil.StencilZipReduce then return StencilC.zip_reduce_array_artifact(op, reduction, plan, info) end
        error("luajit_backend: unsupported selected stencil vocab " .. tostring(vocab), 3)
    end

    local function collect_artifact(artifacts, vocab, op, reduction, plan, info)
        local artifact = artifact_for(vocab, op, reduction, plan, info)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end

    function api.lower_module(module, opts)
        opts = opts or {}
        local artifacts = {}
        local rejects = opts.collect_rejects or {}
        local lj_module, facts = Lower.lower_module(module, {
            contracts = opts.contracts,
            graph = opts.graph,
            flow = opts.flow,
            value = opts.value,
            mem = opts.mem,
            effect = opts.effect,
            kernel = opts.kernel,
            collect_rejects = rejects,
            stencil_store_artifact_for = function(_func, vocab, op, plan, info)
                return collect_artifact(artifacts, vocab, op, nil, plan, info)
            end,
            stencil_reduce_artifact_for = function(_func, vocab, op, reduction, plan, info)
                return collect_artifact(artifacts, vocab, op, reduction, plan, info)
            end,
            stencil_skeleton_artifact_for = function(_func, vocab, op, reduction, plan, info)
                return collect_artifact(artifacts, vocab, op, reduction, plan, info)
            end,
        })
        return lj_module, facts, artifacts, rejects
    end

    function api.realize_artifacts(artifacts, opts)
        opts = opts or {}
        if #artifacts == 0 then
            return { kind = "BinaryStencilBankRealization", symbols = {}, installed = {}, bank = nil }, nil
        end
        local bank = opts.bank
        if bank == nil then
            return nil, "luajit_backend: binary realization requires a prebuilt BinaryStencilBank"
        end
        return StencilBank.realize_binary_artifacts(artifacts, {
            bank = bank,
            patch_values = opts.patch_values,
            install_policy = opts.install_policy,
        })
    end

    function api.build_binary_bank(artifacts, opts)
        return StencilBank.build_binary_bank(artifacts or {}, opts or {})
    end

    function api.compile_lj_module(lj_module, artifacts, opts)
        opts = opts or {}
        local realized, realize_err, realize_source = api.realize_artifacts(artifacts or {}, opts)
        if realized == nil then return nil, realize_err, realize_source end
        local compiled, emit_err, source = Emit.compile_module(lj_module, {
            chunk_name = opts.chunk_name or "moonlift_luajit_backend",
            stencil_symbols = realized.symbols,
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
        local bank = opts.bank
        if bank == nil and #(artifacts or {}) > 0 then
            return nil, "luajit_backend.emit_lua_artifact requires a prebuilt BinaryStencilBank"
        end
        local bank_source = bank and StencilBank.emit_lua_bank_source(bank, opts) or "local __moonlift_luajit_stencil_symbols = {}\n"
        local module_source = Emit.emit_module(lj_module, {
            chunk_name = opts.chunk_name or "moonlift_luajit_artifact",
        })
        local source = table.concat({
            "-- Generated Moonlift LuaJIT copy-and-patch artifact.\n",
            "-- Native stencil bytes are embedded below as data and installed before the residual module loads.\n",
            bank_source,
            module_source,
        })
        if opts.path ~= nil then
            mkdir_parent(opts.path)
            local f = assert(io.open(opts.path, "wb"))
            f:write(source)
            f:close()
        end
        return source
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
            artifacts = artifacts,
            rejects = rejects,
            bank = opts.bank,
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
        result.artifacts = artifacts
        result.rejects = rejects
        return result
    end

    api.artifact_for = artifact_for

    T._moonlift_api_cache.luajit_backend = api
    return api
end

return bind_context
