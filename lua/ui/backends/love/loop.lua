local M = {}
local Boundary = {}
Boundary.__index = Boundary

local function dimensions()
    local width, height = love.graphics.getDimensions()
    local pixel_width, pixel_height = love.graphics.getPixelDimensions()
    local dpi = love.window.getDPIScale and love.window.getDPIScale() or 1
    return width, height, pixel_width, pixel_height, dpi
end

local function assert_window_synchronized(driver)
    local width, height, pixel_width, pixel_height, dpi = dimensions()
    local host = driver.application.host
    assert(host.logical_width == width and host.logical_height == height)
    assert(host.pixel_width == pixel_width and host.pixel_height == pixel_height)
    assert(host.dpi_scale == dpi)
end

function M.new(smoke, resize_smoke)
    return setmetatable({
        smoke = smoke == true,
        resize_smoke = resize_smoke == true,
        smoke_frames = 0,
        benchmark_turns = 0,
        benchmark_frames = 0,
        benchmark_dirty = false,
        benchmark_uploads = 0,
        benchmark_draws = 0,
        benchmark_meshes = 0,
        benchmark_texts = 0,
        benchmark_renders = 0,
    }, Boundary)
end

function M.benchmark(dirty, turns)
    local boundary = M.new(false, false)
    boundary.benchmark_dirty = dirty == true
    boundary.benchmark_turns = assert(tonumber(turns))
    assert(boundary.benchmark_turns > 0, "benchmark turns must be positive")
    return boundary
end

function Boundary:drain_events(driver, owner, drained, quitting)
    local measured = driver.metrics.enabled ~= 0
    local started = measured and love.timer.getTime() or 0
    local drained_count = 0
    local ignored_count = 0
    love.event.pump()

    for name, a, b, c, d in love.event.poll() do
        if name == "quit" then
            local seconds = measured and math.max(0, love.timer.getTime() - started) or 0
            return quitting(driver, owner, self, a or 0, drained_count + 1, ignored_count, seconds)
        elseif name == "keypressed" and a == "escape" then
            local seconds = measured and math.max(0, love.timer.getTime() - started) or 0
            return quitting(driver, owner, self, 0, drained_count + 1, ignored_count, seconds)
        elseif name == "resize" then
            driver:resize_damaged(owner)
        elseif name == "focus" then
            driver:focus_changed(owner, a)
        elseif name == "visible" then
            driver:visibility_changed(owner, a)
        elseif name == "mousefocus" then
            if a then driver:surface_damaged(owner) end
        elseif name == "mousemoved" then
            driver:pointer_moved(owner, a, b, c, d)
        elseif name == "mousepressed" then
            driver:pointer_pressed(owner, a, b, c)
        elseif name == "mousereleased" then
            driver:pointer_released(owner, a, b, c)
        elseif name == "wheelmoved" then
            driver:wheel_moved(owner, a, b)
        elseif name == "textinput" then
            driver:text_entered(owner, a)
        else
            ignored_count = ignored_count + 1
        end
        drained_count = drained_count + 1
    end

    local seconds = measured and math.max(0, love.timer.getTime() - started) or 0
    return drained(driver, owner, self, drained_count, ignored_count, seconds)
end

function Boundary:sample_window(driver, owner, sampled)
    local measured = driver.metrics.enabled ~= 0
    local started = measured and love.timer.getTime() or 0
    local width, height, pixel_width, pixel_height, dpi = dimensions()
    local focused = not love.window.hasFocus or love.window.hasFocus()
    local visible = not love.window.isVisible or love.window.isVisible()
    local seconds = measured and math.max(0, love.timer.getTime() - started) or 0
    return sampled(driver, owner, self, width, height, pixel_width, pixel_height, dpi,
        focused, visible, seconds)
end

function Boundary:sample_time(driver, owner, sampled)
    local delta = love.timer and love.timer.step() or 0
    local now = love.timer and love.timer.getTime() or 0
    return sampled(driver, owner, self, now, delta)
end

function Boundary:clock(_driver, _owner) return love.timer.getTime() end

function Boundary:metric_snapshot(_driver, owner)
    return love.timer.getTime(), collectgarbage("count"), owner.uploads, owner.draw_calls,
        owner.mesh_rebuilds, owner.text_rebuilds
end

function Boundary:report_metrics(driver, _owner)
    if self.benchmark_turns ~= 0 then return end
    local metrics = driver.metrics
    love.window.setTitle(("Lalin CPS · %.3f ms turn · %.3f ms render max · %.3f ms present max · "
        .. "%d uploads · %d draws · mesh/text %d/%d · %+.1f KiB heap"):format(
        metrics.last_turn_seconds * 1000, metrics.max_render_seconds * 1000,
        metrics.max_present_seconds * 1000, tonumber(metrics.upload_count),
        tonumber(metrics.draw_count), tonumber(metrics.mesh_rebuild_count),
        tonumber(metrics.text_rebuild_count), metrics.last_heap_delta_kb))
