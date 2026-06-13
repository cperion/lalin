package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")
local sdl3 = ui.backends.sdl3
local paint = ui.paint
local Layout = ui.T.Layout

local host = sdl3.new_host {
    title = "ui SDL3 paint smoke",
    width = 320,
    height = 200,
    vsync = false,
}

local driver = host.driver
host:begin_frame(0x020617ff)

driver:draw_rect(8, 8, 80, 40, Layout.BoxVisual(
    0x0f172aff,
    0x38bdf8ff,
    3,
    Layout.ShapeRoundRect,
    10,
    100
))

driver:draw_rect(96, 8, 80, 40, Layout.BoxVisual(
    0x1e293bff,
    0xf59e0bff,
    4,
    Layout.ShapeCapsule,
    999,
    100
))

driver:draw_paint(0, 0, 320, 200, paint.list {
    paint.line(20, 80, 120, 120, paint.stroke(0x38bdf8ff, 4)),
    paint.polyline({ 140, 80, 170, 110, 200, 90, 230, 130 }, paint.stroke(0xa78bfaff, 3)),
    paint.polygon({ 20, 140, 70, 130, 90, 180, 30, 170 }, paint.fill(0x14b8a688), paint.stroke(0x2dd4bfff, 2)),
    paint.circle(150, 155, 24, paint.fill(0xf59e0b88), paint.stroke(0xfbbf24ff, 3)),
    paint.arc(220, 155, 28, -2.4, 0.8, 24, paint.stroke(0xef4444ff, 5)),
    paint.bezier({ 250, 130, 290, 110, 290, 190, 315, 170 }, 20, paint.stroke(0x22c55eff, 3)),
    paint.mesh(paint.mesh_fan, {
        paint.vertex(260, 40),
        paint.vertex(300, 60),
        paint.vertex(280, 95),
        paint.vertex(240, 90),
        paint.vertex(230, 55),
    }, nil, 0x60a5faff, 80),
})

host:present()
host:close()

print("ok test_ui_sdl3_paint")
