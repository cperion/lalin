local ffi = require("ffi")
local ABI = require("experiments.gccjit_driver.abi")
local State = require("experiments.gccjit_driver.tail_bridge_state")
local monotonic_now = require("lalin.luajit_measure").now

local lib = ABI.lib
local C = ABI.constants
local STATUS = State.constants.status
local DIAG = State.constants.diagnostic
local STAGE = State.constants.stage

local Driver = State.Driver
local AcquireMachine = State.AcquireMachine
local TypeMachine = State.TypeMachine
local GraphMachine = State.GraphMachine
local CompileMachine = State.CompileMachine

local function now_ns() return math.floor(monotonic_now() * 1000000000 + 0.5) end
local function elapsed(started) return now_ns() - started end
local function missing(value) return value == nil end

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
    self.owner.entry, self.owner.callback_entry = nil, nil
    return self
end

function Driver:prepare(optimization_level)
    assert(optimization_level >= 0 and optimization_level <= 3, "optimization level must be 0..3")
    self:release_foreign()
    ffi.fill(self.types, ffi.sizeof(self.types))
    ffi.fill(self.functions, ffi.sizeof(self.functions))
    ffi.fill(self.diagnostic, ffi.sizeof(self.diagnostic))
    ffi.fill(self.metrics, ffi.sizeof(self.metrics))
    self.status, self.optimization_level = STATUS.building, optimization_level
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
    message = message or fallback or "tail bridge construction rejected"
    local length = math.min(#message, 511)
    ffi.copy(self.diagnostic.message, message, length)
    self.diagnostic.message[length] = 0
    self.diagnostic.length = length
    self.status = STATUS.rejected
    self.revision = self.revision + 1
    self:release_foreign()
    return self
end

function Driver:diagnostic_text() return ffi.string(self.diagnostic.message, self.diagnostic.length) end
function Driver:succeeded() return self.status == STATUS.ready end

function Driver:free()
    self:release_foreign()
    self.status = STATUS.released
    return self
end

function Driver:cook(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.acquired)
end

function Driver:inspect(optimization_level)
    self:prepare(optimization_level or 3)
    return self.acquire_machine:run(self, AcquireMachine.inspected_acquired)
end

function AcquireMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    cc.owner.context = lib.gcc_jit_context_acquire()
    if missing(cc.owner.context) then
        return cc:reject(DIAG.context, STAGE.acquire, "could not acquire libgccjit context")
    end
    lib.gcc_jit_context_set_int_option(
        cc.owner.context, C.int_option.optimization_level, cc.optimization_level)
    cc.metrics.acquire_ns = elapsed(started)
    return completed(self, cc)
end

function AcquireMachine:acquired(cc) return cc.type_machine:run(cc, TypeMachine.types_ready) end
function AcquireMachine:inspected_acquired(cc)
    return cc.type_machine:run(cc, TypeMachine.inspected_types_ready)
end

function TypeMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    local types = cc.types
    local context = cc.owner.context
    types.i64 = lib.gcc_jit_context_get_type(context, C.type.int64)
    types.u64 = lib.gcc_jit_context_get_type(context, C.type.uint64)
    types.u32 = lib.gcc_jit_context_get_type(context, C.type.uint32)
    types.state_fields[0] = lib.gcc_jit_context_new_field(context, nil, types.i64, "cursor")
    types.state_fields[1] = lib.gcc_jit_context_new_field(context, nil, types.i64, "limit")
    types.state_fields[2] = lib.gcc_jit_context_new_field(context, nil, types.i64, "accumulator")
    types.state_fields[3] = lib.gcc_jit_context_new_field(context, nil, types.u64, "native_transitions")
    types.state_fields[4] = lib.gcc_jit_context_new_field(context, nil, types.u32, "exit_code")
    types.state_fields[5] = lib.gcc_jit_context_new_field(context, nil, types.u32, "reserved")
    types.state_struct = lib.gcc_jit_context_new_struct_type(
        context, nil, "TailBridgeV1_State", 6, types.state_fields)
    if missing(types.i64) or missing(types.u64) or missing(types.u32)
        or missing(types.state_struct) then
        return cc:reject(DIAG.type, STAGE.types, "could not declare bridge state")
    end
    types.state_type = lib.gcc_jit_struct_as_type(types.state_struct)
    types.state_pointer = lib.gcc_jit_type_get_pointer(types.state_type)
    types.callback_parameter_types[0] = types.state_pointer
    types.callback_type = lib.gcc_jit_context_new_function_ptr_type(
        context, nil, types.i64, 1, types.callback_parameter_types, 0)
    if missing(types.state_pointer) or missing(types.callback_type) then
        return cc:reject(DIAG.type, STAGE.types, "could not declare callback ABI")
    end
    cc.metrics.type_ns = elapsed(started)
    return completed(self, cc)
end

function TypeMachine:types_ready(cc) return cc.graph_machine:run(cc, GraphMachine.graph_ready) end
function TypeMachine:inspected_types_ready(cc)
    return cc.graph_machine:run(cc, GraphMachine.inspected_graph_ready)
end

local function field_lvalue(parameter, field)
    return lib.gcc_jit_rvalue_dereference_field(
        lib.gcc_jit_param_as_rvalue(parameter), nil, field)
end

local function require_tail_return(block, call)
    lib.gcc_jit_rvalue_set_bool_require_tail_call(call, 1)
    lib.gcc_jit_block_end_with_return(block, nil, call)
end

function GraphMachine:run(cc, completed)
    local started = now_ns()
    self.runs = self.runs + 1
    local context, types, functions = cc.owner.context, cc.types, cc.functions

    functions.entry_parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, types.state_pointer, "state")
    functions.run_parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, types.state_pointer, "state")
    functions.complete_parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, types.state_pointer, "state")
    functions.callback_parameters[0] = lib.gcc_jit_context_new_param(
        context, nil, types.state_pointer, "state")
    functions.callback_parameters[1] = lib.gcc_jit_context_new_param(
        context, nil, types.callback_type, "callback")

    functions.entry_function = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.exported, types.i64, "tail_bridge_entry",
        1, functions.entry_parameters, 0)
    functions.run_function = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.internal, types.i64, "tail_bridge_run",
        1, functions.run_parameters, 0)
    functions.complete_function = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.internal, types.i64, "tail_bridge_complete",
        1, functions.complete_parameters, 0)
    functions.callback_function = lib.gcc_jit_context_new_function(
        context, nil, C.function_kind.exported, types.i64, "tail_bridge_callback",
        2, functions.callback_parameters, 0)
    if missing(functions.entry_function) or missing(functions.run_function)
        or missing(functions.complete_function) or missing(functions.callback_function) then
        return cc:reject(DIAG.graph, STAGE.graph, "could not declare bridge functions")
    end
    lib.gcc_jit_function_add_attribute(functions.run_function, C.function_attribute.noinline)
    lib.gcc_jit_function_add_attribute(functions.complete_function, C.function_attribute.noinline)

    functions.entry_body = lib.gcc_jit_function_new_block(functions.entry_function, "entry")
    functions.run_check = lib.gcc_jit_function_new_block(functions.run_function, "check")
    functions.run_body = lib.gcc_jit_function_new_block(functions.run_function, "body")
    functions.run_done = lib.gcc_jit_function_new_block(functions.run_function, "done")
    functions.complete_body = lib.gcc_jit_function_new_block(functions.complete_function, "complete")
    functions.callback_body = lib.gcc_jit_function_new_block(functions.callback_function, "callback")

    functions.call_arguments[0] = lib.gcc_jit_param_as_rvalue(functions.entry_parameters[0])
    local entry_call = lib.gcc_jit_context_new_call(
        context, nil, functions.run_function, 1, functions.call_arguments)
    require_tail_return(functions.entry_body, entry_call)

    local run_cursor = field_lvalue(functions.run_parameters[0], types.state_fields[0])
    local run_limit = field_lvalue(functions.run_parameters[0], types.state_fields[1])
    local run_accumulator = field_lvalue(functions.run_parameters[0], types.state_fields[2])
    local run_transitions = field_lvalue(functions.run_parameters[0], types.state_fields[3])
    local condition = lib.gcc_jit_context_new_comparison(
        context, nil, C.comparison.ge, lib.gcc_jit_lvalue_as_rvalue(run_cursor),
        lib.gcc_jit_lvalue_as_rvalue(run_limit))
    lib.gcc_jit_block_end_with_conditional(
        functions.run_check, nil, condition, functions.run_done, functions.run_body)
    local square = lib.gcc_jit_context_new_binary_op(
        context, nil, C.binary.multiply, types.i64,
        lib.gcc_jit_lvalue_as_rvalue(run_cursor), lib.gcc_jit_lvalue_as_rvalue(run_cursor))
    lib.gcc_jit_block_add_assignment_op(
        functions.run_body, nil, run_accumulator, C.binary.plus, square)
    lib.gcc_jit_block_add_assignment_op(
        functions.run_body, nil, run_cursor, C.binary.plus, lib.gcc_jit_context_one(context, types.i64))
    lib.gcc_jit_block_add_assignment_op(
        functions.run_body, nil, run_transitions, C.binary.plus,
        lib.gcc_jit_context_one(context, types.u64))
    lib.gcc_jit_block_end_with_jump(functions.run_body, nil, functions.run_check)
    functions.call_arguments[0] = lib.gcc_jit_param_as_rvalue(functions.run_parameters[0])
    local complete_call = lib.gcc_jit_context_new_call(
        context, nil, functions.complete_function, 1, functions.call_arguments)
    require_tail_return(functions.run_done, complete_call)

    local complete_exit = field_lvalue(functions.complete_parameters[0], types.state_fields[4])
    local complete_accumulator = field_lvalue(functions.complete_parameters[0], types.state_fields[2])
    lib.gcc_jit_block_add_assignment(
        functions.complete_body, nil, complete_exit, lib.gcc_jit_context_one(context, types.u32))
    lib.gcc_jit_block_end_with_return(
        functions.complete_body, nil, lib.gcc_jit_lvalue_as_rvalue(complete_accumulator))

    local callback_transitions = field_lvalue(functions.callback_parameters[0], types.state_fields[3])
    lib.gcc_jit_block_add_assignment_op(
        functions.callback_body, nil, callback_transitions, C.binary.plus,
        lib.gcc_jit_context_one(context, types.u64))
    functions.call_arguments[0] = lib.gcc_jit_param_as_rvalue(functions.callback_parameters[0])
    local callback_call = lib.gcc_jit_context_new_call_through_ptr(
        context, nil, lib.gcc_jit_param_as_rvalue(functions.callback_parameters[1]),
        1, functions.call_arguments)
    require_tail_return(functions.callback_body, callback_call)

    if lib.gcc_jit_context_get_last_error(context) ~= nil then
        return cc:reject(DIAG.graph, STAGE.graph, "bridge graph construction failed")
    end
    cc.metrics.graph_ns = elapsed(started)
    return completed(self, cc)
