local ffi = require("ffi")
local ABI = require("experiments.gccjit_driver.abi")
local State = require("experiments.gccjit_driver.state")

local lib = ABI.lib
local C = ABI.constants
local STATUS = State.constants.status
local DIAG = State.constants.diagnostic
local STAGE = State.constants.stage

local Driver = State.Driver
local AcquireMachine = State.AcquireMachine
local TypeMachine = State.TypeMachine
local BlockGraphMachine = State.BlockGraphMachine
local TailGraphMachine = State.TailGraphMachine
local CompileMachine = State.CompileMachine

local monotonic_now = require("lalin.luajit_measure").now
local function now_ns()
    return math.floor(monotonic_now() * 1000000000 + 0.5)
end

local function elapsed(started)
    return now_ns() - started
end

local function pointer_missing(value)
    return value == nil
end

function Driver:release_foreign()
    if self.owner.context ~= nil then
        lib.gcc_jit_context_release(self.owner.context)
        self.owner.context = nil
        self.metrics.releases = self.metrics.releases + 1
    end
    if self.owner.result ~= nil then
        lib.gcc_jit_result_release(self.owner.result)
        self.owner.result = nil
        self.metrics.releases = self.metrics.releases + 1
    end
    self.owner.entry = nil
    return self
end

function Driver:prepare(optimization_level)
    assert(optimization_level >= 0 and optimization_level <= 3, "optimization level must be 0..3")
    self:release_foreign()
    ffi.fill(self.types, ffi.sizeof(self.types))
    ffi.fill(self.function_projection, ffi.sizeof(self.function_projection))
    ffi.fill(self.diagnostic, ffi.sizeof(self.diagnostic))
    ffi.fill(self.metrics, ffi.sizeof(self.metrics))
    self.status = STATUS.building
    self.optimization_level = optimization_level
    self.generation = self.generation + 1
    if self.generation == 0 then self.generation = 1 end
    return self
end

