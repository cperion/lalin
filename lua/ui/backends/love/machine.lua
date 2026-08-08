local bit = require("bit")
local ffi = require("ffi")
local State = require("ui.backends.love.state")

local S = State.Context
local Host = State.Host
local Input = State.Input
local Interaction = State.Interaction
local ToolbarModel = State.ToolbarModel
local WorkspaceModel = State.WorkspaceModel
local StatusModel = State.StatusModel
local TextMeasure = State.TextMeasure
local Layout = State.Layout
local Paint = State.Paint
local GeometryRenderer = State.GeometryRenderer
local TextRenderer = State.TextRenderer
local ImageRenderer = State.ImageRenderer
local ClipRenderer = State.ClipRenderer
local LayerRenderer = State.LayerRenderer
local Renderer = State.Renderer
local Application = State.Application
local DriverMetrics = State.DriverMetrics
local Driver = State.Driver

local NODE_NONE = 0
local NODE_TOOLBAR = 1
local NODE_WORKSPACE = 2
local NODE_STATUS = 3
local NODE_SIDEBAR = 4
local NODE_HEADER = 5
local TOOL_BASE = 100
local NAV_BASE = 200
local CARD_BASE = 1000
local DECOR_GRID_BASE = 10000
local DECOR_ACCENT_BASE = 12000
local DECOR_BAR_BASE = 20000
local DECOR_BADGE_BASE = 30000
local TOOL_COUNT = 4
local NAV_COUNT = 7
local CARD_COUNT = 12
local FLAG_HITTABLE = 1
local FLAG_WORKSPACE = 2
local CONTENT_HEADER = 100
local CONTENT_TOOL_BASE = 101
local CONTENT_NAV_BASE = 110
local CONTENT_CARD_BASE = 120
local CONTENT_SUBTITLE = 140
local DEFAULT_FONT = 1

local DRAG_IDLE = 0
local DRAG_PENDING = 1
local DRAGGING = 2

local SEGMENT_GEOMETRY = 1
local SEGMENT_TEXT = 2
local SEGMENT_IMAGE = 3
local SEGMENT_CLIP_PUSH = 4
local SEGMENT_CLIP_POP = 5
local SEGMENT_LAYER_PUSH = 6
local SEGMENT_LAYER_POP = 7

local TOPOLOGY_TRIANGLES = 1
local BLEND_ALPHA = 1

local function same_number(a, b) return tonumber(a) == tonumber(b) end

function Host:initialize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    assert(logical_width > 0 and logical_height > 0, "logical dimensions must be positive")
    assert(pixel_width > 0 and pixel_height > 0, "pixel dimensions must be positive")
    assert(dpi_scale > 0, "DPI scale must be positive")
    self.now_seconds = 0
    self.delta_seconds = 0
    self.frame_index = 0
    self.event_count = 0
    self.present_count = 0
    self.logical_width = logical_width
    self.logical_height = logical_height
    self.pixel_width = pixel_width
    self.pixel_height = pixel_height
    self.dpi_scale = dpi_scale
    self.focused = 1
    self.visible = 1
    self.quit_requested = 0
    self.redraw_requested = 1
    return self
end

function Host:begin_tick(now_seconds, delta_seconds, owner, parent, completed)
    self.now_seconds = now_seconds
    self.delta_seconds = delta_seconds
    self.frame_index = self.frame_index + 1
    return completed(parent, owner)
end

function Host:resize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale,
        owner, parent, changed, unchanged)
    if self.logical_width == logical_width
        and self.logical_height == logical_height
        and self.pixel_width == pixel_width
        and self.pixel_height == pixel_height
        and self.dpi_scale == dpi_scale then
        return unchanged(parent, owner)
    end
    self.logical_width = logical_width
    self.logical_height = logical_height
    self.pixel_width = pixel_width
    self.pixel_height = pixel_height
    self.dpi_scale = dpi_scale
    self.redraw_requested = 1
    return changed(parent, owner)
end

function Host:set_focus(focused, owner, parent, changed, unchanged)
    local value = focused and 1 or 0
    if self.focused == value then return unchanged(parent, owner) end
    self.focused = value
    self.redraw_requested = 1
    return changed(parent, owner)
end

function Host:set_visible(visible, owner, parent, changed, unchanged)
    local value = visible and 1 or 0
    if self.visible == value then return unchanged(parent, owner) end
    self.visible = value
    if value ~= 0 then self.redraw_requested = 1 end
    return changed(parent, owner)
end

function Host:request_redraw() self.redraw_requested = 1 end

function Host:presented()
    self.present_count = self.present_count + 1
    self.redraw_requested = 0
end

function Input:initialize()
    self.pointer_x, self.pointer_y = 0, 0
    self.pointer_dx, self.pointer_dy = 0, 0
    self.wheel_x, self.wheel_y = 0, 0
    self.revision = 0
    self.pointer_revision = 0
    self.key_revision = 0
    self.text_revision = 0
    self.button_mask = 0
    self.modifiers = 0
    self.pointer_inside = 0
    self.text_input_active = 0
    return self
end

function Input:pointer_moved(x, y, dx, dy, owner, parent, accepted)
    self.pointer_x, self.pointer_y = x, y
    self.pointer_dx, self.pointer_dy = dx, dy
    self.pointer_inside = 1
    self.revision = self.revision + 1
    self.pointer_revision = self.pointer_revision + 1
    return accepted(parent, owner)
end

function Input:pointer_pressed(button, owner, parent, accepted)
    assert(button >= 1 and button <= 32, "pointer button outside mask")
    self.button_mask = bit.bor(self.button_mask, bit.lshift(1, button - 1))
    self.revision = self.revision + 1
    self.pointer_revision = self.pointer_revision + 1
    return accepted(parent, owner)
end

function Input:pointer_released(button, owner, parent, accepted)
    assert(button >= 1 and button <= 32, "pointer button outside mask")
    self.button_mask = bit.band(self.button_mask, bit.bnot(bit.lshift(1, button - 1)))
    self.revision = self.revision + 1
    self.pointer_revision = self.pointer_revision + 1
    return accepted(parent, owner)
end

function Input:wheel_moved(x, y, owner, parent, accepted)
    self.wheel_x, self.wheel_y = x, y
    self.revision = self.revision + 1
    self.pointer_revision = self.pointer_revision + 1
    return accepted(parent, owner)
end

function Input:key_changed(modifiers, owner, parent, accepted)
    self.modifiers = modifiers
    self.revision = self.revision + 1
    self.key_revision = self.key_revision + 1
    return accepted(parent, owner)
end

function Input:text_entered(content, owner, parent, accepted)
    self.revision = self.revision + 1
    self.text_revision = self.text_revision + 1
    return accepted(parent, owner, content)
end

function Input:set_text_input(active)
    self.text_input_active = active and 1 or 0
end

function ToolbarModel:select(tool, owner, parent, changed, unchanged)
    assert(tool >= 1 and tool <= 4, "toolbar tool outside concrete range")
    if self.active_tool == tool then return unchanged(parent, owner) end
    self.active_tool = tool
    self.revision = self.revision + 1
    return changed(parent, owner)
end

