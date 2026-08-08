-- Host-stage UI exotypes. Component topology is stable, but UI values belong to
-- Lua and LÖVE, so the residual representation is an exact Lua-owned object tree.
-- No generated CDEF, C compiler, generic component node, or runtime description
-- interpreter is involved.

local Exotype = {}

local ComponentShapeQuote = {}
ComponentShapeQuote.__index = ComponentShapeQuote
local ApplicationShapeQuote = {}
ApplicationShapeQuote.__index = ApplicationShapeQuote
local DriverShapeQuote = {}
DriverShapeQuote.__index = DriverShapeQuote
local RuntimeProgramQuote = {}
RuntimeProgramQuote.__index = RuntimeProgramQuote
local Program = {}
Program.__index = Program

local function is_shape(value)
    local class = getmetatable(value)
    return class == ComponentShapeQuote or class == ApplicationShapeQuote or class == DriverShapeQuote
end

local next_property_id = 0
local next_owner_id = 0

local function property(name, accepts)
    next_property_id = next_property_id + 1
    return { id = next_property_id, name = name, accepts = accepts }
end

local LuaShape = property("LuaShape", is_shape)
local RuntimeProgram = property("RuntimeProgram", function(value)
    return getmetatable(value) == RuntimeProgramQuote
end)
Exotype.LuaShape = LuaShape
Exotype.RuntimeProgram = RuntimeProgram

