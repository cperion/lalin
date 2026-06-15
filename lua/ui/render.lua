local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local T = ui_asdl.T
local Style = T.Style
local Layout = T.Layout
local Decor = T.Decor
local Solve = T.Solve
local View = T.View
local Interact = T.Interact

local M = {}

local render_phase

local function rect(x, y, w, h)
    return Layout.Rect(x, y, w, h)
end

local function has_box_visual(v)
    return v ~= nil and (v.bg ~= 0 or v.border_w > 0)
end

local function once_trip(op)
    local g, p, c = pvm.once(op)
    return { g, p, c }
end

local function concat(parts)
    if #parts == 0 then return pvm.empty() end
    return pvm.concat_all(parts)
end

local function solve_box(node)
    local cls = pvm.classof(node)
    if cls == Solve.WithInput or cls == Solve.WithDragSource or cls == Solve.WithDropTarget or cls == Solve.WithDropSlot
        or cls == Solve.FocusScope or cls == Solve.Layer or cls == Solve.Overlay or cls == Solve.Modal then
        return solve_box(node.child)
    end
    if cls == Solve.GridItem then return solve_box(node.node) end
    return node.box
end

local function decor_cursor(node)
    if node == nil then return Style.CursorDefault end
    local cls = pvm.classof(node)
    if cls == Decor.Flow or cls == Decor.Flex or cls == Decor.Grid or cls == Decor.Leaf or cls == Decor.Canvas or cls == Decor.Scroll then
        return node.box.cursor or Style.CursorDefault
    end
    if cls == Decor.WithInput or cls == Decor.WithDragSource or cls == Decor.WithDropTarget or cls == Decor.WithDropSlot
        or cls == Decor.FocusScope or cls == Decor.Layer or cls == Decor.Overlay or cls == Decor.Modal then
        return decor_cursor(node.child)
    end
    return Style.CursorDefault
end

