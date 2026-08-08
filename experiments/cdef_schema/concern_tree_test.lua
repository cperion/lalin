package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Tree = require("experiments.cdef_schema.concern_tree")

local app = Tree.App()
assert(app:initialize(0, 100, 9, 100) == app)

assert(ffi.sizeof(app) == ffi.sizeof("ConcernTreeV1_App"))
assert(ffi.offsetof("ConcernTreeV1_App", "input") == 0)
assert(ffi.offsetof("ConcernTreeV1_App", "model") > 0)
assert(app.model.value == 9)
assert(app.layout.model_revision == app.model.revision)
assert(app.paint.layout_revision == app.layout.revision)
assert(app.paint.command_count == 2)
assert(app.paint.commands[0].opcode == Tree.PAINT_CLEAR)
assert(app.paint.commands[1].opcode == Tree.PAINT_VALUE)
assert(app.paint.commands[1].value == 9)
assert(tonumber(app.commits) == 0)

assert(app:increment() == 10)
assert(app.model.value == 10)
assert(app.model.revision == 2)
assert(app.layout.model_revision == 2)
assert(app.paint.commands[1].value == 10)
assert(app.layout.text_width == 16)
assert(app.layout.text_x == 42)
assert(tonumber(app.commits) == 1)

local layout_revision = app.layout.revision
local paint_revision = app.paint.revision
assert(app:resize(100) == 10)
assert(app.layout.revision == layout_revision)
assert(app.paint.revision == paint_revision)
assert(tonumber(app.ignored) == 1)

assert(app:resize(120) == 10)
assert(app.layout.viewport_width == 120)
assert(app.layout.text_x == 52)
assert(app.paint.commands[0].value == 120)
assert(app.paint.commands[1].x == 52)
assert(tonumber(app.commits) == 2)

assert(app:decrement() == 9)
assert(app.layout.text_width == 8)
assert(app.layout.text_x == 56)
assert(tonumber(app.commits) == 3)

local oracle = 9
local expected_commits = 3
local expected_ignored = 1
for index = 1, 100000 do
    if index % 3 == 0 then
        local width = 80 + index % 17
        if width == app.layout.viewport_width then expected_ignored = expected_ignored + 1
        else expected_commits = expected_commits + 1 end
        assert(app:resize(width) == oracle)
    elseif index % 2 == 0 then
        local next_value = oracle + 1
        if next_value <= 100 then oracle = next_value; expected_commits = expected_commits + 1
        else expected_ignored = expected_ignored + 1 end
        assert(app:increment() == oracle)
    else
        local next_value = oracle - 1
        if next_value >= 0 then oracle = next_value; expected_commits = expected_commits + 1
        else expected_ignored = expected_ignored + 1 end
        assert(app:decrement() == oracle)
    end
    assert(app.paint.commands[1].value == app.model.value)
    assert(app.paint.layout_revision == app.layout.revision)
end

assert(tonumber(app.commits) == expected_commits)
assert(tonumber(app.ignored) == expected_ignored)
assert(tonumber(app.epoch) == 100004)
assert(tonumber(app.input.increment_events + app.input.decrement_events) == 66669)

local bounded = Tree.App()
bounded:initialize(5, 5, 5, 80)
assert(bounded:increment() == 5)
assert(bounded:decrement() == 5)
assert(tonumber(bounded.commits) == 0)
assert(tonumber(bounded.ignored) == 2)

print("composed CDEF concern machine tree: ok")

