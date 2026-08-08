package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local State = require("ui.backends.love.state")

local function count(array_ctype, item_ctype)
    return ffi.sizeof(array_ctype) / ffi.sizeof(item_ctype)
end

-- Physical review happens before any behavior or metatype is installed.
local construct_ok, construct_error = pcall(State.Application)
assert(not construct_ok)
assert(tostring(construct_error):find("construction requires sealed context", 1, true))
local driver_construct_ok = pcall(State.Driver)
assert(not driver_construct_ok)

local app_ctype = ffi.typeof("LoveUiV1_Application")
local driver_ctype = ffi.typeof("LoveUiV1_Driver")
local app = ffi.new(app_ctype)
local other = ffi.new(app_ctype)
local driver = ffi.new(driver_ctype)

local method_ok = pcall(function() return app.initialize end)
assert(not method_ok)
assert(ffi.offsetof(app_ctype, "host") == 0)
assert(ffi.offsetof(app_ctype, "input") > ffi.offsetof(app_ctype, "host"))
assert(ffi.offsetof(app_ctype, "interaction") > ffi.offsetof(app_ctype, "input"))
assert(ffi.offsetof(app_ctype, "model") > ffi.offsetof(app_ctype, "interaction"))
assert(ffi.offsetof(app_ctype, "text_measure") > ffi.offsetof(app_ctype, "model"))
assert(ffi.offsetof(app_ctype, "layout") > ffi.offsetof(app_ctype, "text_measure"))
assert(ffi.offsetof(app_ctype, "paint") > ffi.offsetof(app_ctype, "layout"))
assert(ffi.offsetof(app_ctype, "renderer") > ffi.offsetof(app_ctype, "paint"))
assert(ffi.offsetof(driver_ctype, "application") == 0)
assert(ffi.offsetof(driver_ctype, "metrics") >= ffi.sizeof(app_ctype))
assert(ffi.offsetof(driver_ctype, "turn_count") > ffi.offsetof(driver_ctype, "metrics"))

app.host.logical_width = 1280
app.input.pointer_x = 42.5
app.model.toolbar.active_tool = 3
app.model.workspace.zoom = 2.0
app.model.status.content = 91
app.text_measure.items[0].node = 7
app.layout.boxes[0].node = 7
app.paint.frame.vertices[0].x = 12.5
app.paint.frame.text_draws[0].content = 91
app.renderer.geometry.mesh = 4

assert(other.host.logical_width == 0)
assert(other.model.toolbar.active_tool == 0)
assert(other.paint.frame.vertices[0].x == 0)
assert(app.host.logical_width == 1280)
assert(app.input.pointer_x == 42.5)
assert(app.model.toolbar.active_tool == 3)
assert(app.model.workspace.zoom == 2.0)
assert(tonumber(app.model.status.content) == 91)
assert(tonumber(app.paint.frame.text_draws[0].content) == 91)

local frame = app.paint.frame
assert(count(ffi.typeof(frame.vertices), "LoveUiV1_Vertex") == State.capacities.vertices)
assert(count(ffi.typeof(frame.indices), "uint32_t") == State.capacities.indices)
assert(count(ffi.typeof(frame.geometry_batches), "LoveUiV1_GeometryBatch") ==
    State.capacities.geometry_batches)
assert(count(ffi.typeof(frame.text_draws), "LoveUiV1_TextDraw") ==
    State.capacities.text_draws)
assert(count(ffi.typeof(frame.image_draws), "LoveUiV1_ImageDraw") ==
    State.capacities.image_draws)
assert(count(ffi.typeof(frame.clips), "LoveUiV1_Clip") == State.capacities.clips)
assert(count(ffi.typeof(frame.layers), "LoveUiV1_Layer") == State.capacities.layers)
assert(count(ffi.typeof(frame.segments), "LoveUiV1_Segment") == State.capacities.segments)
assert(count(ffi.typeof(app.text_measure.items), "LoveUiV1_TextMetric") ==
    State.capacities.text_metrics)
assert(count(ffi.typeof(app.layout.boxes), "LoveUiV1_LayoutBox") ==
    State.capacities.layout_boxes)
assert(count(ffi.typeof(app.renderer.clip.stack), "LoveUiV1_Rect") ==
    State.capacities.clip_depth)
assert(count(ffi.typeof(app.renderer.layer.stack), "LoveUiV1_ResourceHandle") ==
    State.capacities.layer_depth)

app.interaction.drag.kind = ffi.C.LoveUiV1_DragPendingKind
app.interaction.drag.payload.pending.source = 123
app.interaction.drag.payload.pending.press_x = 10
app.interaction.drag.payload.pending.press_y = 20
app.interaction.drag.payload.pending.threshold_squared = 36
assert(app.interaction.drag.kind == ffi.C.LoveUiV1_DragPendingKind)
assert(State.DragPayload:is(app.interaction.drag.payload))
assert(State.Drag:is(app.interaction.drag.payload.pending))
assert(not State.Drag:is(app.interaction.drag))
assert(tonumber(app.interaction.drag.payload.pending.source) == 123)
assert(app.interaction.drag.payload.pending.threshold_squared == 36)

assert(ffi.sizeof("LoveUiV1_Vertex") == 24)
assert(ffi.sizeof("LoveUiV1_Segment") == 8)
assert(ffi.sizeof("LoveUiV1_Rect") == 16)
assert(ffi.sizeof(app) < 2 * 1024 * 1024)
assert(ffi.sizeof("LoveUiV1_DriverMetrics") == 304)
assert(ffi.sizeof(driver) == 1801448)

print(("ok test_ui_love_cdef_state app_bytes=%d driver_bytes=%d frame_bytes=%d"):format(
    ffi.sizeof(app), ffi.sizeof(driver), ffi.sizeof("LoveUiV1_FrameProjection")))

