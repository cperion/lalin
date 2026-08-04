package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- End-to-end proof of the general Object–Region–Projection pattern:
-- typed object frames, continuation transitions, readonly projections, a tiny
-- layout world, terminal rasterization, physical boundary decoding, effects,
-- deterministic execution, and real emitted C cooked by GCC.

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
    assert(why.skip == true)
    io.write("Lalin ORP grid GCC skipped\n")
    os.exit(0)
end

local ffi = require("ffi")
ffi.cdef[[
typedef struct { int32_t target; uint8_t op; uint8_t arg; } InputRecord;
typedef struct { uint8_t content; uint8_t focused; uint8_t active; uint32_t epoch; } CellFrame;
typedef struct { int32_t ticks; uint8_t done; } TaskFrame;
typedef struct { uint8_t id, row, width, height, mark; } ViewDecl;
typedef struct { uint8_t id, x, y, width, height, mark; } SolvedCell;
typedef struct { uint8_t kind, arg, phase; } EffectRecord;
typedef struct {
  CellFrame *cells; size_t cell_count;
  TaskFrame *task;
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

local src = assert(io.open("demo/orp_grid.lln", "rb")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/orp_grid.lln", {
    env = { GridOp = GridOp, GridId = GridId, EffectKind = EffectKind, GridCtl = GridCtl },
}))
local session, source = lalin.compile_c_gcc("lalin_orp_grid_gcc", decls, {
    gcc_opts = { opt = 3, out_dir = "target/test_lalin_orp_grid_gcc" },
})

local called = {
    "InputRecord_decode",
    "CellFrame_set_char", "CellFrame_activate", "CellFrame_blur", "TaskFrame_step",
    "CellFrame_view", "TaskFrame_view",
    "GridStore_enqueue", "GridStore_solve", "GridStore_raster",
}
for _, name in ipairs(called) do
    assert(source:match("__lalin_region_result_" .. name), "sealed object-machine result for " .. name)
    assert(source:match("= " .. name .. "%(") ~= nil, "pump invokes sealed object-machine " .. name)
end

local grid_step = assert(session:symbol("grid_step", "int32_t (*)(InputRecord*, size_t, GridStore*)"))
local grid_reset = assert(session:symbol("grid_reset", "void (*)(GridStore*)"))

local function fixture(task_ticks, decl_cap)
    local f = {
        cells = ffi.new("CellFrame[2]"),
        task = ffi.new("TaskFrame", { ticks = task_ticks or 2, done = 0 }),
        decls = ffi.new("ViewDecl[8]"),
        solved = ffi.new("SolvedCell[8]"),
        effects = ffi.new("EffectRecord[8]"),
        screen = ffi.new("uint8_t[31]"),
    }
    f.store = ffi.new("GridStore", {
        cells = f.cells, cell_count = 2, task = f.task,
        decls = f.decls, decl_cap = decl_cap or 8, decl_count = 0,
        solved = f.solved, solve_cap = 8, solve_count = 0,
        effects = f.effects, effect_cap = 8, effect_count = 0,
        screen = f.screen, screen_cap = 31, screen_len = 0,
        cursor_row = 0, cursor_col = 0, epoch = 0, task_result = 0,
    })
    return f
end

local function event_array(rows)
    local a = ffi.new("InputRecord[?]", #rows)
    for i, row in ipairs(rows) do a[i - 1] = row end
    return a
end

local expected_initial = "[ ] [ ]   [o]       " .. string.rep(" ", 10)
local expected_x = "[x] [ ]   [o]       " .. string.rep(" ", 10)
local expected_active = "#x# [ ]   [o]       " .. string.rep(" ", 10)
local expected_done = "[ ] [ ]   [D]       " .. string.rep(" ", 10)

-- Full cycle: decode -> route -> sealed transitions -> readonly projection ->
-- solve -> raster, with immediate physical effects.
do
    local f = fixture()
    local events = event_array {
        { target = 0, op = GridOp.KEY, arg = string.byte("x") },
        { target = 0, op = GridOp.ENTER, arg = 0 },
        { target = 0, op = GridOp.TAB, arg = 0 },
    }
    assert(grid_step(events, 3, f.store) == 2)
    assert(f.cells[0].content == string.byte("x") and f.cells[0].focused == 0 and f.cells[0].active == 0)
    assert(f.cells[0].epoch == 1 and f.store.epoch == 3, "frame and root generations reflect transitions")
    assert(f.store.cursor_row == 0 and f.store.cursor_col == 1)
    assert(f.effects[0].kind == EffectKind.CURSOR and f.effects[0].arg == 0 and f.effects[0].phase == 0)
    assert(f.effects[1].kind == EffectKind.BEEP and f.effects[1].phase == 0)
    assert(f.store.decl_count == 3 and f.store.solve_count == 3)
    assert(f.decls[0].id == 0 and f.decls[0].row == 0 and f.decls[0].width == 4)
    assert(f.decls[2].id == 2 and f.decls[2].row == 1 and f.decls[2].width == 0)
    assert(f.solved[0].x == 0 and f.solved[0].width == 4)
    assert(f.solved[1].x == 4 and f.solved[1].width == 4)
    assert(f.solved[2].x == 0 and f.solved[2].y == 1 and f.solved[2].width == 10)
    assert(ffi.string(f.screen) == expected_x, "terminal raster mismatch: " .. ffi.string(f.screen))
end

-- The second activation changes persistent state; projection mark controls the
-- physical border. This proves the view reads the frame without owning it.
do
    local f = fixture()
    local events = event_array {
        { target = 0, op = GridOp.KEY, arg = string.byte("x") },
        { target = 0, op = GridOp.ENTER, arg = 0 },
        { target = 0, op = GridOp.ENTER, arg = 0 },
        { target = 0, op = GridOp.TAB, arg = 0 },
    }
    assert(grid_step(events, 4, f.store) == 3)
    assert(f.cells[0].active == 1 and f.cells[0].focused == 0)
    assert(f.decls[0].mark == 2)
    assert(ffi.string(f.screen) == expected_active)
end

-- A delayed machine outcome survives across pump calls. Completion emits a
-- phase-1 host effect and changes the later projection world.
do
    local f = fixture(2)
    local tick = event_array { { target = GridId.TASK, op = GridOp.TICK, arg = 0 } }
    assert(grid_step(tick, 1, f.store) == 0)
    assert(f.task.ticks == 1 and f.task.done == 0 and f.store.task_result == 0)
    assert(ffi.string(f.screen) == expected_initial)
    assert(grid_step(tick, 1, f.store) == 1)
    assert(f.task.done == 1 and f.store.task_result == 1)
    assert(f.effects[0].kind == EffectKind.SAVE and f.effects[0].phase == 1)
    assert(ffi.string(f.screen) == expected_done)
end

-- Unknown physical data is owned by the decoder and becomes one explicit
-- diagnostic effect; no semantic frame sees the opcode.
do
    local f = fixture()
    local bad = event_array { { target = 99, op = 255, arg = 0 } }
    assert(grid_step(bad, 1, f.store) == 1)
    assert(f.effects[0].kind == EffectKind.ERROR and f.effects[0].arg == 255)
    assert(f.store.epoch == 0 and f.cells[0].epoch == 0)
    assert(ffi.string(f.screen) == expected_initial)
end

-- Capacity failure is a continuation outcome, not truncation or nil.
do
    local f = fixture(2, 1)
    assert(grid_step(event_array {}, 0, f.store) == 1)
    assert(f.effects[0].kind == EffectKind.ERROR and f.effects[0].arg == 1)
end

-- Reset is an object-owned method exposed through a plain ABI wrapper.
do
    local f = fixture()
    f.store.epoch = 9
    f.store.decl_count = 7
    grid_reset(f.store)
    assert(f.store.epoch == 0 and f.store.decl_count == 0 and f.store.effect_count == 0)
end

-- Determinism: equal frames and physical input produce equal projected output.
do
    local events = event_array { { target = 0, op = GridOp.KEY, arg = string.byte("x") } }
    local a, b = fixture(), fixture()
    assert(grid_step(events, 1, a.store) == grid_step(events, 1, b.store))
    assert(ffi.string(a.screen) == ffi.string(b.screen))
    assert(a.store.epoch == b.store.epoch and a.effects[0].kind == b.effects[0].kind)
end

session:free()
io.write("Object-Region-Projection grid GCC ok: controllers=4 projections=3 effects+pump+layout\n")
