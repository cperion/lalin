package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Backend = require("ui.backends.love")
local Machine = Backend.Machine
assert(Backend.capabilities.host.events == "bounded-cps-driver-drain")

local function fake_owner()
    local self = {
        contents = { [10] = "ready", [20] = "edited status" },
        measured = 0,
        begun = 0,
        uploaded = 0,
        geometry = 0,
        text = 0,
        images = 0,
        clip_pushes = 0,
        clip_pops = 0,
        layer_pushes = 0,
        layer_pops = 0,
        ended = 0,
    }
    for handle = 100, 140 do self.contents[handle] = "resource " .. handle end

    function self:measure_text(content, _font, font_size, wrap_width)
        local value = assert(self.contents[tonumber(content)], "unknown content handle")
        self.measured = self.measured + 1
        local width = math.min(#value * font_size * 0.5, wrap_width)
        return width, font_size, font_size * 0.8, font_size, 1
    end

    function self:begin_frame(host, projection)
        assert(host.logical_width > 0)
        assert(projection.segment_count > 0)
        self.begun = self.begun + 1
    end

    function self:upload_geometry(projection)
        assert(projection.vertex_count > 0)
        assert(projection.index_count > 0)
        self.uploaded = self.uploaded + 1
    end

    function self:draw_geometry(projection, batch)
        assert(batch.first_vertex + batch.vertex_count <= projection.vertex_count)
        assert(batch.first_index + batch.index_count <= projection.index_count)
        self.geometry = self.geometry + 1
    end

    function self:draw_text(draw)
        assert(self.contents[tonumber(draw.content)])
        self.text = self.text + 1
    end

    function self:draw_image(_draw) self.images = self.images + 1 end
    function self:push_clip(_clip) self.clip_pushes = self.clip_pushes + 1 end
    function self:pop_clip() self.clip_pops = self.clip_pops + 1 end
    function self:push_layer(_layer) self.layer_pushes = self.layer_pushes + 1 end
    function self:pop_layer() self.layer_pops = self.layer_pops + 1 end
    function self:end_frame() self.ended = self.ended + 1 end
    function self:append_content(handle, suffix)
        local next_handle = 30 + self.text
        self.contents[next_handle] = assert(self.contents[tonumber(handle)]) .. suffix
        return next_handle
    end

    return self
end

local owner = fake_owner()
local app = Machine.Application()
assert(app:initialize(owner, 800, 600, 800, 600, 1, 10) == app)

assert(ffi.sizeof(app) == 1801080)
assert(app.text_measure.count == 1)
assert(app.layout.box_count == 192)
assert(app.paint.frame.vertex_count == 768)
assert(app.paint.frame.index_count == 1152)
assert(app.paint.frame.geometry_batch_count == 2)
assert(app.paint.frame.text_draw_count == 26)
assert(app.paint.frame.image_draw_count == Machine.CARD_COUNT)
assert(app.paint.frame.clip_count == 1 and app.paint.frame.layer_count == 1)
assert(app.paint.frame.segment_count == 44)
assert(owner.measured == 1)

assert(app:tick(owner, 1.0, 1 / 60) == true)
assert(app:draw(owner) == true)
assert(owner.begun == 1)
assert(owner.uploaded == 1)
assert(owner.geometry == 2)
assert(owner.images == Machine.CARD_COUNT)
assert(owner.clip_pushes == 1 and owner.clip_pops == 1)
assert(owner.layer_pushes == 1 and owner.layer_pops == 1)
assert(owner.text == 26)
assert(owner.ended == 1)
assert(app.host.present_count == 0)
assert(app.renderer.rendered_revision == app.paint.frame.revision)
assert(app.host.redraw_requested == 1)
app.host:presented()
assert(app.host.present_count == 1)
assert(app:draw(owner) == false)

-- Hover changes only the visual projection.
local paint_revision = app.paint.frame.revision
assert(app:pointer_moved(owner, 300, 200, 300, 200) == true)
assert(tonumber(app.interaction.hover) == Machine.CARD_BASE)
assert(app.paint.frame.revision == paint_revision + 1)
assert(app.layout.solve_count == 1)

-- Workspace wheel changes the model and then only repainting.
local model_revision = app.model.revision
assert(app:wheel_moved(owner, 0, 1) == true)
assert(app.model.workspace.zoom == 1.1)
assert(app.model.revision == model_revision + 1)
assert(app.layout.solve_count == 1)

-- Toolbar activation is owned by the toolbar subapplication.
assert(app:pointer_moved(owner, 430, 20, 130, -180) == true)
assert(app:pointer_pressed(owner, 1) == true)
assert(app:pointer_released(owner, 1) == true)
assert(app.model.toolbar.active_tool == 3)
assert(app.input.button_mask == 0)
assert(tonumber(app.interaction.pressed) == Machine.NODE_NONE)

-- Text invalidation crosses text measurement, layout, and paint concerns.
local measures = owner.measured
local solves = app.layout.solve_count
assert(app:text_entered(owner, 20) == true)
assert(owner.measured == measures + 1)
assert(app.layout.solve_count == solves + 1)
assert(tonumber(app.model.status.content) == 20)
local status_draw = app.paint.frame.text_draws[app.paint.frame.text_draw_count - 1]
assert(tonumber(status_draw.content) == 20)

-- Resize changes layout; an identical resize takes the named unchanged exit.
solves = app.layout.solve_count
assert(app:resize(owner, 1024, 768, 2048, 1536, 2) == true)
assert(app.layout.solve_count == solves + 1)
assert(app.host.dpi_scale == 2)
assert(app:resize(owner, 1024, 768, 2048, 1536, 2) == false)

-- Visibility and external window damage have explicit redraw entries.
assert(app:set_visible(owner, false) == false)
assert(app.host.visible == 0)
assert(app:set_visible(owner, true) == true)
assert(app.host.visible == 1 and app.host.redraw_requested == 1)
assert(app:invalidate(owner) == true)

-- Drag is a durable tagged C union, not optional fields.
assert(app:pointer_moved(owner, 200, 200, -300, 180) == true)
assert(app:pointer_pressed(owner, 1) == true)
assert(app.interaction.drag.kind == ffi.C.LoveUiV1_DragPendingKind)
assert(app:pointer_moved(owner, 220, 220, 20, 20) == true)
assert(app.interaction.drag.kind == ffi.C.LoveUiV1_DraggingKind)
assert(app:pointer_released(owner, 1) == true)
assert(app.interaction.drag.kind == ffi.C.LoveUiV1_DragIdleKind)

-- The renderer owns all segment concern transitions, including balanced stacks.
local clips_before = owner.clip_pushes
local layers_before = owner.layer_pushes
local images_before = owner.images
local layered = Machine.Application()
assert(layered:initialize(owner, 320, 240, 320, 240, 1, 10) == layered)
local frame = layered.paint.frame
frame.clip_count = 1
frame.clips[0].rect.x = 0
frame.clips[0].rect.y = 0
frame.clips[0].rect.width = 320
frame.clips[0].rect.height = 240
frame.layer_count = 1
frame.layers[0].canvas = 77
frame.image_draw_count = 1
frame.image_draws[0].image = 88
frame.segment_count = 7
frame.segments[0].kind, frame.segments[0].item_index = Machine.SEGMENT_CLIP_PUSH, 0
frame.segments[1].kind, frame.segments[1].item_index = Machine.SEGMENT_GEOMETRY, 0
frame.segments[2].kind, frame.segments[2].item_index = Machine.SEGMENT_LAYER_PUSH, 0
frame.segments[3].kind, frame.segments[3].item_index = Machine.SEGMENT_IMAGE, 0
frame.segments[4].kind, frame.segments[4].item_index = Machine.SEGMENT_TEXT, 0
frame.segments[5].kind, frame.segments[5].item_index = Machine.SEGMENT_LAYER_POP, 0
frame.segments[6].kind, frame.segments[6].item_index = Machine.SEGMENT_CLIP_POP, 0
frame.revision = frame.revision + 1
layered.host.redraw_requested = 1

assert(layered:draw(owner) == true)
assert(layered.renderer.clip.depth == 0)
assert(layered.renderer.layer.depth == 0)
assert(owner.clip_pushes == clips_before + 1 and owner.clip_pops == clips_before + 1)
assert(owner.layer_pushes == layers_before + 1 and owner.layer_pops == layers_before + 1)
assert(owner.images == images_before + 1)

-- The physical driver owns the application and one complete host turn is a
-- stable CPS graph over event drain, window sample, time sample, render/idle,
-- presentation, and completion.
local driver = Machine.Driver()
assert(driver:initialize(owner, 640, 480, 640, 480, 1, 10, 0, true) == driver)
local boundary = {
    width = 640, height = 480, pixel_width = 640, pixel_height = 480,
    now = 0, metric_now = 10, heap = 1000, presents = 0, sleeps = 0, reports = 0,
    inject_text = false, quit = false,
}
function boundary:drain_events(active, resource_owner, drained, quitting)
    if self.quit then return quitting(active, resource_owner, self, 7, 1, 0, 0.0002) end
    if self.inject_text then
        self.inject_text = false
        active:text_entered(resource_owner, "!")
        return drained(active, resource_owner, self, 1, 0, 0.0002)
    end
    return drained(active, resource_owner, self, 0, 0, 0.0002)
end
function boundary:sample_window(active, resource_owner, sampled)
    return sampled(active, resource_owner, self, self.width, self.height,
        self.pixel_width, self.pixel_height, 1, true, true, 0.0003)
end
function boundary:sample_time(active, resource_owner, sampled)
    self.now = self.now + 1 / 60
    return sampled(active, resource_owner, self, self.now, 1 / 60)
end
function boundary:clock()
    self.metric_now = self.metric_now + 0.0001
    return self.metric_now
end
function boundary:metric_snapshot(_active, resource_owner)
    self.metric_now = self.metric_now + 0.3
    self.heap = self.heap + 0.25
    return self.metric_now, self.heap, resource_owner.uploaded,
        resource_owner.geometry + resource_owner.text + resource_owner.images, 1, 1
end
function boundary:report_metrics() self.reports = self.reports + 1 end
function boundary:graphics_active() return true end
function boundary:present() self.presents = self.presents + 1 end
function boundary:sleep() self.sleeps = self.sleeps + 1 end
function boundary:on_quit() self.closed = true end

assert(driver:turn(owner, boundary) == driver)
assert(driver.render_turn_count == 1 and boundary.presents == 1)
assert(driver.application.host.present_count == 1)
assert(driver:turn(owner, boundary) == driver)
assert(driver.idle_turn_count == 1 and boundary.presents == 1)
boundary.inject_text = true
assert(driver:turn(owner, boundary) == driver)
assert(driver.render_turn_count == 2 and driver.drained_event_count == 1)
boundary.width, boundary.pixel_width = 900, 900
assert(driver:turn(owner, boundary) == driver)
assert(driver.application.host.logical_width == 900)
assert(driver.render_turn_count == 3 and boundary.presents == 3)
boundary.quit = true
assert(driver:turn(owner, boundary) == driver)
assert(driver.running == 0 and driver.exit_code == 7)
assert(driver.quit_turn_count == 1 and driver.drained_event_count == 2)
assert(boundary.closed == true and boundary.sleeps == 4)
assert(driver.metrics.enabled == 1 and driver.metrics.measured_turns == 5)
assert(driver.metrics.last_drain_seconds == 0.0002)
assert(driver.metrics.last_window_seconds == 0)
assert(driver.metrics.max_window_seconds == 0.0003)
assert(driver.metrics.max_render_seconds > 0 and driver.metrics.max_present_seconds > 0)
assert(driver.metrics.max_turn_seconds > 0 and driver.metrics.max_heap_growth_kb == 0.25)
assert(driver.metrics.upload_count == owner.uploaded)
assert(driver.metrics.draw_count == owner.geometry + owner.text + owner.images)
assert(boundary.reports > 0)

-- Sealing is final: neither fields nor methods can be added now.
local method_ok, method_error = pcall(function()
    Machine.Application.late_method = function() end
end)
assert(not method_ok)
assert(tostring(method_error):find("not allowed after sealing", 1, true))
local hidden_ok = pcall(function() app._owner = owner end)
assert(not hidden_ok)

print("ok test_ui_love_cps_machine")

