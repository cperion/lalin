local ui_asdl = require("ui.asdl")
local widget = require("ui.widget")

local T = ui_asdl.T
local Core = T.Core

local M = {}

function M.id_string(id)
    return widget.key(id)
end

function M.surface_lookup(map, id)
    if map == nil then return nil end
    local key = M.id_string(id)
    if key == nil then return nil end
    return map[key]
end

function M.add_surface(map, id, value)
    local key = M.id_string(id)
    if key == nil then return map end
    if map[key] ~= nil then
        error("duplicate recipe surface id " .. string.format("%q", key), 2)
    end
    value = value or {}
    if value.id == nil then value.id = id end
    map[key] = value
    return map
end

function M.route_many(surfaces, ui_events, route_one)
    local out = {}
    if ui_events == nil then return out end
    for i = 1, #ui_events do
        local ev = route_one(surfaces, ui_events[i])
        if ev ~= nil then
            out[#out + 1] = ev
        end
    end
    return out
end

function M.empty_route()
    return function()
        return nil
    end
end

local function validate_grouped_surfaces(surfaces)
    surfaces = surfaces or {}
    for group, map in pairs(surfaces) do
        if type(map) ~= "table" then
            error("recipe surfaces." .. tostring(group) .. " must be a table", 3)
        end
        for key, info in pairs(map) do
            if type(key) ~= "string" then
                error("recipe surfaces." .. tostring(group) .. " contains a non-string key", 3)
            end
            if type(info) ~= "table" then
                error("recipe surfaces." .. tostring(group) .. "." .. key .. " must be a table", 3)
            end
            local actual = M.id_string(info.id)
            if actual ~= key then
                error("recipe surfaces." .. tostring(group) .. "." .. key .. " id mismatch " .. tostring(actual), 3)
            end
        end
    end
end

function M.bundle(node, surfaces, route_one, extras)
    extras = extras or {}
    route_one = route_one or M.empty_route()
    surfaces = surfaces or {}
    validate_grouped_surfaces(surfaces)

    local bundle = widget.bundle {
        kind = extras.kind or "recipe",
        id = extras.id,
        node = node,
        surfaces = surfaces,
        route_one = route_one,
        model = extras.model,
        events = extras.events,
        disabled = extras.disabled,
        selected = extras.selected,
        style_slots = extras.style_slots or extras.styles,
        role = extras.role,
        label = extras.label,
        description = extras.description,
        metadata = extras.metadata,
        route_disabled = true,
    }

    -- Preserve the original recipe return shape and method names.
    bundle.route_one = route_one
    function bundle:route_ui_event(ui_event)
        return route_one(self.surfaces, ui_event)
    end

    function bundle:route_ui_events(ui_events)
        return M.route_many(self.surfaces, ui_events, route_one)
    end

    for k, v in pairs(extras) do
        bundle[k] = v
    end

    return bundle
end

M.event = widget.event
M.activate_event = widget.activate_event
M.value_event = widget.value_event
M.input_event = widget.input_event
M.edit_event = widget.edit_event
M.focus_event = widget.focus_event
M.cancel_event = widget.cancel_event
M.widget = widget
M.T = T
M.Core = Core

return M