function Driver:reject(code, stage, fallback)
    self.diagnostic.code, self.diagnostic.stage = code, stage
    local message
    if self.owner.context ~= nil then
        local foreign = lib.gcc_jit_context_get_last_error(self.owner.context)
        if foreign == nil then foreign = lib.gcc_jit_context_get_first_error(self.owner.context) end
        if foreign ~= nil then message = ffi.string(foreign) end
    end
    message = message or fallback or "libgccjit rejected the construction"
    local length = math.min(#message, 511)
    ffi.copy(self.diagnostic.message, message, length)
    self.diagnostic.message[length] = 0
    self.diagnostic.length = length
    self.status = STATUS.rejected
    self.revision = self.revision + 1
    self:release_foreign()
    return self
end

function Driver:diagnostic_text()
    return ffi.string(self.diagnostic.message, self.diagnostic.length)
end

function Driver:succeeded() return self.status == STATUS.ready end
function Driver:failed() return self.status == STATUS.rejected end

function Driver:free()
    self:release_foreign()
    self.status = STATUS.released
    return self
end

function Driver:cook_blocks(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.blocks_acquired)
end

function Driver:inspect_blocks(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.inspected_blocks_acquired)
end

function Driver:cook_tail(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.tail_acquired)
end

function Driver:inspect_tail(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.inspected_tail_acquired)
end

function AcquireMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    cc.owner.context = lib.gcc_jit_context_acquire()
    if pointer_missing(cc.owner.context) then
        return cc:reject(DIAG.context, STAGE.acquire, "could not acquire libgccjit context")
    end
    lib.gcc_jit_context_set_int_option(
        cc.owner.context, C.int_option.optimization_level, cc.optimization_level)
    cc.metrics.acquire_ns = elapsed(started)
    return completed(self, cc)
end

function AcquireMachine:blocks_acquired(cc)
    return cc.type_machine:run(cc, TypeMachine.blocks_ready)
end

function AcquireMachine:inspected_blocks_acquired(cc)
    return cc.type_machine:run(cc, TypeMachine.inspected_blocks_ready)
end

function AcquireMachine:tail_acquired(cc)
    return cc.type_machine:run(cc, TypeMachine.tail_ready)
end

function AcquireMachine:inspected_tail_acquired(cc)
    return cc.type_machine:run(cc, TypeMachine.inspected_tail_ready)
end

function TypeMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    local types = cc.types
    types.i64 = lib.gcc_jit_context_get_type(cc.owner.context, C.type.int64)
    types.runtime_fields[0] = lib.gcc_jit_context_new_field(
        cc.owner.context, nil, types.i64, "cursor")
    types.runtime_fields[1] = lib.gcc_jit_context_new_field(
        cc.owner.context, nil, types.i64, "limit")
    types.runtime_fields[2] = lib.gcc_jit_context_new_field(
        cc.owner.context, nil, types.i64, "accumulator")
    types.runtime_struct = lib.gcc_jit_context_new_struct_type(
        cc.owner.context, nil, "GccJitDriverV1_RuntimeState", 3, types.runtime_fields)
    if pointer_missing(types.i64) or pointer_missing(types.runtime_fields[0])
        or pointer_missing(types.runtime_fields[1]) or pointer_missing(types.runtime_fields[2])
        or pointer_missing(types.runtime_struct) then
        return cc:reject(DIAG.type, STAGE.types, "could not declare runtime state")
    end
    types.runtime_type = lib.gcc_jit_struct_as_type(types.runtime_struct)
    types.runtime_pointer = lib.gcc_jit_type_get_pointer(types.runtime_type)
    types.runtime_size = ffi.sizeof("GccJitDriverV1_RuntimeState")
    if pointer_missing(types.runtime_type) or pointer_missing(types.runtime_pointer) then
        return cc:reject(DIAG.type, STAGE.types, "runtime state type is unavailable")
    end
    cc.metrics.type_ns = elapsed(started)
    return completed(self, cc)
end

function TypeMachine:blocks_ready(cc)
    return cc.block_machine:run(cc, BlockGraphMachine.graph_ready)
end

function TypeMachine:inspected_blocks_ready(cc)
    return cc.block_machine:run(cc, BlockGraphMachine.inspected_graph_ready)
end

function TypeMachine:tail_ready(cc)
    return cc.tail_machine:run(cc, TailGraphMachine.graph_ready)
end

function TypeMachine:inspected_tail_ready(cc)
    return cc.tail_machine:run(cc, TailGraphMachine.inspected_graph_ready)
end

local function bind_runtime_lvalues(cc)
    local projection = cc.function_projection
    local state = lib.gcc_jit_param_as_rvalue(projection.parameters[0])
    projection.cursor = lib.gcc_jit_rvalue_dereference_field(
        state, nil, cc.types.runtime_fields[0])
    projection.limit = lib.gcc_jit_rvalue_dereference_field(
        state, nil, cc.types.runtime_fields[1])
    projection.accumulator = lib.gcc_jit_rvalue_dereference_field(
        state, nil, cc.types.runtime_fields[2])
end

function BlockGraphMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    local context = cc.owner.context
    local projection = cc.function_projection
    projection.parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, cc.types.runtime_pointer, "state")
    projection.function_handle = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.exported, cc.types.i64, "gccjit_block_sum",
        1, projection.parameters, 0)
    projection.entry = lib.gcc_jit_function_new_block(projection.function_handle, "entry")
    projection.check = lib.gcc_jit_function_new_block(projection.function_handle, "check")
    projection.body = lib.gcc_jit_function_new_block(projection.function_handle, "body")
    projection.done = lib.gcc_jit_function_new_block(projection.function_handle, "done")
    bind_runtime_lvalues(cc)
    if pointer_missing(projection.function_handle) or pointer_missing(projection.entry)
        or pointer_missing(projection.check) or pointer_missing(projection.body)
        or pointer_missing(projection.done) or pointer_missing(projection.cursor)
        or pointer_missing(projection.limit) or pointer_missing(projection.accumulator) then
        return cc:reject(DIAG.graph, STAGE.graph, "could not declare block machine")
    end

    lib.gcc_jit_block_end_with_jump(projection.entry, nil, projection.check)
    local condition = lib.gcc_jit_context_new_comparison(
        context, nil, C.comparison.ge, lib.gcc_jit_lvalue_as_rvalue(projection.cursor),
        lib.gcc_jit_lvalue_as_rvalue(projection.limit))
    lib.gcc_jit_block_end_with_conditional(
        projection.check, nil, condition, projection.done, projection.body)
    local square = lib.gcc_jit_context_new_binary_op(
        context, nil, C.binary.multiply, cc.types.i64,
        lib.gcc_jit_lvalue_as_rvalue(projection.cursor),
        lib.gcc_jit_lvalue_as_rvalue(projection.cursor))
    lib.gcc_jit_block_add_assignment_op(
        projection.body, nil, projection.accumulator, C.binary.plus, square)
    lib.gcc_jit_block_add_assignment_op(
        projection.body, nil, projection.cursor, C.binary.plus,
        lib.gcc_jit_context_one(context, cc.types.i64))
    lib.gcc_jit_block_end_with_jump(projection.body, nil, projection.check)
    lib.gcc_jit_block_end_with_return(
        projection.done, nil, lib.gcc_jit_lvalue_as_rvalue(projection.accumulator))
    if lib.gcc_jit_context_get_last_error(context) ~= nil then
        return cc:reject(DIAG.graph, STAGE.graph, "block graph construction failed")
    end
    cc.metrics.graph_ns = elapsed(started)
    return completed(self, cc)