function WorkspaceModel:zoom_by(delta, owner, parent, changed, unchanged)
    if delta == 0 then return unchanged(parent, owner) end
    local zoom = self.zoom + delta
    if zoom < 0.25 then zoom = 0.25 end
    if zoom > 8 then zoom = 8 end
    if zoom == self.zoom then return unchanged(parent, owner) end
    self.zoom = zoom
    self.revision = self.revision + 1
    return changed(parent, owner)
end

function WorkspaceModel:select(node, owner, parent, changed, unchanged)
    if same_number(self.selection, node) then return unchanged(parent, owner) end
    self.selection = node
    self.revision = self.revision + 1
    return changed(parent, owner)
end

function StatusModel:set_content(content, owner, parent, changed, unchanged)
    if same_number(self.content, content) then return unchanged(parent, owner) end
    self.content = content
    self.revision = self.revision + 1
    return changed(parent, owner)
end

function TextMeasure:initialize()
    self.count = 0
    self.overflow_count = 0
    self.model_revision = 0
    self.revision = 0
    self.measure_count = 0
    return self
end

function TextMeasure:synchronize(model, host, owner, parent, completed, rejected)
    if model.status.content == 0 then
        self.count = 0
        self.model_revision = model.revision
        self.revision = self.revision + 1
        return completed(parent, owner)
    end
    if State.capacities.text_metrics < 1 then
        self.overflow_count = self.overflow_count + 1
        return rejected(parent, owner, "text metric capacity exhausted")
    end

    local metric = self.items[0]
    local font_size = 14
    local wrap_width = math.max(1, host.logical_width - 16)
    local width, height, baseline, line_height, line_count =
        owner:measure_text(model.status.content, DEFAULT_FONT, font_size, wrap_width)
    if width == nil or height == nil or baseline == nil or line_height == nil or line_count == nil then
        return rejected(parent, owner, "LÖVE text measurement rejected")
    end

    metric.node = NODE_STATUS
    metric.content = model.status.content
    metric.font = DEFAULT_FONT
    metric.font_size = font_size
    metric.wrap_width = wrap_width
    metric.measured_width = width
    metric.measured_height = height
    metric.baseline = baseline
    metric.line_height = line_height
    metric.line_count = line_count
    metric.input_revision = model.status.revision
    metric.output_revision = self.revision + 1

    self.count = 1
    self.model_revision = model.revision
    self.revision = self.revision + 1
    self.measure_count = self.measure_count + 1
    return completed(parent, owner)
end

function Layout:initialize()
    self.box_count = 0
    self.overflow_count = 0
    self.model_revision = 0
    self.interaction_revision = 0
    self.text_revision = 0
    self.revision = 0
    self.solve_count = 0
    return self
end

local function set_box(box, node, parent_index, z_index, x, y, width, height, flags)
    box.node = node
    box.parent_index = parent_index
    box.z_index = z_index
    box.border_rect.x, box.border_rect.y = x, y
    box.border_rect.width, box.border_rect.height = math.max(0, width), math.max(0, height)
    box.content_rect.x, box.content_rect.y = x, y
    box.content_rect.width, box.content_rect.height = math.max(0, width), math.max(0, height)
    box.clip_index = 0
    box.flags = flags
end

local function append_box(layout, node, parent_index, z_index, x, y, width, height, flags)
    local index = tonumber(layout.box_count)
    if index >= State.capacities.layout_boxes then
        layout.overflow_count = layout.overflow_count + 1
        return -1
    end
    set_box(layout.boxes[index], node, parent_index, z_index, x, y, width, height, flags)
    layout.box_count = index + 1
    return index
end

function Layout:solve(host, model, interaction, text_measure, parent, owner, completed, rejected)
    local overflow_before = self.overflow_count
    self.box_count = 0

    local width, height = tonumber(host.logical_width), tonumber(host.logical_height)
    local toolbar_height = 56
    local status_height = 28
    local sidebar_width = math.min(210, math.max(156, width * 0.21))
    local body_y = toolbar_height
    local body_height = math.max(0, height - toolbar_height - status_height)
    local workspace_x = sidebar_width
    local workspace_width = math.max(0, width - sidebar_width)
    local root = 0xffffffff

    local toolbar_index = append_box(self, NODE_TOOLBAR, root, 0,
        0, 0, width, toolbar_height, FLAG_HITTABLE)
    local sidebar_index = append_box(self, NODE_SIDEBAR, root, 0,
        0, body_y, sidebar_width, body_height, FLAG_HITTABLE)
    append_box(self, NODE_STATUS, root, 0,
        0, height - status_height, width, status_height, FLAG_HITTABLE)

    local tool_width = math.min(92, math.max(64, (width - sidebar_width - 48) / TOOL_COUNT))
    for tool = 0, TOOL_COUNT - 1 do
        append_box(self, TOOL_BASE + tool, toolbar_index, 2,
            sidebar_width + 18 + tool * (tool_width + 8), 10, tool_width, 36, FLAG_HITTABLE)
    end

    for item = 0, NAV_COUNT - 1 do
        append_box(self, NAV_BASE + item, sidebar_index, 2,
            12, body_y + 18 + item * 48, sidebar_width - 24, 38, FLAG_HITTABLE)
    end

    local workspace_index = append_box(self, NODE_WORKSPACE, root, 0,
        workspace_x, body_y, workspace_width, body_height, FLAG_HITTABLE + FLAG_WORKSPACE)
    local header_height = 70
    append_box(self, NODE_HEADER, workspace_index, 1,
        workspace_x, body_y, workspace_width, header_height, FLAG_HITTABLE + FLAG_WORKSPACE)

    local content_y = body_y + header_height
    for line = 0, 11 do
        local x = workspace_x + line * math.max(1, workspace_width / 11)
        append_box(self, DECOR_GRID_BASE + line, workspace_index, 0,
            x, content_y, 1, math.max(0, body_height - header_height), FLAG_WORKSPACE)
    end
    for line = 0, 7 do
        local y = content_y + line * 48
        append_box(self, DECOR_GRID_BASE + 100 + line, workspace_index, 0,
            workspace_x, y, workspace_width, 1, FLAG_WORKSPACE)
    end

    local padding, gap = 18, 14
    local columns = math.floor((workspace_width - padding * 2 + gap) / (220 + gap))
    columns = math.max(1, math.min(4, columns))
    local card_width = math.max(120, (workspace_width - padding * 2 - gap * (columns - 1)) / columns)
    local card_height = 142
    for card = 0, CARD_COUNT - 1 do
        local column = card % columns
        local row = math.floor(card / columns)
        local x = workspace_x + padding + column * (card_width + gap)
        local y = content_y + padding + row * (card_height + gap)
        local card_index = append_box(self, CARD_BASE + card, workspace_index, 3,
            x, y, card_width, card_height, FLAG_HITTABLE + FLAG_WORKSPACE)
        append_box(self, DECOR_ACCENT_BASE + card, card_index, 4,
            x + 12, y + 12, 6, 34, FLAG_WORKSPACE)
        append_box(self, DECOR_BADGE_BASE + card, card_index, 4,
            x + 26, y + 14, math.max(20, card_width * 0.28), 14, FLAG_WORKSPACE)

        local chart_x, chart_y = x + 14, y + 66
        local chart_width, chart_height = math.max(20, card_width - 28), 58
        local bar_gap = 3
        local bar_width = math.max(2, (chart_width - bar_gap * 9) / 10)
        for bar = 0, 9 do
            local value = 0.2 + ((card * 37 + bar * 19) % 79) / 100
            local bar_height = chart_height * value
            append_box(self, DECOR_BAR_BASE + card * 16 + bar, card_index, 4,
                chart_x + bar * (bar_width + bar_gap), chart_y + chart_height - bar_height,
                bar_width, bar_height, FLAG_WORKSPACE)
        end
    end

    if self.overflow_count ~= overflow_before then
        return rejected(parent, owner, "layout capacity exhausted")
    end
    self.model_revision = model.revision
    self.interaction_revision = interaction.layout_revision
    self.text_revision = text_measure.revision
    self.revision = self.revision + 1
    self.solve_count = self.solve_count + 1
    return completed(parent, owner)
