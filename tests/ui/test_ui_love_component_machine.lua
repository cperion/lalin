package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Machine = require("ui.backends.love.components").State

local function fake_owner()
    local self = {
        contents = { [10] = "ready", [20] = "edited" },
        begun = 0, uploaded = 0, geometry = 0, text = 0, images = 0, ended = 0,
        clip_pushes = 0, clip_pops = 0,
        uploads = 0, draw_calls = 0, mesh_rebuilds = 0, text_rebuilds = 0,
    }
    for handle = 100, 140 do self.contents[handle] = "resource " .. handle end
    function self:append_content(handle, suffix)
        self.contents[20] = assert(self.contents[tonumber(handle)]) .. suffix
        return 20
    end
    function self:begin_frame(host, frame)
        assert(host.logical_width > 0 and frame.geometry_batch_count == 2)
        self.begun = self.begun + 1
    end
    function self:upload_geometry(frame)
        assert(frame.vertex_count > 0 and frame.index_count > 0)
        self.uploaded = self.uploaded + 1
        self.uploads = self.uploads + 1
    end
    function self:draw_geometry() self.geometry = self.geometry + 1; self.draw_calls = self.draw_calls + 1 end
    function self:draw_text(draw)
        assert(self.contents[tonumber(draw.content)])
        self.text = self.text + 1
        self.draw_calls = self.draw_calls + 1
    end
    function self:draw_image() self.images = self.images + 1; self.draw_calls = self.draw_calls + 1 end
    function self:push_clip() self.clip_pushes = self.clip_pushes + 1 end
    function self:pop_clip() self.clip_pops = self.clip_pops + 1 end
    function self:push_layer() error("unexpected layer") end
    function self:pop_layer() error("unexpected layer") end
    function self:end_frame() self.ended = self.ended + 1 end
    return self
end

local owner = fake_owner()
local app = Machine.Application()
assert(app:initialize(owner, 800, 600, 800, 600, 1, 10) == app)

assert(app.dashboard.toolbar.buttons[0].selected == 1)
assert(app.dashboard.sidebar.items[0].selected == 1)
assert(app.dashboard.workspace.grid.cards[0].bars[0].value > 0)
assert(app.layout.workspace.grid.visible_count == 6)
assert(app.paint.frame.vertex_count == 328)
assert(app.paint.frame.index_count == 492)
assert(app.paint.frame.geometry_batch_count == 2)
assert(app.paint.frame.image_draw_count == 6)
assert(app.paint.frame.text_draw_count == 20)
assert(app.paint.frame.clip_count == 1)
assert(app.paint.frame.segments == nil)

assert(app:draw(owner) == true)
assert(owner.uploaded == 1 and owner.geometry == 2)
assert(owner.images == 6 and owner.text == 20 and owner.ended == 1)
assert(owner.clip_pushes == 1 and owner.clip_pops == 1)
app.host:presented()
assert(app:draw(owner) == false)

local revision = app.paint.frame.revision
assert(app:pointer_moved(owner, 300, 200, 300, 200) == app or app.paint.frame.revision > revision)
assert(app.dashboard.workspace.grid.hovered_index == 0)
assert(app.dashboard.workspace.grid.cards[0].hovered == 1)
assert(app:pointer_pressed(owner, 1) == app or app.dashboard.workspace.grid.cards[0].pressed == 1)
assert(app:pointer_released(owner, 1) == app or app.dashboard.workspace.grid.cards[0].selected == 1)
assert(app.dashboard.workspace.grid.selected_index == 0)
assert(app.dashboard.workspace.grid.cards[0].expanded == 1)

assert(app:pointer_moved(owner, 430, 20, 130, -180))
assert(app.dashboard.toolbar.hovered_index == 2)
assert(app.dashboard.workspace.grid.hovered_index == Machine.INVALID_INDEX)
assert(app:pointer_pressed(owner, 1))
assert(app:pointer_released(owner, 1))
assert(app.dashboard.toolbar.active_index == 2)
assert(app.dashboard.toolbar.buttons[2].selected == 1)
assert(app.dashboard.toolbar.buttons[0].selected == 0)

local solve_count = app.layout.solve_count
assert(app:wheel_moved(owner, 0, -1))
assert(app.dashboard.workspace.grid.scroll_offset == 48)
assert(app.layout.solve_count == solve_count + 1)
assert(app:text_entered(owner, 20))
assert(app.dashboard.status.content == 20)
assert(app:resize(owner, 1024, 768, 2048, 1536, 2))
assert(app.host.logical_width == 1024 and app.host.dpi_scale == 2)

local driver = Machine.Driver()
assert(driver:initialize(owner, 640, 480, 640, 480, 1, 10, 0, false) == driver)
local boundary = { now = 0, presents = 0, sleeps = 0 }
function boundary:drain_events(active, resource_owner, drained)
    return drained(active, resource_owner, self, 0, 0, 0)
end
function boundary:sample_window(active, resource_owner, sampled)
    return sampled(active, resource_owner, self, 640, 480, 640, 480, 1, true, true, 0)
end
function boundary:sample_time(active, resource_owner, sampled)
    self.now = self.now + 1 / 60
    return sampled(active, resource_owner, self, self.now, 1 / 60)
end
function boundary:graphics_active() return true end
function boundary:present() self.presents = self.presents + 1 end
function boundary:sleep() self.sleeps = self.sleeps + 1 end
function boundary:on_quit() self.closed = true end

assert(driver:turn(owner, boundary) == driver)
assert(driver.render_turn_count == 1 and driver.application.host.present_count == 1)
assert(boundary.presents == 1 and boundary.sleeps == 1)

local late_ok = pcall(function() Machine.ButtonState.late = function() end end)
assert(not late_ok)
local hidden_ok = pcall(function() driver._owner = owner end)
assert(not hidden_ok)

print(("ok test_ui_love_component_machine boxes=%d vertices=%d texts=%d images=%d"):format(
    4 + 7 + 12, app.paint.frame.vertex_count, app.paint.frame.text_draw_count,
    app.paint.frame.image_draw_count))

