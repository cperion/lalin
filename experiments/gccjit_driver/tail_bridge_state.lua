local schema = require("cdefschema")
local ffi = require("ffi")
require("experiments.gccjit_driver.abi")

local S = schema.context {
    name = "gccjit-tail-bridge",
    version = 1,
    prefix = "TailBridgeV1_",
}

S:cdef [[
enum { TailBridgeV1_DiagnosticCapacity = 512 };

typedef struct {
    int64_t cursor;
    int64_t limit;
    int64_t accumulator;
    uint64_t native_transitions;
    uint32_t exit_code;
    uint32_t reserved;
} TailBridgeV1_State;

typedef int64_t (*TailBridgeV1_Entry)(TailBridgeV1_State *state);
typedef int64_t (*TailBridgeV1_Callback)(TailBridgeV1_State *state);
typedef int64_t (*TailBridgeV1_CallbackEntry)(
    TailBridgeV1_State *state, TailBridgeV1_Callback callback);

typedef struct {
    gcc_jit_context *context;
    gcc_jit_result *result;
    TailBridgeV1_Entry entry;
    TailBridgeV1_CallbackEntry callback_entry;
} TailBridgeV1_ForeignOwner;

typedef struct {
    gcc_jit_type *i64;
    gcc_jit_type *u64;
    gcc_jit_type *u32;
    gcc_jit_struct *state_struct;
    gcc_jit_type *state_type;
    gcc_jit_type *state_pointer;
    gcc_jit_field *state_fields[6];
    gcc_jit_type *callback_parameter_types[1];
    gcc_jit_type *callback_type;
} TailBridgeV1_TypeProjection;

typedef struct {
    gcc_jit_function *entry_function;
    gcc_jit_function *run_function;
    gcc_jit_function *complete_function;
    gcc_jit_function *callback_function;
    gcc_jit_param *entry_parameters[1];
    gcc_jit_param *run_parameters[1];
    gcc_jit_param *complete_parameters[1];
    gcc_jit_param *callback_parameters[2];
    gcc_jit_block *entry_body;
    gcc_jit_block *run_check;
    gcc_jit_block *run_body;
    gcc_jit_block *run_done;
    gcc_jit_block *complete_body;
    gcc_jit_block *callback_body;
    gcc_jit_rvalue *call_arguments[1];
} TailBridgeV1_FunctionProjection;

typedef struct {
    uint32_t code;
    uint32_t stage;
    uint32_t length;
    uint32_t reserved;
    char message[TailBridgeV1_DiagnosticCapacity];
} TailBridgeV1_Diagnostic;

typedef struct {
    uint64_t acquire_ns;
    uint64_t type_ns;
    uint64_t graph_ns;
    uint64_t compile_ns;
    uint64_t lookup_ns;
    uint64_t releases;
} TailBridgeV1_Metrics;

typedef struct { uint64_t runs; } TailBridgeV1_AcquireMachine;
typedef struct { uint64_t runs; } TailBridgeV1_TypeMachine;
typedef struct { uint64_t runs; } TailBridgeV1_GraphMachine;
typedef struct { uint64_t runs; } TailBridgeV1_CompileMachine;

typedef struct {
    TailBridgeV1_ForeignOwner owner;
    TailBridgeV1_TypeProjection types;
    TailBridgeV1_FunctionProjection functions;
    TailBridgeV1_Diagnostic diagnostic;
    TailBridgeV1_Metrics metrics;
    TailBridgeV1_AcquireMachine acquire_machine;
    TailBridgeV1_TypeMachine type_machine;
    TailBridgeV1_GraphMachine graph_machine;
    TailBridgeV1_CompileMachine compile_machine;
    uint64_t revision;
    uint32_t status;
    uint32_t optimization_level;
} TailBridgeV1_Driver;
]]

local State = {
    Context = S,
    RuntimeState = S:product("TailBridgeV1_State"),
    ForeignOwner = S:product("TailBridgeV1_ForeignOwner"),
    TypeProjection = S:product("TailBridgeV1_TypeProjection"),
    FunctionProjection = S:product("TailBridgeV1_FunctionProjection"),
    Diagnostic = S:product("TailBridgeV1_Diagnostic"),
    Metrics = S:product("TailBridgeV1_Metrics"),
    AcquireMachine = S:product("TailBridgeV1_AcquireMachine"),
    TypeMachine = S:product("TailBridgeV1_TypeMachine"),
    GraphMachine = S:product("TailBridgeV1_GraphMachine"),
    CompileMachine = S:product("TailBridgeV1_CompileMachine"),
    Driver = S:product("TailBridgeV1_Driver"),
}

State.RuntimeStateArray = ffi.typeof("TailBridgeV1_State[1]")
State.constants = {
    status = { empty = 0, building = 1, ready = 2, rejected = 3, released = 4 },
    diagnostic = { context = 1, type = 2, graph = 3, compile = 4, symbol = 5 },
    stage = { acquire = 1, types = 2, graph = 3, compile = 4, lookup = 5 },
    exit = { native_completed = 1, lua_callback = 2 },
}

return State