end

function Layout:find_box(node)
    for index = 0, self.box_count - 1 do
        if same_number(self.boxes[index].node, node) then return index end
    end
    return 0xffffffff
end

function Layout:hit_test(x, y)
    for index = self.box_count - 1, 0, -1 do
        local box = self.boxes[index]
        local rect = box.border_rect
        if bit.band(box.flags, FLAG_HITTABLE) ~= 0
            and x >= rect.x and y >= rect.y
            and x < rect.x + rect.width and y < rect.y + rect.height then
            return tonumber(box.node)
        end
    end
    return NODE_NONE
end

function Interaction:initialize()
    self.hover = NODE_NONE
    self.focus = NODE_NONE
    self.pressed = NODE_NONE
    self.captured = NODE_NONE
    self.drop_target = NODE_NONE
    self.drag.kind = DRAG_IDLE
    self.drag.payload.idle.revision = 0
    self.revision = 0
    self.visual_revision = 0
    self.layout_revision = 0
    return self
end

function Interaction:pointer_moved(input, layout, owner, parent, visual_changed, unchanged)
    local hit = layout:hit_test(input.pointer_x, input.pointer_y)
    local changed = not same_number(self.hover, hit)
    if changed then self.hover = hit end

    if self.drag.kind == DRAG_PENDING then
        local pending = self.drag.payload.pending
        local dx = input.pointer_x - pending.press_x
        local dy = input.pointer_y - pending.press_y
        if dx * dx + dy * dy >= pending.threshold_squared then
            local source = pending.source
            local revision = pending.revision + 1
            self.drag.kind = DRAGGING
            self.drag.payload.dragging.source = source
            self.drag.payload.dragging.target = hit
            self.drag.payload.dragging.origin_x = pending.press_x
            self.drag.payload.dragging.origin_y = pending.press_y
            self.drag.payload.dragging.current_x = input.pointer_x
            self.drag.payload.dragging.current_y = input.pointer_y
            self.drag.payload.dragging.revision = revision
            changed = true
        end
    elseif self.drag.kind == DRAGGING then
        local dragging = self.drag.payload.dragging
        dragging.current_x = input.pointer_x
        dragging.current_y = input.pointer_y
        dragging.target = hit
        dragging.revision = dragging.revision + 1
        changed = true
    end

    if not changed then return unchanged(parent, owner) end
    self.revision = self.revision + 1
    self.visual_revision = self.visual_revision + 1
    return visual_changed(parent, owner)
end

function Interaction:pointer_pressed(input, layout, owner, parent, visual_changed)
    local hit = layout:hit_test(input.pointer_x, input.pointer_y)
    self.hover = hit
    self.pressed = hit
    self.captured = hit
    self.focus = hit
    self.drag.kind = DRAG_PENDING
    self.drag.payload.pending.source = hit
    self.drag.payload.pending.press_x = input.pointer_x
    self.drag.payload.pending.press_y = input.pointer_y
    self.drag.payload.pending.threshold_squared = 36
    self.drag.payload.pending.revision = self.revision + 1
    self.revision = self.revision + 1
    self.visual_revision = self.visual_revision + 1
    return visual_changed(parent, owner)
end

function Interaction:pointer_released(input, layout, owner, parent,
        activated, visual_changed, unchanged)
    local hit = layout:hit_test(input.pointer_x, input.pointer_y)
    local pressed = tonumber(self.pressed)
    local had_state = pressed ~= NODE_NONE or self.drag.kind ~= DRAG_IDLE
    self.hover = hit
    self.pressed = NODE_NONE
    self.captured = NODE_NONE
    self.drop_target = NODE_NONE
    self.drag.kind = DRAG_IDLE
    self.drag.payload.idle.revision = self.revision + 1
    if not had_state then return unchanged(parent, owner) end
    self.revision = self.revision + 1
    self.visual_revision = self.visual_revision + 1
    if pressed == hit and hit ~= NODE_NONE then return activated(parent, owner, hit) end
    return visual_changed(parent, owner)
end

function Interaction:focus_lost(owner, parent, visual_changed, unchanged)
    local had_state = self.focus ~= 0 or self.pressed ~= 0 or self.captured ~= 0
        or self.drag.kind ~= DRAG_IDLE
    self.focus = NODE_NONE
    self.pressed = NODE_NONE
    self.captured = NODE_NONE
    self.drop_target = NODE_NONE
    self.drag.kind = DRAG_IDLE
    self.drag.payload.idle.revision = self.revision + 1
    if not had_state then return unchanged(parent, owner) end
    self.revision = self.revision + 1
    self.visual_revision = self.visual_revision + 1
    return visual_changed(parent, owner)
end

local function set_vertex(vertex, x, y, rgba8)
    vertex.x, vertex.y = x, y
    vertex.u, vertex.v = 0, 0
    vertex.rgba8 = rgba8
    vertex.reserved = 0
end

local function append_quad(frame, x, y, width, height, rgba8)
    if frame.vertex_count + 4 > State.capacities.vertices
        or frame.index_count + 6 > State.capacities.indices then
        return false
    end
    local base = frame.vertex_count
    set_vertex(frame.vertices[base], x, y, rgba8)
    set_vertex(frame.vertices[base + 1], x + width, y, rgba8)
    set_vertex(frame.vertices[base + 2], x + width, y + height, rgba8)
    set_vertex(frame.vertices[base + 3], x, y + height, rgba8)
    local first = frame.index_count
    frame.indices[first] = base
    frame.indices[first + 1] = base + 1
    frame.indices[first + 2] = base + 2
    frame.indices[first + 3] = base
    frame.indices[first + 4] = base + 2
    frame.indices[first + 5] = base + 3
    frame.vertex_count = base + 4
    frame.index_count = first + 6
    return true
end

local function in_node_range(node, first, count) return node >= first and node < first + count end

local function workspace_node(node)
    return node == NODE_WORKSPACE or node == NODE_HEADER
        or in_node_range(node, CARD_BASE, CARD_COUNT)
end

