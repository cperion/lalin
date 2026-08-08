local ffi = require("ffi")

ffi.cdef [[
typedef struct gcc_jit_context gcc_jit_context;
typedef struct gcc_jit_result gcc_jit_result;
typedef struct gcc_jit_object gcc_jit_object;
typedef struct gcc_jit_type gcc_jit_type;
typedef struct gcc_jit_field gcc_jit_field;
typedef struct gcc_jit_struct gcc_jit_struct;
typedef struct gcc_jit_function gcc_jit_function;
typedef struct gcc_jit_block gcc_jit_block;
typedef struct gcc_jit_rvalue gcc_jit_rvalue;
typedef struct gcc_jit_lvalue gcc_jit_lvalue;
typedef struct gcc_jit_param gcc_jit_param;

gcc_jit_context *gcc_jit_context_acquire(void);
void gcc_jit_context_release(gcc_jit_context *ctxt);
void gcc_jit_context_set_int_option(gcc_jit_context *ctxt, int opt, int value);
void gcc_jit_context_set_bool_option(gcc_jit_context *ctxt, int opt, int value);
const char *gcc_jit_context_get_first_error(gcc_jit_context *ctxt);
const char *gcc_jit_context_get_last_error(gcc_jit_context *ctxt);
gcc_jit_result *gcc_jit_context_compile(gcc_jit_context *ctxt);
void gcc_jit_context_compile_to_file(gcc_jit_context *ctxt, int output_kind, const char *output_path);
void gcc_jit_context_dump_to_file(gcc_jit_context *ctxt, const char *path, int update_locations);
void *gcc_jit_result_get_code(gcc_jit_result *result, const char *funcname);
void gcc_jit_result_release(gcc_jit_result *result);

gcc_jit_type *gcc_jit_context_get_type(gcc_jit_context *ctxt, int type_);
gcc_jit_field *gcc_jit_context_new_field(gcc_jit_context *ctxt, void *loc, gcc_jit_type *type, const char *name);
gcc_jit_struct *gcc_jit_context_new_struct_type(gcc_jit_context *ctxt, void *loc, const char *name,
    int num_fields, gcc_jit_field **fields);
gcc_jit_type *gcc_jit_struct_as_type(gcc_jit_struct *struct_type);
gcc_jit_type *gcc_jit_type_get_pointer(gcc_jit_type *type);
gcc_jit_type *gcc_jit_context_new_function_ptr_type(gcc_jit_context *ctxt, void *loc,
    gcc_jit_type *return_type, int num_params, gcc_jit_type **param_types, int is_variadic);
long gcc_jit_type_get_size(gcc_jit_type *type);

gcc_jit_param *gcc_jit_context_new_param(gcc_jit_context *ctxt, void *loc, gcc_jit_type *type,
    const char *name);
gcc_jit_rvalue *gcc_jit_param_as_rvalue(gcc_jit_param *param);
gcc_jit_function *gcc_jit_context_new_function(gcc_jit_context *ctxt, void *loc, int kind,
    gcc_jit_type *return_type, const char *name, int num_params, gcc_jit_param **params, int is_variadic);
gcc_jit_block *gcc_jit_function_new_block(gcc_jit_function *func, const char *name);
void gcc_jit_function_dump_to_dot(gcc_jit_function *func, const char *path);
void gcc_jit_function_add_attribute(gcc_jit_function *func, int attribute);

gcc_jit_lvalue *gcc_jit_rvalue_dereference_field(gcc_jit_rvalue *ptr, void *loc, gcc_jit_field *field);
gcc_jit_rvalue *gcc_jit_lvalue_as_rvalue(gcc_jit_lvalue *lvalue);
gcc_jit_rvalue *gcc_jit_context_new_rvalue_from_long(gcc_jit_context *ctxt,
    gcc_jit_type *numeric_type, long value);
gcc_jit_rvalue *gcc_jit_context_zero(gcc_jit_context *ctxt, gcc_jit_type *numeric_type);
gcc_jit_rvalue *gcc_jit_context_one(gcc_jit_context *ctxt, gcc_jit_type *numeric_type);
gcc_jit_rvalue *gcc_jit_context_new_binary_op(gcc_jit_context *ctxt, void *loc, int op,
    gcc_jit_type *result_type, gcc_jit_rvalue *a, gcc_jit_rvalue *b);
gcc_jit_rvalue *gcc_jit_context_new_comparison(gcc_jit_context *ctxt, void *loc, int op,
    gcc_jit_rvalue *a, gcc_jit_rvalue *b);
gcc_jit_rvalue *gcc_jit_context_new_call(gcc_jit_context *ctxt, void *loc, gcc_jit_function *func,
    int numargs, gcc_jit_rvalue **args);
gcc_jit_rvalue *gcc_jit_context_new_call_through_ptr(gcc_jit_context *ctxt, void *loc,
    gcc_jit_rvalue *fn_ptr, int numargs, gcc_jit_rvalue **args);
void gcc_jit_rvalue_set_bool_require_tail_call(gcc_jit_rvalue *call, int require_tail_call);

void gcc_jit_block_add_assignment(gcc_jit_block *block, void *loc, gcc_jit_lvalue *lvalue,
    gcc_jit_rvalue *rvalue);
void gcc_jit_block_add_assignment_op(gcc_jit_block *block, void *loc, gcc_jit_lvalue *lvalue,
    int op, gcc_jit_rvalue *rvalue);
void gcc_jit_block_end_with_conditional(gcc_jit_block *block, void *loc, gcc_jit_rvalue *boolval,
    gcc_jit_block *on_true, gcc_jit_block *on_false);
void gcc_jit_block_end_with_jump(gcc_jit_block *block, void *loc, gcc_jit_block *target);
void gcc_jit_block_end_with_return(gcc_jit_block *block, void *loc, gcc_jit_rvalue *rvalue);

int gcc_jit_version_major(void);
int gcc_jit_version_minor(void);
int gcc_jit_version_patchlevel(void);
]]

local candidates = {}
if os.getenv("LIBGCCJIT_PATH") then candidates[#candidates + 1] = os.getenv("LIBGCCJIT_PATH") end
candidates[#candidates + 1] = "gccjit"

local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local root = source:match("^(.*)/experiments/gccjit_driver/abi%.lua$")
if root then candidates[#candidates + 1] = root .. "/target/libgccjit/usr/lib64/libgccjit.so.0" end
candidates[#candidates + 1] = "target/libgccjit/usr/lib64/libgccjit.so.0"

local lib, failures
for index = 1, #candidates do
    local ok, loaded = pcall(ffi.load, candidates[index])
    if ok then
        lib = loaded
        break
    end
    failures = (failures and failures .. "\n" or "") .. tostring(loaded)
end
assert(lib, "libgccjit is unavailable:\n" .. tostring(failures))

return {
    lib = lib,
    constants = {
        int_option = { optimization_level = 0 },
        bool_option = { dump_generated_code = 3, dump_summary = 4, keep_intermediates = 7 },
        type = { uint32 = 25, uint64 = 26, int64 = 31 },
        function_kind = { exported = 0, internal = 1, imported = 2, always_inline = 3 },
        function_attribute = { alias = 0, always_inline = 1, inline = 2, noinline = 3 },
        binary = { plus = 0, minus = 1, multiply = 2 },
        comparison = { ge = 5 },
        output = { assembler = 0, object = 1, dynamic_library = 2, executable = 3 },
    },
}
