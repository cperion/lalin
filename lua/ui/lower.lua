local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local norm = require("ui.normalize")
local resolve = require("ui.resolve")
local id_validation = require("ui.id")
local state_bridge = require("ui.state")

local T = ui_asdl.T
local Core = T.Core
local Auth = T.Auth
local S = T.Style
local Layout = T.Layout
local Resolved = T.Resolved
local Decor = T.Decor
local Scene = T.Scene

local M = {}

local NO_STATE = S.State(false, false, false, false, false)

local lower_phase

local function merge_state(parent, child)
    parent = parent or NO_STATE
    child = child or NO_STATE
    return S.State(
        parent.hovered or child.hovered,
        parent.focused or child.focused,
        parent.active or child.active,
        parent.selected or child.selected,
        parent.disabled or child.disabled
    )
end

local function resolve_style(tokens, theme, env, state)
    local sg, sp, sc = norm.normalize_phase(tokens, env, state or NO_STATE)
    local spec = pvm.one(sg, sp, sc)
    local lg, lp, lc = resolve.layout_phase(spec.layout, theme)
    local dg, dp, dc = resolve.decor_phase(spec.decor, theme)
    return T.Resolved.Facts(pvm.one(lg, lp, lc), pvm.one(dg, dp, dc))
end

local function to_layout_box(box)
    return Layout.BoxLayout(
        box.w,
        box.h,
        box.min_w,
        box.max_w,
        box.min_h,
        box.max_h,
        box.grow,
        box.shrink,
        box.basis,
        box.self_align,
        box.padding,
        box.margin,
        box.overflow_x,
        box.overflow_y
    )
end

local EMPTY_VISUAL = Resolved.BoxVisual(0, 0, 0, Layout.ShapeRect, 0, 100)
local EMPTY_DECOR_BOX = Decor.Box(EMPTY_VISUAL, S.CursorDefault)

local function decor_box(facts)
    return Decor.Box(facts.decor.visual, facts.decor.interaction.cursor)
end

local function lower_scenes(auth_node, theme, env, state)
    return pvm.drain(lower_phase(auth_node, theme, env, state))
end

