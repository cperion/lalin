local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local measure_mod = require("ui.measure")
local plan = require("ui.plan")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Layout = T.Layout
local Solve = T.Solve

local M = {}

local measure_phase = measure_mod.phase
local text_layout_phase = measure_mod.text_layout_phase
local max0 = plan.max0
local should_clip = plan.should_clip
local flow_plan = plan.flow_plan
local flex_plan = plan.flex_plan
local grid_plan = plan.grid_plan

local solve_phase

local content_cache = setmetatable({}, { __mode = "k" })

local function content_map(store)
    if store == nil then return nil end
    local map = content_cache[store]
    if map ~= nil then return map end
    map = {}
    local items = store.items or store
    for i = 1, #items do
        local item = items[i]
        map[item.id] = item.content
    end
    content_cache[store] = map
    return map
end

local function content_string(store, id)
    if store == nil or id == nil or id == Core.NoId then return "" end
    local map = content_map(store)
    return map[id] or ""
end

local function leaf_text_measure(text_spec, content_store)
    if text_spec == nil then return nil end
    local cls = pvm.classof(text_spec)
    if cls == Layout.TextLiteral then
        return text_spec.text
    end
    if cls == Layout.TextBinding then
        return Layout.TextMeasure(text_spec.metrics, content_string(content_store, text_spec.content_id))
    end
    return text_spec
end

local function rect(x, y, w, h)
    return Layout.Rect(x, y, w, h)
end

local function placed(id, box, x, y, w, h, baseline)
    local pad = box and box.padding or Layout.Edges(0, 0, 0, 0)
    return Solve.Placed(
        id,
        rect(x or 0, y or 0, w or 0, h or 0),
        rect(pad.left, pad.top, max0((w or 0) - pad.left - pad.right), max0((h or 0) - pad.top - pad.bottom)),
        baseline or 0,
        box ~= nil and should_clip(box) or false
    )
end

local function measure_one(node, constraint, text_system, content_store)
    return pvm.one(measure_phase(node, constraint, text_system, content_store))
end

local function text_layout_one(text_measure, constraint, text_system)
    return pvm.one(text_layout_phase(text_measure, constraint, text_system))
end

local function solve_one(node, x, y, w, h, text_system, content_store)
    return pvm.one(solve_phase(node, x or 0, y or 0, w, h, text_system, content_store))
end

local function scroll_child_constraint(axis, inner_w, inner_h)
    if axis == Style.ScrollX then
        return Layout.Constraint(math.huge, inner_h)
    elseif axis == Style.ScrollY then
        return Layout.Constraint(inner_w, math.huge)
    end
    return Layout.Constraint(math.huge, math.huge)
end

local function child_box(node)
    local cls = pvm.classof(node)
    if cls == Solve.WithInput or cls == Solve.WithDragSource or cls == Solve.WithDropTarget or cls == Solve.WithDropSlot
        or cls == Solve.FocusScope or cls == Solve.Layer or cls == Solve.Overlay or cls == Solve.Modal then
        return child_box(node.child)
    end
    if cls == Solve.GridItem then return child_box(node.node) end
    return node.box
end

solve_phase = pvm.phase("ui.solve", {
    [Layout.WithInput] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.WithInput(self.id, self.role, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.WithDragSource] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.WithDragSource(self.id, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.WithDropTarget] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.WithDropTarget(self.id, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.WithDropSlot] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.WithDropSlot(self.id, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.FocusScope] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.FocusScope(self.id, self.policy, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.Layer] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.Layer(self.id, self.kind, self.order, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.Overlay] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.Overlay(self.id, self.anchor_id, self.placement, self.modal, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.Modal] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.Modal(self.id, solve_one(self.child, x, y, w, h, text_system, content_store)))
    end,

    [Layout.Leaf] = function(self, x, y, w, h, text_system, content_store)
        local text_measure = leaf_text_measure(self.text, content_store)
        local tl = nil
        local baseline = 0
        if text_measure ~= nil then
            local c = placed(self.id, self.box, x, y, w, h, 0).content
            tl = text_layout_one(text_measure, Layout.Constraint(c.w, c.h), text_system)
            baseline = tl.baseline + self.box.padding.top
        end
        return pvm.once(Solve.Leaf(placed(self.id, self.box, x, y, w, h, baseline), tl))
    end,

    [Layout.Canvas] = function(self, x, y, w, h, text_system, content_store)
        return pvm.once(Solve.Canvas(placed(self.id, self.box, x, y, w, h, 0)))
    end,

    [Layout.Scroll] = function(self, x, y, w, h, text_system, content_store)
        local p = placed(self.id, self.box, x, y, w, h, 0)
        local child_size = measure_one(self.child, scroll_child_constraint(self.axis, p.content.w, p.content.h), text_system, content_store)
        local child = solve_one(self.child, 0, 0, child_size.w, child_size.h, text_system, content_store)
        return pvm.once(Solve.Scroll(p, self.axis, child_size.w, child_size.h, child))
    end,

    [Layout.Flow] = function(self, x, y, w, h, text_system, content_store)
        local p = placed(self.id, self.box, x, y, w, h, 0)
        local placements = flow_plan(self, p.content.w, p.content.h, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system, content_store)
        end)
        local children = {}
        for i = 1, #placements do
            local item = placements[i]
            children[i] = solve_one(item.node, item.dx, item.dy, item.w, item.h, text_system, content_store)
        end
        return pvm.once(Solve.Flow(p, children))
    end,

    [Layout.Flex] = function(self, x, y, w, h, text_system, content_store)
        local p = placed(self.id, self.box, x, y, w, h, 0)
        local solved = flex_plan(self, p.content.w, p.content.h, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system, content_store)
        end, true)
        local children = {}
        for i = 1, #solved.items do
            local item = solved.items[i]
            children[i] = solve_one(item.node, item.dx, item.dy, item.w, item.h, text_system, content_store)
        end
        return pvm.once(Solve.Flex(p, children))
    end,

    [Layout.Grid] = function(self, x, y, w, h, text_system, content_store)
        local p = placed(self.id, self.box, x, y, w, h, 0)
        local solved = grid_plan(self, p.content.w, p.content.h, function(node, child_constraint)
            return measure_one(node, child_constraint, text_system, content_store)
        end)
        local items = {}
        for i = 1, #solved.items do
            local item = solved.items[i]
            local child = solve_one(item.node, item.dx, item.dy, item.w, item.h, text_system, content_store)
            items[i] = Solve.GridItem(child, rect(item.dx, item.dy, item.w, item.h))
        end
        return pvm.once(Solve.Grid(p, items))
    end,
}, {
    args_cache = "last",
})

function M.root(layout, env, text_system, content_store)
    return solve_phase(layout, 0, 0, env.vw, env.vh, text_system, content_store)
end

M.phase = solve_phase
M.child_box = child_box
M.T = T

return M
