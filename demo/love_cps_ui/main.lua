local root = love.filesystem.getWorkingDirectory()
package.path = table.concat({
    root .. "/lua/?.lua",
    root .. "/lua/?/init.lua",
    root .. "/?.lua",
    root .. "/?/init.lua",
    package.path,
}, ";")

if os.getenv("LOVE_CPS_JOFF") == "1" then require("jit").off() end

local Backend = require("ui.backends.love")
local Machine = Backend.Machine
local Owner = Backend.Owner
local Loop = Backend.Loop

local driver
local owner

local function dimensions() return Loop.dimensions() end

function love.load()
    love.graphics.setBackgroundColor(0.06, 0.08, 0.11, 1)
    owner = Owner.new()
    local status = owner:register_content(
        "12 live cards · hover, click, drag, wheel, type · CDEF+CPS · retained Mesh/Text/Image")
    driver = Machine.Driver()
    local width, height, pixel_width, pixel_height, dpi = dimensions()
    driver:initialize(owner, width, height, pixel_width, pixel_height, dpi, status, 8, true)
    love.keyboard.setTextInput(true)
    print(("LÖVE CPS UI ready: driver=%d bytes renderer=%s"):format(
        require("ffi").sizeof(driver), ({ love.graphics.getRendererInfo() })[1]))
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    local benchmark_mode = os.getenv("LOVE_CPS_BENCH")
    local boundary
    if benchmark_mode == "idle" or benchmark_mode == "dirty" then
        boundary = Loop.benchmark(
            benchmark_mode == "dirty", tonumber(os.getenv("LOVE_CPS_BENCH_TURNS")) or 1000)
    else
        boundary = Loop.new(
            os.getenv("LOVE_CPS_SMOKE") == "1",
            os.getenv("LOVE_CPS_RESIZE_SMOKE") == "1")
    end
    return Loop.run(driver, owner, boundary)
end

