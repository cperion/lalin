local ffi = require("ffi")
local Tcc = require("experiments.wasm_gcps.tcc_jit")

local M = {}

function M.new()
    local session = Tcc.compile()
    local i32_add = session.i32_add
    local f64_add = session.f64_add
    local f64_mul = session.f64_mul
    local sum_step = session.sum_step
    local mixed_step = session.mixed_step
    local sum_region = session.sum_region
    local mixed_region = session.mixed_region

    local function opcode_sum_cycle(n, index, result)
        if index > n then return result end
        return opcode_sum_cycle(n, i32_add(index, 1), i32_add(result, index))
    end

    local function opcode_mixed_cycle(n, index, result)
        if index > n then return result end
        return opcode_mixed_cycle(n, i32_add(index, 1),
            f64_add(result, f64_mul(index, 1.5)))
    end

    local sum_state = ffi.new("WasmGcpsTccState")
    local function step_sum_cycle(state)
        if state.index > state.n then return tonumber(state.result) end
        sum_step(state)
        return step_sum_cycle(state)
    end

    local mixed_state = ffi.new("WasmGcpsTccState")
    local function step_mixed_cycle(state)
        if state.index > state.n then return state.mixed end
        mixed_step(state)
        return step_mixed_cycle(state)
    end

    local shapes = { session = session }

    function shapes.opcode_sum(n) return opcode_sum_cycle(n, 1, 0) end
    function shapes.opcode_mixed(n) return opcode_mixed_cycle(n, 1, 0.0) end

    function shapes.step_sum(n)
        sum_state.n, sum_state.index, sum_state.result = n, 1, 0
        return step_sum_cycle(sum_state)
    end

    function shapes.step_mixed(n)
        mixed_state.n, mixed_state.index, mixed_state.mixed = n, 1, 0.0
        return step_mixed_cycle(mixed_state)
    end

    function shapes.region_sum(n) return tonumber(sum_region(n)) end
    function shapes.region_mixed(n) return mixed_region(n) end
    function shapes:free() self.session:free() end

    return shapes
end

return M

