local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local b = require("ui.build")
local tw = require("ui.tw")
local core = require("ui.recipes._core")
local collection = require("ui.recipes._collection")

local T = ui_asdl.T

local function wrap_row(id, child, focusable, activatable)
    if activatable then
        if focusable then
            child = b.with_input(id, T.Interact.ActivateTarget, child)
        else
            child = b.with_input(id, T.Interact.HitTarget, child)
        end
    elseif focusable then
        child = b.with_input(id, T.Interact.FocusTarget, child)
    end
    return b.drag_source(id, child)
end

local function default_slot(id, active)
    return b.drop_slot(id,
        b.box {
            tw.w_full,
            tw.h_px(8),
            tw.rounded_full,
            active and tw.bg.sky[400] or tw.bg.transparent,
        })
end

return function(opts)
    opts = opts or {}
    if opts.id == nil then error("reorderable_list recipe requires opts.id", 2) end
    if opts.items == nil then error("reorderable_list recipe requires opts.items", 2) end
    if opts.key_of == nil then error("reorderable_list recipe requires opts.key_of", 2) end
    if opts.row == nil then error("reorderable_list recipe requires opts.row", 2) end

    local focusable = opts.focusable ~= false
    local activatable = opts.activatable ~= false

    local built = collection.build {
        id = opts.id,
        items = opts.items,
        key_of = opts.key_of,
        row = opts.row,
        selected_key = opts.selected_key,
        focused_key = opts.focused_key,
        dragged_key = opts.dragged_key,
        drop_index = opts.drop_index,
        before_each = opts.before_each,
        after_each = opts.after_each,
        before_all = opts.before_all,
        after_all = opts.after_all,
        wrap_row = function(child, item, ctx)
            return wrap_row(ctx.row_id, child, focusable, activatable)
        end,
        build_slot = function(index, active, item, ctx, slot_id)
            if opts.slot ~= nil then
                local child = opts.slot(index, active, item, ctx, slot_id)
                if child == nil or child == false then return nil end
                return b.drop_slot(slot_id, child)
            end
            return default_slot(slot_id, active)
        end,
    }

    local surfaces = {
        items = {},
        activate = {},
        focus = {},
        slots = {},
        drag_sources = {},
        drag = {},
    }
    for i = 1, #built.row_infos do
        local info = built.row_infos[i]
        info.widget_id = opts.id
        core.add_surface(surfaces.items, info.id, info)
        if activatable then core.add_surface(surfaces.activate, info.id, info) end
        if focusable then core.add_surface(surfaces.focus, info.id, info) end
        core.add_surface(surfaces.drag_sources, info.id, info)
        core.add_surface(surfaces.drag, info.id, info)
    end
    for i = 1, #built.slot_infos do
        local info = built.slot_infos[i]
        core.add_surface(surfaces.slots, info.id, info)
    end

    local function route_one(surfaces_, ui_event)
        local cls = pvm.classof(ui_event)
        if cls == T.Interact.Activate and activatable then
            local info = core.surface_lookup(surfaces_.items, ui_event.id)
            if info ~= nil then
                if opts.on_select ~= nil then return opts.on_select(info.key, info.item, info.ctx) end
                return core.event("select", opts.id, { id = info.id, key = info.key, item = info.item, index = info.index, ctx = info.ctx, source = ui_event })
            end
        elseif cls == T.Interact.SetFocus and focusable then
            local info = core.surface_lookup(surfaces_.items, ui_event.id)
            if info ~= nil then
                if opts.on_focus ~= nil then return opts.on_focus(info.key, info.item, info.ctx) end
                return core.focus_event(opts.id, true, { id = info.id, key = info.key, item = info.item, index = info.index, ctx = info.ctx, source = ui_event })
            end
        elseif cls == T.Interact.DragStarted then
            local info = core.surface_lookup(surfaces_.drag_sources, ui_event.source_id)
            if info ~= nil then
                if opts.on_drag_start ~= nil then return opts.on_drag_start(info.key, info.item, info.ctx) end
                return core.event("drag_start", opts.id, { id = info.id, key = info.key, item = info.item, index = info.index, ctx = info.ctx, source = ui_event })
            end
        elseif cls == T.Interact.DragMoved then
            local slot = core.surface_lookup(surfaces_.slots, ui_event.over_slot_id)
            if slot ~= nil then
                if opts.on_drag_preview ~= nil then
                    return opts.on_drag_preview(slot.index)
                end
                return core.event("drag_preview", opts.id, { id = slot.id, index = slot.index, source = ui_event })
            elseif opts.on_drag_clear_preview ~= nil then
                return opts.on_drag_clear_preview()
            else
                return core.event("drag_clear_preview", opts.id, { source = ui_event })
            end
        elseif cls == T.Interact.DragDropped then
            local slot = core.surface_lookup(surfaces_.slots, ui_event.over_slot_id)
            if slot ~= nil then
                if opts.on_drag_commit ~= nil then
                    return opts.on_drag_commit(slot.index)
                end
                return core.event("drag_commit", opts.id, { id = slot.id, index = slot.index, source = ui_event })
            elseif opts.on_drag_cancel ~= nil then
                return opts.on_drag_cancel()
            else
                return core.cancel_event(opts.id, { source = ui_event })
            end
        elseif cls == T.Interact.DragCancelled then
            if opts.on_drag_cancel ~= nil then
                return opts.on_drag_cancel()
            end
            return core.cancel_event(opts.id, { source = ui_event })
        end
        return nil
    end

    return core.bundle(built.node, surfaces, route_one, {
        kind = "reorderable_list",
        id = opts.id,
        selected = opts.selected_key ~= nil,
        role = "listbox",
        label = opts.label,
    })
end
