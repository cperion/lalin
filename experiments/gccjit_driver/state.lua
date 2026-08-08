local schema = require("cdefschema")
local ffi = require("ffi")
require("experiments.gccjit_driver.abi")

local S = schema.context {
    name = "gccjit-driver",
    version = 1,
    prefix = "GccJitDriverV1_",
}

S:cdef [[
enum {
    GccJitDriverV1_DiagnosticCapacity = 512
};

typedef struct {
    int64_t cursor;
    int64_t limit;
    int64_t accumulator;
} GccJitDriverV1_RuntimeState;

typedef struct {
    gcc_jit_context *context;
    gcc_jit_result *result;
    void *entry;
} GccJitDriverV1_ForeignOwner;

typedef struct {
    gcc_jit_type *i64;
    gcc_jit_struct *runtime_struct;
    gcc_jit_type *runtime_type;
    gcc_jit_type *runtime_pointer;
    gcc_jit_field *runtime_fields[3];
    int64_t runtime_size;
} GccJitDriverV1_TypeProjection;

typedef struct {
    gcc_jit_param *parameters[1];
    gcc_jit_function *function_handle;
    gcc_jit_block *entry;
    gcc_jit_block *check;
    gcc_jit_block *body;
    gcc_jit_block *done;
    gcc_jit_lvalue *cursor;
    gcc_jit_lvalue *limit;
    gcc_jit_lvalue *accumulator;
    gcc_jit_rvalue *call_arguments[1];
} GccJitDriverV1_FunctionProjection;

typedef struct {
    uint32_t code;
    uint32_t stage;
    uint32_t length;
    uint32_t reserved;
    char message[GccJitDriverV1_DiagnosticCapacity];
} GccJitDriverV1_Diagnostic;

typedef struct {
    uint64_t acquire_ns;
    uint64_t type_ns;
    uint64_t graph_ns;
    uint64_t compile_ns;
    uint64_t lookup_ns;
    uint64_t releases;
} GccJitDriverV1_Metrics;

typedef struct { uint64_t runs; } GccJitDriverV1_AcquireMachine;
typedef struct { uint64_t runs; } GccJitDriverV1_TypeMachine;
typedef struct { uint64_t runs; } GccJitDriverV1_BlockGraphMachine;
typedef struct { uint64_t runs; } GccJitDriverV1_TailGraphMachine;
typedef struct { uint64_t runs; } GccJitDriverV1_CompileMachine;

typedef struct {
    GccJitDriverV1_ForeignOwner owner;
    GccJitDriverV1_TypeProjection types;
    GccJitDriverV1_FunctionProjection function_projection;
    GccJitDriverV1_Diagnostic diagnostic;
    GccJitDriverV1_Metrics metrics;
    GccJitDriverV1_AcquireMachine acquire_machine;
    GccJitDriverV1_TypeMachine type_machine;
    GccJitDriverV1_BlockGraphMachine block_machine;
    GccJitDriverV1_TailGraphMachine tail_machine;
    GccJitDriverV1_CompileMachine compile_machine;
    uint64_t revision;
    uint32_t generation;
    uint32_t status;
    uint32_t optimization_level;
    uint32_t reserved;
} GccJitDriverV1_Driver;
]]

local State = {
    Context = S,
    RuntimeState = S:product("GccJitDriverV1_RuntimeState"),
    ForeignOwner = S:product("GccJitDriverV1_ForeignOwner"),
    TypeProjection = S:product("GccJitDriverV1_TypeProjection"),
    FunctionProjection = S:product("GccJitDriverV1_FunctionProjection"),
    Diagnostic = S:product("GccJitDriverV1_Diagnostic"),
    Metrics = S:product("GccJitDriverV1_Metrics"),
    AcquireMachine = S:product("GccJitDriverV1_AcquireMachine"),
    TypeMachine = S:product("GccJitDriverV1_TypeMachine"),
    BlockGraphMachine = S:product("GccJitDriverV1_BlockGraphMachine"),
    TailGraphMachine = S:product("GccJitDriverV1_TailGraphMachine"),
    CompileMachine = S:product("GccJitDriverV1_CompileMachine"),
    Driver = S:product("GccJitDriverV1_Driver"),
}

State.RuntimeStateArray = ffi.typeof("GccJitDriverV1_RuntimeState[1]")
State.constants = {
    status = { empty = 0, building = 1, ready = 2, rejected = 3, released = 4 },
    diagnostic = { context = 1, type = 2, graph = 3, compile = 4, symbol = 5 },
    stage = { acquire = 1, types = 2, graph = 3, compile = 4, lookup = 5 },
}

return State
