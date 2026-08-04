-- demo/ui/run.lua
--
-- Drive demo/ui.lln through the lalin binary:
--   make lalin-bin
--   target/lalin demo/ui/run.lua
--
-- Compiles the self-documented UI machine demo (demo/ui.lln) through the
-- GCC pipeline, feeds scripted input events into the pump, and prints the
-- rendered screen after each scenario.  The pump (ui_step) is a region
-- machine: Toggle/Field/Dialog are sealed region calls wired by
-- continuations, Render.screen is the readonly draw pass.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local ffi = require("ffi")

ffi.cdef[[
typedef struct { int32_t target; uint8_t kind; uint8_t key; } InputEvent;
typedef struct { uint8_t active; } ToggleFrame;
typedef struct { uint8_t focused; int32_t len; uint8_t *buf; } FieldFrame;
typedef struct { uint8_t active; } DialogFrame;
typedef struct { uint8_t toggle_on; int32_t field_len; uint8_t field_first;
                 uint8_t dialog_open; uint8_t message; int32_t focus; } UiStatus;
]]

local UIId = { TOGGLE = 1, FIELD = 2, OPEN = 3, OK = 4 }
local UIKind = { CLICK = 1, KEY = 2, TAB = 3 }
local UI = { FIELD_CAP = 16 }

local src = assert(io.open("demo/ui.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/ui.lln", { env = { UIId = UIId, UIKind = UIKind, UI = UI } }))
local session = lalin.compile_c_gcc("lalin_ui_demo", decls, {
    gcc_opts = { opt = 3, out_dir = "target/demo/ui" },
})
local ui_step = assert(session:symbol(
    "ui_step",
    "int32_t (*)(InputEvent*, size_t, ToggleFrame*, FieldFrame*, DialogFrame*, UiStatus*, uint8_t*, size_t)"))

local function frames()
    return {
        toggle = ffi.new("ToggleFrame", { active = 0 }),
        field = ffi.new("FieldFrame", { focused = 0, len = 0, buf = ffi.new("uint8_t[16]") }),
        dialog = ffi.new("DialogFrame", { active = 0 }),
        status = ffi.new("UiStatus"),
        screen = ffi.new("uint8_t[64]"),
    }
end

local function run(label, events)
    local f = frames()
    local ev = ffi.new("InputEvent[" .. #events .. "]")
    for i, e in ipairs(events) do ev[i - 1] = e end
    assert(ui_step(ev, #events, f.toggle, f.field, f.dialog, f.status, f.screen, 64) == 0)
    print(string.format("%-24s screen: %s", label, ffi.string(f.screen)))
    return f
end

run("toggle flip", {
    { target = UIId.TOGGLE, kind = UIKind.CLICK, key = 0 },
})

run("field focus + typing", {
    { target = UIId.FIELD, kind = UIKind.CLICK, key = 0 },
    { target = UIId.FIELD, kind = UIKind.KEY, key = 104 }, -- 'h'
    { target = UIId.FIELD, kind = UIKind.KEY, key = 105 }, -- 'i'
    { target = UIId.FIELD, kind = UIKind.KEY, key = 33 },  -- '!'
})

run("focus ring: TAB blurs", {
    { target = UIId.FIELD, kind = UIKind.CLICK, key = 0 },
    { target = UIId.FIELD, kind = UIKind.KEY, key = 97 }, -- 'a'
    { target = 0, kind = UIKind.TAB, key = 0 },
    { target = UIId.FIELD, kind = UIKind.KEY, key = 98 }, -- 'b' ignored (blurred)
})

run("dialog: open, stay, OK", {
    { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 },
    { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 }, -- stays open (not OK)
    { target = UIId.OK, kind = UIKind.CLICK, key = 0 },    -- done wire -> message
})

run("interleaved batch", {
    { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 },
    { target = UIId.TOGGLE, kind = UIKind.CLICK, key = 0 },
    { target = UIId.OK, kind = UIKind.CLICK, key = 0 },
})

session:free()
io.write("ui demo ok\n")