end

function BlockGraphMachine:graph_ready(cc)
    return cc.compile_machine:blocks(cc)
end

function BlockGraphMachine:inspected_graph_ready(cc)
    lib.gcc_jit_function_dump_to_dot(
        cc.function_projection.function_handle, "target/gccjit_driver/blocks.dot")
    lib.gcc_jit_context_dump_to_file(
        cc.owner.context, "target/gccjit_driver/blocks.context.txt", 1)
    lib.gcc_jit_context_compile_to_file(
        cc.owner.context, C.output.assembler, "target/gccjit_driver/blocks.s")
    if lib.gcc_jit_context_get_last_error(cc.owner.context) ~= nil then
        return cc:reject(DIAG.compile, STAGE.compile, "inspected block compilation failed")
    end
    return cc.compile_machine:blocks(cc)
end

function TailGraphMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    local context = cc.owner.context
    local projection = cc.function_projection
    projection.parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, cc.types.runtime_pointer, "state")
    projection.function_handle = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.exported, cc.types.i64, "gccjit_tail_sum",
        1, projection.parameters, 0)
    projection.check = lib.gcc_jit_function_new_block(projection.function_handle, "check")
    projection.body = lib.gcc_jit_function_new_block(projection.function_handle, "body")
    projection.done = lib.gcc_jit_function_new_block(projection.function_handle, "done")
    bind_runtime_lvalues(cc)
    if pointer_missing(projection.function_handle) or pointer_missing(projection.check)
        or pointer_missing(projection.body) or pointer_missing(projection.done)
        or pointer_missing(projection.cursor) or pointer_missing(projection.limit)
        or pointer_missing(projection.accumulator) then
        return cc:reject(DIAG.graph, STAGE.graph, "could not declare tail machine")
    end

    local condition = lib.gcc_jit_context_new_comparison(
        context, nil, C.comparison.ge, lib.gcc_jit_lvalue_as_rvalue(projection.cursor),
        lib.gcc_jit_lvalue_as_rvalue(projection.limit))
    lib.gcc_jit_block_end_with_conditional(
        projection.check, nil, condition, projection.done, projection.body)
    local square = lib.gcc_jit_context_new_binary_op(
        context, nil, C.binary.multiply, cc.types.i64,
        lib.gcc_jit_lvalue_as_rvalue(projection.cursor),
        lib.gcc_jit_lvalue_as_rvalue(projection.cursor))
    lib.gcc_jit_block_add_assignment_op(
        projection.body, nil, projection.accumulator, C.binary.plus, square)
    lib.gcc_jit_block_add_assignment_op(
        projection.body, nil, projection.cursor, C.binary.plus,
        lib.gcc_jit_context_one(context, cc.types.i64))
    projection.call_arguments[0] = lib.gcc_jit_param_as_rvalue(projection.parameters[0])
    local call = lib.gcc_jit_context_new_call(
        context, nil, projection.function_handle, 1, projection.call_arguments)
    lib.gcc_jit_rvalue_set_bool_require_tail_call(call, 1)
    lib.gcc_jit_block_end_with_return(projection.body, nil, call)
    lib.gcc_jit_block_end_with_return(
        projection.done, nil, lib.gcc_jit_lvalue_as_rvalue(projection.accumulator))
    if lib.gcc_jit_context_get_last_error(context) ~= nil then
        return cc:reject(DIAG.graph, STAGE.graph, "tail graph construction failed")
    end
    cc.metrics.graph_ns = elapsed(started)
    return completed(self, cc)
