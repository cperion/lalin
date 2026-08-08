-- UI-specific behavior quotation binder. Calling this function is staging work:
-- it binds stable Lua methods for one exact component topology.
return function(State)

local capacities = State.capacities
local Host = State.Host
local Input = State.Input
local TextMeasure = State.TextMeasure
local Paint = State.Paint
local DriverMetrics = State.DriverMetrics
local Button = State.ButtonState
local Toolbar = State.ToolbarState
local Sidebar = State.SidebarState
local SparkBar = State.SparkBarState
local MetricCard = State.MetricCardState
local CardGrid = State.CardGridState
local Header = State.HeaderState
local Workspace = State.WorkspaceState
local Status = State.StatusBarState
local Dashboard = State.DashboardState
local ButtonLayout = State.ButtonLayout
local ToolbarLayout = State.ToolbarLayout
local SidebarLayout = State.SidebarLayout
local CardGridLayout = State.CardGridLayout
local HeaderLayout = State.HeaderLayout
local WorkspaceLayout = State.WorkspaceLayout
local StatusLayout = State.StatusBarLayout
local DashboardLayout = State.DashboardLayout
local Application = State.Application
local Driver = State.Driver

local INVALID = 0xffffffff
local CONCERN_NONE = 0
local CONCERN_TOOLBAR = 1
local CONCERN_SIDEBAR = 2
local CONCERN_GRID = 3
local TOOL_COUNT = State.counts.tools
local NAV_COUNT = State.counts.navigation
local CARD_COUNT = State.counts.cards
local BAR_COUNT = State.counts.spark_bars

local NODE_TOOL_BASE = 100
local NODE_NAV_BASE = 200
local NODE_CARD_BASE = 1000
local CONTENT_TOOL_BASE = 101
local CONTENT_NAV_BASE = 110
local CONTENT_CARD_BASE = 120
local CONTENT_HEADER = 100
local CONTENT_SUBTITLE = 140
local DEFAULT_FONT = 1


local function contains(rect, x, y)
    return x >= rect.x and y >= rect.y
        and x < rect.x + rect.width and y < rect.y + rect.height
end

local function assign_rect(rect, x, y, width, height)
    rect.x, rect.y = x, y
    rect.width, rect.height = math.max(0, width), math.max(0, height)
end

function Host:initialize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    assert(logical_width > 0 and logical_height > 0, "logical dimensions must be positive")
    self.now_seconds, self.delta_seconds = 0, 0
    self.frame_index, self.event_count, self.present_count = 0, 0, 0
    self.logical_width, self.logical_height = logical_width, logical_height
    self.pixel_width, self.pixel_height, self.dpi_scale = pixel_width, pixel_height, dpi_scale
    self.focused, self.visible, self.quit_requested, self.redraw_requested = 1, 1, 0, 1
    return self
end

function Host:request_redraw() self.redraw_requested = 1 end
function Host:presented()
    self.present_count = self.present_count + 1
    self.redraw_requested = 0
end

function Input:initialize()
    self.pointer_x, self.pointer_y, self.pointer_dx, self.pointer_dy = 0, 0, 0, 0
    self.pointer_inside, self.pointer_revision, self.revision = 0, 0, 0
    return self
end

function TextMeasure:initialize()
    self.count, self.overflow_count, self.model_revision = 0, 0, 0
    self.revision, self.measure_count = 0, 0
    return self
end

function Paint:initialize()
    self.commit_count = 0
    return self
end

function Button:initialize(node, content)
    self.node = node
    self.content = content
    self.revision = 0
    self.enabled = 1
    self.hovered = 0
    self.pressed = 0
    self.selected = 0
    return self
end

