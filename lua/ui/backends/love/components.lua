local Ui = require("ui.backends.love.component_state")

local Button = Ui.Button {}
local SparkBar = Ui.SparkBar {}
local MetricCard = Ui.MetricCard { bar = SparkBar, count = 10 }
local Grid = Ui.CardGrid { card = MetricCard, count = 12 }
local Header = Ui.Header {}
local Workspace = Ui.Workspace { header = Header, grid = Grid }
local Toolbar = Ui.Toolbar { button = Button, count = 4 }
local Sidebar = Ui.Sidebar { button = Button, count = 7 }
local Status = Ui.StatusBar {}
local Dashboard = Ui.Dashboard {
    toolbar = Toolbar,
    sidebar = Sidebar,
    workspace = Workspace,
    status = Status,
}
local Application = Ui.Application { dashboard = Dashboard }
local Driver = Ui.Driver { application = Application }
local Program = Ui.compile(Driver)
local State = Program.State

return {
    name = "love-components-exotype",
    Exotype = Ui,
    Type = Driver,
    Program = Program,
    State = State,
    Machine = State,
    Driver = State.Driver,
    Application = State.Application,
}
