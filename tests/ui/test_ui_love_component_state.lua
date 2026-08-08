package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Components = require("ui.backends.love.components")
local Ui = Components.Exotype
local State = Components.State

local driver = Components.Program:new_driver()
local other = Components.Program:new_driver()
local app = driver.application
local dashboard = app.dashboard
local layout = app.layout

assert(type(driver) == "table")
assert(Components.Program.physical == nil)
assert(Components.Program:entry() == State.Driver.turn)
assert(Components.Type.query_count == 2)
assert(Components.Program.query_count == 13)
assert(Ui.Button {} == Ui.Button {})
local mutation_ok = pcall(function() Components.Type.application = false end)
assert(not mutation_ok)

assert(dashboard.toolbar.buttons[0] ~= nil and dashboard.toolbar.buttons[4] == nil)
assert(dashboard.sidebar.items[0] ~= nil and dashboard.sidebar.items[7] == nil)
assert(dashboard.workspace.grid.cards[0] ~= nil and dashboard.workspace.grid.cards[12] == nil)
assert(dashboard.workspace.grid.cards[0].bars[0] ~= nil)
assert(dashboard.workspace.grid.cards[0].bars[10] == nil)
assert(layout.workspace.grid.cards[11].bars[9].bar.width == 0)

dashboard.toolbar.buttons[0].node = 100
dashboard.toolbar.buttons[0].selected = 1
dashboard.workspace.grid.cards[0].bars[0].value = 0.75
layout.workspace.grid.cards[0].bounds.width = 240
assert(other.application.dashboard.toolbar.buttons[0].node == 0)
assert(other.application.dashboard.workspace.grid.cards[0].bars[0].value == 0)
assert(other.application.layout.workspace.grid.cards[0].bounds.width == 0)

assert(State.capacities.vertices == 592)
assert(State.capacities.indices == 888)
assert(State.capacities.text_draws == 26)
assert(State.capacities.image_draws == 12)

local AlternateButton = Ui.Button {}
local AlternateBar = Ui.SparkBar {}
local AlternateCard = Ui.MetricCard { bar = AlternateBar, count = 4 }
local AlternateGrid = Ui.CardGrid { card = AlternateCard, count = 5 }
local AlternateWorkspace = Ui.Workspace {
    header = Ui.Header {},
    grid = AlternateGrid,
}
local AlternateDashboard = Ui.Dashboard {
    toolbar = Ui.Toolbar { button = AlternateButton, count = 2 },
    sidebar = Ui.Sidebar { button = AlternateButton, count = 3 },
    workspace = AlternateWorkspace,
    status = Ui.StatusBar {},
}
local AlternateType = Ui.Driver {
    application = Ui.Application { dashboard = AlternateDashboard },
}
local AlternateProgram = Ui.compile(AlternateType)
local Alternate = AlternateProgram.State
local alternate = AlternateProgram:new_application()

assert(AlternateType ~= Components.Type)
assert(Alternate.ButtonState ~= State.ButtonState)
assert(AlternateType.query_count == 2)
assert(Alternate.counts.tools == 2)
assert(Alternate.counts.navigation == 3)
assert(Alternate.counts.cards == 5)
assert(Alternate.counts.spark_bars == 4)
assert(Alternate.capacities.vertices == (5 + 2 + 3 + 5 * 5) * 4)
assert(alternate:initialize({}, 800, 600, 800, 600, 1, 10) == alternate)
assert(alternate.dashboard.toolbar.buttons[0].selected == 1)
assert(alternate.dashboard.workspace.grid.cards[4].bars[3].value > 0)

local late_ok = pcall(function() State.ButtonState.late = function() end end)
assert(not late_ok)
local hidden_ok = pcall(function() driver._owner = Components.Type end)
assert(not hidden_ok)

print(("ok exotyped Lua UI queries=%d vertices=%d alternate_vertices=%d"):format(
    Components.Program.query_count, State.capacities.vertices, Alternate.capacities.vertices))