function Button:set_hovered(value, parent, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.hovered == value then return unchanged(parent, dashboard, cc, self) end
    self.hovered = value
    self.revision = self.revision + 1
    return changed(parent, dashboard, cc, self)
end

function Button:set_pressed(value, parent, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.pressed == value then return unchanged(parent, dashboard, cc, self) end
    self.pressed = value
    self.revision = self.revision + 1
    return changed(parent, dashboard, cc, self)
end

function Button:activate(parent, dashboard, cc, changed, unchanged)
    if self.enabled == 0 then return unchanged(parent, dashboard, cc, self) end
    self.pressed = 0
    self.selected = 1
    self.revision = self.revision + 1
    return changed(parent, dashboard, cc, self)
end

function Button:set_selected(value, parent, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.selected == value then return unchanged(parent, dashboard, cc, self) end
    self.selected = value
    self.revision = self.revision + 1
    return changed(parent, dashboard, cc, self)
end

function SparkBar:initialize(value)
    self.value = value
    self.target = value
    self.revision = 0
    return self
end

function MetricCard:initialize(index)
    self.node = NODE_CARD_BASE + index
    self.title = CONTENT_CARD_BASE + index
    self.image = 1
    self.revision = 0
    self.hovered = 0
    self.pressed = 0
    self.selected = 0
    self.expanded = 0
    self.bar_cursor = 0
    self.reserved = 0
    for bar = 0, BAR_COUNT - 1 do
        self.bars[bar]:initialize(0.2 + ((index * 37 + bar * 19) % 79) / 100)
    end
    return self
end

function MetricCard:set_hovered(value, grid, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.hovered == value then return unchanged(grid, dashboard, cc, self) end
    self.hovered = value
    self.revision = self.revision + 1
    return changed(grid, dashboard, cc, self)
end

function MetricCard:set_pressed(value, grid, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.pressed == value then return unchanged(grid, dashboard, cc, self) end
    self.pressed = value
    self.revision = self.revision + 1
    return changed(grid, dashboard, cc, self)
end

function MetricCard:activate(grid, dashboard, cc, changed, unchanged)
    self.pressed = 0
    self.selected = 1
    self.expanded = self.expanded == 0 and 1 or 0
    self.revision = self.revision + 1
    return changed(grid, dashboard, cc, self)
end

function MetricCard:set_selected(value, grid, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.selected == value then return unchanged(grid, dashboard, cc, self) end
    self.selected = value
    self.revision = self.revision + 1
    return changed(grid, dashboard, cc, self)
end

function Toolbar:initialize()
    for index = 0, TOOL_COUNT - 1 do
        self.buttons[index]:initialize(NODE_TOOL_BASE + index, CONTENT_TOOL_BASE + index)
    end
    self.buttons[0].selected = 1
    self.revision = 0
    self.active_index = 0
    self.hovered_index = INVALID
    self.target_hover_index = INVALID
    self.target_active_index = 0
    self.projection_cursor = 0
    return self
end

function Sidebar:initialize()
    for index = 0, NAV_COUNT - 1 do
        self.items[index]:initialize(NODE_NAV_BASE + index, CONTENT_NAV_BASE + index)
    end
    self.items[0].selected = 1
    self.revision = 0
    self.selected_index = 0
    self.hovered_index = INVALID
    self.target_hover_index = INVALID
    self.target_selected_index = 0
    self.projection_cursor = 0
    return self
end

function CardGrid:initialize()
    for index = 0, CARD_COUNT - 1 do self.cards[index]:initialize(index) end
    self.scroll_offset = 0
    self.scroll_target = 0
    self.revision = 0
    self.selected_index = INVALID
    self.hovered_index = INVALID
    self.target_hover_index = INVALID
    self.target_selected_index = INVALID
    self.columns = 1
    self.projection_cursor = 0
    self.reserved = 0
    return self
end

function Header:initialize()
    self.title = CONTENT_HEADER
    self.subtitle = CONTENT_SUBTITLE
    self.revision = 0
    return self
end

function Workspace:initialize()
    self.header:initialize()
    self.grid:initialize()
    self.zoom = 1
    self.pan_x, self.pan_y = 0, 0
    self.revision = 0
    return self
end

function Status:initialize(content)
    self.content = content
    self.revision = 0
    return self
end

function Dashboard:initialize(status_content)
    self.toolbar:initialize()
    self.sidebar:initialize()
    self.workspace:initialize()
    self.status:initialize(status_content)
    self.revision = 0
    self.hovered_concern = CONCERN_NONE
    self.target_hover_concern = CONCERN_NONE
    self.projection_stage = 0
    self.route_changed = 0
    self.pressed_concern = CONCERN_NONE
    self.pressed_index = INVALID
    self.workspace_first_vertex = 0
    self.workspace_first_index = 0
    self.shell_text_count = 0
    self.reserved = 0
    return self
end

function ButtonLayout:solve(x, y, width, height, z_index)
    assign_rect(self.border, x, y, width, height)
    assign_rect(self.content, x + 12, y + 9, width - 24, height - 18)
    self.z_index = z_index
    self.visible = width > 0 and height > 0 and 1 or 0
    return self
end

function ToolbarLayout:solve(host, model, parent, cc, completed)
    local width = tonumber(host.logical_width)
    assign_rect(self.bounds, 0, 0, width, 56)
    local sidebar_width = math.min(210, math.max(156, width * 0.21))
    local button_width = math.min(92, math.max(64, (width - sidebar_width - 48) / TOOL_COUNT))
    for index = 0, TOOL_COUNT - 1 do
        self.buttons[index]:solve(sidebar_width + 18 + index * (button_width + 8),
            10, button_width, 36, 2)
    end
    self.revision = self.revision + 1
    return completed(parent, cc)
end

function SidebarLayout:solve(host, model, parent, cc, completed)
    local width, height = tonumber(host.logical_width), tonumber(host.logical_height)
    local sidebar_width = math.min(210, math.max(156, width * 0.21))
    assign_rect(self.bounds, 0, 56, sidebar_width, math.max(0, height - 84))
    for index = 0, NAV_COUNT - 1 do
        self.items[index]:solve(12, 74 + index * 48, sidebar_width - 24, 38, 2)
    end
    self.revision = self.revision + 1
    return completed(parent, cc)
end

function CardGridLayout:solve(bounds, model, parent, cc, completed)
    assign_rect(self.bounds, bounds.x, bounds.y, bounds.width, bounds.height)
    assign_rect(self.clip, bounds.x, bounds.y, bounds.width, bounds.height)
    local padding, gap = 18, 14
    local columns = math.floor((bounds.width - padding * 2 + gap) / (220 + gap))
    columns = math.max(1, math.min(4, columns))
    self.columns = columns
    model.columns = columns
    local card_width = math.max(120, (bounds.width - padding * 2 - gap * (columns - 1)) / columns)
    local card_height = 142
    local visible_count = 0
    for index = 0, CARD_COUNT - 1 do
        local column, row = index % columns, math.floor(index / columns)
        local x = bounds.x + padding + column * (card_width + gap)
        local y = bounds.y + padding + row * (card_height + gap) - model.scroll_offset
        local card = self.cards[index]
        assign_rect(card.bounds, x, y, card_width, card_height)
        assign_rect(card.image, x + card_width - 60, y + 10, 46, 46)
        card.z_index = 3
        card.visible = y + card_height > bounds.y and y < bounds.y + bounds.height and 1 or 0
        if card.visible ~= 0 then visible_count = visible_count + 1 end
        local chart_x, chart_y = x + 14, y + 66
        local chart_width, chart_height = math.max(20, card_width - 28), 58
        local bar_width = math.max(2, (chart_width - 27) / BAR_COUNT)
        for bar = 0, BAR_COUNT - 1 do
            local value = model.cards[index].bars[bar].value
            local bar_height = chart_height * value
            assign_rect(card.bars[bar].bar, chart_x + bar * (bar_width + 3),
                chart_y + chart_height - bar_height, bar_width, bar_height)
            card.bars[bar].visible = card.visible
            card.bars[bar].reserved = 0
        end
        card.revision = card.revision + 1
    end
    self.visible_count = visible_count
    self.revision = self.revision + 1
    return completed(parent, cc)
end

function WorkspaceLayout:solve(host, model, parent, cc, completed)
    local width, height = tonumber(host.logical_width), tonumber(host.logical_height)
    local sidebar_width = math.min(210, math.max(156, width * 0.21))
    assign_rect(self.bounds, sidebar_width, 56, width - sidebar_width, math.max(0, height - 84))
    assign_rect(self.header.bounds, sidebar_width, 56, width - sidebar_width, 70)
    self.header.revision = self.header.revision + 1
    local grid_bounds = self.grid.bounds
    assign_rect(grid_bounds, sidebar_width, 126, width - sidebar_width, math.max(0, height - 154))
    self.revision = self.revision + 1
    return self.grid:solve(grid_bounds, model.grid, parent, cc, completed)
end

function StatusLayout:solve(host, model, parent, cc, completed)
    local width, height = tonumber(host.logical_width), tonumber(host.logical_height)
    assign_rect(self.bounds, 0, height - 28, width, 28)
    self.revision = self.revision + 1
    return completed(parent, cc)
end

local dashboard_toolbar_laid_out
local dashboard_sidebar_laid_out
local dashboard_workspace_laid_out
local dashboard_status_laid_out

function DashboardLayout:initialize()
    self.revision = 0
    self.solve_count = 0
    return self
end

function DashboardLayout:solve(host, model, cc)
    return self.toolbar:solve(host, model.toolbar, self, cc, dashboard_toolbar_laid_out)
end

function DashboardLayout:toolbar_laid_out(cc)
    return self.sidebar:solve(cc.host, cc.dashboard.sidebar, self, cc, dashboard_sidebar_laid_out)
end

function DashboardLayout:sidebar_laid_out(cc)
    return self.workspace:solve(cc.host, cc.dashboard.workspace, self, cc, dashboard_workspace_laid_out)
end

function DashboardLayout:workspace_laid_out(cc)
    return self.status:solve(cc.host, cc.dashboard.status, self, cc, dashboard_status_laid_out)
end

function DashboardLayout:status_laid_out(cc)
    self.revision = self.revision + 1
    self.solve_count = self.solve_count + 1
    return cc:layout_ready()
end

dashboard_toolbar_laid_out = DashboardLayout.toolbar_laid_out
dashboard_sidebar_laid_out = DashboardLayout.sidebar_laid_out
dashboard_workspace_laid_out = DashboardLayout.workspace_laid_out
dashboard_status_laid_out = DashboardLayout.status_laid_out

local function set_vertex(vertex, x, y, rgba8)
    vertex.x, vertex.y, vertex.u, vertex.v = x, y, 0, 0
    vertex.rgba8, vertex.reserved = rgba8, 0
end

local function append_quad(frame, rect, rgba8)
    if frame.vertex_count + 4 > capacities.vertices
        or frame.index_count + 6 > capacities.indices then return false end
    local base, first = frame.vertex_count, frame.index_count
    set_vertex(frame.vertices[base], rect.x, rect.y, rgba8)
    set_vertex(frame.vertices[base + 1], rect.x + rect.width, rect.y, rgba8)
    set_vertex(frame.vertices[base + 2], rect.x + rect.width, rect.y + rect.height, rgba8)
    set_vertex(frame.vertices[base + 3], rect.x, rect.y + rect.height, rgba8)
    frame.indices[first], frame.indices[first + 1], frame.indices[first + 2] = base, base + 1, base + 2
    frame.indices[first + 3], frame.indices[first + 4], frame.indices[first + 5] = base, base + 2, base + 3
    frame.vertex_count, frame.index_count = base + 4, first + 6
    return true
end

local function append_text(frame, node, content, x, y, width, rgba8)
    if frame.text_draw_count >= capacities.text_draws then return false end
    local draw = frame.text_draws[frame.text_draw_count]
    draw.node, draw.content, draw.font, draw.text_resource = node, content, DEFAULT_FONT, 0
    draw.x, draw.y, draw.wrap_width = x, y, math.max(1, width)
    draw.opacity, draw.rgba8, draw.alignment = 1, rgba8, 0
    frame.text_draw_count = frame.text_draw_count + 1
    return true
end

local function append_image(frame, node, image, rect)
    if frame.image_draw_count >= capacities.image_draws then return false end
    local draw = frame.image_draws[frame.image_draw_count]
    draw.node, draw.image = node, image
    assign_rect(draw.source, 0, 0, 0, 0)
    assign_rect(draw.destination, rect.x, rect.y, rect.width, rect.height)
    draw.rotation, draw.opacity, draw.tint_rgba8, draw.reserved = 0, 0.92, 0xffffffff, 0
    frame.image_draw_count = frame.image_draw_count + 1
    return true
end

local function button_color(button)
    if button.pressed ~= 0 then return 0xf97360ff end
    if button.selected ~= 0 then return 0x4f8fefff end
    if button.hovered ~= 0 then return 0x465a73ff end
    return 0x2b3749ff
end

function Button:project(layout, parent, dashboard, cc, completed, rejected)
    local frame = cc.paint.frame
    if not append_quad(frame, layout.border, button_color(self))
        or not append_text(frame, self.node, self.content, layout.content.x, layout.content.y,
            layout.content.width, 0xe4edf9ff) then
        return rejected(cc, "button projection capacity exhausted")
    end
    return completed(parent, dashboard, cc, self)
end

local toolbar_button_projected
local sidebar_button_projected
local card_projected

function Toolbar:project(dashboard, cc)
    self.projection_cursor = 0
    return self:project_next(dashboard, cc)
end

function Toolbar:project_next(dashboard, cc)
    if self.projection_cursor >= TOOL_COUNT then return Dashboard.toolbar_projected(dashboard, cc, self) end
    local index = self.projection_cursor
    return self.buttons[index]:project(cc.layout.toolbar.buttons[index], self, dashboard, cc,
        toolbar_button_projected, Application.project_rejected)
end

function Toolbar:button_projected(dashboard, cc)
    self.projection_cursor = self.projection_cursor + 1
    return self:project_next(dashboard, cc)
end

function Sidebar:project(dashboard, cc)
    local frame = cc.paint.frame
    if not append_quad(frame, cc.layout.sidebar.bounds, 0x18202cff) then
        return Application.project_rejected(cc, "sidebar projection capacity exhausted")
    end
    self.projection_cursor = 0
    return self:project_next(dashboard, cc)
end

function Sidebar:project_next(dashboard, cc)
    if self.projection_cursor >= NAV_COUNT then return Dashboard.sidebar_projected(dashboard, cc, self) end
    local index = self.projection_cursor
    return self.items[index]:project(cc.layout.sidebar.items[index], self, dashboard, cc,
        sidebar_button_projected, Application.project_rejected)
end

function Sidebar:button_projected(dashboard, cc)
    self.projection_cursor = self.projection_cursor + 1
    return self:project_next(dashboard, cc)
end

local metric_bar_projected

function SparkBar:project(layout, rgba8, card, card_layout, grid, dashboard, cc,
        completed, card_completed, rejected)
    if layout.visible ~= 0 and not append_quad(cc.paint.frame, layout.bar, rgba8) then
        return rejected(cc, "spark bar projection capacity exhausted")
    end
    return completed(card, card_layout, grid, dashboard, cc, card_completed, rejected, self)
end

function MetricCard:project(layout, grid, dashboard, cc, completed, rejected)
    if layout.visible ~= 0 then
        local color = self.pressed ~= 0 and 0x513a40ff
            or self.selected ~= 0 and 0x263f5dff
            or self.hovered ~= 0 and 0x29384bff or 0x1c2736ff
        if not append_quad(cc.paint.frame, layout.bounds, color)
            or not append_image(cc.paint.frame, self.node, self.image, layout.image)
            or not append_text(cc.paint.frame, self.node, self.title,
                layout.bounds.x + 18, layout.bounds.y + 36, layout.bounds.width - 92, 0xcbd9ebff) then
            return rejected(cc, "card projection capacity exhausted")
        end
    end
    self.bar_cursor = 0
    return self:project_bar_next(layout, grid, dashboard, cc, completed, rejected)
end

function MetricCard:project_bar_next(layout, grid, dashboard, cc, completed, rejected)
    if self.bar_cursor >= BAR_COUNT then return completed(grid, dashboard, cc, self) end
    local index = self.bar_cursor
    local shade = 0x3f78c8ff + (index % 4) * 0x06040000
    return self.bars[index]:project(layout.bars[index], shade, self, layout, grid, dashboard, cc,
        metric_bar_projected, completed, rejected)
end

function MetricCard:bar_projected(layout, grid, dashboard, cc, completed, rejected)
    self.bar_cursor = self.bar_cursor + 1
    return self:project_bar_next(layout, grid, dashboard, cc, completed, rejected)
end

metric_bar_projected = MetricCard.bar_projected

function CardGrid:project(dashboard, cc)
    self.projection_cursor = 0
    return self:project_next(dashboard, cc)
end

function CardGrid:project_next(dashboard, cc)
    if self.projection_cursor >= CARD_COUNT then return Dashboard.grid_projected(dashboard, cc, self) end
    local index = self.projection_cursor
    return self.cards[index]:project(cc.layout.workspace.grid.cards[index], self, dashboard, cc,
        card_projected, Application.project_rejected)
end

function CardGrid:card_projected(dashboard, cc)
    self.projection_cursor = self.projection_cursor + 1
    return self:project_next(dashboard, cc)
end

toolbar_button_projected = Toolbar.button_projected
sidebar_button_projected = Sidebar.button_projected
card_projected = CardGrid.card_projected

function Header:project(layout, dashboard, cc)
    local frame = cc.paint.frame
    if not append_quad(frame, layout.bounds, 0x161f2dff)
        or not append_text(frame, 10, self.title, layout.bounds.x + 20, layout.bounds.y + 12,
            layout.bounds.width - 40, 0xf0f6ffff)
        or not append_text(frame, 10, self.subtitle, layout.bounds.x + 20, layout.bounds.y + 38,
            layout.bounds.width - 40, 0x8fa5c0ff) then
        return Application.project_rejected(cc, "header projection capacity exhausted")
    end
    return Dashboard.header_projected(dashboard, cc, self)
end

function Status:project(layout, dashboard, cc)
    if not append_quad(cc.paint.frame, layout.bounds, 0x202735ff)
        or not append_text(cc.paint.frame, 11, self.content, layout.bounds.x + 10,
            layout.bounds.y + 6, layout.bounds.width - 20, 0xdce8f7ff) then
        return Application.project_rejected(cc, "status projection capacity exhausted")
    end
    return Dashboard.status_projected(dashboard, cc, self)
end

function Dashboard:project(cc)
    local frame = cc.paint.frame
    frame.vertex_count, frame.index_count, frame.geometry_batch_count = 0, 0, 0
    frame.text_draw_count, frame.image_draw_count = 0, 0
    frame.clip_count = 0
    self.projection_stage = 1
    if not append_quad(frame, cc.layout.toolbar.bounds, 0x202938ff) then
        return Application.project_rejected(cc, "toolbar background capacity exhausted")
    end
    return self.toolbar:project(self, cc)
end

function Dashboard:toolbar_projected(cc)
    self.projection_stage = 2
    return self.sidebar:project(self, cc)
end

function Dashboard:sidebar_projected(cc)
    self.projection_stage = 3
    return self.status:project(cc.layout.status, self, cc)
end

function Dashboard:status_projected(cc)
    local frame = cc.paint.frame
    self.workspace_first_vertex = frame.vertex_count
    self.workspace_first_index = frame.index_count
    self.shell_text_count = frame.text_draw_count
    local bounds = cc.layout.workspace.bounds
    if not append_quad(frame, bounds, 0x0f1520ff) then
        return Application.project_rejected(cc, "workspace background capacity exhausted")
    end
    return self.workspace.header:project(cc.layout.workspace.header, self, cc)
end

function Dashboard:header_projected(cc)
    return self.workspace.grid:project(self, cc)
end

function Dashboard:grid_projected(cc)
    local frame = cc.paint.frame
    if frame.geometry_batches[1] == nil or frame.clips[0] == nil then
        return Application.project_rejected(cc, "component paint capacity exhausted")
    end

    local shell = frame.geometry_batches[0]
    shell.first_vertex, shell.vertex_count = 0, self.workspace_first_vertex
    shell.first_index, shell.index_count = 0, self.workspace_first_index
    shell.image, shell.shader, shell.topology, shell.blend_mode = 0, 0, 1, 1

    local workspace = frame.geometry_batches[1]
    workspace.first_vertex = self.workspace_first_vertex
    workspace.vertex_count = frame.vertex_count - self.workspace_first_vertex
    workspace.first_index = self.workspace_first_index
    workspace.index_count = frame.index_count - self.workspace_first_index
    workspace.image, workspace.shader, workspace.topology, workspace.blend_mode = 0, 0, 1, 1
    frame.geometry_batch_count = 2

    local clip = frame.clips[0]
    assign_rect(clip.rect, cc.layout.workspace.bounds.x, cc.layout.workspace.bounds.y,
        cc.layout.workspace.bounds.width, cc.layout.workspace.bounds.height)
    clip.radius, clip.kind, clip.revision = 0, 0, cc.layout.revision
    frame.clip_count = 1

    frame.layout_revision = cc.layout.revision
    frame.revision = frame.revision + 1
    cc.paint.commit_count = cc.paint.commit_count + 1
    self.projection_stage = 0
    return cc:paint_ready()
end

function Application:project_rejected(reason)
    self.rejection_count = self.rejection_count + 1
    error(reason, 2)
end

function Application:initialize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale,
        status_content)
    self.host:initialize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    self.input:initialize()
    self.dashboard:initialize(status_content)
    self.layout:initialize()
    self.text_measure:initialize()
    self.paint:initialize()
    self.rendered_revision = 0
    self.epoch, self.ignored_count = 0, 0
    self.component_change_count, self.layout_change_count = 0, 0
    self.paint_change_count, self.rejection_count = 0, 0
    return self.layout:solve(self.host, self.dashboard, self)
end

function Application:layout_ready()
    self.layout_change_count = self.layout_change_count + 1
    return self.dashboard:project(self)
end

function Application:paint_ready()
    self.paint_change_count = self.paint_change_count + 1
    self.host:request_redraw()
    return self
end

function Application:component_changed()
    self.component_change_count = self.component_change_count + 1
    self.dashboard.revision = self.dashboard.revision + 1
    return self.dashboard:project(self)
end

function Application:component_layout_changed()
    self.component_change_count = self.component_change_count + 1
    self.dashboard.revision = self.dashboard.revision + 1
    return self.layout:solve(self.host, self.dashboard, self)
end

function Application:component_unchanged()
    self.ignored_count = self.ignored_count + 1
    return false
end

local function button_index_at(layouts, count, x, y)
    for index = 0, count - 1 do
        if contains(layouts[index].border, x, y) then return index end
    end
    return INVALID
end

local function card_index_at(layout, x, y)
    for index = 0, CARD_COUNT - 1 do
        if layout.cards[index].visible ~= 0
            and contains(layout.cards[index].bounds, x, y) then return index end
    end
    return INVALID
end

local toolbar_old_hover_done
local toolbar_new_hover_done
local sidebar_old_hover_done
local sidebar_new_hover_done
local grid_old_hover_done
local grid_new_hover_done

function Toolbar:pointer_moved(input, layout, dashboard, cc)
    local target = button_index_at(layout.buttons, TOOL_COUNT, input.pointer_x, input.pointer_y)
    if target == self.hovered_index then return Dashboard.toolbar_pointer_unchanged(dashboard, cc, self) end
    self.target_hover_index = target
    if self.hovered_index ~= INVALID then
        return self.buttons[self.hovered_index]:set_hovered(
            false, self, dashboard, cc, toolbar_old_hover_done, toolbar_old_hover_done)
    end
    return self:old_hover_done(dashboard, cc)
end

function Toolbar:old_hover_done(dashboard, cc)
    if self.target_hover_index ~= INVALID then
        return self.buttons[self.target_hover_index]:set_hovered(
            true, self, dashboard, cc, toolbar_new_hover_done, toolbar_new_hover_done)
    end
    return self:new_hover_done(dashboard, cc)
end

function Toolbar:new_hover_done(dashboard, cc)
    self.hovered_index = self.target_hover_index
    self.revision = self.revision + 1
    return Dashboard.toolbar_pointer_changed(dashboard, cc, self)
end

function Sidebar:pointer_moved(input, layout, dashboard, cc)
    local target = button_index_at(layout.items, NAV_COUNT, input.pointer_x, input.pointer_y)
    if target == self.hovered_index then return Dashboard.sidebar_pointer_unchanged(dashboard, cc, self) end
    self.target_hover_index = target
    if self.hovered_index ~= INVALID then
        return self.items[self.hovered_index]:set_hovered(
            false, self, dashboard, cc, sidebar_old_hover_done, sidebar_old_hover_done)
    end
    return self:old_hover_done(dashboard, cc)
end

function Sidebar:old_hover_done(dashboard, cc)
    if self.target_hover_index ~= INVALID then
        return self.items[self.target_hover_index]:set_hovered(
            true, self, dashboard, cc, sidebar_new_hover_done, sidebar_new_hover_done)
    end
    return self:new_hover_done(dashboard, cc)
end

function Sidebar:new_hover_done(dashboard, cc)
    self.hovered_index = self.target_hover_index
    self.revision = self.revision + 1
    return Dashboard.sidebar_pointer_changed(dashboard, cc, self)
end

function CardGrid:pointer_moved(input, layout, dashboard, cc)
    local target = card_index_at(layout, input.pointer_x, input.pointer_y)
    if target == self.hovered_index then return Dashboard.grid_pointer_unchanged(dashboard, cc, self) end
    self.target_hover_index = target
    if self.hovered_index ~= INVALID then
        return self.cards[self.hovered_index]:set_hovered(
            false, self, dashboard, cc, grid_old_hover_done, grid_old_hover_done)
    end
    return self:old_hover_done(dashboard, cc)
end

function CardGrid:old_hover_done(dashboard, cc)
    if self.target_hover_index ~= INVALID then
        return self.cards[self.target_hover_index]:set_hovered(
            true, self, dashboard, cc, grid_new_hover_done, grid_new_hover_done)
    end
    return self:new_hover_done(dashboard, cc)
end

function CardGrid:new_hover_done(dashboard, cc)
    self.hovered_index = self.target_hover_index
    self.revision = self.revision + 1
    return Dashboard.grid_pointer_changed(dashboard, cc, self)
end

toolbar_old_hover_done = Toolbar.old_hover_done
toolbar_new_hover_done = Toolbar.new_hover_done
sidebar_old_hover_done = Sidebar.old_hover_done
sidebar_new_hover_done = Sidebar.new_hover_done
grid_old_hover_done = CardGrid.old_hover_done
grid_new_hover_done = CardGrid.new_hover_done

function Dashboard:pointer_moved(input, layout, cc)
    self.route_changed = 0
    if contains(layout.toolbar.bounds, input.pointer_x, input.pointer_y) then
        self.target_hover_concern = CONCERN_TOOLBAR
    elseif contains(layout.sidebar.bounds, input.pointer_x, input.pointer_y) then
        self.target_hover_concern = CONCERN_SIDEBAR
    elseif contains(layout.workspace.grid.bounds, input.pointer_x, input.pointer_y) then
        self.target_hover_concern = CONCERN_GRID
    else
        self.target_hover_concern = CONCERN_NONE
    end
    return self.toolbar:pointer_moved(input, layout.toolbar, self, cc)
end

function Dashboard:toolbar_pointer_changed(cc)
    self.route_changed = 1
    return self.sidebar:pointer_moved(cc.input, cc.layout.sidebar, self, cc)
end

function Dashboard:toolbar_pointer_unchanged(cc)
    return self.sidebar:pointer_moved(cc.input, cc.layout.sidebar, self, cc)
end

function Dashboard:sidebar_pointer_changed(cc)
    self.route_changed = 1
    return self.workspace.grid:pointer_moved(cc.input, cc.layout.workspace.grid, self, cc)
end

function Dashboard:sidebar_pointer_unchanged(cc)
    return self.workspace.grid:pointer_moved(cc.input, cc.layout.workspace.grid, self, cc)
end

function Dashboard:grid_pointer_changed(cc)
    self.route_changed = 1
    return self:pointer_routed(cc)
end

function Dashboard:grid_pointer_unchanged(cc) return self:pointer_routed(cc) end

function Dashboard:pointer_routed(cc)
    self.hovered_concern = self.target_hover_concern
    if self.route_changed == 0 then return cc:component_unchanged() end
    self.revision = self.revision + 1
    return cc:component_changed()
end

function Application:pointer_moved(owner, x, y, dx, dy)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    self.input.pointer_x, self.input.pointer_y = x, y
    self.input.pointer_dx, self.input.pointer_dy = dx, dy
    self.input.pointer_inside = 1
    self.input.pointer_revision = self.input.pointer_revision + 1
    self.input.revision = self.input.revision + 1
    return self.dashboard:pointer_moved(self.input, self.layout, self)
end

function Application:pointer_pressed(owner, button)
    if button ~= 1 then return self:component_unchanged() end
    local dashboard = self.dashboard
    local concern = dashboard.hovered_concern
    if concern == CONCERN_TOOLBAR then
        local index = dashboard.toolbar.hovered_index
        if index ~= INVALID then
            dashboard.pressed_concern, dashboard.pressed_index = concern, index
            return dashboard.toolbar.buttons[index]:set_pressed(
                true, dashboard.toolbar, dashboard, self, Toolbar.button_pressed, Toolbar.button_pressed)
        end
    elseif concern == CONCERN_SIDEBAR then
        local index = dashboard.sidebar.hovered_index
        if index ~= INVALID then
            dashboard.pressed_concern, dashboard.pressed_index = concern, index
            return dashboard.sidebar.items[index]:set_pressed(
                true, dashboard.sidebar, dashboard, self, Sidebar.button_pressed, Sidebar.button_pressed)
        end
    elseif concern == CONCERN_GRID then
        local index = dashboard.workspace.grid.hovered_index
        if index ~= INVALID then
            dashboard.pressed_concern, dashboard.pressed_index = concern, index
            return dashboard.workspace.grid.cards[index]:set_pressed(
                true, dashboard.workspace.grid, dashboard, self, CardGrid.card_pressed, CardGrid.card_pressed)
        end
    end
    return self:component_unchanged()
end

function Toolbar:button_pressed(dashboard, cc)
    self.revision = self.revision + 1
    return cc:component_changed()
end

function Sidebar:button_pressed(dashboard, cc)
    self.revision = self.revision + 1
    return cc:component_changed()
end

function CardGrid:card_pressed(dashboard, cc)
    self.revision = self.revision + 1
    return cc:component_changed()
end

function Application:pointer_released(owner, button)
    if button ~= 1 then return self:component_unchanged() end
    local dashboard = self.dashboard
    local concern, index = dashboard.pressed_concern, dashboard.pressed_index
    dashboard.pressed_concern, dashboard.pressed_index = CONCERN_NONE, INVALID
    if concern == CONCERN_TOOLBAR and index ~= INVALID then
        return dashboard.toolbar.buttons[index]:activate(
            dashboard.toolbar, dashboard, self, Toolbar.button_activated, Toolbar.button_activated)
    elseif concern == CONCERN_SIDEBAR and index ~= INVALID then
        return dashboard.sidebar.items[index]:activate(
            dashboard.sidebar, dashboard, self, Sidebar.button_activated, Sidebar.button_activated)
    elseif concern == CONCERN_GRID and index ~= INVALID then
        return dashboard.workspace.grid.cards[index]:activate(
            dashboard.workspace.grid, dashboard, self, CardGrid.card_activated, CardGrid.card_activated)
    end
    return self:component_unchanged()
end

local toolbar_old_selection_cleared
local sidebar_old_selection_cleared
local grid_old_selection_cleared

function Toolbar:button_activated(dashboard, cc, button)
    local index = tonumber(button.node) - NODE_TOOL_BASE
    self.target_active_index = index
    if self.active_index ~= INVALID and self.active_index ~= index then
        return self.buttons[self.active_index]:set_selected(
            false, self, dashboard, cc, toolbar_old_selection_cleared, toolbar_old_selection_cleared)
    end
    return self:old_selection_cleared(dashboard, cc)
end

function Toolbar:old_selection_cleared(dashboard, cc)
    self.active_index = self.target_active_index
    self.revision = self.revision + 1
    return cc:component_changed()
end

function Sidebar:button_activated(dashboard, cc, button)
    local index = tonumber(button.node) - NODE_NAV_BASE
    self.target_selected_index = index
    if self.selected_index ~= INVALID and self.selected_index ~= index then
        return self.items[self.selected_index]:set_selected(
            false, self, dashboard, cc, sidebar_old_selection_cleared, sidebar_old_selection_cleared)
    end
    return self:old_selection_cleared(dashboard, cc)
end

function Sidebar:old_selection_cleared(dashboard, cc)
    self.selected_index = self.target_selected_index
    self.revision = self.revision + 1
    return cc:component_changed()
end

function CardGrid:card_activated(dashboard, cc, card)
    local index = tonumber(card.node) - NODE_CARD_BASE
    self.target_selected_index = index
    if self.selected_index ~= INVALID and self.selected_index ~= index then
        return self.cards[self.selected_index]:set_selected(
            false, self, dashboard, cc, grid_old_selection_cleared, grid_old_selection_cleared)
    end
    return self:old_selection_cleared(dashboard, cc)
end

function CardGrid:old_selection_cleared(dashboard, cc)
    self.selected_index = self.target_selected_index
    self.revision = self.revision + 1
    return cc:component_changed()
end

toolbar_old_selection_cleared = Toolbar.old_selection_cleared
sidebar_old_selection_cleared = Sidebar.old_selection_cleared
grid_old_selection_cleared = CardGrid.old_selection_cleared

function Application:wheel_moved(owner, x, y)
    local grid = self.dashboard.workspace.grid
    grid.scroll_target = math.max(0, grid.scroll_target - y * 48)
    grid.scroll_offset = grid.scroll_target
    grid.revision = grid.revision + 1
    return self:component_layout_changed()
end

function Application:text_entered(owner, content)
    if self.dashboard.status.content == content then return self:component_unchanged() end
    self.dashboard.status.content = content
    self.dashboard.status.revision = self.dashboard.status.revision + 1
    return self:component_changed()
end

function Application:resize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    local changed = self.host.logical_width ~= logical_width or self.host.logical_height ~= logical_height
        or self.host.pixel_width ~= pixel_width or self.host.pixel_height ~= pixel_height
        or self.host.dpi_scale ~= dpi_scale
    if not changed then return self:component_unchanged() end
    self.host.logical_width, self.host.logical_height = logical_width, logical_height
    self.host.pixel_width, self.host.pixel_height = pixel_width, pixel_height
    self.host.dpi_scale = dpi_scale
    self.host.redraw_requested = 1
    return self.layout:solve(self.host, self.dashboard, self)
end

function Application:set_focus(owner, focused)
    local value = focused and 1 or 0
    if self.host.focused == value then return self:component_unchanged() end
    self.host.focused = value
    self.host.redraw_requested = 1
    return self:component_changed()
end

function Application:set_visible(owner, visible)
    local value = visible and 1 or 0
    if self.host.visible == value then return self:component_unchanged() end
    self.host.visible = value
    if value ~= 0 then self.host.redraw_requested = 1 end
    return true
end

function Application:invalidate(owner) self.host:request_redraw(); return true end

function Application:tick(owner, now_seconds, delta_seconds)
    self.host.now_seconds, self.host.delta_seconds = now_seconds, delta_seconds
    self.host.frame_index = self.host.frame_index + 1
    return self.host.redraw_requested ~= 0
end

function Application:draw(owner)
    local frame = self.paint.frame
    if self.host.redraw_requested == 0 and self.rendered_revision == frame.revision then return false end
    owner:begin_frame(self.host, frame)
    owner:upload_geometry(frame)
    owner:draw_geometry(frame, frame.geometry_batches[0])
    for index = 0, self.dashboard.shell_text_count - 1 do
        owner:draw_text(frame.text_draws[index])
    end
    owner:push_clip(frame.clips[0])
    owner:draw_geometry(frame, frame.geometry_batches[1])
    for index = 0, frame.image_draw_count - 1 do owner:draw_image(frame.image_draws[index]) end
    for index = self.dashboard.shell_text_count, frame.text_draw_count - 1 do
        owner:draw_text(frame.text_draws[index])
    end
    owner:pop_clip()
    owner:end_frame(self.host, frame)
    self.rendered_revision = frame.revision
    return true
end

function Application:rendered(owner) return true end
function Application:render_rejected(owner, reason) error(reason, 2) end

function Driver:initialize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale,
        status_content, bootstrap_presentations, metrics_enabled)
    self.turn_count, self.drained_event_count, self.ignored_event_count = 0, 0, 0
    self.render_turn_count, self.idle_turn_count, self.quit_turn_count = 0, 0, 0
    self.running, self.exit_code = 1, 0
    self.bootstrap_remaining, self.reserved = bootstrap_presentations or 0, 0
    self.metrics:initialize(metrics_enabled)
    self.application:initialize(owner, logical_width, logical_height, pixel_width, pixel_height,
        dpi_scale, status_content)
    return self
end

function DriverMetrics:initialize(enabled)
    for key in pairs(self) do
        if key ~= "name" then self[key] = 0 end
    end
    self.enabled = enabled and 1 or 0
    return self
end

function DriverMetrics:begin_turn(now, heap, uploads, draws, meshes, texts)
    self.turn_started_seconds, self.heap_started_kb = now, heap
    self.uploads_started, self.draws_started = uploads, draws
    self.mesh_rebuilds_started, self.text_rebuilds_started = meshes, texts
    self.last_drain_seconds, self.last_window_seconds = 0, 0
    self.last_tick_seconds, self.last_render_seconds, self.last_present_seconds = 0, 0, 0
end

local function record(metric, last, total, maximum, seconds)
    metric[last] = seconds
    metric[total] = metric[total] + seconds
    if seconds > metric[maximum] then metric[maximum] = seconds end
end

function DriverMetrics:record_drain(seconds)
    record(self, "last_drain_seconds", "total_drain_seconds", "max_drain_seconds", seconds)
end
function DriverMetrics:record_window(seconds)
    record(self, "last_window_seconds", "total_window_seconds", "max_window_seconds", seconds)
end
function DriverMetrics:record_tick(seconds)
    record(self, "last_tick_seconds", "total_tick_seconds", "max_tick_seconds", seconds)
end
function DriverMetrics:record_render(seconds)
    record(self, "last_render_seconds", "total_render_seconds", "max_render_seconds", seconds)
end
function DriverMetrics:record_present(seconds)
    record(self, "last_present_seconds", "total_present_seconds", "max_present_seconds", seconds)
end
function DriverMetrics:finish_turn(now, heap, uploads, draws, meshes, texts)
    record(self, "last_turn_seconds", "total_turn_seconds", "max_turn_seconds",
        math.max(0, now - self.turn_started_seconds))
    self.last_heap_delta_kb = heap - self.heap_started_kb
    if self.last_heap_delta_kb > self.max_heap_growth_kb then
        self.max_heap_growth_kb = self.last_heap_delta_kb
    end
    self.last_uploads, self.last_draws = uploads - self.uploads_started, draws - self.draws_started
    self.last_mesh_rebuilds = meshes - self.mesh_rebuilds_started
    self.last_text_rebuilds = texts - self.text_rebuilds_started
    self.upload_count, self.draw_count = uploads, draws
    self.mesh_rebuild_count, self.text_rebuild_count = meshes, texts
    self.measured_turns = self.measured_turns + 1
    if self.next_report_seconds == 0 then self.next_report_seconds = now + 1 end
end

function DriverMetrics:report_due(now) return now >= self.next_report_seconds end
function DriverMetrics:reported(now)
    self.report_count = self.report_count + 1
    self.next_report_seconds = now + 1
end

local driver_events_drained
local driver_quit_requested
local driver_window_sampled
local driver_time_sampled

function Driver:turn(owner, boundary)
    assert(self.running ~= 0, "cannot turn a stopped LÖVE driver")
    if self.metrics.enabled ~= 0 then
        local now, heap, uploads, draws, meshes, texts = boundary:metric_snapshot(self, owner)
        self.metrics:begin_turn(now, heap, uploads, draws, meshes, texts)
    end
    self.turn_count = self.turn_count + 1
    return boundary:drain_events(self, owner, driver_events_drained, driver_quit_requested)
end

function Driver:events_drained(owner, boundary, drained_count, ignored_count, drain_seconds)
    self.drained_event_count = self.drained_event_count + drained_count
    self.ignored_event_count = self.ignored_event_count + ignored_count
    if self.metrics.enabled ~= 0 then self.metrics:record_drain(drain_seconds) end
    return boundary:sample_window(self, owner, driver_window_sampled)
end

function Driver:quit_requested(owner, boundary, exit_code, drained_count, ignored_count, drain_seconds)
    self.drained_event_count = self.drained_event_count + drained_count
    self.ignored_event_count = self.ignored_event_count + ignored_count
    if self.metrics.enabled ~= 0 then self.metrics:record_drain(drain_seconds) end
    self.quit_turn_count, self.running, self.exit_code = self.quit_turn_count + 1, 0, exit_code
    self.application.host.quit_requested = 1
    self:finish_metrics(owner, boundary)
    boundary:on_quit(self, owner)
    return self
end

function Driver:window_sampled(owner, boundary, width, height, pixel_width, pixel_height, dpi,
        focused, visible, seconds)
    if self.metrics.enabled ~= 0 then self.metrics:record_window(seconds) end
    local app, host = self.application, self.application.host
    if host.logical_width ~= width or host.logical_height ~= height
        or host.pixel_width ~= pixel_width or host.pixel_height ~= pixel_height or host.dpi_scale ~= dpi then
        app:resize(owner, width, height, pixel_width, pixel_height, dpi)
    end
    if (host.focused ~= 0) ~= focused then app:set_focus(owner, focused) end
    if (host.visible ~= 0) ~= visible then app:set_visible(owner, visible) end
    return boundary:sample_time(self, owner, driver_time_sampled)
end

function Driver:time_sampled(owner, boundary, now, delta)
    local measured = self.metrics.enabled ~= 0
    local started = measured and boundary:clock(self, owner) or 0
    self.application:tick(owner, now, delta)
    if measured then self.metrics:record_tick(math.max(0, boundary:clock(self, owner) - started)) end
    if self.bootstrap_remaining ~= 0 then self.application:invalidate(owner) end
    return self:select_frame(owner, boundary)
end

function Driver:select_frame(owner, boundary)
    local app = self.application
    if boundary:graphics_active(self, owner) and app.host.visible ~= 0 and app.host.redraw_requested ~= 0 then
        return self:render(owner, boundary)
    end
    return self:idle(owner, boundary)
end

function Driver:render(owner, boundary)
    local measured = self.metrics.enabled ~= 0
    local started = measured and boundary:clock(self, owner) or 0
    if self.application:draw(owner) then
        if measured then self.metrics:record_render(math.max(0, boundary:clock(self, owner) - started)) end
        local present_started = measured and boundary:clock(self, owner) or 0
        boundary:present(self, owner)
        if measured then
            self.metrics:record_present(math.max(0, boundary:clock(self, owner) - present_started))
        end
        self.application.host:presented()
        self.render_turn_count = self.render_turn_count + 1
        if self.bootstrap_remaining ~= 0 then self.bootstrap_remaining = self.bootstrap_remaining - 1 end
    else
        self.idle_turn_count = self.idle_turn_count + 1
    end
    return self:completed(owner, boundary)
end

function Driver:idle(owner, boundary)
    self.idle_turn_count = self.idle_turn_count + 1
    return self:completed(owner, boundary)
end

function Driver:finish_metrics(owner, boundary)
    if self.metrics.enabled == 0 then return self end
    local now, heap, uploads, draws, meshes, texts = boundary:metric_snapshot(self, owner)
    self.metrics:finish_turn(now, heap, uploads, draws, meshes, texts)
    if self.metrics:report_due(now) then
        boundary:report_metrics(self, owner)
        self.metrics:reported(now)
    end
    return self
end

function Driver:completed(owner, boundary)
    self:finish_metrics(owner, boundary)
    boundary:sleep(self, owner)
    return self
end

function Driver:resize_damaged(owner) self.application:invalidate(owner); return self end
function Driver:focus_changed(owner, focused) self.application:set_focus(owner, focused); return self end
function Driver:visibility_changed(owner, visible) self.application:set_visible(owner, visible); return self end
function Driver:surface_damaged(owner) self.application:invalidate(owner); return self end
function Driver:pointer_moved(owner, x, y, dx, dy)
    self.application:pointer_moved(owner, x, y, dx, dy)
    return self
end
function Driver:pointer_pressed(owner, x, y, button)
    self.application:pointer_moved(owner, x, y, 0, 0)
    self.application:pointer_pressed(owner, button)
    return self
end
function Driver:pointer_released(owner, x, y, button)
    self.application:pointer_moved(owner, x, y, 0, 0)
    self.application:pointer_released(owner, button)
    return self
end
function Driver:wheel_moved(owner, x, y) self.application:wheel_moved(owner, x, y); return self end

driver_events_drained = Driver.events_drained
driver_quit_requested = Driver.quit_requested
driver_window_sampled = Driver.window_sampled
driver_time_sampled = Driver.time_sampled

function Driver:text_entered(owner, text)
    local content = owner:append_content(self.application.dashboard.status.content, text)
    self.application:text_entered(owner, content)
    return self
end

State:seal()

State.CONCERN_NONE = CONCERN_NONE
State.CONCERN_TOOLBAR = CONCERN_TOOLBAR
State.CONCERN_SIDEBAR = CONCERN_SIDEBAR
State.CONCERN_GRID = CONCERN_GRID
State.INVALID_INDEX = INVALID

return State
end
