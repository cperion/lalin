local pvm = require("pvm")
local ui_asdl = require("ui.asdl")
local ids = require("ui.id")

local T = ui_asdl.T
local Core = T.Core
local Interact = T.Interact

local M = {}

M.EventActivate = "activate"
M.EventChange = "change"
M.EventInput = "input"
M.EventEdit = "edit"
M.EventFocus = "focus"
M.EventBlur = "blur"
M.EventCancel = "cancel"
M.EventScroll = "scroll"
M.EventDragStart = "drag_start"
M.EventDragMove = "drag_move"
M.EventDrop = "drop"
M.EventDragCancel = "drag_cancel"

local function append(out, value)
    out[#out + 1] = value
end

local function classof(value)
    if value == nil then return nil end
    return pvm.classof(value)
end

local function id_key(id)
    return ids.key(id)
end

function M.id(value)
    return ids.id(value)
end

function M.key(id)
    return ids.key(id)
end

function M.require_id(id, label)
    label = label or "widget id"
    local out = id
    if type(out) == "string" then out = ids.id(out) end
    if out == nil or out == Core.NoId or id_key(out) == nil or id_key(out) == "" then
        error(label .. " must be a non-empty id", 2)
    end
    return out
end

function M.child_id(parent, suffix)
    return ids.child(parent, suffix)
end

function M.semantic_id(parent, role, index)
    if index == nil then
        return M.child_id(parent, role)
    end
    return M.child_id(parent, tostring(role) .. ":" .. tostring(index))
end

function M.model(opts)
    opts = opts or {}
    return {
        value = opts.value,
        selected = opts.selected == true,
        disabled = opts.disabled == true,
        focused = opts.focused == true,
        active = opts.active == true,
        metadata = opts.metadata,
    }
end

local function ensure_surface_group(surfaces, group)
    surfaces = surfaces or {}
    local map = surfaces[group]
    if map == nil then
        map = {}
        surfaces[group] = map
    elseif type(map) ~= "table" then
        error("widget surface group " .. tostring(group) .. " must be a table", 3)
    end
    return surfaces, map
end

function M.surface(kind, id, value)
    id = M.require_id(id, "surface id")
    value = value or {}
    if value.id == nil then value.id = id end
    if value.kind == nil then value.kind = kind end
    return value
end

function M.add_surface(surfaces, group, id, value)
    if type(group) ~= "string" then
        error("ui.widget.add_surface requires a string group", 2)
    end
    local key = id_key(id)
    if key == nil then return surfaces end
    local root, map = ensure_surface_group(surfaces, group)
    if map[key] ~= nil then
        error("duplicate widget surface id " .. string.format("%q", key) .. " in group " .. group, 2)
    end
    map[key] = M.surface(group, id, value)
    return root, map[key]
end

function M.lookup_surface(surfaces, group, id)
    if surfaces == nil then return nil end
    local map = surfaces[group]
    if map == nil then return nil end
    local key = id_key(id)
    if key == nil then return nil end
    return map[key]
end

function M.has_surface(surfaces, group, id)
    return M.lookup_surface(surfaces, group, id) ~= nil
end

local function collect_surface_errors(surfaces, errors)
    if surfaces == nil then return end
    if type(surfaces) ~= "table" then
        append(errors, "surfaces must be a table")
        return
    end
    for group, map in pairs(surfaces) do
        if type(map) ~= "table" then
            append(errors, "surfaces." .. tostring(group) .. " must be a table")
        else
            for key, info in pairs(map) do
                if type(key) ~= "string" then
                    append(errors, "surfaces." .. tostring(group) .. " contains non-string key")
                end
                if type(info) ~= "table" then
                    append(errors, "surfaces." .. tostring(group) .. "." .. tostring(key) .. " must be a table")
                else
                    local actual = id_key(info.id)
                    if actual ~= key then
                        append(errors, "surfaces." .. tostring(group) .. "." .. tostring(key) .. " id mismatch " .. tostring(actual))
                    end
                end
            end
        end
    end
end

function M.validate_surfaces(surfaces)
    local errors = {}
    collect_surface_errors(surfaces, errors)
    return #errors == 0, errors
end

function M.assert_surfaces(surfaces)
    local ok, errors = M.validate_surfaces(surfaces)
    if not ok then error("ui.widget surfaces invalid: " .. table.concat(errors, "; "), 2) end
    return true
end

function M.event(kind, id, fields)
    fields = fields or {}
    local ev = {}
    for k, v in pairs(fields) do ev[k] = v end
    ev.kind = kind
    ev.type = kind
    ev.id = id
    ev.widget_id = fields.widget_id or id
    return ev
end

function M.activate_event(id, fields)
    return M.event(M.EventActivate, id, fields)
end

function M.value_event(id, value, fields)
    fields = fields or {}
    fields.value = value
    return M.event(M.EventChange, id, fields)
end

function M.input_event(id, text, fields)
    fields = fields or {}
    fields.text = text
    return M.event(M.EventInput, id, fields)
end

function M.edit_event(id, text, start, length, fields)
    fields = fields or {}
    fields.text = text
    fields.start = start
    fields.length = length
    return M.event(M.EventEdit, id, fields)
end

function M.focus_event(id, focused, fields)
    fields = fields or {}
    fields.focused = focused == true
    return M.event(focused and M.EventFocus or M.EventBlur, id, fields)
end

function M.cancel_event(id, fields)
    return M.event(M.EventCancel, id, fields)
end

function M.route_interact_event(surfaces, ui_event, opts)
    opts = opts or {}
    local cls = classof(ui_event)

    if cls == Interact.Activate then
        local info = M.lookup_surface(surfaces, "activate", ui_event.id)
        if info == nil then info = M.lookup_surface(surfaces, "input", ui_event.id) end
        if info ~= nil then return M.activate_event(info.widget_id or info.id, { id = info.id, surface = info, source = ui_event }) end
    elseif cls == Interact.InputText then
        local info = M.lookup_surface(surfaces, "edit", ui_event.id) or M.lookup_surface(surfaces, "text", ui_event.id)
        if info ~= nil then return M.input_event(info.widget_id or info.id, ui_event.text, { id = info.id, surface = info, source = ui_event }) end
    elseif cls == Interact.EditText then
        local info = M.lookup_surface(surfaces, "edit", ui_event.id) or M.lookup_surface(surfaces, "text", ui_event.id)
        if info ~= nil then return M.edit_event(info.widget_id or info.id, ui_event.text, ui_event.start, ui_event.length, { id = info.id, surface = info, source = ui_event }) end
    elseif cls == Interact.SetFocus then
        local info = M.lookup_surface(surfaces, "focus", ui_event.id) or M.lookup_surface(surfaces, "activate", ui_event.id) or M.lookup_surface(surfaces, "edit", ui_event.id)
        if info ~= nil then return M.focus_event(info.widget_id or info.id, true, { id = info.id, surface = info, source = ui_event }) end
    elseif cls == Interact.ClearFocus then
        if opts.focus_id ~= nil then return M.focus_event(opts.focus_id, false, { source = ui_event }) end
    elseif cls == Interact.ScrollBy then
        local info = M.lookup_surface(surfaces, "scroll", ui_event.id)
        if info ~= nil then return M.event(M.EventScroll, info.widget_id or info.id, { id = info.id, dx = ui_event.dx, dy = ui_event.dy, surface = info, source = ui_event }) end
    elseif cls == Interact.DragStarted then
        local info = M.lookup_surface(surfaces, "drag", ui_event.source_id) or M.lookup_surface(surfaces, "drag_source", ui_event.source_id)
        if info ~= nil then return M.event(M.EventDragStart, info.widget_id or info.id, { id = info.id, x = ui_event.start_x, y = ui_event.start_y, surface = info, source = ui_event }) end
    elseif cls == Interact.DragMoved then
        local info = M.lookup_surface(surfaces, "drag", ui_event.source_id) or M.lookup_surface(surfaces, "drag_source", ui_event.source_id)
        if info ~= nil then return M.event(M.EventDragMove, info.widget_id or info.id, { id = info.id, x = ui_event.x, y = ui_event.y, over_target_id = ui_event.over_target_id, over_slot_id = ui_event.over_slot_id, surface = info, source = ui_event }) end
    elseif cls == Interact.DragDropped then
        local info = M.lookup_surface(surfaces, "drag", ui_event.source_id) or M.lookup_surface(surfaces, "drag_source", ui_event.source_id)
        if info ~= nil then return M.event(M.EventDrop, info.widget_id or info.id, { id = info.id, x = ui_event.x, y = ui_event.y, over_target_id = ui_event.over_target_id, over_slot_id = ui_event.over_slot_id, surface = info, source = ui_event }) end
    elseif cls == Interact.DragCancelled then
        local info = M.lookup_surface(surfaces, "drag", ui_event.source_id) or M.lookup_surface(surfaces, "drag_source", ui_event.source_id)
        if info ~= nil then return M.event(M.EventDragCancel, info.widget_id or info.id, { id = info.id, surface = info, source = ui_event }) end
    end

    return nil
end

function M.route_many(surfaces, ui_events, route_one)
    local out = {}
    if ui_events == nil then return out end
    route_one = route_one or M.route_interact_event
    for i = 1, #ui_events do
        local ev = route_one(surfaces, ui_events[i])
        if ev ~= nil then out[#out + 1] = ev end
    end
    return out
end

function M.empty_route()
    return function() return nil end
end

function M.validate_bundle(bundle, opts)
    opts = opts or {}
    local errors = {}
    if type(bundle) ~= "table" then return false, { "bundle must be a table" } end
    if type(bundle.kind) ~= "string" or bundle.kind == "" then append(errors, "bundle.kind must be a non-empty string") end
    if opts.require_id ~= false and (bundle.id == nil or bundle.id == Core.NoId) then append(errors, "bundle.id is required") end
    if bundle.node == nil and opts.require_node ~= false then append(errors, "bundle.node is required") end
    local ok, surface_errors = M.validate_surfaces(bundle.surfaces)
    if not ok then for i = 1, #surface_errors do append(errors, surface_errors[i]) end end
    if bundle.node ~= nil and opts.validate_ids == true then
        local id_ok, id_errors = ids.validate_auth(bundle.node)
        if not id_ok then for i = 1, #id_errors do append(errors, id_errors[i]) end end
    end
    return #errors == 0, errors
end

function M.assert_bundle(bundle, opts)
    local ok, errors = M.validate_bundle(bundle, opts)
    if not ok then error("ui.widget bundle invalid: " .. table.concat(errors, "; "), 2) end
    return true
end

function M.bundle(spec)
    spec = spec or {}
    local id = spec.id
    if id ~= nil and type(id) == "string" then id = ids.id(id) end
    local surfaces = spec.surfaces or {}
    local route_one = spec.route_one or spec.route_ui_event or M.route_interact_event
    local disabled = spec.disabled == true or (type(spec.model) == "table" and spec.model.disabled == true)

    local bundle = {
        kind = spec.kind or "widget",
        id = id,
        node = spec.node,
        surfaces = surfaces,
        model = spec.model,
        events = spec.events or {},
        disabled = disabled,
        selected = spec.selected == true or (type(spec.model) == "table" and spec.model.selected == true),
        style_slots = spec.style_slots or spec.styles or {},
        role = spec.role,
        label = spec.label,
        description = spec.description,
        metadata = spec.metadata,
        route_one = route_one,
    }

    function bundle:route_ui_event(ui_event)
        if self.disabled and spec.route_disabled ~= true then return nil end
        return route_one(self.surfaces, ui_event, self)
    end

    function bundle:route_ui_events(ui_events)
        local out = {}
        if ui_events == nil then return out end
        for i = 1, #ui_events do
            local ev = self:route_ui_event(ui_events[i])
            if ev ~= nil then out[#out + 1] = ev end
        end
        return out
    end

    function bundle:validate(opts)
        return M.validate_bundle(self, opts)
    end

    for k, v in pairs(spec) do
        if bundle[k] == nil and k ~= "route_ui_event" then bundle[k] = v end
    end

    if spec.validate == true then M.assert_bundle(bundle, spec.validate_opts) end
    return bundle
end

function M.state_maps(bundle_or_opts)
    local opts = bundle_or_opts or {}
    local id = opts.id
    local key = id_key(id)
    local selected = {}
    local disabled = {}
    local active = {}
    if key ~= nil then
        if opts.selected == true then selected[key] = true end
        if opts.disabled == true then disabled[key] = true end
        if opts.active == true then active[key] = true end
    end
    return { selected = selected, disabled = disabled, active = active }
end

M.T = T

return M