local function query(compiler, owner, requested)
    local values = compiler.values[owner]
    if values == nil then values = {}; compiler.values[owner] = values end
    local value = values[requested]
    if value ~= nil then return value end
    local key = owner.id .. ":" .. requested.id
    if compiler.active[key] then
        local trace = {}
        for index = 1, #compiler.stack do trace[index] = compiler.stack[index] end
        trace[#trace + 1] = owner.name .. "." .. requested.name
        error("cyclic UI exotype property query: " .. table.concat(trace, " -> "), 2)
    end
    local implementation = owner.properties[requested]
    assert(implementation, owner.name .. " does not implement " .. requested.name)
    compiler.active[key] = true
    compiler.stack[#compiler.stack + 1] = owner.name .. "." .. requested.name
    local result = { pcall(implementation, compiler, owner) }
    compiler.stack[#compiler.stack] = nil
    compiler.active[key] = nil
    if not result[1] then error(result[2], 2) end
    value = result[2]
    assert(requested.accepts(value), owner.name .. "." .. requested.name .. " returned the wrong quotation")
    values[requested] = value
    owner.query_count = owner.query_count + 1
    compiler.query_count = compiler.query_count + 1
    return value
end

local function structural_token(value)
    local first, second = 0, 2166136261
    for index = 1, #value do
        local byte = value:byte(index)
        first = (first * 131 + byte) % 4294967296
        second = (second * 65599 + byte) % 4294967296
    end
    return ("%08x%08x"):format(first, second)
end

local function owner_class(label)
    local class = { label = label }
    class.__index = function(self, key)
        local member = class[key]
        if member ~= nil then return member end
        return self._parameters[key]
    end
    class.__newindex = function() error("UI exotype owners are immutable", 2) end
    return class
end

local ButtonOwner = owner_class("Button")
local ToolbarOwner = owner_class("Toolbar")
local SidebarOwner = owner_class("Sidebar")
local SparkBarOwner = owner_class("SparkBar")
local MetricCardOwner = owner_class("MetricCard")
local CardGridOwner = owner_class("CardGrid")
local HeaderOwner = owner_class("Header")
local WorkspaceOwner = owner_class("Workspace")
local StatusBarOwner = owner_class("StatusBar")
local DashboardOwner = owner_class("Dashboard")
local ApplicationOwner = owner_class("Application")
local DriverOwner = owner_class("Driver")

local function make_owner(class, structural_key, parameters)
    next_owner_id = next_owner_id + 1
    local token = structural_token(structural_key)
    local owner = setmetatable({
        _parameters = parameters or {},
        id = next_owner_id,
        token = token,
        name = class.label .. "_" .. token,
        properties = {},
        query_count = 0,
        program = false,
    }, class)
    owner.properties[LuaShape] = function(compiler) return owner:shape(compiler) end
    return owner
end

local function description(value, name)
    assert(type(value) == "table", name .. " requires a table description")
    return value
end

local function count(value, name)
    assert(type(value) == "number" and value >= 1 and value <= 256 and value == math.floor(value),
        name .. " must be an integer from 1 through 256")
    return value
end

local function child(value, class, name)
    assert(getmetatable(value) == class, name .. " has the wrong component owner")
    return value
end

local function new_class(name)
    local class = { name = name }
    class.__index = class
    class.__newindex = function(_, key) error("unknown generated UI instance field " .. tostring(key), 2) end
    return class
end

local function make_callable(class, constructor)
    return setmetatable(class, {
        __call = function() return constructor() end,
    })
end

local function rect() return { x = 0, y = 0, width = 0, height = 0 } end

local Builder = {}
Builder.__index = Builder

function Builder.new() return setmetatable({ classes = {}, capacities = false }, Builder) end
function Builder:query(compiler, owner) return query(compiler, owner, LuaShape) end

function ButtonOwner:shape(_compiler)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state()
        return setmetatable({
            node = 0, content = 0, revision = 0, enabled = 0, hovered = 0, pressed = 0, selected = 0,
        }, State)
    end
    local function new_layout()
        return setmetatable({ border = rect(), content = rect(), z_index = 0, visible = 0 }, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

local function repeated_shape(owner, compiler, child_owner, state_field, role)
    local child_shape = compiler.builder:query(compiler, child_owner)
    local State, Layout = new_class(owner.name .. "State"), new_class(owner.name .. "Layout")
    local function new_state()
        local items = {}
        for index = 0, owner.count - 1 do items[index] = child_shape.new_state() end
        local value = {
            revision = 0, active_index = 0, selected_index = 0, hovered_index = 0,
            target_hover_index = 0, target_active_index = 0, target_selected_index = 0,
            projection_cursor = 0,
        }
        value[state_field] = items
        return setmetatable(value, State)
    end
    local function new_layout()
        local items = {}
        for index = 0, owner.count - 1 do items[index] = child_shape.new_layout() end
        local value = { bounds = rect(), revision = 0 }
        value[state_field] = items
        return setmetatable(value, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    compiler.builder.classes[role .. "State"] = State
    compiler.builder.classes[role .. "Layout"] = Layout
    return setmetatable({
        State = State, Layout = Layout, new_state = new_state, new_layout = new_layout, child = child_shape,
    },
        ComponentShapeQuote)
end

function ToolbarOwner:shape(compiler)
    return repeated_shape(self, compiler, self.button, "buttons", "Toolbar")
end

function SidebarOwner:shape(compiler)
    return repeated_shape(self, compiler, self.button, "items", "Sidebar")
end

function SparkBarOwner:shape(_compiler)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state() return setmetatable({ value = 0, target = 0, revision = 0 }, State) end
    local function new_layout() return setmetatable({ bar = rect(), visible = 0, reserved = 0 }, Layout) end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

function MetricCardOwner:shape(compiler)
    local bar = compiler.builder:query(compiler, self.bar)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state()
        local bars = {}
        for index = 0, self.count - 1 do bars[index] = bar.new_state() end
        return setmetatable({
            node = 0, title = 0, image = 0, bars = bars, revision = 0, hovered = 0, pressed = 0,
            selected = 0, expanded = 0, bar_cursor = 0, reserved = 0,
        }, State)
    end
    local function new_layout()
        local bars = {}
        for index = 0, self.count - 1 do bars[index] = bar.new_layout() end
        return setmetatable({
            bounds = rect(), image = rect(), bars = bars, z_index = 0, visible = 0, revision = 0,
        }, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    compiler.builder.classes.SparkBarState = bar.State
    compiler.builder.classes.SparkBarLayout = bar.Layout
    compiler.builder.classes.MetricCardState = State
    compiler.builder.classes.MetricCardLayout = Layout
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

function CardGridOwner:shape(compiler)
    local card = compiler.builder:query(compiler, self.card)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state()
        local cards = {}
        for index = 0, self.count - 1 do cards[index] = card.new_state() end
        return setmetatable({
            cards = cards, scroll_offset = 0, scroll_target = 0, revision = 0, selected_index = 0,
            hovered_index = 0, target_hover_index = 0, target_selected_index = 0, columns = 0,
            projection_cursor = 0, reserved = 0,
        }, State)
    end
    local function new_layout()
        local cards = {}
        for index = 0, self.count - 1 do cards[index] = card.new_layout() end
        return setmetatable({
            bounds = rect(), clip = rect(), cards = cards, revision = 0, columns = 0, visible_count = 0,
        }, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    compiler.builder.classes.CardGridState = State
    compiler.builder.classes.CardGridLayout = Layout
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

function HeaderOwner:shape(_compiler)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state() return setmetatable({ title = 0, subtitle = 0, revision = 0 }, State) end
    local function new_layout() return setmetatable({ bounds = rect(), revision = 0 }, Layout) end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

function WorkspaceOwner:shape(compiler)
    local header = compiler.builder:query(compiler, self.header)
    local grid = compiler.builder:query(compiler, self.grid)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state()
        return setmetatable({
            header = header.new_state(), grid = grid.new_state(), zoom = 0, pan_x = 0, pan_y = 0, revision = 0,
        }, State)
    end
    local function new_layout()
        return setmetatable({
            bounds = rect(), header = header.new_layout(), grid = grid.new_layout(), revision = 0,
        }, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    compiler.builder.classes.HeaderState = header.State
    compiler.builder.classes.HeaderLayout = header.Layout
    compiler.builder.classes.WorkspaceState = State
    compiler.builder.classes.WorkspaceLayout = Layout
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

function StatusBarOwner:shape(_compiler)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state() return setmetatable({ content = 0, revision = 0 }, State) end
    local function new_layout() return setmetatable({ bounds = rect(), revision = 0 }, Layout) end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

local function array(capacity, constructor)
    local values = {}
    for index = 0, capacity - 1 do values[index] = constructor() end
    return values
end

local function frame(capacities)
    return {
        vertices = array(capacities.vertices, function()
            return { x = 0, y = 0, u = 0, v = 0, rgba8 = 0, reserved = 0 }
        end),
        indices = array(capacities.indices, function() return 0 end),
        geometry_batches = array(2, function()
            return {
                first_vertex = 0, vertex_count = 0, first_index = 0, index_count = 0, image = 0,
                shader = 0, topology = 0, blend_mode = 0,
            }
        end),
        text_draws = array(capacities.text_draws, function()
            return {
                node = 0, content = 0, font = 0, text_resource = 0, x = 0, y = 0, wrap_width = 0,
                opacity = 0, rgba8 = 0, alignment = 0,
            }
        end),
        image_draws = array(capacities.image_draws, function()
            return {
                node = 0, image = 0, source = rect(), destination = rect(), rotation = 0, opacity = 0,
                tint_rgba8 = 0, reserved = 0,
            }
        end),
        clips = { [0] = { rect = rect(), radius = 0, kind = 0, revision = 0 } },
        vertex_count = 0, index_count = 0, geometry_batch_count = 0, text_draw_count = 0,
        image_draw_count = 0, clip_count = 0, layout_revision = 0, revision = 0,
    }
end

function DashboardOwner:shape(compiler)
    local toolbar = compiler.builder:query(compiler, self.toolbar)
    local sidebar = compiler.builder:query(compiler, self.sidebar)
    local workspace = compiler.builder:query(compiler, self.workspace)
    local status = compiler.builder:query(compiler, self.status)
    local State, Layout = new_class(self.name .. "State"), new_class(self.name .. "Layout")
    local function new_state()
        return setmetatable({
            toolbar = toolbar.new_state(), sidebar = sidebar.new_state(), workspace = workspace.new_state(),
            status = status.new_state(), revision = 0, hovered_concern = 0, target_hover_concern = 0,
            projection_stage = 0, route_changed = 0, pressed_concern = 0, pressed_index = 0,
            workspace_first_vertex = 0, workspace_first_index = 0, shell_text_count = 0, reserved = 0,
        }, State)
    end
    local function new_layout()
        return setmetatable({
            toolbar = toolbar.new_layout(), sidebar = sidebar.new_layout(), workspace = workspace.new_layout(),
            status = status.new_layout(), revision = 0, solve_count = 0,
        }, Layout)
    end
    make_callable(State, new_state)
    make_callable(Layout, new_layout)
    local classes = compiler.builder.classes
    classes.ButtonState = toolbar.child.State
    classes.ButtonLayout = toolbar.child.Layout
    classes.ToolbarState, classes.ToolbarLayout = toolbar.State, toolbar.Layout
    classes.SidebarState, classes.SidebarLayout = sidebar.State, sidebar.Layout
    classes.StatusBarState, classes.StatusBarLayout = status.State, status.Layout
    classes.DashboardState, classes.DashboardLayout = State, Layout
    return setmetatable({ State = State, Layout = Layout, new_state = new_state, new_layout = new_layout },
        ComponentShapeQuote)
end

local function runtime_class(name)
    local class = new_class(name)
    return class
end

function ApplicationOwner:shape(compiler)
    local dashboard = compiler.builder:query(compiler, self.dashboard)
    local classes = compiler.builder.classes
    local Host = runtime_class(self.name .. "Host")
    local Input = runtime_class(self.name .. "Input")
    local TextMeasure = runtime_class(self.name .. "TextMeasure")
    local Paint = runtime_class(self.name .. "Paint")
    local Metrics = runtime_class(self.name .. "DriverMetrics")
    local Application = runtime_class(self.name .. "State")
    local tools = self.dashboard.toolbar.count
    local navigation = self.dashboard.sidebar.count
    local cards = self.dashboard.workspace.grid.count
    local bars = self.dashboard.workspace.grid.card.count
    local quads = 5 + tools + navigation + cards * (1 + bars)
    local capacities = {
        vertices = quads * 4,
        indices = quads * 6,
        text_draws = tools + navigation + cards + 3,
        image_draws = cards,
    }
    compiler.builder.capacities = capacities
    local function new_host()
        return setmetatable({
            now_seconds = 0, delta_seconds = 0, frame_index = 0, event_count = 0, present_count = 0,
            logical_width = 0, logical_height = 0, pixel_width = 0, pixel_height = 0, dpi_scale = 0,
            focused = 0, visible = 0, quit_requested = 0, redraw_requested = 0,
        }, Host)
    end
    local function new_input()
        return setmetatable({
            pointer_x = 0, pointer_y = 0, pointer_dx = 0, pointer_dy = 0, pointer_inside = 0,
            pointer_revision = 0, revision = 0,
        }, Input)
    end
    local function new_text_measure()
        return setmetatable({
            count = 0, overflow_count = 0, model_revision = 0, revision = 0, measure_count = 0,
        }, TextMeasure)
    end
    local function new_paint() return setmetatable({ frame = frame(capacities), commit_count = 0 }, Paint) end
    local metric_fields = {
        "enabled", "measured_turns", "report_count", "turn_started_seconds", "heap_started_kb",
        "uploads_started", "draws_started", "mesh_rebuilds_started", "text_rebuilds_started",
        "last_drain_seconds", "total_drain_seconds", "max_drain_seconds", "last_window_seconds",
        "total_window_seconds", "max_window_seconds", "last_tick_seconds", "total_tick_seconds",
        "max_tick_seconds", "last_render_seconds", "total_render_seconds", "max_render_seconds",
        "last_present_seconds", "total_present_seconds", "max_present_seconds", "last_turn_seconds",
        "total_turn_seconds", "max_turn_seconds", "last_heap_delta_kb", "max_heap_growth_kb",
        "last_uploads", "last_draws", "last_mesh_rebuilds", "last_text_rebuilds", "upload_count",
        "draw_count", "mesh_rebuild_count", "text_rebuild_count", "next_report_seconds",
    }
    local function new_metrics()
        local value = {}
        for index = 1, #metric_fields do value[metric_fields[index]] = 0 end
        return setmetatable(value, Metrics)
    end
    local function new_state()
        return setmetatable({
            host = new_host(), input = new_input(), dashboard = dashboard.new_state(),
            layout = dashboard.new_layout(), text_measure = new_text_measure(), paint = new_paint(),
            rendered_revision = 0, epoch = 0, ignored_count = 0, component_change_count = 0,
            layout_change_count = 0, paint_change_count = 0, rejection_count = 0,
        }, Application)
    end
    make_callable(Host, new_host)
    make_callable(Input, new_input)
    make_callable(TextMeasure, new_text_measure)
    make_callable(Paint, new_paint)
    make_callable(Metrics, new_metrics)
    make_callable(Application, new_state)
    classes.Host, classes.Input, classes.TextMeasure = Host, Input, TextMeasure
    classes.Paint, classes.DriverMetrics, classes.Application = Paint, Metrics, Application
    classes.DashboardState, classes.DashboardLayout = dashboard.State, dashboard.Layout
    return setmetatable({ State = Application, new_state = new_state, metrics = new_metrics },
        ApplicationShapeQuote)
end

function DriverOwner:shape(compiler)
    local application = query(compiler, self.application, LuaShape)
    local Driver = runtime_class(self.name .. "State")
    local function new_state()
        return setmetatable({
            application = application.new_state(), metrics = application.metrics(), turn_count = 0,
            drained_event_count = 0, ignored_event_count = 0, render_turn_count = 0, idle_turn_count = 0,
            quit_turn_count = 0, running = 0, exit_code = 0, bootstrap_remaining = 0, reserved = 0,
        }, Driver)
    end
    make_callable(Driver, new_state)
    compiler.builder.classes.Driver = Driver
    return setmetatable({ State = Driver, new_state = new_state, application = application }, DriverShapeQuote)
end

local button_cache, spark_bar_cache, header_cache, status_cache = {}, {}, {}, {}
local toolbar_cache, sidebar_cache, metric_card_cache, card_grid_cache = {}, {}, {}, {}
local workspace_cache, dashboard_cache, application_cache, driver_cache = {}, {}, {}, {}

function Exotype.Button(specification)
    description(specification, "Button")
    if button_cache.one == nil then button_cache.one = make_owner(ButtonOwner, "button") end
    return button_cache.one
end

function Exotype.SparkBar(specification)
    description(specification, "SparkBar")
    if spark_bar_cache.one == nil then spark_bar_cache.one = make_owner(SparkBarOwner, "spark-bar") end
    return spark_bar_cache.one
end

function Exotype.Header(specification)
    description(specification, "Header")
    if header_cache.one == nil then header_cache.one = make_owner(HeaderOwner, "header") end
    return header_cache.one
end

function Exotype.StatusBar(specification)
    description(specification, "StatusBar")
    if status_cache.one == nil then status_cache.one = make_owner(StatusBarOwner, "status-bar") end
    return status_cache.one
end

local function repeated_owner(cache, class, label, field, item, item_class, item_count)
    child(item, item_class, label .. ".item")
    count(item_count, label .. ".count")
    local key = item.id .. ":" .. item_count
    if cache[key] == nil then
        local parameters = { count = item_count }
        parameters[field] = item
        cache[key] = make_owner(class, label .. ":" .. item.token .. ":" .. item_count, parameters)
    end
    return cache[key]
end

function Exotype.Toolbar(specification)
    local spec = description(specification, "Toolbar")
    return repeated_owner(toolbar_cache, ToolbarOwner, "toolbar", "button",
        spec.button, ButtonOwner, spec.count)
end

function Exotype.Sidebar(specification)
    local spec = description(specification, "Sidebar")
    return repeated_owner(sidebar_cache, SidebarOwner, "sidebar", "button",
        spec.button, ButtonOwner, spec.count)
end

function Exotype.MetricCard(specification)
    local spec = description(specification, "MetricCard")
    return repeated_owner(metric_card_cache, MetricCardOwner, "metric-card", "bar",
        spec.bar, SparkBarOwner, spec.count)
end

function Exotype.CardGrid(specification)
    local spec = description(specification, "CardGrid")
    return repeated_owner(card_grid_cache, CardGridOwner, "card-grid", "card",
        spec.card, MetricCardOwner, spec.count)
end

function Exotype.Workspace(specification)
    local spec = description(specification, "Workspace")
    local header = child(spec.header, HeaderOwner, "Workspace.header")
    local grid = child(spec.grid, CardGridOwner, "Workspace.grid")
    local key = header.id .. ":" .. grid.id
    if workspace_cache[key] == nil then
        workspace_cache[key] = make_owner(WorkspaceOwner, "workspace:" .. header.token .. ":" .. grid.token,
            { header = header, grid = grid })
    end
    return workspace_cache[key]
end

function Exotype.Dashboard(specification)
    local spec = description(specification, "Dashboard")
    local toolbar = child(spec.toolbar, ToolbarOwner, "Dashboard.toolbar")
    local sidebar = child(spec.sidebar, SidebarOwner, "Dashboard.sidebar")
    local workspace = child(spec.workspace, WorkspaceOwner, "Dashboard.workspace")
    local status = child(spec.status, StatusBarOwner, "Dashboard.status")
    assert(toolbar.button == sidebar.button, "dashboard toolbar and sidebar must share one button owner")
    local key = table.concat({ toolbar.id, sidebar.id, workspace.id, status.id }, ":")
    if dashboard_cache[key] == nil then
        local structural = table.concat({ toolbar.token, sidebar.token, workspace.token, status.token }, ":")
        dashboard_cache[key] = make_owner(DashboardOwner, "dashboard:" .. structural, {
            toolbar = toolbar, sidebar = sidebar, workspace = workspace, status = status,
        })
    end
    return dashboard_cache[key]
end

function Exotype.Application(specification)
    local spec = description(specification, "Application")
    local dashboard = child(spec.dashboard, DashboardOwner, "Application.dashboard")
    if application_cache[dashboard] == nil then
        application_cache[dashboard] = make_owner(ApplicationOwner, "application:" .. dashboard.token,
            { dashboard = dashboard })
    end
    return application_cache[dashboard]
end

function Exotype.Driver(specification)
    local spec = description(specification, "Driver")
    local application = child(spec.application, ApplicationOwner, "Driver.application")
    if driver_cache[application] == nil then
        local owner = make_owner(DriverOwner, "driver:" .. application.token, { application = application })
        owner.properties[RuntimeProgram] = function(compiler)
            local shape = query(compiler, owner, LuaShape)
            return setmetatable({
                shape = shape,
                behavior = require("ui.backends.love.component_machine"),
            }, RuntimeProgramQuote)
        end
        driver_cache[application] = owner
    end
    return driver_cache[application]
end

function RuntimeProgramQuote:bind(State) return self.behavior(State) end

function Exotype.compile(owner)
    assert(getmetatable(owner) == DriverOwner, "UI exotype compilation requires a Driver owner")
    if owner.program ~= false then return owner.program end
    local compiler = { active = {}, stack = {}, values = {}, query_count = 0, builder = Builder.new() }
    local quotation = query(compiler, owner, RuntimeProgram)
    local State = compiler.builder.classes
    State.Driver = quotation.shape.State
    State.counts = {
        tools = owner.application.dashboard.toolbar.count,
        navigation = owner.application.dashboard.sidebar.count,
        cards = owner.application.dashboard.workspace.grid.count,
        spark_bars = owner.application.dashboard.workspace.grid.card.count,
    }
    State.capacities = compiler.builder.capacities
    function State:seal()
        for _, class in pairs(self) do
            if type(class) == "table" and class.__index == class then
                getmetatable(class).__newindex = function() error("generated UI class is sealed", 2) end
            end
        end
    end
    quotation:bind(State)
    local program = setmetatable({
        owner = owner, State = State, Driver = State.Driver, Application = State.Application,
        entry_function = State.Driver.turn, query_count = compiler.query_count,
    }, Program)
    owner.program = program
    return program
end

function Program:entry() return self.entry_function end
function Program:new_driver() return self.Driver() end
function Program:new_application() return self.Application() end

return Exotype
