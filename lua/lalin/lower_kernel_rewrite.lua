-- lower_kernel_rewrite.lua
-- Kernel proof → CBackend block rewrite.
--
-- When a kernel plan proves a loop is equivalent to a closed-form expression,
-- a reduction, a memcpy, a scan, a find, or similar, this module emits the
-- equivalent CBackend IR that replaces the original loop blocks.
--
-- This operates at the CBackend level (into c_emission), not at the Code IR
-- level, because lower_to_c.lua already runs after CodeToC.module(). The
-- established precedent is emit_closed_form_fragment which uses the same pattern.

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_kernel_rewrite ~= nil then
        return T._lalin_api_cache.lower_kernel_rewrite
    end

    local Code = T.LalinCode
    local C = T.LalinC
    local Lower = T.LalinLower
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Value = T.LalinValue
    local Mem = T.LalinMem
    local Stencil = T.LalinStencil
    local Graph = T.LalinGraph
    local Core = T.LalinCore
    local asdl = require("lalin.asdl")

    local api = {}

    -- Leaf methods for display names (eliminate stringly-typed dispatch)
    function Value.ReductionAdd:display_name() return "add" end
    function Value.ReductionMul:display_name() return "mul" end
    function Value.ReductionAnd:display_name() return "and" end
    function Value.ReductionOr:display_name() return "or" end
    function Value.ReductionXor:display_name() return "xor" end
    function Value.ReductionMin:display_name() return "min" end
    function Value.ReductionMax:display_name() return "max" end

    function Stencil.StencilScanInclusive:display_name() return "inclusive" end
    function Stencil.StencilScanExclusive:display_name() return "exclusive" end
    ------------------------------------------------------------------------
    -- apply: main entry point
    --
    -- @param kplan      KernelPlanned with the kernel proof
    -- @param fragment   LowerFragment with the strategy
    -- @param graph      CodeGraph for loop lookup
    -- @param flow       FlowFactSet for edge facts
    -- @param c_emission mutable emission context (same as lower_to_c uses)
    -- @return LowerRewriteApplication or nil
    ------------------------------------------------------------------------
    function api.apply(kplan, fragment, graph, flow, c_emission)
        local result = kplan.body.result
        local rewrite_plan = result:lower_rewrite_plan(kplan.id, kplan)
        local kind = rewrite_plan.kind

        -- Dispatch on KernelRewriteKind using ASDL leaf methods
        return kind:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
    end

    ------------------------------------------------------------------------
    -- Closed-form rewrite: replace loop with computed expression + jump.
    -- This is the same semantic as emit_closed_form_fragment but wrapped
    -- as a LowerRewriteApplication for structured tracking.
    ------------------------------------------------------------------------
    function api.lower_rewrite_closed_form(kplan, fragment, graph, flow, c_emission, kind)
        local loop = kplan_loop(kplan, graph)
        if loop == nil then return nil end

        -- Must have exactly one exit edge
        if #(loop.exits or {}) ~= 1 then return nil end

        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local jump_dest = exit.to.block
        local jump_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]

        -- Check if exit block has a forward jump (chained exit)
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if block.id == exit.to.block then
                local dest_ref = block.term and block.term.op and block.term.op:lower_c_jump_dest()
                if dest_ref ~= nil then
                    jump_dest = dest_ref
                    jump_fact = edge_facts[block.id.text .. "\0" .. block.term.op.dest.text] or jump_fact
                end
            end
        end

        -- Emit the closed-form expression into c_emission
        c_emission.stmts = {
            C.CBackendComment("semantic closed-form rewrite " .. tostring(kind.expression))
        }

        local expr = kind.expression
        local result_atom
        if expr ~= nil then
            result_atom = lower_value_expr(c_emission, expr)
        end

        -- Build jump args from the original exit edge facts
        local args = {}
        if jump_fact and jump_fact.args then
            local accumulator = kind.accumulator
            for i, arg_info in ipairs(jump_fact.args) do
                if accumulator and arg_info.src == accumulator then
                    args[i] = result_atom or C.CBackendAtomNull(Code.CodeTyI32)
                else
                    args[i] = atom_from_value(c_emission, arg_info.src)
                end
            end
        end

        -- Get original header block for params
        local header = c_emission.block_by_id and c_emission.block_by_id[loop.header.block.text]
        local header_params = {}
        if header then
            for _, p in ipairs(header.params or {}) do
                header_params[#header_params + 1] = p
            end
        end

        local new_block = C.CBackendBlock(
            clabel(loop.header.block),
            header_params,
            c_emission.stmts,
            C.CBackendGoto(clabel(jump_dest), args)
        )

        -- Register this as a replacement for the loop header
        c_emission.blocks[#c_emission.blocks + 1] = new_block

        -- Build block elimination mappings
        local mappings = {}
        for _, bid in ipairs(loop.body or {}) do
            mappings[#mappings + 1] = Lower.LowerBlockEliminated(bid)
        end

        return Lower.LowerRewriteApplication(
            fragment,
            kplan.body.result:lower_rewrite_plan(kplan.id, kplan),
            -- replacement_blocks as CodeBlock refs is schema-constrained;
            -- at CBackend level we track via c_emission.blocks
            {},
            mappings
        )
    end

    ------------------------------------------------------------------------
    -- Reduction rewrite: replace loop with a scalar reduction accumulator.
    -- When the kernel proves the loop body is a pure reduction without
    -- closed-form, we can sometimes emit a tighter loop.
    ------------------------------------------------------------------------
    function api.lower_rewrite_reduce(kplan, fragment, graph, flow, c_emission, kind)
        local reduction = kind.reduction
        if reduction == nil then return nil end

        local loop = kplan_loop(kplan, graph)
        if loop == nil then return nil end

        -- For reduction-only (no closed-form), fall through to normal
        -- CMat inline path. The CMat infrastructure handles the accumulator
        -- threading more robustly than a hand-written rewrite.
        -- The comment tracks what the proof provides for future optimization.
        c_emission.stmts = c_emission.stmts or {}
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendComment(
            "semantic reduction rewrite available (op=" ..
            reduction.op:display_name() ..
            "), emitting via CMat inline path"
        )

        return nil -- Signal: use existing CMat path for this fragment
    end

    ------------------------------------------------------------------------
    -- Memcpy rewrite: replace loop with memcpy/memmove call.
    ------------------------------------------------------------------------
    function api.lower_rewrite_memcpy(kplan, fragment, graph, flow, c_emission, kind)
        -- Placeholder: full implementation requires memcpy helper generation
        -- in emit_c_helpers.lua (T019). For now log and fall through.
        c_emission.stmts = c_emission.stmts or {}
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendComment(
            "semantic memcpy rewrite (dst=" .. tostring(kind.dst_base) ..
            ", src=" .. tostring(kind.src_base) ..
            ", elem_size=" .. tostring(kind.elem_size) .. ")"
        )
        return nil -- Fall through to CMat inline path until helper generation exists
    end

    ------------------------------------------------------------------------
    -- Scan rewrite: replace loop with scan helper call.
    ------------------------------------------------------------------------
    function api.lower_rewrite_scan(kplan, fragment, graph, flow, c_emission, kind)
        c_emission.stmts = c_emission.stmts or {}
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendComment(
            "semantic scan rewrite (mode=" ..
            (kind.mode or Stencil.StencilScanInclusive):display_name() ..
            "), emitting via CMat inline path"
        )
        return nil -- Fall through to CMat inline until scan helper generation exists
    end

    ------------------------------------------------------------------------
    -- Find rewrite: replace loop with find helper call.
    ------------------------------------------------------------------------
    function api.lower_rewrite_find(kplan, fragment, graph, flow, c_emission, kind)
        c_emission.stmts = c_emission.stmts or {}
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendComment(
            "semantic find rewrite, emitting via CMat inline path"
        )
        return nil -- Fall through to CMat inline until find helper generation exists
    end

    ------------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------------

    local function kplan_loop(kplan, graph)
        local func_graphs = graph and graph.funcs or {}
        local loop_id = kplan.subject.loop
        if loop_id == nil then return nil end
        for _, fg in ipairs(func_graphs) do
            for _, gl in ipairs(fg.loops or {}) do
                if gl.id == loop_id then return gl end
            end
        end
        return nil
    end

    local function edge_fact_by_key(flow)
        local out = {}
        if not flow then return out end
        for _, ef in ipairs(flow.edges or {}) do
            local key = ef.src and ef.src.block and ef.src.block.text or ""
            key = key .. "\0" .. (ef.dst and ef.dst.block and ef.dst.block.text or "")
            out[key] = ef
        end
        return out
    end

    local function clabel(block_id)
        return C.CBackendLabel(tostring(block_id and block_id.text or "block"))
    end

    -- These resolve from c_emission's value_types / code_func data
    -- Mirror helpers from lower_to_c.lua
    local function atom_from_value(c_emission, value_id)
        if value_id == nil then return C.CBackendAtomNull(Code.CodeTyI32) end
        return C.CBackendAtomLocal(C.CBackendLocalId(tostring(value_id.text)))
    end

    -- lower_value_expr is the same as in lower_to_c.lua
    -- We reference it from c_emission if available, or build inline
    local function lower_value_expr(c_emission, expr)
        -- If lower_to_c has installed lower_value_expr on c_emission, use it
        if c_emission.lower_value_expr then
            return c_emission.lower_value_expr(c_emission, expr)
        end
        -- Inline fallback: delegate to the ValueExpr leaf methods
        return expr:lower_c_value(c_emission)
    end

    api.kplan_loop = kplan_loop
    api.edge_fact_by_key = edge_fact_by_key

    -- KernelRewriteKind leaf methods
    function Kernel.KernelRewriteClosedForm:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return api.lower_rewrite_closed_form(kplan, fragment, graph, flow, c_emission, self)
    end
    function Kernel.KernelRewriteReduce:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return api.lower_rewrite_reduce(kplan, fragment, graph, flow, c_emission, self)
    end
    function Kernel.KernelRewriteMemcpy:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return api.lower_rewrite_memcpy(kplan, fragment, graph, flow, c_emission, self)
    end
    function Kernel.KernelRewriteScan:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return api.lower_rewrite_scan(kplan, fragment, graph, flow, c_emission, self)
    end
    function Kernel.KernelRewriteFind:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return api.lower_rewrite_find(kplan, fragment, graph, flow, c_emission, self)
    end
    function Kernel.KernelRewriteNone:lower_rewrite_apply(kplan, fragment, graph, flow, c_emission)
        return nil
    end

    return api
end

return bind_context