local function box_color(node, model, interaction)
    if same_number(interaction.pressed, node) then return 0xf97360ff end
    if same_number(interaction.hover, node) and bit.band(node, 1) == 0 then return 0x51647fff end
    if same_number(interaction.hover, node) then return 0x465a73ff end
    if node == NODE_TOOLBAR then return 0x202938ff end
    if node == NODE_SIDEBAR then return 0x18202cff end
    if node == NODE_STATUS then return 0x202735ff end
    if node == NODE_WORKSPACE then return 0x0f1520ff end
    if node == NODE_HEADER then return 0x161f2dff end
    if in_node_range(node, TOOL_BASE, TOOL_COUNT) then
        local selected = node - TOOL_BASE + 1 == model.toolbar.active_tool
        return selected and 0x4f8fefff or 0x2b3749ff
    end
    if in_node_range(node, NAV_BASE, NAV_COUNT) then
        return same_number(model.workspace.selection, node) and 0x334f70ff or 0x222d3cff
    end
    if in_node_range(node, CARD_BASE, CARD_COUNT) then
        return same_number(model.workspace.selection, node) and 0x263f5dff or 0x1c2736ff
    end
    if in_node_range(node, DECOR_GRID_BASE, 200) then return 0x26314255 end
    if in_node_range(node, DECOR_ACCENT_BASE, CARD_COUNT) then
        local shade = (node - DECOR_ACCENT_BASE) % 4
        return 0x4f8fefff + shade * 0x08070000
    end
    if in_node_range(node, DECOR_BADGE_BASE, CARD_COUNT) then return 0x34445aff end
    if in_node_range(node, DECOR_BAR_BASE, CARD_COUNT * 16) then
        local zoom_phase = math.floor(model.workspace.zoom * 4)
        local shade = (math.floor((node - DECOR_BAR_BASE) / 16) + zoom_phase) % 4
        return 0x3f78c8ff + shade * 0x09050000
    end
    return 0x252a33ff
end

function Paint:initialize()
    local frame = self.frame
    frame.vertex_count = 0
    frame.index_count = 0
    frame.geometry_batch_count = 0
    frame.text_draw_count = 0
    frame.image_draw_count = 0
    frame.clip_count = 0
    frame.layer_count = 0
    frame.segment_count = 0
    frame.overflow_count = 0
    frame.layout_revision = 0
    frame.revision = 0
    self.commit_count = 0
    return self
end

local function append_segment(frame, kind, item_index)
    if frame.segment_count >= State.capacities.segments then return false end
    local segment = frame.segments[frame.segment_count]
    segment.kind, segment.item_index = kind, item_index
    frame.segment_count = frame.segment_count + 1
    return true
end

local function append_geometry_batch(frame, first_vertex, first_index)
    if frame.geometry_batch_count >= State.capacities.geometry_batches then return false end
    local index = frame.geometry_batch_count
    local batch = frame.geometry_batches[index]
    batch.first_vertex = first_vertex
    batch.vertex_count = frame.vertex_count - first_vertex
    batch.first_index = first_index
    batch.index_count = frame.index_count - first_index
    batch.image = 0
    batch.shader = 0
    batch.topology = TOPOLOGY_TRIANGLES
    batch.blend_mode = BLEND_ALPHA
    frame.geometry_batch_count = index + 1
    return append_segment(frame, SEGMENT_GEOMETRY, index)
end

local function append_text_projection(frame, node, content, x, y, width, rgba8)
    if frame.text_draw_count >= State.capacities.text_draws then return false end
    local index = frame.text_draw_count
    local draw = frame.text_draws[index]
    draw.node = node
    draw.content = content
    draw.font = DEFAULT_FONT
    draw.text_resource = 0
    draw.x, draw.y = x, y
    draw.wrap_width = math.max(1, width)
    draw.opacity = 1
    draw.rgba8 = rgba8
    draw.alignment = 0
    frame.text_draw_count = index + 1
    return append_segment(frame, SEGMENT_TEXT, index)
end

function Paint:commit(layout, model, interaction, text_measure, parent, owner, completed, rejected)
    local frame = self.frame
    frame.vertex_count = 0
    frame.index_count = 0
    frame.geometry_batch_count = 0
    frame.text_draw_count = 0
    frame.image_draw_count = 0
    frame.clip_count = 0
    frame.layer_count = 0
    frame.segment_count = 0

    local first_vertex, first_index = frame.vertex_count, frame.index_count
    for index = 0, layout.box_count - 1 do
        local box = layout.boxes[index]
        if bit.band(tonumber(box.flags), FLAG_WORKSPACE) == 0 then
            local rect = box.border_rect
            if not append_quad(frame, rect.x, rect.y, rect.width, rect.height,
                    box_color(tonumber(box.node), model, interaction)) then
                frame.overflow_count = frame.overflow_count + 1
                return rejected(parent, owner, "shell geometry capacity exhausted")
            end
        end
    end
    if not append_geometry_batch(frame, first_vertex, first_index) then
        return rejected(parent, owner, "shell paint spine capacity exhausted")
    end
    for tool = 0, TOOL_COUNT - 1 do
        local index = layout:find_box(TOOL_BASE + tool)
        local rect = layout.boxes[index].content_rect
        if not append_text_projection(frame, TOOL_BASE + tool, CONTENT_TOOL_BASE + tool,
                rect.x + 12, rect.y + 10, rect.width - 24, 0xe4edf9ff) then
            return rejected(parent, owner, "toolbar text capacity exhausted")
        end
    end
    for item = 0, NAV_COUNT - 1 do
        local index = layout:find_box(NAV_BASE + item)
        local rect = layout.boxes[index].content_rect
        if not append_text_projection(frame, NAV_BASE + item, CONTENT_NAV_BASE + item,
                rect.x + 14, rect.y + 10, rect.width - 28, 0xb9c8dcff) then
            return rejected(parent, owner, "navigation text capacity exhausted")
        end
    end

    local workspace_index = layout:find_box(NODE_WORKSPACE)
    if workspace_index == 0xffffffff then
        return rejected(parent, owner, "workspace layout box missing")
    end
    local workspace_rect = layout.boxes[workspace_index].border_rect
    local clip = frame.clips[0]
    clip.rect = workspace_rect
    clip.radius = 0
    clip.kind = 0
    clip.revision = layout.revision
    frame.clip_count = 1

    local layer = frame.layers[0]
    layer.canvas = 1
    layer.bounds.x, layer.bounds.y = 0, 0
    layer.bounds.width = layout.boxes[0].border_rect.width
    local status_index = layout:find_box(NODE_STATUS)
    if status_index == 0xffffffff then return rejected(parent, owner, "status layout box missing") end
    local status_rect = layout.boxes[status_index].border_rect
    layer.bounds.height = status_rect.y + status_rect.height
    layer.opacity = 0.98
    layer.blend_mode = BLEND_ALPHA
    layer.revision = layout.revision
    frame.layer_count = 1

    if not append_segment(frame, SEGMENT_LAYER_PUSH, 0)
        or not append_segment(frame, SEGMENT_CLIP_PUSH, 0) then
        return rejected(parent, owner, "workspace boundary spine capacity exhausted")
    end

    first_vertex, first_index = frame.vertex_count, frame.index_count
    for index = 0, layout.box_count - 1 do
        local box = layout.boxes[index]
        if bit.band(tonumber(box.flags), FLAG_WORKSPACE) ~= 0 then
            local rect = box.border_rect
            if not append_quad(frame, rect.x, rect.y, rect.width, rect.height,
                    box_color(tonumber(box.node), model, interaction)) then
                frame.overflow_count = frame.overflow_count + 1
                return rejected(parent, owner, "workspace geometry capacity exhausted")
            end
        end
    end
    if not append_geometry_batch(frame, first_vertex, first_index) then
        return rejected(parent, owner, "workspace paint spine capacity exhausted")
    end

    for index = 0, layout.box_count - 1 do
        local box = layout.boxes[index]
        local node = tonumber(box.node)
        if in_node_range(node, CARD_BASE, CARD_COUNT) then
            if frame.image_draw_count >= State.capacities.image_draws then
                return rejected(parent, owner, "image projection capacity exhausted")
            end
            local image_index = frame.image_draw_count
            local draw = frame.image_draws[image_index]
            local rect = box.border_rect
            draw.node = node
            draw.image = 1
            draw.source.x, draw.source.y, draw.source.width, draw.source.height = 0, 0, 0, 0
            draw.destination.x, draw.destination.y = rect.x + rect.width - 60, rect.y + 10
            draw.destination.width, draw.destination.height = 46, 46
            draw.rotation = 0
            draw.opacity = 0.92
            draw.tint_rgba8 = 0xffffffff
            draw.reserved = 0
            frame.image_draw_count = image_index + 1
            if not append_segment(frame, SEGMENT_IMAGE, image_index) then
                return rejected(parent, owner, "image spine capacity exhausted")
            end
        end
    end

    local header_index = layout:find_box(NODE_HEADER)
    local header_rect = layout.boxes[header_index].content_rect
    if not append_text_projection(frame, NODE_HEADER, CONTENT_HEADER,
            header_rect.x + 20, header_rect.y + 12, header_rect.width - 40, 0xf0f6ffff)
        or not append_text_projection(frame, NODE_HEADER, CONTENT_SUBTITLE,
            header_rect.x + 20, header_rect.y + 38, header_rect.width - 40, 0x8fa5c0ff) then
        return rejected(parent, owner, "workspace header text capacity exhausted")
    end
    for card = 0, CARD_COUNT - 1 do
        local node = CARD_BASE + card
        local index = layout:find_box(node)
        local rect = layout.boxes[index].content_rect
        if not append_text_projection(frame, node, CONTENT_CARD_BASE + card,
                rect.x + 26, rect.y + 36, rect.width - 96, 0xcbd9ebff) then
            return rejected(parent, owner, "card text capacity exhausted")
        end
    end

    if not append_segment(frame, SEGMENT_CLIP_POP, 0)
        or not append_segment(frame, SEGMENT_LAYER_POP, 0) then
        return rejected(parent, owner, "workspace completion spine capacity exhausted")
    end

    if text_measure.count > 0 then
        local metric = text_measure.items[0]
        local status_box = layout.boxes[status_index].content_rect
        if not append_text_projection(frame, metric.node, metric.content,
                status_box.x + 10,
                status_box.y + math.max(0, (status_box.height - metric.line_height) * 0.5),
                status_box.width - 20, 0xdce8f7ff) then
            return rejected(parent, owner, "status text capacity exhausted")
        end
    end

    frame.layout_revision = layout.revision
    frame.revision = frame.revision + 1
    self.commit_count = self.commit_count + 1
    return completed(parent, owner)
