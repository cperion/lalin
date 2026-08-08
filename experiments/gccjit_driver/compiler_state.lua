local schema = require("cdefschema")
local Retained = require("experiments.retained_compiler.machine")
require("experiments.gccjit_driver.abi")

local S = schema.context {
    name = "gccjit-compiler",
    version = 1,
    prefix = "GccJitCompilerV1_",
}

S:cdef [[
enum {
    GccJitCompilerV1_RegisterCapacity = 8192,
    GccJitCompilerV1_DiagnosticCapacity = 512
};

typedef struct {
    gcc_jit_context *context;
    gcc_jit_result *result;
    void *entry;
} GccJitCompilerV1_ForeignOwner;

typedef struct {
    gcc_jit_type *i64;
} GccJitCompilerV1_TypeProjection;

typedef struct {
    gcc_jit_function *function_handle;
    gcc_jit_block *body;
    gcc_jit_rvalue *registers[GccJitCompilerV1_RegisterCapacity];
} GccJitCompilerV1_FunctionProjection;

typedef struct {
    uint32_t cursor;
    uint32_t terminated;
    uint64_t projected_count;
    uint64_t started_ns;
} GccJitCompilerV1_BackendProgress;

typedef struct {
    uint32_t code;
    uint32_t stage;
    uint32_t length;
    uint32_t reserved;
    char message[GccJitCompilerV1_DiagnosticCapacity];
} GccJitCompilerV1_Diagnostic;

typedef struct {
    uint64_t acquire_ns;
    uint64_t type_ns;
    uint64_t function_ns;
    uint64_t projection_ns;
    uint64_t compile_ns;
    uint64_t lookup_ns;
    uint64_t releases;
} GccJitCompilerV1_Metrics;

typedef struct {
    RetainedCompilerV1_Compiler retained;
    GccJitCompilerV1_ForeignOwner gcc;
    GccJitCompilerV1_TypeProjection types;
    GccJitCompilerV1_FunctionProjection functions;
    GccJitCompilerV1_BackendProgress backend;
    GccJitCompilerV1_Diagnostic diagnostic;
    GccJitCompilerV1_Metrics metrics;
    uint64_t revision;
    uint32_t generation;
    uint32_t status;
    uint32_t optimization_level;
    uint32_t input_instruction_count;
} GccJitCompilerV1_Compiler;
]]

local State = {
    Context = S,
    ForeignOwner = S:product("GccJitCompilerV1_ForeignOwner"),
    TypeProjection = S:product("GccJitCompilerV1_TypeProjection"),
    FunctionProjection = S:product("GccJitCompilerV1_FunctionProjection"),
    BackendProgress = S:product("GccJitCompilerV1_BackendProgress"),
    Diagnostic = S:product("GccJitCompilerV1_Diagnostic"),
    Metrics = S:product("GccJitCompilerV1_Metrics"),
    Compiler = S:product("GccJitCompilerV1_Compiler"),
}

State.Retained = Retained
State.constants = {
    register_capacity = 8192,
    status = { empty = 0, lowered = 1, building = 2, ready = 3, rejected = 4, released = 5 },
    diagnostic = { frontend = 1, context = 2, type = 3, func = 4, instruction = 5, compile = 6, symbol = 7 },
    stage = { frontend = 1, acquire = 2, types = 3, func = 4, projection = 5, compile = 6, lookup = 7 },
}

return State
