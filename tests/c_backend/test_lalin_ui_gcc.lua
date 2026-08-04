package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Lalin UI demo through the real GCC pipeline.
--
-- Evidence goal: a UI driven purely by region machines and continuations.
-- demo/ui.lln defines widget machines (Toggle, Field, Dialog) as regions,
-- a pump (ui_step) that routes input events by identity and resumes each
-- machine through a sealed `call` whose continuation carries the dispatch
-- loop index, and a readonly draw pass (Render.screen) that renders the
-- frames into a caller-owned buffer.
--
-- The proof is headless: scripted InputEvents are fed to ui_step, and the
-- returned status + screen buffer must match the machine semantics exactly:
--   scenario 1  toggle flips, field focuses, keys append, TAB blurs, then
--               the blurred field ignores a key.
--   scenario 2  dialog opens, stays open on a non-OK click, then OK resumes
--               the done wire and the message flag is set.

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
    assert(why.skip == true)
    io.write("lalin ui machine GCC skipped\n")
    os.exit(0)
end

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
local session, source = lalin.compile_c_gcc("lalin_ui_gcc", decls, {
    gcc_opts = { opt = 3, out_dir = "target/test_lalin_ui_gcc" },
})

-- Sealed frame boundaries: each widget machine must materialize as a callable
-- returning its generated continuation-result union, and the pump must
-- dispatch those results (never inline the widgets).
local sealed = 0
for _, name in ipairs({ "Toggle_run", "Field_run", "Dialog_step", "Render_screen" }) do
    assert(source:match("__lalin_region_result_" .. name) ~= nil, "sealed result union for " .. name .. " must be emitted")
    assert(source:match("= " .. name .. "%(") ~= nil, "pump must invoke the sealed callable " .. name)
    sealed = sealed + 1
end
assert(sealed == 4, "all four machines must be sealed call boundaries")

local ui_step = assert(session:symbol(
    "ui_step",
    "int32_t (*)(InputEvent*, size_t, ToggleFrame*, FieldFrame*, DialogFrame*, UiStatus*, uint8_t*, size_t)"))

local function fresh_frames()
    return {
        toggle = ffi.new("ToggleFrame", { active = 0 }),
        field = ffi.new("FieldFrame", { focused = 0, len = 0, buf = ffi.new("uint8_t[16]") }),
        dialog = ffi.new("DialogFrame", { active = 0 }),
        status = ffi.new("UiStatus"),
        screen = ffi.new("uint8_t[64]"),
    }
end

-- Scenario 1: toggle flips; field focus + typing; TAB focus ring blurs; the
-- blurred field ignores the final key.
do
    local f = fresh_frames()
    local ev = ffi.new("InputEvent[6]")
    ev[0] = { target = UIId.TOGGLE, kind = UIKind.CLICK, key = 0 }   -- toggle on
    ev[1] = { target = UIId.FIELD, kind = UIKind.CLICK, key = 0 }    -- focus field
    ev[2] = { target = UIId.FIELD, kind = UIKind.KEY, key = 97 }     -- 'a'
    ev[3] = { target = UIId.FIELD, kind = UIKind.KEY, key = 98 }     -- 'b'
    ev[4] = { target = 0, kind = UIKind.TAB, key = 0 }               -- focus ring: blur
    ev[5] = { target = UIId.FIELD, kind = UIKind.KEY, key = 99 }     -- 'c' ignored (blurred)
    assert(ui_step(ev, 6, f.toggle, f.field, f.dialog, f.status, f.screen, 64) == 0)
    assert(f.status.toggle_on == 1, "toggle must be on after click")
    assert(f.status.field_len == 2, "field must hold exactly 'ab'")
    assert(f.status.field_first == 97, "field must start with 'a'")
    assert(f.status.focus == 0, "TAB must blur the field (focus ring)")
    assert(ffi.string(f.screen) == "T=1F=0:abD=0M=0",
        "screen render mismatch: " .. tostring(ffi.string(f.screen)))
end

-- Scenario 2: dialog opens, stays open on a non-OK click (stay wire), then
-- OK resumes the done wire: active clears and the message flag is set.
do
    local f = fresh_frames()
    local ev = ffi.new("InputEvent[3]")
    ev[0] = { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 }     -- open dialog
    ev[1] = { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 }     -- stays open (not OK)
    ev[2] = { target = UIId.OK, kind = UIKind.CLICK, key = 0 }       -- OK -> done wire
    assert(ui_step(ev, 3, f.toggle, f.field, f.dialog, f.status, f.screen, 64) == 0)
    assert(f.status.dialog_open == 0, "dialog must close after OK")
    assert(f.status.message == 1, "done wire must set the message flag")
    assert(ffi.string(f.screen) == "T=0F=0:D=0M=1",
        "screen render mismatch: " .. tostring(ffi.string(f.screen)))
end

-- Scenario 3: interleaved machines in one batch (parallel composition):
-- dialog opens, toggle flips, dialog stays open, OK closes it.
do
    local f = fresh_frames()
    local ev = ffi.new("InputEvent[4]")
    ev[0] = { target = UIId.OPEN, kind = UIKind.CLICK, key = 0 }
    ev[1] = { target = UIId.TOGGLE, kind = UIKind.CLICK, key = 0 }
    ev[2] = { target = UIId.OK, kind = UIKind.CLICK, key = 0 }
    ev[3] = { target = UIId.TOGGLE, kind = UIKind.CLICK, key = 0 }   -- flips back off
    assert(ui_step(ev, 4, f.toggle, f.field, f.dialog, f.status, f.screen, 64) == 0)
    assert(f.status.toggle_on == 0 and f.status.message == 1 and f.status.dialog_open == 0,
        "interleaved machines must compose in one batch")
    assert(ffi.string(f.screen) == "T=0F=0:D=0M=1",
        "screen render mismatch: " .. tostring(ffi.string(f.screen)))
end

session:free()
io.write("lalin ui machine GCC ok: sealed=" .. sealed .. " toggle/field/dialog/pump wired\n")