end

function GraphMachine:graph_ready(cc) return cc.compile_machine:run(cc) end

function GraphMachine:inspected_graph_ready(cc)
    os.execute("mkdir -p target/gccjit_driver")
    lib.gcc_jit_function_dump_to_dot(cc.functions.entry_function, "target/gccjit_driver/bridge_entry.dot")
    lib.gcc_jit_function_dump_to_dot(cc.functions.run_function, "target/gccjit_driver/bridge_run.dot")
    lib.gcc_jit_function_dump_to_dot(
        cc.functions.callback_function, "target/gccjit_driver/bridge_callback.dot")
    lib.gcc_jit_context_dump_to_file(
        cc.owner.context, "target/gccjit_driver/bridge.context.txt", 1)
    lib.gcc_jit_context_compile_to_file(
        cc.owner.context, C.output.assembler, "target/gccjit_driver/bridge.s")
    if lib.gcc_jit_context_get_last_error(cc.owner.context) ~= nil then
        return cc:reject(DIAG.compile, STAGE.compile, "bridge inspection compilation failed")
    end
    return cc.compile_machine:run(cc)
end

function CompileMachine:run(cc)
    local started = now_ns()
    self.runs = self.runs + 1
    cc.owner.result = lib.gcc_jit_context_compile(cc.owner.context)
    cc.metrics.compile_ns = elapsed(started)
    if missing(cc.owner.result) then
        return cc:reject(DIAG.compile, STAGE.compile, "tail bridge compilation failed")
    end
    started = now_ns()
    local entry = lib.gcc_jit_result_get_code(cc.owner.result, "tail_bridge_entry")
    local callback_entry = lib.gcc_jit_result_get_code(cc.owner.result, "tail_bridge_callback")
    cc.metrics.lookup_ns = elapsed(started)
    if missing(entry) or missing(callback_entry) then
        return cc:reject(DIAG.symbol, STAGE.lookup, "tail bridge symbols are unavailable")
    end
    cc.owner.entry = ffi.cast("TailBridgeV1_Entry", entry)
    cc.owner.callback_entry = ffi.cast("TailBridgeV1_CallbackEntry", callback_entry)
    lib.gcc_jit_context_release(cc.owner.context)
    cc.owner.context = nil
    cc.metrics.releases = cc.metrics.releases + 1
    return cc:completed()
end

function Driver:completed()
    self.status = STATUS.ready
    self.revision = self.revision + 1
    return self
end

function Driver:turn(runtime)
    return self.owner.entry(runtime)
end

function Driver:callback_turn(runtime, callback)
    return self.owner.callback_entry(runtime, callback)
end

State.Context:seal()

return State