local function lower_children(children, theme, env, state)
    local layouts = {}
    local decors = {}
    for i = 1, #children do
        local scenes = lower_scenes(children[i], theme, env, state)
        for j = 1, #scenes do
            layouts[#layouts + 1] = scenes[j].layout
            decors[#decors + 1] = scenes[j].decor
        end
    end
    return layouts, decors
end

local function once_scene(layout, decor)
    return pvm.once(Scene.Node(layout, decor))
end

local function concat_trips(trips)
    if #trips == 0 then return pvm.empty() end
    return pvm.concat_all(trips)
end

local function placement_source(auth_node)
    local cls = pvm.classof(auth_node)
    if cls == Auth.WithInput
        or cls == Auth.WithState
        or cls == Auth.WithDragSource
        or cls == Auth.WithDropTarget
        or cls == Auth.WithDropSlot
        or cls == Auth.FocusScope
        or cls == Auth.Layer
        or cls == Auth.Overlay
        or cls == Auth.Modal then
        return placement_source(auth_node.child)
    end
    return auth_node
end

local function has_scroll_overflow(box)
    return box.overflow_x == Layout.OScroll or box.overflow_x == Layout.OAuto
        or box.overflow_y == Layout.OScroll or box.overflow_y == Layout.OAuto
end

local function scroll_axis_from_box(box)
    local sx = box.overflow_x == Layout.OScroll or box.overflow_x == Layout.OAuto
    local sy = box.overflow_y == Layout.OScroll or box.overflow_y == Layout.OAuto
    if sx and sy then return S.ScrollBoth end
    if sx then return S.ScrollX end
    if sy then return S.ScrollY end
    return nil
end

local function visible_box(box)
    return Layout.BoxLayout(
        box.w,
        box.h,
        box.min_w,
        box.max_w,
        box.min_h,
        box.max_h,
        box.grow,
        box.shrink,
        box.basis,
        box.self_align,
        box.padding,
        box.margin,
        Layout.OVisible,
        Layout.OVisible
    )
end

local function content_box_for_scroll(axis)
    local w = (axis == S.ScrollY) and Layout.SFill or Layout.SHug
    local h = (axis == S.ScrollX) and Layout.SFill or Layout.SHug
    if axis == S.ScrollBoth then
        w, h = Layout.SFill, Layout.SFill
    end
    return Layout.BoxLayout(
        w,
        h,
        Layout.NoMin,
        Layout.NoMax,
        Layout.NoMin,
        Layout.NoMax,
        0,
        1,
        Layout.BasisAuto,
        Layout.SelfAuto,
        Layout.Edges(0, 0, 0, 0),
        Layout.Margin(Layout.MarginPx(0), Layout.MarginPx(0), Layout.MarginPx(0), Layout.MarginPx(0)),
        Layout.OVisible,
        Layout.OVisible
    )
end

local function wrap_layout_children_for_scroll(axis, nodes)
    if #nodes == 0 then
        return Layout.Flow(Core.NoId, content_box_for_scroll(axis), Layout.MStart, Layout.CStart, 0, {})
    end
    if #nodes == 1 then return nodes[1] end
    return Layout.Flow(Core.NoId, content_box_for_scroll(axis), Layout.MStart, Layout.CStart, 0, nodes)
end

local function wrap_decor_children_for_scroll(nodes)
    if #nodes == 0 then
        return Decor.Flow(Core.NoId, EMPTY_DECOR_BOX, {})
    end
    if #nodes == 1 then return nodes[1] end
    return Decor.Flow(Core.NoId, EMPTY_DECOR_BOX, nodes)
end

local function maybe_wrap_scroll(id, box, axis, layout_child, decor, decor_child)
    return Scene.Node(
        Layout.Scroll(id, visible_box(box), axis, layout_child),
        Decor.Scroll(id, decor, decor_child)
    )
end

local function append_grid_items(layout_items, decor_items, auth_node, theme, env, state)
    local cls = pvm.classof(auth_node)

    if cls == Auth.Empty or auth_node == Auth.Empty then
        return
    end

    if cls == Auth.Fragment then
        local children = auth_node.children
        for i = 1, #children do
            append_grid_items(layout_items, decor_items, children[i], theme, env, state)
        end
        return
    end

    local source = placement_source(auth_node)
    local facts = resolve_style(source.styles, theme, env, state)
    local gp = facts.layout.placement
    local scenes = lower_scenes(auth_node, theme, env, state)

    for i = 1, #scenes do
        layout_items[#layout_items + 1] = Layout.GridItem(
            scenes[i].layout,
            gp.col_start,
            gp.col_span,
            gp.row_start,
            gp.row_span,
            Layout.CStretch,
            Layout.CStretch
        )
        decor_items[#decor_items + 1] = Decor.GridItem(
            scenes[i].decor,
            gp.col_start,
            gp.col_span,
            gp.row_start,
            gp.row_span
        )
    end
end

local function lower_box_node(id, facts, children, theme, env, state)
    local lf = facts.layout
    local df = facts.decor
    local box = to_layout_box(lf.box)
    local db = decor_box(facts)

    if has_scroll_overflow(box) then
        local axis = scroll_axis_from_box(box)
        if lf.display == S.DisplayGrid then
            local layout_items, decor_items = {}, {}
            append_grid_items(layout_items, decor_items, Auth.Fragment(children), theme, env, state)
            local layout_child = Layout.Grid(Core.NoId, content_box_for_scroll(axis), lf.cols, lf.rows, lf.col_gap, lf.row_gap, layout_items)
            local decor_child = Decor.Grid(Core.NoId, EMPTY_DECOR_BOX, decor_items)
            return maybe_wrap_scroll(id, box, axis, layout_child, db, decor_child)
        end

        local layouts, decors = lower_children(children, theme, env, state)
        if lf.display == S.DisplayFlex then
            local layout_child = Layout.Flex(Core.NoId, content_box_for_scroll(axis), lf.axis, lf.wrap, lf.justify, lf.items, lf.gap_x, lf.gap_y, layouts)
            local decor_child = Decor.Flex(Core.NoId, EMPTY_DECOR_BOX, decors)
            return maybe_wrap_scroll(id, box, axis, layout_child, db, decor_child)
        end

        local layout_child = Layout.Flow(Core.NoId, content_box_for_scroll(axis), lf.justify, lf.items, lf.gap_y, layouts)
        local decor_child = Decor.Flow(Core.NoId, EMPTY_DECOR_BOX, decors)
        return maybe_wrap_scroll(id, box, axis, layout_child, db, decor_child)
    end

    if lf.display == S.DisplayGrid then
        local layout_items, decor_items = {}, {}
        append_grid_items(layout_items, decor_items, Auth.Fragment(children), theme, env, state)
        return Scene.Node(
            Layout.Grid(id, box, lf.cols, lf.rows, lf.col_gap, lf.row_gap, layout_items),
            Decor.Grid(id, db, decor_items)
        )
    end

    local layouts, decors = lower_children(children, theme, env, state)
    if lf.display == S.DisplayFlex then
        return Scene.Node(
            Layout.Flex(id, box, lf.axis, lf.wrap, lf.justify, lf.items, lf.gap_x, lf.gap_y, layouts),
            Decor.Flex(id, db, decors)
        )
    end

    return Scene.Node(
        Layout.Flow(id, box, lf.justify, lf.items, lf.gap_y, layouts),
        Decor.Flow(id, db, decors)
    )
end

lower_phase = pvm.phase("ui.lower", {
    [Auth.Empty] = function(self, theme, env, state)
        return pvm.empty()
    end,

    [Auth.Fragment] = function(self, theme, env, state)
        local children = self.children
        local n = #children
        if n == 0 then return pvm.empty() end
        local trips = {}
        for i = 1, n do
            local g, p, c = lower_phase(children[i], theme, env, state)
            trips[i] = { g, p, c }
        end
        return concat_trips(trips)
    end,

    [Auth.WithState] = function(self, theme, env, state)
        return lower_phase(self.child, theme, env, merge_state(state, self.state))
    end,

    [Auth.WithInput] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(
                Layout.WithInput(self.id, self.role, scenes[i].layout),
                Decor.WithInput(self.id, scenes[i].decor)
            ) }
        end
        return concat_trips(trips)
    end,

    [Auth.WithDragSource] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.WithDragSource(self.id, scenes[i].layout), Decor.WithDragSource(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.WithDropTarget] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.WithDropTarget(self.id, scenes[i].layout), Decor.WithDropTarget(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.WithDropSlot] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.WithDropSlot(self.id, scenes[i].layout), Decor.WithDropSlot(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.FocusScope] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.FocusScope(self.id, self.policy, scenes[i].layout), Decor.FocusScope(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.Layer] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.Layer(self.id, self.kind, self.order, scenes[i].layout), Decor.Layer(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.Overlay] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.Overlay(self.id, self.anchor_id, self.placement, self.modal, scenes[i].layout), Decor.Overlay(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.Modal] = function(self, theme, env, state)
        local scenes = lower_scenes(self.child, theme, env, state)
        local trips = {}
        for i = 1, #scenes do
            trips[i] = { once_scene(Layout.Modal(self.id, scenes[i].layout), Decor.Modal(self.id, scenes[i].decor)) }
        end
        return concat_trips(trips)
    end,

    [Auth.Text] = function(self, theme, env, state)
        local facts = resolve_style(self.styles, theme, env, state)
        local box = to_layout_box(facts.layout.box)
        local text = Layout.TextLiteral(Layout.TextMeasure(facts.layout.text_metrics, self.content))
        local scene = Scene.Node(
            Layout.Leaf(self.id, box, text),
            Decor.Leaf(self.id, decor_box(facts), Decor.Text(facts.decor.text_paint))
        )
        if has_scroll_overflow(box) then
            local axis = scroll_axis_from_box(box)
            local inner_layout = Layout.Leaf(Core.NoId, content_box_for_scroll(axis), text)
            local inner_decor = Decor.Leaf(Core.NoId, EMPTY_DECOR_BOX, Decor.Text(facts.decor.text_paint))
            scene = maybe_wrap_scroll(self.id, box, axis, inner_layout, decor_box(facts), inner_decor)
        end
        return pvm.once(scene)
    end,

    [Auth.TextRef] = function(self, theme, env, state)
        local facts = resolve_style(self.styles, theme, env, state)
        local box = to_layout_box(facts.layout.box)
        local text = Layout.TextBinding(self.content_id, facts.layout.text_metrics)
        local scene = Scene.Node(
            Layout.Leaf(self.id, box, text),
            Decor.Leaf(self.id, decor_box(facts), Decor.Text(facts.decor.text_paint))
        )
        if has_scroll_overflow(box) then
            local axis = scroll_axis_from_box(box)
            local inner_layout = Layout.Leaf(Core.NoId, content_box_for_scroll(axis), text)
            local inner_decor = Decor.Leaf(Core.NoId, EMPTY_DECOR_BOX, Decor.Text(facts.decor.text_paint))
            scene = maybe_wrap_scroll(self.id, box, axis, inner_layout, decor_box(facts), inner_decor)
        end
        return pvm.once(scene)
    end,

    [Auth.Paint] = function(self, theme, env, state)
        local facts = resolve_style(self.styles, theme, env, state)
        local box = to_layout_box(facts.layout.box)
        local scene = Scene.Node(
            Layout.Canvas(self.id, box),
            Decor.Canvas(self.id, decor_box(facts), Decor.Paint(self.paint))
        )
        if has_scroll_overflow(box) then
            local axis = scroll_axis_from_box(box)
            local inner_layout = Layout.Canvas(Core.NoId, content_box_for_scroll(axis))
            local inner_decor = Decor.Canvas(Core.NoId, EMPTY_DECOR_BOX, Decor.Paint(self.paint))
            scene = maybe_wrap_scroll(self.id, box, axis, inner_layout, decor_box(facts), inner_decor)
        end
        return pvm.once(scene)
    end,

    [Auth.Scroll] = function(self, theme, env, state)
        local facts = resolve_style(self.styles, theme, env, state)
        local box = to_layout_box(facts.layout.box)
        local scenes = lower_scenes(self.child, theme, env, state)
        local layouts, decors = {}, {}
        for i = 1, #scenes do
            layouts[i] = scenes[i].layout
            decors[i] = scenes[i].decor
        end
        return pvm.once(maybe_wrap_scroll(
            self.id,
            box,
            self.axis,
            wrap_layout_children_for_scroll(self.axis, layouts),
            decor_box(facts),
            wrap_decor_children_for_scroll(decors)
        ))
    end,

    [Auth.Box] = function(self, theme, env, state)
        local facts = resolve_style(self.styles, theme, env, state)
        return pvm.once(lower_box_node(self.id, facts, self.children, theme, env, state))
    end,
})

local function prepare_root_auth(node, opts)
    opts = opts or {}

    if opts.validate_ids ~= false then
        id_validation.assert_auth(node, opts.id_opts or opts)
    end

    if opts.state_provider ~= nil then
        return state_bridge.apply_to_auth(node, opts.state_provider, opts.state_opts or opts)
    end

    if opts.model ~= nil
        or opts.report ~= nil
        or opts.selected ~= nil
        or opts.selected_ids ~= nil
        or opts.disabled ~= nil
        or opts.disabled_ids ~= nil
        or opts.active ~= nil
        or opts.active_ids ~= nil then
        return state_bridge.apply_model_to_auth(node, opts.model, opts.report, opts.state_opts or opts)
    end

    return node
end

function M.root(node, theme, env, opts)
    local auth = prepare_root_auth(node, opts)
    local g, p, c = lower_phase(auth, theme, env, opts and opts.state or nil)
    return pvm.drain(g, p, c)
end

M.phase = lower_phase
M.T = T

return M
