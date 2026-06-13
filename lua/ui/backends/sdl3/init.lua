local host = require("ui.backends.sdl3.host")
local runtime = require("ui.backends.sdl3.runtime")
local text = require("ui.backends.sdl3.text")
local ffi = require("ui.backends.sdl3.ffi")

local capabilities = {
    runtime = {
        boxes = true,
        rounded_boxes = true,
        capsules = true,
        clipping = true,
        transforms = true,
        scrolling = true,
        layers = "generic",
        cursors = true,
        density = "logical-noop",
    },
    paint = {
        line = true,
        polyline = true,
        polygon_fill = true,
        circle_fill = true,
        arc = true,
        bezier = true,
        mesh = true,
        image = "texture-or-bmp-resolver",
        stroke_width = true,
    },
    text = {
        measure = true,
        draw = true,
        hit_test = true,
        ranges = true,
        ime = true,
        clipboard = true,
        shaping = "sdl_ttf",
    },
    host = {
        windows = true,
        multi_window = true,
        events = true,
        text_input_rect = true,
        clipboard = true,
        timers = true,
        hidpi = false,
    },
}

return {
    name = "sdl3",
    ffi = ffi,
    host = host,
    runtime = runtime,
    text = text,
    new_host = host.new,
    poll_events = host.poll_events,
    filter_events = host.filter_events,
    partition_events = host.partition_events,
    new_text_system = text.new,
    capabilities = capabilities,
}