end

function Boundary:graphics_active(_driver, _owner) return love.graphics.isActive() end
function Boundary:present(_driver, _owner) love.graphics.present() end
function Boundary:on_quit(_driver, _owner) love.keyboard.setTextInput(false) end

local function print_benchmark(driver, owner, boundary)
    local metrics = driver.metrics
    local turns = tonumber(metrics.measured_turns)
    local renders = tonumber(driver.render_turn_count) - tonumber(boundary.benchmark_renders)
    local present_average = renders > 0 and metrics.total_present_seconds / renders or 0
    local render_average = renders > 0 and metrics.total_render_seconds / renders or 0
    local active_average = (metrics.total_turn_seconds - metrics.total_present_seconds) / turns
    print(("BENCH mode=%s turns=%d renders=%d turn_us=%.3f active_us=%.3f "
        .. "drain_us=%.3f window_us=%.3f tick_us=%.3f render_us=%.3f present_ms=%.3f "
        .. "turn_max_ms=%.3f render_max_us=%.3f heap_growth_kb=%.3f uploads=%d draws=%d "
        .. "mesh_rebuilds=%d text_rebuilds=%d"):format(
        boundary.benchmark_dirty and "dirty" or "idle", turns, renders,
        metrics.total_turn_seconds * 1000000 / turns, active_average * 1000000,
        metrics.total_drain_seconds * 1000000 / turns,
        metrics.total_window_seconds * 1000000 / turns,
        metrics.total_tick_seconds * 1000000 / turns, render_average * 1000000,
        present_average * 1000, metrics.max_turn_seconds * 1000,
        metrics.max_render_seconds * 1000000, metrics.max_heap_growth_kb,
        owner.uploads - boundary.benchmark_uploads, owner.draw_calls - boundary.benchmark_draws,
        owner.mesh_rebuilds - boundary.benchmark_meshes,
        owner.text_rebuilds - boundary.benchmark_texts))
    io.stdout:flush()
end

function Boundary:sleep(driver, owner)
    if self.smoke then
        self.smoke_frames = self.smoke_frames + 1
        if self.resize_smoke and self.smoke_frames == 2 then
            love.window.setMode(901, 611, { resizable = true, highdpi = true, vsync = 1 })
        elseif self.resize_smoke and self.smoke_frames == 3 then
            assert_window_synchronized(driver)
            love.window.setMode(820, 570, { resizable = true, highdpi = true, vsync = 1 })
        elseif self.resize_smoke and self.smoke_frames == 4 then
            assert_window_synchronized(driver)
            love.window.setMode(1000, 650, { resizable = true, highdpi = true, vsync = 1 })
        elseif self.resize_smoke and self.smoke_frames == 5 then
            assert_window_synchronized(driver)
            print("LÖVE CPS UI resize tracking: ok")
        end
        if self.smoke_frames == 5 then
            love.graphics.captureScreenshot("love_cps_ui.png")
        elseif self.smoke_frames >= 8 then
            print("LÖVE CPS UI smoke: ok")
            love.event.quit()
        end
    end
    if self.benchmark_turns ~= 0 then
        self.benchmark_frames = self.benchmark_frames + 1
        if self.benchmark_frames == 32 then
            driver.metrics:initialize(true)
            self.benchmark_uploads = owner.uploads
            self.benchmark_draws = owner.draw_calls
            self.benchmark_meshes = owner.mesh_rebuilds
            self.benchmark_texts = owner.text_rebuilds
            self.benchmark_renders = tonumber(driver.render_turn_count)
        elseif self.benchmark_frames > 32
            and driver.metrics.measured_turns >= self.benchmark_turns then
            print_benchmark(driver, owner, self)
            love.event.quit()
        end
        if self.benchmark_dirty then
            local y = self.benchmark_frames % 2 == 0 and 20 or 200
            love.event.push("mousemoved", 100, y, 0, 0, false)
        end
    end
    if love.timer then love.timer.sleep(0.001) end
end

function M.run(driver, owner, boundary, entry)
    boundary = boundary or M.new(false, false)
    local turn = entry or driver.turn
    if love.timer then love.timer.step() end
    return function()
        turn(driver, owner, boundary)
        if driver.running == 0 then return tonumber(driver.exit_code) end
    end
end

M.Boundary = Boundary
M.dimensions = dimensions
M.print_benchmark = print_benchmark

return M