end

function GeometryRenderer:initialize()
    self.mesh = 0
    self.shader = 0
    self.uploaded_revision = 0
    self.draw_count = 0
    self.uploaded_vertices = 0
    self.uploaded_indices = 0
    return self
end

function GeometryRenderer:prepare(owner, projection, renderer, parent, completed, rejected, next)
    if self.uploaded_revision ~= projection.revision then
        owner:upload_geometry(projection)
        self.uploaded_revision = projection.revision
        self.uploaded_vertices = self.uploaded_vertices + projection.vertex_count
        self.uploaded_indices = self.uploaded_indices + projection.index_count
    end
    return next(renderer, owner, projection, parent, completed, rejected)
end

function GeometryRenderer:submit(owner, projection, item_index, renderer, parent,
        completed, rejected, next, failed)
    if item_index >= projection.geometry_batch_count then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "geometry batch index outside projection")
    end
    owner:draw_geometry(projection, projection.geometry_batches[item_index])
    self.draw_count = self.draw_count + 1
    return next(renderer, owner, projection, parent, completed, rejected)
end

function TextRenderer:initialize()
    self.drawn_revision = 0
    self.draw_count = 0
    self.rebuilt_count = 0
    return self
end

function TextRenderer:submit(owner, projection, item_index, renderer, parent,
        completed, rejected, next, failed)
    if item_index >= projection.text_draw_count then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "text draw index outside projection")
    end
    owner:draw_text(projection.text_draws[item_index])
    self.drawn_revision = projection.revision
    self.draw_count = self.draw_count + 1
    return next(renderer, owner, projection, parent, completed, rejected)
end

function ImageRenderer:initialize()
    self.sprite_batch = 0
    self.drawn_revision = 0
    self.draw_count = 0
    self.rebuilt_count = 0
    return self
end

function ImageRenderer:submit(owner, projection, item_index, renderer, parent,
        completed, rejected, next, failed)
    if item_index >= projection.image_draw_count then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "image draw index outside projection")
    end
    owner:draw_image(projection.image_draws[item_index])
    self.drawn_revision = projection.revision
    self.draw_count = self.draw_count + 1
    return next(renderer, owner, projection, parent, completed, rejected)
end

function ClipRenderer:initialize()
    self.depth = 0
    self.maximum_depth = 0
    self.change_count = 0
    return self
end

function ClipRenderer:push(owner, projection, item_index, renderer, parent,
        completed, rejected, next, failed)
    if item_index >= projection.clip_count then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "clip index outside projection")
    end
    if self.depth >= State.capacities.clip_depth then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "clip stack exhausted")
    end
    local clip = projection.clips[item_index]
    self.stack[self.depth] = clip.rect
    self.depth = self.depth + 1
    if self.depth > self.maximum_depth then self.maximum_depth = self.depth end
    self.change_count = self.change_count + 1
    owner:push_clip(clip)
    return next(renderer, owner, projection, parent, completed, rejected)
end

function ClipRenderer:pop(owner, projection, renderer, parent, completed, rejected, next, failed)
    if self.depth == 0 then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "clip stack underflow")
    end
    self.depth = self.depth - 1
    self.change_count = self.change_count + 1
    owner:pop_clip()
    return next(renderer, owner, projection, parent, completed, rejected)
end

function LayerRenderer:initialize()
    self.depth = 0
    self.maximum_depth = 0
    self.change_count = 0
    return self
end

function LayerRenderer:push(owner, projection, item_index, renderer, parent,
        completed, rejected, next, failed)
    if item_index >= projection.layer_count then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "layer index outside projection")
    end
    if self.depth >= State.capacities.layer_depth then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "layer stack exhausted")
    end
    local layer = projection.layers[item_index]
    self.stack[self.depth] = layer.canvas
    self.depth = self.depth + 1
    if self.depth > self.maximum_depth then self.maximum_depth = self.depth end
    self.change_count = self.change_count + 1
    owner:push_layer(layer)
    return next(renderer, owner, projection, parent, completed, rejected)