local function append_box(parts, id, box, decor_box)
    if decor_box ~= nil and has_box_visual(decor_box.visual) then
        parts[#parts + 1] = once_trip(View.Box(id, rect(0, 0, box.border.w, box.border.h), decor_box.visual))
    end
end

local function append_clip_begin(parts, box)
    if box.clipped then
        parts[#parts + 1] = once_trip(View.PushClipRect(box.id, rect(0, 0, box.border.w, box.border.h)))
        return true
    end
    return false
end

local function append_clip_end(parts, id, clipped)
    if clipped then
        parts[#parts + 1] = once_trip(View.PopClip(id))
    end
end

local function append_node(parts, solved, decor, is_root)
    local g, p, c = render_phase(solved, decor, is_root == true)
    parts[#parts + 1] = { g, p, c }
end

local function render_placed_begin(parts, box, is_root)
    local pushed = false
    if not is_root then
        parts[#parts + 1] = once_trip(View.PushTx(box.id, box.border.x, box.border.y))
        pushed = true
    end
    return pushed
end

local function render_placed_end(parts, box, pushed)
    if pushed then
        parts[#parts + 1] = once_trip(View.PopTx(box.id))
    end
end

local function child_decor(decor, i)
    if decor == nil then return nil end
    if decor.children ~= nil then return decor.children[i] end
    if decor.items ~= nil then return decor.items[i] and decor.items[i].node end
    return nil
end

render_phase = pvm.phase("ui.render.solved", {
    [Solve.WithInput] = function(self, decor, is_root)
        local parts = {}
        local box = solve_box(self.child).border
        local r = rect(box.x, box.y, box.w, box.h)
        if self.role ~= Interact.Passive then
            if self.role == Interact.HitTarget or self.role == Interact.ActivateTarget or self.role == Interact.EditTarget then
                parts[#parts + 1] = once_trip(View.Hit(self.id, r))
            end
            if self.role == Interact.FocusTarget or self.role == Interact.ActivateTarget or self.role == Interact.EditTarget then
                parts[#parts + 1] = once_trip(View.Focus(self.id, r))
            end
            local cursor = decor_cursor(decor and decor.child)
            if cursor ~= Style.CursorDefault then
                parts[#parts + 1] = once_trip(View.Cursor(self.id, r, cursor))
            end
        end
        append_node(parts, self.child, decor and decor.child, is_root)
        return concat(parts)
    end,

    [Solve.WithDragSource] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        parts[#parts + 1] = once_trip(View.DragSource(self.id, rect(b.x, b.y, b.w, b.h)))
        append_node(parts, self.child, decor and decor.child, is_root)
        return concat(parts)
    end,

    [Solve.WithDropTarget] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        parts[#parts + 1] = once_trip(View.DropTarget(self.id, rect(b.x, b.y, b.w, b.h)))
        append_node(parts, self.child, decor and decor.child, is_root)
        return concat(parts)
    end,

    [Solve.WithDropSlot] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        parts[#parts + 1] = once_trip(View.DropSlot(self.id, rect(b.x, b.y, b.w, b.h)))
        append_node(parts, self.child, decor and decor.child, is_root)
        return concat(parts)
    end,

    [Solve.FocusScope] = function(self, decor, is_root)
        local parts = {}
        parts[#parts + 1] = once_trip(View.BeginFocusScope(self.id, self.policy))
        append_node(parts, self.child, decor and decor.child, is_root)
        parts[#parts + 1] = once_trip(View.EndFocusScope(self.id))
        return concat(parts)
    end,

    [Solve.Layer] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        parts[#parts + 1] = once_trip(View.BeginLayer(self.id, self.kind, self.order or 0, rect(b.x, b.y, b.w, b.h)))
        append_node(parts, self.child, decor and decor.child, is_root)
        parts[#parts + 1] = once_trip(View.EndLayer(self.id))
        return concat(parts)
    end,

    [Solve.Overlay] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        local r = rect(b.x, b.y, b.w, b.h)
        parts[#parts + 1] = once_trip(View.Overlay(self.id, self.anchor_id, self.placement, self.modal == true, r))
        if self.modal then
            parts[#parts + 1] = once_trip(View.ModalBarrier(self.id, r))
        end
        append_node(parts, self.child, decor and decor.child, is_root)
        return concat(parts)
    end,

    [Solve.Modal] = function(self, decor, is_root)
        local parts = {}
        local b = solve_box(self.child).border
        local r = rect(b.x, b.y, b.w, b.h)
        parts[#parts + 1] = once_trip(View.ModalBarrier(self.id, r))
        parts[#parts + 1] = once_trip(View.BeginLayer(self.id, Interact.LayerModal, 0, r))
        append_node(parts, self.child, decor and decor.child, is_root)
        parts[#parts + 1] = once_trip(View.EndLayer(self.id))
        return concat(parts)
    end,

    [Solve.Leaf] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        if self.text ~= nil and decor ~= nil and decor.text ~= nil then
            parts[#parts + 1] = once_trip(View.Text(box.id, box.content, self.text, decor.text.paint))
        end
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,

    [Solve.Canvas] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        if decor ~= nil and decor.paint ~= nil and #decor.paint.program.items > 0 then
            parts[#parts + 1] = once_trip(View.Paint(box.id, box.content, decor.paint.program))
        end
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,

    [Solve.Scroll] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        local clipped = append_clip_begin(parts, box)
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PushTx(box.id, box.content.x, box.content.y))
        end
        parts[#parts + 1] = once_trip(View.PushScroll(box.id, rect(0, 0, box.content.w, box.content.h), self.axis, self.content_w, self.content_h))
        append_node(parts, self.child, decor and decor.child, false)
        parts[#parts + 1] = once_trip(View.PopScroll(box.id))
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PopTx(box.id))
        end
        append_clip_end(parts, box.id, clipped)
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,

    [Solve.Flow] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        local clipped = append_clip_begin(parts, box)
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PushTx(box.id, box.content.x, box.content.y))
        end
        for i = 1, #self.children do
            append_node(parts, self.children[i], child_decor(decor, i), false)
        end
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PopTx(box.id))
        end
        append_clip_end(parts, box.id, clipped)
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,

    [Solve.Flex] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        local clipped = append_clip_begin(parts, box)
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PushTx(box.id, box.content.x, box.content.y))
        end
        for i = 1, #self.children do
            append_node(parts, self.children[i], child_decor(decor, i), false)
        end
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PopTx(box.id))
        end
        append_clip_end(parts, box.id, clipped)
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,

    [Solve.Grid] = function(self, decor, is_root)
        local parts = {}
        local box = self.box
        local pushed = render_placed_begin(parts, box, is_root)
        append_box(parts, box.id, box, decor and decor.box)
        local clipped = append_clip_begin(parts, box)
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PushTx(box.id, box.content.x, box.content.y))
        end
        for i = 1, #self.items do
            append_node(parts, self.items[i].node, child_decor(decor, i), false)
        end
        if box.content.x ~= 0 or box.content.y ~= 0 then
            parts[#parts + 1] = once_trip(View.PopTx(box.id))
        end
        append_clip_end(parts, box.id, clipped)
        render_placed_end(parts, box, pushed)
        return concat(parts)
    end,
}, {
    args_cache = "last",
})

function M.root(solved, decor)
    return render_phase(solved, decor, true)
end

M.phase = render_phase
M.T = T

return M
