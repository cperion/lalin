function love.conf(t)
    t.identity = "lalin-love-cps-ui"
    t.version = "11.5"
    t.console = true
    t.window.title = "Lalin — CDEF + CPS + LÖVE"
    t.window.width = 960
    t.window.height = 640
    t.window.resizable = true
    t.window.highdpi = true
    t.window.vsync = 1
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.physics = false
end