end

function TailGraphMachine:graph_ready(cc)
    return cc.compile_machine:tail(cc)
end

function TailGraphMachine:inspected_graph_ready(cc)
    lib.gcc_jit_function_dump_to_dot(
        cc.function_projection.function_handle, "target/gccjit_driver/tail.dot")
    lib.gcc_jit_context_dump_to_file(
        cc.owner.context, "target/gccjit_driver/tail.context.txt", 1)
    lib.gcc_jit_context_compile_to_file(
        cc.owner.context, C.output.assembler, "target/gccjit_driver/tail.s")
    if lib.gcc_jit_context_get_last_error(cc.owner.context) ~= nil then
        return cc:reject(DIAG.compile, STAGE.compile, "inspected tail compilation failed")
    end
    return cc.compile_machine:tail(cc)
end

local function context_released(cc)
    lib.gcc_jit_context_release(cc.owner.context)
    cc.owner.context = nil
    cc.metrics.releases = cc.metrics.releases + 1
end

function CompileMachine:blocks(cc)
    local started = now_ns()
    self.runs = self.runs + 1
    cc.owner.result = lib.gcc_jit_context_compile(cc.owner.context)
    cc.metrics.compile_ns = elapsed(started)
    if pointer_missing(cc.owner.result) then
        return cc:reject(DIAG.compile, STAGE.compile, "block machine compilation failed")
    end
    started = now_ns()
    cc.owner.entry = lib.gcc_jit_result_get_code(cc.owner.result, "gccjit_block_sum")
    cc.metrics.lookup_ns = elapsed(started)
    if pointer_missing(cc.owner.entry) then
        return cc:reject(DIAG.symbol, STAGE.lookup, "block entry symbol is unavailable")
    end
    context_released(cc)
    return cc:completed()
end

function CompileMachine:tail(cc)
    local started = now_ns()
    self.runs = self.runs + 1
    cc.owner.result = lib.gcc_jit_context_compile(cc.owner.context)
    cc.metrics.compile_ns = elapsed(started)
    if pointer_missing(cc.owner.result) then
        return cc:reject(DIAG.compile, STAGE.compile, "tail machine compilation failed")
    end
    started = now_ns()
    cc.owner.entry = lib.gcc_jit_result_get_code(cc.owner.result, "gccjit_tail_sum")
    cc.metrics.lookup_ns = elapsed(started)
    if pointer_missing(cc.owner.entry) then
        return cc:reject(DIAG.symbol, STAGE.lookup, "tail entry symbol is unavailable")
    end
    context_released(cc)
    return cc:completed()
end

function Driver:completed()
    self.status = STATUS.ready
    self.revision = self.revision + 1
    return self
end

function Driver:entrypoint()
    assert(self:succeeded(), self:diagnostic_text())
    return ffi.cast("int64_t (*)(GccJitDriverV1_RuntimeState *)", self.owner.entry)
end

function Driver:invoke(runtime)
    return tonumber(self:entrypoint()(runtime))
end

function Driver:version()
    return lib.gcc_jit_version_major(), lib.gcc_jit_version_minor(), lib.gcc_jit_version_patchlevel()
end

State.Context:seal()

return State
