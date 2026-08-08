local ffi = require("ffi")
local ABI = require("experiments.gccjit_driver.abi")
local State = require("experiments.gccjit_driver.compiler_state")
local monotonic_now = require("lalin.luajit_measure").now

local lib = ABI.lib
local C = ABI.constants
local Retained = State.Retained
local RC = Retained.constants
local STATUS = State.constants.status
local DIAG = State.constants.diagnostic
local STAGE = State.constants.stage
local REGISTER_CAPACITY = State.constants.register_capacity
local OP_ADD, OP_SUBTRACT, OP_MULTIPLY =
    RC.operator.add, RC.operator.subtract, RC.operator.multiply
local GCC_PLUS, GCC_MINUS, GCC_MULTIPLY = C.binary.plus, C.binary.minus, C.binary.multiply

local Compiler = State.Compiler

local function now_ns() return math.floor(monotonic_now() * 1000000000 + 0.5) end
local function elapsed(started) return now_ns() - started end
local function missing(value) return value == nil end

function Compiler:release_foreign()
    if self.gcc.context ~= nil then
        lib.gcc_jit_context_release(self.gcc.context)
        self.gcc.context = nil
        self.metrics.releases = self.metrics.releases + 1
    end
    if self.gcc.result ~= nil then
        lib.gcc_jit_result_release(self.gcc.result)
        self.gcc.result = nil
        self.metrics.releases = self.metrics.releases + 1
    end
    self.gcc.entry = nil
    return self
end

function Compiler:prepare()
    self:release_foreign()
    ffi.fill(self.types, ffi.sizeof(self.types))
    ffi.fill(self.functions, ffi.sizeof(self.functions))
    ffi.fill(self.backend, ffi.sizeof(self.backend))
    ffi.fill(self.diagnostic, ffi.sizeof(self.diagnostic))
    ffi.fill(self.metrics, ffi.sizeof(self.metrics))
    self.generation = self.generation + 1
    if self.generation == 0 then self.generation = 1 end
    self.input_instruction_count = 0
    self.status = STATUS.empty
    return self
end

