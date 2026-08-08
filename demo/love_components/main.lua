local root = love.filesystem.getWorkingDirectory()
package.path = table.concat({
    root .. "/lua/?.lua",
    root .. "/lua/?/init.lua",
    root .. "/?.lua",
    root .. "/?/init.lua",
    package.path,
}, ";")

if os.getenv("LOVE_CPS_JOFF") == "1" then require("jit").off() end

local Components = require("ui.backends.love.components")
local Owner = require("ui.backends.love.owner")
local Loop = require("ui.backends.love.loop")

local driver
local owner

function love.load()
    love.graphics.setBackgroundColor(0.04, 0.06, 0.09, 1)
    owner = Owner.new()
    local status = owner:register_content(
        "Exotyped Lua components · named CPS exits · exact capacities · recursive projections")
    driver = Components.Driver()
    local width, height, pixel_width, pixel_height, dpi = Loop.dimensions()
    driver:initialize(owner, width, height, pixel_width, pixel_height, dpi, status, 8, true)
    love.keyboard.setTextInput(true)
    print(("LÖVE exotyped Lua UI ready: queries=%d vertex_capacity=%d"):format(
        Components.Program.query_count, Components.State.capacities.vertices))
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

