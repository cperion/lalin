-- Run the Object–Region–Projection terminal-grid proof:
--   make lalin-bin
--   ./target/lalin demo/orp_grid_run.lua

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local ffi = require("ffi")

ffi.cdef[[
typedef struct { int32_t target; uint8_t op; uint8_t arg; } InputRecord;
typedef struct { uint8_t content; uint8_t focused; uint8_t active; uint32_t epoch; } CellFrame;
typedef struct { int32_t ticks; uint8_t done; } TaskFrame;
typedef struct { uint8_t id, row, width, height, mark; } ViewDecl;
typedef struct { uint8_t id, x, y, width, height, mark; } SolvedCell;
typedef struct { uint8_t kind, arg, phase; } EffectRecord;
typedef struct {
  CellFrame *cells; size_t cell_count; TaskFrame *task;
  ViewDecl *decls; size_t decl_cap; size_t decl_count;
  SolvedCell *solved; size_t solve_cap; size_t solve_count;
  EffectRecord *effects; size_t effect_cap; size_t effect_count;
  uint8_t *screen; size_t screen_cap; size_t screen_len;
  int32_t cursor_row; int32_t cursor_col; uint32_t epoch; uint8_t task_result;
} GridStore;
 ]]

local GridOp = { KEY = 1, ENTER = 2, TAB = 3, TICK = 4 }
local GridId = { CELL_A = 0, CELL_B = 1, TASK = 2 }
local EffectKind = { CURSOR = 1, BEEP = 2, SAVE = 3, ERROR = 4 }
local GridCtl = { W = 10, H = 3, DECL_CAP = 8, SOLVE_CAP = 8, EFFECT_CAP = 8, SCREEN_CAP = 31 }

local decls = assert(lalin.loadfile("demo/orp_grid.lln", {
    env = { GridOp = GridOp, GridId = GridId, EffectKind = EffectKind, GridCtl = GridCtl },
}))
local session = lalin.compile_c_gcc("orp_grid_demo", decls, {
    gcc_opts = { opt = 3, out_dir = "target/demo/orp_grid" },
})
local grid_step = assert(session:symbol("grid_step", "int32_t (*)(InputRecord*, size_t, GridStore*)"))

local cells = ffi.new("CellFrame[2]")
local task = ffi.new("TaskFrame", { ticks = 2, done = 0 })
local decls_buf = ffi.new("ViewDecl[8]")
local solved = ffi.new("SolvedCell[8]")
local effects = ffi.new("EffectRecord[8]")
local screen = ffi.new("uint8_t[31]")
local store = ffi.new("GridStore", {
    cells = cells, cell_count = 2, task = task,
    decls = decls_buf, decl_cap = 8, solved = solved, solve_cap = 8,
    effects = effects, effect_cap = 8, screen = screen, screen_cap = 31,
})

local effect_names = { [1] = "cursor", [2] = "beep", [3] = "save", [4] = "error" }

local function events(rows)
    local out = ffi.new("InputRecord[?]", #rows)
    for i, row in ipairs(rows) do out[i - 1] = row end
    return out
end

local function show(label, rows)
    local input = events(rows)
    grid_step(input, #rows, store)
    local bytes = ffi.string(screen, tonumber(store.screen_len))
    print("\n" .. label)
    for y = 0, GridCtl.H - 1 do
        print("|" .. bytes:sub(y * GridCtl.W + 1, (y + 1) * GridCtl.W) .. "|")
    end
    io.write(string.format("frame epoch=%d, effects=", tonumber(store.epoch)))
    for i = 0, tonumber(store.effect_count) - 1 do
        local e = effects[i]
        io.write(string.format(" %s(arg=%d,phase=%d)", effect_names[e.kind] or "?", e.arg, e.phase))
    end
    io.write("\n")
end

show("initial projection", {})
show("key 'x' + activate + blur", {
    { target = 0, op = GridOp.KEY, arg = string.byte("x") },
    { target = 0, op = GridOp.ENTER, arg = 0 },
    { target = 0, op = GridOp.TAB, arg = 0 },
})
show("activate again (focus)", { { target = 0, op = GridOp.ENTER, arg = 0 } })
show("activate again (persistent active mark)", { { target = 0, op = GridOp.ENTER, arg = 0 } })
show("task tick: running", { { target = GridId.TASK, op = GridOp.TICK, arg = 0 } })
show("task tick: done + delayed save effect", { { target = GridId.TASK, op = GridOp.TICK, arg = 0 } })
show("unsupported physical opcode", { { target = 99, op = 255, arg = 0 } })

session:free()
print("\nORP demo complete")