function Compiler:reject(code, stage, fallback)
    self.diagnostic.code, self.diagnostic.stage = code, stage
    local message
    if self.gcc.context ~= nil then
        local foreign = lib.gcc_jit_context_get_last_error(self.gcc.context)
        if foreign == nil then foreign = lib.gcc_jit_context_get_first_error(self.gcc.context) end
        if foreign ~= nil then message = ffi.string(foreign) end
    end
    message = message or fallback or "gccjit compiler rejected"
    local length = math.min(#message, 511)
    ffi.copy(self.diagnostic.message, message, length)
    self.diagnostic.message[length] = 0
    self.diagnostic.length = length
    self.status = STATUS.rejected
    self.revision = self.revision + 1
    self:release_foreign()
    return self
end

function Compiler:diagnostic_text()
    if self.diagnostic.length ~= 0 then
        return ffi.string(self.diagnostic.message, self.diagnostic.length)
    end
    return self.retained:diagnostic_text()
end

function Compiler:succeeded() return self.status == STATUS.ready end
function Compiler:lowered() return self.status == STATUS.lowered end

function Compiler:free()
    self:release_foreign()
    self.status = STATUS.released
    return self
end

function Compiler:lower(source)
    self:prepare()
    self.retained:compile(source)
    if not self.retained:succeeded() then
        return self:reject(DIAG.frontend, STAGE.frontend, self.retained:diagnostic_text())
    end
    self.input_instruction_count = self.retained.instructions.count
    self.status = STATUS.lowered
    return self
end

function Compiler:compile(source, optimization_level)
    self:lower(source)
    if not self:lowered() then return self end
    return self:cook(optimization_level)
end

function Compiler:inspect(source, optimization_level)
    self:lower(source)
    if not self:lowered() then return self end
    return self:cook_inspected(optimization_level)
end

function Compiler:cook(optimization_level)
    assert(self:lowered(), "compiler must own successfully lowered input")
    self.optimization_level = optimization_level or 3
    assert(self.optimization_level >= 0 and self.optimization_level <= 3,
        "optimization level must be 0..3")
    self.status = STATUS.building
    return self:gcc_acquire(Compiler.gcc_acquired)
end

function Compiler:cook_inspected(optimization_level)
    assert(self:lowered(), "compiler must own successfully lowered input")
    self.optimization_level = optimization_level or 3
    assert(self.optimization_level >= 0 and self.optimization_level <= 3,
        "optimization level must be 0..3")
    self.status = STATUS.building
    return self:gcc_acquire(Compiler.gcc_inspected_acquired)
end

function Compiler:gcc_acquire(completed)
    local started = now_ns()
    self.gcc.context = lib.gcc_jit_context_acquire()
    if missing(self.gcc.context) then
        return self:reject(DIAG.context, STAGE.acquire, "could not acquire libgccjit context")
    end
    lib.gcc_jit_context_set_int_option(
        self.gcc.context, C.int_option.optimization_level, self.optimization_level)
    self.metrics.acquire_ns = elapsed(started)
    return completed(self)
end

function Compiler:gcc_acquired() return self:gcc_declare_type(Compiler.gcc_type_ready) end
function Compiler:gcc_inspected_acquired()
    return self:gcc_declare_type(Compiler.gcc_inspected_type_ready)
end

function Compiler:gcc_declare_type(completed)
    local started = now_ns()
    self.types.i64 = lib.gcc_jit_context_get_type(self.gcc.context, C.type.int64)
    if missing(self.types.i64) then
        return self:reject(DIAG.type, STAGE.types, "int64 type is unavailable")
    end
    self.metrics.type_ns = elapsed(started)
    return completed(self)
end

function Compiler:gcc_type_ready()
    return self:gcc_declare_function(Compiler.gcc_function_ready)
end

function Compiler:gcc_inspected_type_ready()
    return self:gcc_declare_function(Compiler.gcc_inspected_function_ready)
end

function Compiler:gcc_declare_function(completed)
    local started = now_ns()
    self.functions.function_handle = lib.gcc_jit_context_new_function(
        self.gcc.context, nil, C.function_kind.exported, self.types.i64,
        "retained_eval", 0, nil, 0)
    if missing(self.functions.function_handle) then
        return self:reject(DIAG.func, STAGE.func, "could not declare retained_eval")
    end
    self.functions.body = lib.gcc_jit_function_new_block(
        self.functions.function_handle, "body")
    if missing(self.functions.body) then
        return self:reject(DIAG.func, STAGE.func, "could not declare retained_eval body")
    end
    self.metrics.function_ns = elapsed(started)
    return completed(self)
end

function Compiler:gcc_function_ready() return self:gcc_project() end
function Compiler:gcc_inspected_function_ready() return self:gcc_project_inspected() end

function Compiler:gcc_project()
    self.backend.cursor, self.backend.terminated, self.backend.projected_count = 0, 0, 0
    self.backend.started_ns = now_ns()
    return self:gcc_project_next()
end

function Compiler:gcc_project_next()
    if self.backend.cursor >= self.retained.instructions.count then
        if self.backend.terminated == 0 then
            return self:reject(DIAG.instruction, STAGE.projection, "lowered function has no return")
        end
        self.metrics.projection_ns = elapsed(tonumber(self.backend.started_ns))
        return self:gcc_compile_result()
    end
    if self.backend.terminated ~= 0 then
        return self:reject(DIAG.instruction, STAGE.projection, "instruction follows return")
    end
    return self.retained.instructions.items[self.backend.cursor]:project_gccjit(
        self, Compiler.gcc_instruction_projected)
end

function Compiler:gcc_instruction_projected()
    self.backend.cursor = self.backend.cursor + 1
    self.backend.projected_count = self.backend.projected_count + 1
    return self:gcc_project_next()
end

function Compiler:gcc_project_inspected()
    self.backend.cursor, self.backend.terminated, self.backend.projected_count = 0, 0, 0
    self.backend.started_ns = now_ns()
    return self:gcc_project_inspected_next()
end

function Compiler:gcc_project_inspected_next()
    if self.backend.cursor >= self.retained.instructions.count then
        if self.backend.terminated == 0 then
            return self:reject(DIAG.instruction, STAGE.projection, "lowered function has no return")
        end
        self.metrics.projection_ns = elapsed(tonumber(self.backend.started_ns))
        os.execute("mkdir -p target/gccjit_driver")
        lib.gcc_jit_function_dump_to_dot(
            self.functions.function_handle, "target/gccjit_driver/compiler.dot")
        lib.gcc_jit_context_dump_to_file(
            self.gcc.context, "target/gccjit_driver/compiler.context.txt", 1)
        lib.gcc_jit_context_compile_to_file(
            self.gcc.context, C.output.assembler, "target/gccjit_driver/compiler.s")
        if lib.gcc_jit_context_get_last_error(self.gcc.context) ~= nil then
            return self:reject(DIAG.compile, STAGE.compile, "inspected compilation failed")
        end
        return self:gcc_compile_result()
    end
    if self.backend.terminated ~= 0 then
        return self:reject(DIAG.instruction, STAGE.projection, "instruction follows return")
    end
    return self.retained.instructions.items[self.backend.cursor]:project_gccjit(
        self, Compiler.gcc_inspected_instruction_projected)
end

function Compiler:gcc_inspected_instruction_projected()
    self.backend.cursor = self.backend.cursor + 1
    self.backend.projected_count = self.backend.projected_count + 1
    return self:gcc_project_inspected_next()
end

function Compiler:invalid_retained_instruction()
    return self:reject(DIAG.instruction, STAGE.projection, "invalid retained instruction")
end

function Compiler:gcc_project_constant(instruction, completed)
    if instruction.target >= REGISTER_CAPACITY then
        return self:reject(DIAG.instruction, STAGE.projection, "constant target is out of range")
    end
    local value = lib.gcc_jit_context_new_rvalue_from_long(
        self.gcc.context, self.types.i64, instruction.value)
    if missing(value) then
        return self:reject(DIAG.instruction, STAGE.projection, "constant projection failed")
    end
    self.functions.registers[instruction.target] = value
    return completed(self)
end

function Compiler:gcc_project_binary(instruction, completed)
    if instruction.target >= REGISTER_CAPACITY or instruction.left >= REGISTER_CAPACITY
        or instruction.right >= REGISTER_CAPACITY then
        return self:reject(DIAG.instruction, STAGE.projection, "binary register is out of range")
    end
    local left = self.functions.registers[instruction.left]
    local right = self.functions.registers[instruction.right]
    if missing(left) or missing(right) then
        return self:reject(DIAG.instruction, STAGE.projection, "binary operand is unavailable")
    end
    local operator
    if instruction.operator_kind == OP_ADD then operator = GCC_PLUS
    elseif instruction.operator_kind == OP_SUBTRACT then operator = GCC_MINUS
    elseif instruction.operator_kind == OP_MULTIPLY then operator = GCC_MULTIPLY
    else return self:reject(DIAG.instruction, STAGE.projection, "binary operator is invalid") end
    local value = lib.gcc_jit_context_new_binary_op(
        self.gcc.context, nil, operator, self.types.i64, left, right)
    if missing(value) then
        return self:reject(DIAG.instruction, STAGE.projection, "binary projection failed")
    end
    self.functions.registers[instruction.target] = value
    return completed(self)
end

function Compiler:gcc_project_return(instruction, completed)
    if instruction.value >= REGISTER_CAPACITY then
        return self:reject(DIAG.instruction, STAGE.projection, "return register is out of range")
    end
    local value = self.functions.registers[instruction.value]
    if missing(value) then
        return self:reject(DIAG.instruction, STAGE.projection, "return value is unavailable")
    end
    lib.gcc_jit_block_end_with_return(self.functions.body, nil, value)
    if lib.gcc_jit_context_get_last_error(self.gcc.context) ~= nil then
        return self:reject(DIAG.instruction, STAGE.projection, "return projection failed")
    end
    self.backend.terminated = 1
    return completed(self)
end

function Compiler:gcc_compile_result()
    local started = now_ns()
    self.gcc.result = lib.gcc_jit_context_compile(self.gcc.context)
    self.metrics.compile_ns = elapsed(started)
    if missing(self.gcc.result) then
        return self:reject(DIAG.compile, STAGE.compile, "retained function compilation failed")
    end
    started = now_ns()
    self.gcc.entry = lib.gcc_jit_result_get_code(self.gcc.result, "retained_eval")
    self.metrics.lookup_ns = elapsed(started)
    if missing(self.gcc.entry) then
        return self:reject(DIAG.symbol, STAGE.lookup, "retained_eval symbol is unavailable")
    end
    lib.gcc_jit_context_release(self.gcc.context)
    self.gcc.context = nil
    self.metrics.releases = self.metrics.releases + 1
    self.status = STATUS.ready
    self.revision = self.revision + 1
    return self
end

function Compiler:entrypoint()
    assert(self:succeeded(), self:diagnostic_text())
    return ffi.cast("int64_t (*)(void)", self.gcc.entry)
end

function Compiler:invoke() return tonumber(self:entrypoint()()) end

State.Context:seal()

return State