end

function LayerRenderer:pop(owner, projection, renderer, parent, completed, rejected, next, failed)
    if self.depth == 0 then
        return failed(renderer, owner, projection, parent, completed, rejected,
            "layer stack underflow")
    end
    self.depth = self.depth - 1
    self.change_count = self.change_count + 1
    owner:pop_layer()
    return next(renderer, owner, projection, parent, completed, rejected)
end

local renderer_geometry_ready
local renderer_after_segment
local renderer_rejected

function Renderer:initialize()
    self.geometry:initialize()
    self.text:initialize()
    self.image:initialize()
    self.clip:initialize()
    self.layer:initialize()
    self.segment_cursor = 0
    self.rejected_segment = 0xffffffff
    self.projection_revision = 0
    self.rendered_revision = 0
    self.frame_count = 0
    self.rejection_count = 0
    return self
end

function Renderer:render(owner, host, projection, parent, completed, rejected)
    self.segment_cursor = 0
    self.rejected_segment = 0xffffffff
    self.projection_revision = projection.revision
    owner:begin_frame(host, projection)
    return self.geometry:prepare(owner, projection, self, parent, completed, rejected,
        renderer_geometry_ready)
end

function Renderer:geometry_ready(owner, projection, parent, completed, rejected)
    return self:advance(owner, projection, parent, completed, rejected)
end

