local State = require("ui.backends.love.state")
local Machine = require("ui.backends.love.machine")
local Owner = require("ui.backends.love.owner")
local Loop = require("ui.backends.love.loop")
local capabilities = require("ui.backends.love.capabilities")

return {
    name = "love",
    State = State,
    Machine = Machine,
    Owner = Owner,
    Loop = Loop,
    Driver = Machine.Driver,
    Application = Machine.Application,
    new_owner = Owner.new,
    new_boundary = Loop.new,
    run = Loop.run,
    capabilities = capabilities,
}

