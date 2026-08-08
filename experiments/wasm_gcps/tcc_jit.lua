local ffi = require("ffi")

ffi.cdef[[
typedef struct TCCState TCCState;
TCCState *tcc_new(void);
void tcc_delete(TCCState *state);
int tcc_set_output_type(TCCState *state, int output_type);
int tcc_compile_string(TCCState *state, const char *source);
int tcc_relocate(TCCState *state);
void *tcc_get_symbol(TCCState *state, const char *name);

typedef struct {
    int32_t n;
    int32_t index;
    int32_t result;
    double mixed;
} WasmGcpsTccState;
typedef int32_t (*WasmGcpsI32Add)(int32_t, int32_t);
typedef double (*WasmGcpsF64Binary)(double, double);
typedef void (*WasmGcpsStateStep)(WasmGcpsTccState *);
typedef int32_t (*WasmGcpsSumRegion)(int32_t);
typedef double (*WasmGcpsMixedRegion)(int32_t);
]]

local SOURCE = [[
typedef signed int int32_t;
typedef unsigned int uint32_t;

typedef struct {
    int32_t n;
    int32_t index;
    int32_t result;
    double mixed;
} WasmGcpsTccState;

int32_t wasm_gcps_i32_add(int32_t left, int32_t right)
{
    return (int32_t)((uint32_t)left + (uint32_t)right);
}

double wasm_gcps_f64_add(double left, double right)
{
    return left + right;
}

double wasm_gcps_f64_mul(double left, double right)
{
    return left * right;
}

void wasm_gcps_sum_step(WasmGcpsTccState *state)
{
    state->result = (int32_t)((uint32_t)state->result + (uint32_t)state->index);
    state->index = (int32_t)((uint32_t)state->index + 1u);
}

void wasm_gcps_mixed_step(WasmGcpsTccState *state)
{
    state->mixed = state->mixed + (double)state->index * 1.5;
    state->index = (int32_t)((uint32_t)state->index + 1u);
}

int32_t wasm_gcps_sum_region(int32_t n)
{
    int32_t result = 0;
    int32_t index = 1;
    while (index <= n) {
        result = (int32_t)((uint32_t)result + (uint32_t)index);
        index = (int32_t)((uint32_t)index + 1u);
    }
    return result;
}

double wasm_gcps_mixed_region(int32_t n)
{
    double result = 0.0;
    int32_t index = 1;
    while (index <= n) {
        result = result + (double)index * 1.5;
        index = (int32_t)((uint32_t)index + 1u);
    }
    return result;
}
 ]]

local function load_libtcc()
    local ok, library = pcall(ffi.load, "/usr/local/lib/libtcc.so")
    if ok then return library end
    return ffi.load("tcc")
end

local libtcc = load_libtcc()

local Session = {}
Session.__index = Session

local function symbol(session, name, ctype)
    local address = libtcc.tcc_get_symbol(session.state, name)
    assert(address ~= nil, "missing TCC symbol: " .. name)
    local function_pointer = ffi.cast(ctype, address)
    session.symbols[#session.symbols + 1] = function_pointer
    return function_pointer
end

function Session:free()
    if self.state ~= nil then
        ffi.gc(self.state, nil)
        libtcc.tcc_delete(self.state)
        self.state = nil
        self.symbols = nil
    end
end

local M = {}

function M.compile()
    local state = assert(libtcc.tcc_new(), "tcc_new failed")
    ffi.gc(state, libtcc.tcc_delete)
    assert(libtcc.tcc_set_output_type(state, 1) == 0, "tcc_set_output_type failed")
    assert(libtcc.tcc_compile_string(state, SOURCE) == 0, "tcc_compile_string failed")
    assert(libtcc.tcc_relocate(state) == 0, "tcc_relocate failed")

    local session = setmetatable({ state = state, symbols = {} }, Session)
    session.i32_add = symbol(session, "wasm_gcps_i32_add", "WasmGcpsI32Add")
    session.f64_add = symbol(session, "wasm_gcps_f64_add", "WasmGcpsF64Binary")
    session.f64_mul = symbol(session, "wasm_gcps_f64_mul", "WasmGcpsF64Binary")
    session.sum_step = symbol(session, "wasm_gcps_sum_step", "WasmGcpsStateStep")
    session.mixed_step = symbol(session, "wasm_gcps_mixed_step", "WasmGcpsStateStep")
    session.sum_region = symbol(session, "wasm_gcps_sum_region", "WasmGcpsSumRegion")
    session.mixed_region = symbol(session, "wasm_gcps_mixed_region", "WasmGcpsMixedRegion")
    return session
end

M.source = SOURCE

return M