function Renderer:advance(owner, projection, parent, completed, rejected)
    if self.segment_cursor >= projection.segment_count then
        if self.clip.depth ~= 0 then
            return self:reject(owner, parent, rejected, "unbalanced clip stack")
        end
        if self.layer.depth ~= 0 then
            return self:reject(owner, parent, rejected, "unbalanced layer stack")
        end
        owner:end_frame()
        self.rendered_revision = projection.revision
        self.frame_count = self.frame_count + 1
        return completed(parent, owner)
    end

    local segment = projection.segments[self.segment_cursor]
    local kind = segment.kind
    if kind == SEGMENT_GEOMETRY then
        return self.geometry:submit(owner, projection, segment.item_index, self, parent,
            completed, rejected, renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_TEXT then
        return self.text:submit(owner, projection, segment.item_index, self, parent,
            completed, rejected, renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_IMAGE then
        return self.image:submit(owner, projection, segment.item_index, self, parent,
            completed, rejected, renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_CLIP_PUSH then
        return self.clip:push(owner, projection, segment.item_index, self, parent,
            completed, rejected, renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_CLIP_POP then
        return self.clip:pop(owner, projection, self, parent, completed, rejected,
            renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_LAYER_PUSH then
        return self.layer:push(owner, projection, segment.item_index, self, parent,
            completed, rejected, renderer_after_segment, renderer_rejected)
    elseif kind == SEGMENT_LAYER_POP then
        return self.layer:pop(owner, projection, self, parent, completed, rejected,
            renderer_after_segment, renderer_rejected)
    end
    return self:reject(owner, parent, rejected, "unknown paint segment kind")
end

function Renderer:after_segment(owner, projection, parent, completed, rejected)
    self.segment_cursor = self.segment_cursor + 1
    return self:advance(owner, projection, parent, completed, rejected)
end

function Renderer:rejected(owner, _projection, parent, _completed, rejected, reason)
    return self:reject(owner, parent, rejected, reason)
end

function Renderer:reject(owner, parent, rejected, reason)
    self.rejected_segment = self.segment_cursor
    self.rejection_count = self.rejection_count + 1
    return rejected(parent, owner, reason)
end

renderer_geometry_ready = Renderer.geometry_ready
renderer_after_segment = Renderer.after_segment
renderer_rejected = Renderer.rejected

local app_initialized_text
local app_initialized_layout
local app_initialized_paint
local app_input_moved
local app_input_pressed
local app_input_released
local app_input_wheel
local app_input_text
local app_interaction_visual
local app_interaction_unchanged
local app_activated
local app_tool_changed
local app_workspace_changed
local app_model_unchanged_visual
local app_text_changed
local app_text_ready
local app_layout_ready
local app_paint_ready
local app_resize_changed
local app_resize_unchanged
local app_focus_changed
local app_focus_unchanged
local app_visible_changed
local app_visible_unchanged
local app_rendered
local app_render_rejected
local app_tick_ready

function Application:initialize(owner, logical_width, logical_height, pixel_width, pixel_height,
        dpi_scale, status_content)
    self.host:initialize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    self.input:initialize()
    self.interaction:initialize()
    self.model.toolbar.active_tool = 1
    self.model.toolbar.hovered_tool = 0
    self.model.toolbar.revision = 1
    self.model.workspace.pan_x = 0
    self.model.workspace.pan_y = 0
    self.model.workspace.zoom = 1
    self.model.workspace.selection = 0
    self.model.workspace.revision = 1
    self.model.status.content = status_content or 0
    self.model.status.revision = 1
    self.model.revision = 1
    self.text_measure:initialize()
    self.layout:initialize()
    self.paint:initialize()
    self.renderer:initialize()
    self.epoch = 0
    self.ignored_count = 0
    self.local_visual_change_count = 0
    self.model_change_count = 0
    self.text_change_count = 0
    self.layout_change_count = 0
    self.suspension_count = 0
    return self.text_measure:synchronize(
        self.model, self.host, owner, self, app_initialized_text, app_render_rejected)
end

function Application:initialized_text(owner)
    return self.layout:solve(self.host, self.model, self.interaction, self.text_measure,
        self, owner, app_initialized_layout, app_render_rejected)
end

function Application:initialized_layout(owner)
    return self.paint:commit(self.layout, self.model, self.interaction, self.text_measure,
        self, owner, app_initialized_paint, app_render_rejected)
end

function Application:initialized_paint(_owner) return self end

function Application:pointer_moved(owner, x, y, dx, dy)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    return self.input:pointer_moved(x, y, dx, dy, owner, self, app_input_moved)
end

function Application:input_moved(owner)
    return self.interaction:pointer_moved(
        self.input, self.layout, owner, self, app_interaction_visual, app_interaction_unchanged)
end

function Application:pointer_pressed(owner, button)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    return self.input:pointer_pressed(button, owner, self, app_input_pressed)
end

function Application:input_pressed(owner)
    return self.interaction:pointer_pressed(
        self.input, self.layout, owner, self, app_interaction_visual)
end

function Application:pointer_released(owner, button)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    return self.input:pointer_released(button, owner, self, app_input_released)
end

function Application:input_released(owner)
    return self.interaction:pointer_released(self.input, self.layout, owner, self,
        app_activated, app_interaction_visual, app_interaction_unchanged)
end

function Application:interaction_visual(owner)
    return self:local_visual_changed(owner)
end

function Application:interaction_unchanged(_owner)
    self.ignored_count = self.ignored_count + 1
    return false
end

function Application:activated(owner, node)
    if in_node_range(node, TOOL_BASE, TOOL_COUNT) then
        return self.model.toolbar:select(
            node - TOOL_BASE + 1, owner, self, app_tool_changed, app_model_unchanged_visual)
    end
    if workspace_node(node) or in_node_range(node, NAV_BASE, NAV_COUNT) then
        return self.model.workspace:select(
            node, owner, self, app_workspace_changed, app_model_unchanged_visual)
    end
    return self:local_visual_changed(owner)
end

function Application:tool_changed(owner)
    self.model.revision = self.model.revision + 1
    self.model_change_count = self.model_change_count + 1
    return self:local_visual_changed(owner)
end

function Application:workspace_changed(owner)
    self.model.revision = self.model.revision + 1
    self.model_change_count = self.model_change_count + 1
    return self:local_visual_changed(owner)
end

function Application:model_unchanged_visual(owner) return self:local_visual_changed(owner) end

function Application:wheel_moved(owner, x, y)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    return self.input:wheel_moved(x, y, owner, self, app_input_wheel)
end

function Application:input_wheel(owner)
    local hover = tonumber(self.interaction.hover)
    if not workspace_node(hover) then
        self.ignored_count = self.ignored_count + 1
        return false
    end
    return self.model.workspace:zoom_by(
        self.input.wheel_y * 0.1, owner, self, app_workspace_changed, app_interaction_unchanged)
end

function Application:text_entered(owner, content)
    self.epoch = self.epoch + 1
    self.host.event_count = self.host.event_count + 1
    return self.input:text_entered(content, owner, self, app_input_text)
end

function Application:input_text(owner, content)
    return self.model.status:set_content(
        content, owner, self, app_text_changed, app_interaction_unchanged)
end

function Application:text_changed(owner)
    self.model.revision = self.model.revision + 1
    self.text_change_count = self.text_change_count + 1
    return self.text_measure:synchronize(
        self.model, self.host, owner, self, app_text_ready, app_render_rejected)
end

function Application:text_ready(owner)
    return self.layout:solve(self.host, self.model, self.interaction, self.text_measure,
        self, owner, app_layout_ready, app_render_rejected)
end

function Application:resize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    self.epoch = self.epoch + 1
    return self.host:resize(logical_width, logical_height, pixel_width, pixel_height, dpi_scale,
        owner, self, app_resize_changed, app_resize_unchanged)
end

function Application:resize_changed(owner)
    self.layout_change_count = self.layout_change_count + 1
    return self.layout:solve(self.host, self.model, self.interaction, self.text_measure,
        self, owner, app_layout_ready, app_render_rejected)
end

function Application:resize_unchanged(_owner)
    self.ignored_count = self.ignored_count + 1
    return false
end

function Application:set_focus(owner, focused)
    return self.host:set_focus(focused, owner, self, app_focus_changed, app_focus_unchanged)
end

function Application:set_visible(owner, visible)
    return self.host:set_visible(
        visible, owner, self, app_visible_changed, app_visible_unchanged)
end

function Application:visible_changed(_owner) return self.host.visible ~= 0 end

function Application:visible_unchanged(_owner)
    self.ignored_count = self.ignored_count + 1
    return false
end

function Application:invalidate(_owner)
    self.host:request_redraw()
    return true
end

function Application:focus_changed(owner)
    if self.host.focused == 0 then
        return self.interaction:focus_lost(
            owner, self, app_interaction_visual, app_interaction_unchanged)
    end
    return self:local_visual_changed(owner)
end

function Application:focus_unchanged(_owner)
    self.ignored_count = self.ignored_count + 1
    return false
end

function Application:local_visual_changed(owner)
    self.local_visual_change_count = self.local_visual_change_count + 1
    self.host:request_redraw()
    return self.paint:commit(self.layout, self.model, self.interaction, self.text_measure,
        self, owner, app_paint_ready, app_render_rejected)
end

function Application:layout_ready(owner)
    self.layout_change_count = self.layout_change_count + 1
    return self.paint:commit(self.layout, self.model, self.interaction, self.text_measure,
        self, owner, app_paint_ready, app_render_rejected)
end

function Application:paint_ready(_owner)
    self.host:request_redraw()
    return true
end

function Application:tick(owner, now_seconds, delta_seconds)
    return self.host:begin_tick(now_seconds, delta_seconds, owner, self, app_tick_ready)
end

function Application:tick_ready(_owner) return self.host.redraw_requested ~= 0 end

function Application:draw(owner)
    if self.host.redraw_requested == 0
        and self.renderer.rendered_revision == self.paint.frame.revision then
        self.ignored_count = self.ignored_count + 1
        return false
    end
    return self.renderer:render(owner, self.host, self.paint.frame,
        self, app_rendered, app_render_rejected)
end

function Application:rendered(_owner) return true end

function Application:render_rejected(_owner, reason) error(reason, 2) end

function DriverMetrics:initialize(enabled)
    ffi.fill(self, ffi.sizeof(self), 0)
    self.enabled = enabled and 1 or 0
    return self
end

function DriverMetrics:begin_turn(now_seconds, heap_kb, uploads, draws, mesh_rebuilds, text_rebuilds)
    self.turn_started_seconds = now_seconds
    self.heap_started_kb = heap_kb
    self.uploads_started = uploads
    self.draws_started = draws
    self.mesh_rebuilds_started = mesh_rebuilds
    self.text_rebuilds_started = text_rebuilds
    self.last_drain_seconds = 0
    self.last_window_seconds = 0
    self.last_tick_seconds = 0
    self.last_render_seconds = 0
    self.last_present_seconds = 0
end

function DriverMetrics:record_drain(seconds)
    self.last_drain_seconds = seconds
    self.total_drain_seconds = self.total_drain_seconds + seconds
    if seconds > self.max_drain_seconds then self.max_drain_seconds = seconds end
end

function DriverMetrics:record_window(seconds)
    self.last_window_seconds = seconds
    self.total_window_seconds = self.total_window_seconds + seconds
    if seconds > self.max_window_seconds then self.max_window_seconds = seconds end
end

function DriverMetrics:record_tick(seconds)
    self.last_tick_seconds = seconds
    self.total_tick_seconds = self.total_tick_seconds + seconds
    if seconds > self.max_tick_seconds then self.max_tick_seconds = seconds end
end

function DriverMetrics:record_render(seconds)
    self.last_render_seconds = seconds
    self.total_render_seconds = self.total_render_seconds + seconds
    if seconds > self.max_render_seconds then self.max_render_seconds = seconds end
end

function DriverMetrics:record_present(seconds)
    self.last_present_seconds = seconds
    self.total_present_seconds = self.total_present_seconds + seconds
    if seconds > self.max_present_seconds then self.max_present_seconds = seconds end
end

function DriverMetrics:finish_turn(now_seconds, heap_kb, uploads, draws, mesh_rebuilds, text_rebuilds)
    local seconds = math.max(0, now_seconds - self.turn_started_seconds)
    self.last_turn_seconds = seconds
    self.total_turn_seconds = self.total_turn_seconds + seconds
    if seconds > self.max_turn_seconds then self.max_turn_seconds = seconds end
    self.last_heap_delta_kb = heap_kb - self.heap_started_kb
    if self.last_heap_delta_kb > self.max_heap_growth_kb then
        self.max_heap_growth_kb = self.last_heap_delta_kb
    end
    self.last_uploads = uploads - self.uploads_started
    self.last_draws = draws - self.draws_started
    self.last_mesh_rebuilds = mesh_rebuilds - self.mesh_rebuilds_started
    self.last_text_rebuilds = text_rebuilds - self.text_rebuilds_started
    self.upload_count = uploads
    self.draw_count = draws
    self.mesh_rebuild_count = mesh_rebuilds
    self.text_rebuild_count = text_rebuilds
    self.measured_turns = self.measured_turns + 1
    if self.next_report_seconds == 0 then self.next_report_seconds = now_seconds + 1 end
end

function DriverMetrics:report_due(now_seconds) return now_seconds >= self.next_report_seconds end

function DriverMetrics:reported(now_seconds)
    self.report_count = self.report_count + 1
    self.next_report_seconds = now_seconds + 1
end
local driver_events_drained
local driver_quit_requested
local driver_window_sampled
local driver_time_sampled

function Driver:initialize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale,
        status_content, bootstrap_presentations, metrics_enabled)
    self.turn_count = 0
    self.drained_event_count = 0
    self.ignored_event_count = 0
    self.render_turn_count = 0
    self.idle_turn_count = 0
    self.quit_turn_count = 0
    self.running = 1
    self.exit_code = 0
    self.bootstrap_remaining = bootstrap_presentations or 0
    self.reserved = 0
    self.metrics:initialize(metrics_enabled)
    self.application:initialize(owner, logical_width, logical_height, pixel_width, pixel_height,
        dpi_scale, status_content)
    return self
end

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
    self.quit_turn_count = self.quit_turn_count + 1
    self.running = 0
    self.exit_code = exit_code
    self.application.host.quit_requested = 1
    self:finish_metrics(owner, boundary)
    boundary:on_quit(self, owner)
    return self
end

function Driver:window_sampled(owner, boundary, logical_width, logical_height, pixel_width, pixel_height,
        dpi_scale, focused, visible, window_seconds)
    if self.metrics.enabled ~= 0 then self.metrics:record_window(window_seconds) end
    local app = self.application
    local host = app.host
    if host.logical_width ~= logical_width
        or host.logical_height ~= logical_height
        or host.pixel_width ~= pixel_width
        or host.pixel_height ~= pixel_height
        or host.dpi_scale ~= dpi_scale then
        app:resize(owner, logical_width, logical_height, pixel_width, pixel_height, dpi_scale)
    end
    if (host.focused ~= 0) ~= focused then app:set_focus(owner, focused) end
    if (host.visible ~= 0) ~= visible then app:set_visible(owner, visible) end
    return boundary:sample_time(self, owner, driver_time_sampled)
end

function Driver:time_sampled(owner, boundary, now_seconds, delta_seconds)
    local app = self.application
    local started = self.metrics.enabled ~= 0 and boundary:clock(self, owner) or 0
    app:tick(owner, now_seconds, delta_seconds)
    if self.metrics.enabled ~= 0 then
        self.metrics:record_tick(math.max(0, boundary:clock(self, owner) - started))
    end
    if self.bootstrap_remaining ~= 0 then app:invalidate(owner) end
    return self:select_frame(owner, boundary)
end

function Driver:select_frame(owner, boundary)
    local app = self.application
    if boundary:graphics_active(self, owner)
        and app.host.visible ~= 0 and app.host.redraw_requested ~= 0 then
        return self:render(owner, boundary)
    end
    return self:idle(owner, boundary)
end

function Driver:render(owner, boundary)
    local measured = self.metrics.enabled ~= 0
    local render_started = measured and boundary:clock(self, owner) or 0
    if self.application:draw(owner) then
        if measured then
            self.metrics:record_render(math.max(0, boundary:clock(self, owner) - render_started))
        end
        local present_started = measured and boundary:clock(self, owner) or 0
        boundary:present(self, owner)
        if measured then
            self.metrics:record_present(math.max(0, boundary:clock(self, owner) - present_started))
        end
        self.application.host:presented()
        self.render_turn_count = self.render_turn_count + 1
        if self.bootstrap_remaining ~= 0 then
            self.bootstrap_remaining = self.bootstrap_remaining - 1
        end
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

function Driver:resize_damaged(owner)
    self.application:invalidate(owner)
    return self
end

function Driver:focus_changed(owner, focused)
    self.application:set_focus(owner, focused)
    return self
end

function Driver:visibility_changed(owner, visible)
    self.application:set_visible(owner, visible)
    return self
end

function Driver:surface_damaged(owner)
    self.application:invalidate(owner)
    return self
end

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

function Driver:wheel_moved(owner, x, y)
    self.application:wheel_moved(owner, x, y)
    return self
end

function Driver:text_entered(owner, text)
    local content = owner:append_content(self.application.model.status.content, text)
    self.application:text_entered(owner, content)
    return self
end

driver_events_drained = Driver.events_drained
driver_quit_requested = Driver.quit_requested
driver_window_sampled = Driver.window_sampled
driver_time_sampled = Driver.time_sampled

app_initialized_text = Application.initialized_text
app_initialized_layout = Application.initialized_layout
app_initialized_paint = Application.initialized_paint
app_input_moved = Application.input_moved
app_input_pressed = Application.input_pressed
app_input_released = Application.input_released
app_input_wheel = Application.input_wheel
app_input_text = Application.input_text
app_interaction_visual = Application.interaction_visual
app_interaction_unchanged = Application.interaction_unchanged
app_activated = Application.activated
app_tool_changed = Application.tool_changed
app_workspace_changed = Application.workspace_changed
app_model_unchanged_visual = Application.model_unchanged_visual
app_text_changed = Application.text_changed
app_text_ready = Application.text_ready
app_layout_ready = Application.layout_ready
app_paint_ready = Application.paint_ready
app_resize_changed = Application.resize_changed
app_resize_unchanged = Application.resize_unchanged
app_focus_changed = Application.focus_changed
app_focus_unchanged = Application.focus_unchanged
app_visible_changed = Application.visible_changed
app_visible_unchanged = Application.visible_unchanged
app_rendered = Application.rendered
app_render_rejected = Application.render_rejected
app_tick_ready = Application.tick_ready

S:seal()

State.NODE_NONE = NODE_NONE
State.NODE_TOOLBAR = NODE_TOOLBAR
State.NODE_WORKSPACE = NODE_WORKSPACE
State.NODE_STATUS = NODE_STATUS
State.NODE_SIDEBAR = NODE_SIDEBAR
State.NODE_HEADER = NODE_HEADER
State.TOOL_BASE = TOOL_BASE
State.NAV_BASE = NAV_BASE
State.CARD_BASE = CARD_BASE
State.CARD_COUNT = CARD_COUNT
State.SEGMENT_GEOMETRY = SEGMENT_GEOMETRY
State.SEGMENT_TEXT = SEGMENT_TEXT
State.SEGMENT_IMAGE = SEGMENT_IMAGE
State.SEGMENT_CLIP_PUSH = SEGMENT_CLIP_PUSH
State.SEGMENT_CLIP_POP = SEGMENT_CLIP_POP
State.SEGMENT_LAYER_PUSH = SEGMENT_LAYER_PUSH
State.SEGMENT_LAYER_POP = SEGMENT_LAYER_POP

return State

