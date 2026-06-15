local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local View = T.View
local Style = T.Style
local Layout = T.Layout

local M = {}

local WORLD = 1000000000

local function max0(n)
    if n < 0 then return 0 end
    return n
end

local function id_key(id)
    if id == nil or id == Core.NoId then return nil end
    return id.value
end

local function rect_intersect(ax, ay, aw, ah, bx, by, bw, bh)
    local x1 = math.max(ax, bx)
    local y1 = math.max(ay, by)
    local x2 = math.min(ax + aw, bx + bw)
    local y2 = math.min(ay + ah, by + bh)
    local w = x2 - x1
    local h = y2 - y1
    if w <= 0 or h <= 0 then return nil end
    return x1, y1, w, h
end

local function rect_abs(r, tx_x, tx_y)
    return tx_x + r.x, tx_y + r.y, r.w, r.h
end

local function rect_from_xywh(x, y, w, h)
    return Layout.Rect(x, y, w, h)
end

local function scroll_lookup(scrolls, id)
    if scrolls == nil or id == nil or id == Core.NoId then return 0, 0 end
    local k = id_key(id)
    if type(scrolls) == "table" and not pvm.classof(scrolls) and scrolls[k] ~= nil then
        local v = scrolls[k]
        if type(v) == "table" then return v.x or 0, v.y or 0 end
    end
    for i = 1, #scrolls do
        local s = scrolls[i]
        if s.id == id then return s.x, s.y end
    end
    return 0, 0
end

local function cursor_name(cursor)
    if cursor == nil or cursor == Style.CursorDefault then return "default" end
    if cursor == Style.CursorPointer then return "pointer" end
    if cursor == Style.CursorText then return "text" end
    if cursor == Style.CursorMove then return "move" end
    if cursor == Style.CursorGrab then return "grab" end
    if cursor == Style.CursorGrabbing then return "grabbing" end
    if cursor == Style.CursorNotAllowed then return "not-allowed" end
    return "default"
end

local function pointer_inside_xywh(x, y, rx, ry, rw, rh)
    return x ~= nil and y ~= nil and x >= rx and y >= ry and x < rx + rw and y < ry + rh
end

local function driver_push_clip_rect(driver, x, y, w, h)
    if driver == nil then return end
    if driver.push_clip_rect then return driver:push_clip_rect(x, y, w, h) end
    if driver.push_clip then return driver:push_clip(x, y, w, h) end
end

local function driver_pop_clip_rect(driver)
    if driver == nil then return end
    if driver.pop_clip_rect then return driver:pop_clip_rect() end
    if driver.pop_clip then return driver:pop_clip() end
end

local function driver_draw_box(driver, x, y, w, h, visual)
    if driver == nil then return end
    if driver.draw_box then return driver:draw_box(x, y, w, h, visual) end
    if driver.draw_rect then return driver:draw_rect(x, y, w, h, visual) end
end

local function run_common(driver, opts, want_report, g, p, c)
    opts = opts or {}

    local tx_x, tx_y = 0, 0
    local tx_stack_x, tx_stack_y = {}, {}
    local tx_top = 0

    local clip_x = { -WORLD }
    local clip_y = { -WORLD }
    local clip_w = { WORLD * 2 }
    local clip_h = { WORLD * 2 }
    local clip_top = 1

    local scroll_stack_x, scroll_stack_y = {}, {}
    local scroll_top = 0

    local pointer_x = opts.pointer_x
    local pointer_y = opts.pointer_y
    local hover_id = Core.NoId
    local cursor_id = Core.NoId
    local cursor = Style.CursorDefault
    local scroll_id = Core.NoId
    local hits = want_report and {} or nil
    local focusables = want_report and {} or nil
    local scrollables = want_report and {} or nil
    local drag_sources = want_report and {} or nil
    local drop_targets = want_report and {} or nil
    local drop_slots = want_report and {} or nil
    local hit_stack = want_report and {} or nil
    local layers = want_report and {} or nil
    local overlays = want_report and {} or nil
    local modal_barriers = want_report and {} or nil
    local focus_scopes = want_report and {} or nil
    local focus_scope_stack = want_report and {} or nil
    local layer_stack = want_report and {} or nil

    for _, op in g, p, c do
        local cls = pvm.classof(op)

        if cls == View.PushTx then
            tx_top = tx_top + 1
            tx_stack_x[tx_top] = tx_x
            tx_stack_y[tx_top] = tx_y
            tx_x = tx_x + op.dx
            tx_y = tx_y + op.dy

        elseif cls == View.PopTx then
            tx_x = tx_stack_x[tx_top] or 0
            tx_y = tx_stack_y[tx_top] or 0
            tx_stack_x[tx_top], tx_stack_y[tx_top] = nil, nil
            tx_top = tx_top - 1

        elseif cls == View.PushClipRect then
            local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
            local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            clip_top = clip_top + 1
            if ix == nil then
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = abs_x, abs_y, 0, 0
            else
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = ix, iy, iw, ih
            end
            driver_push_clip_rect(driver, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])

        elseif cls == View.PopClip then
            driver_pop_clip_rect(driver)
            clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = nil, nil, nil, nil
            clip_top = clip_top - 1

        elseif cls == View.PushScroll then
            local abs_x, abs_y, rw, rh = rect_abs(op.viewport, tx_x, tx_y)
            local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            local max_x = max0((op.content_w or 0) - rw)
            local max_y = max0((op.content_h or 0) - rh)
            if op.axis == Style.ScrollX then max_y = 0 elseif op.axis == Style.ScrollY then max_x = 0 end

            if want_report and ix ~= nil then
                scrollables[#scrollables + 1] = T.Interact.ScrollBox(op.id, op.axis or Style.ScrollBoth, rect_from_xywh(ix, iy, iw, ih), op.content_w or 0, op.content_h or 0, max_x, max_y)
                if pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then scroll_id = op.id end
            end

            scroll_top = scroll_top + 1
            scroll_stack_x[scroll_top] = tx_x
            scroll_stack_y[scroll_top] = tx_y

            clip_top = clip_top + 1
            if ix == nil then
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = abs_x, abs_y, 0, 0
            else
                clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = ix, iy, iw, ih
            end
            driver_push_clip_rect(driver, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])

            local scroll_x, scroll_y = scroll_lookup(opts.scrolls, op.id)
            if scroll_x < 0 then scroll_x = 0 elseif scroll_x > max_x then scroll_x = max_x end
            if scroll_y < 0 then scroll_y = 0 elseif scroll_y > max_y then scroll_y = max_y end
            tx_x = tx_x - scroll_x
            tx_y = tx_y - scroll_y

        elseif cls == View.PopScroll then
            driver_pop_clip_rect(driver)
            clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top] = nil, nil, nil, nil
            clip_top = clip_top - 1
            tx_x = scroll_stack_x[scroll_top] or 0
            tx_y = scroll_stack_y[scroll_top] or 0
            scroll_stack_x[scroll_top], scroll_stack_y[scroll_top] = nil, nil
            scroll_top = scroll_top - 1

        elseif cls == View.Box then
            local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
            local ix = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil then driver_draw_box(driver, abs_x, abs_y, rw, rh, op.visual) end

        elseif cls == View.Text then
            local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
            local ix = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil and driver and driver.draw_text then driver:draw_text(abs_x, abs_y, rw, rh, op.text, op.paint) end

        elseif cls == View.Paint then
            local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
            local ix = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
            if ix ~= nil and driver and driver.draw_paint and op.paint ~= nil then driver:draw_paint(abs_x, abs_y, rw, rh, op.paint) end

        elseif cls == View.Hit then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    local box = T.Interact.HitBox(op.id, rect_from_xywh(ix, iy, iw, ih))
                    hits[#hits + 1] = box
                    hit_stack[#hit_stack + 1] = box
                    if pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then hover_id = op.id end
                end
            end

        elseif cls == View.Focus then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    local slot = #focusables + 1
                    focusables[slot] = T.Interact.FocusBox(op.id, slot, rect_from_xywh(ix, iy, iw, ih))
                end
            end

        elseif cls == View.Cursor then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil and pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then
                    cursor = op.cursor
                    cursor_id = op.id
                end
            end

        elseif cls == View.DragSource then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then drag_sources[#drag_sources + 1] = T.Interact.DragSourceBox(op.id, rect_from_xywh(ix, iy, iw, ih)) end
            end

        elseif cls == View.DropTarget then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then drop_targets[#drop_targets + 1] = T.Interact.DropTargetBox(op.id, rect_from_xywh(ix, iy, iw, ih)) end
            end

        elseif cls == View.DropSlot then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then drop_slots[#drop_slots + 1] = T.Interact.DropSlotBox(op.id, rect_from_xywh(ix, iy, iw, ih)) end
            end

        elseif cls == View.BeginFocusScope then
            if want_report then
                focus_scope_stack[#focus_scope_stack + 1] = { id = op.id, first_slot = #focusables + 1, policy = op.policy or T.Interact.FocusWrap }
            end

        elseif cls == View.EndFocusScope then
            if want_report then
                local scope = focus_scope_stack[#focus_scope_stack]
                focus_scope_stack[#focus_scope_stack] = nil
                if scope ~= nil then focus_scopes[#focus_scopes + 1] = T.Interact.FocusScopeBox(scope.id, scope.policy, scope.first_slot, #focusables) end
            end

        elseif cls == View.BeginLayer then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                layer_stack[#layer_stack + 1] = op.id
                if ix ~= nil then layers[#layers + 1] = T.Interact.LayerBox(op.id, op.kind or T.Interact.LayerOverlay, op.order or #layer_stack, rect_from_xywh(ix, iy, iw, ih)) end
            end

        elseif cls == View.EndLayer then
            if want_report then layer_stack[#layer_stack] = nil end

        elseif cls == View.Overlay then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then overlays[#overlays + 1] = T.Interact.OverlayBox(op.id, op.anchor_id or Core.NoId, op.placement or T.Interact.PlaceAuto, op.modal == true, rect_from_xywh(ix, iy, iw, ih)) end
            end

        elseif cls == View.ModalBarrier then
            if want_report then
                local abs_x, abs_y, rw, rh = rect_abs(op.rect, tx_x, tx_y)
                local ix, iy, iw, ih = rect_intersect(abs_x, abs_y, rw, rh, clip_x[clip_top], clip_y[clip_top], clip_w[clip_top], clip_h[clip_top])
                if ix ~= nil then
                    modal_barriers[#modal_barriers + 1] = T.Interact.ModalBarrierBox(op.id, rect_from_xywh(ix, iy, iw, ih))
                    if pointer_inside_xywh(pointer_x, pointer_y, ix, iy, iw, ih) then
                        hover_id = Core.NoId
                        cursor_id = Core.NoId
                        cursor = Style.CursorDefault
                        scroll_id = Core.NoId
                        hits, hit_stack, focusables, scrollables = {}, {}, {}, {}
                        drag_sources, drop_targets, drop_slots = {}, {}, {}
                    end
                end
            end
        end
    end

    if want_report then
        if driver and driver.set_cursor_kind then
            driver:set_cursor_kind(cursor)
        elseif driver and driver.set_cursor then
            driver:set_cursor(cursor_name(cursor))
        end
        return T.Interact.Report(hover_id, cursor_id, cursor, scroll_id, hits, focusables, scrollables, drag_sources, drop_targets, drop_slots, hit_stack, layers, overlays, modal_barriers, focus_scopes)
    end
end

function M.run(driver, opts, g, p, c)
    return run_common(driver, opts, true, g, p, c)
end

function M.draw(driver, g, p, c)
    return run_common(driver, nil, false, g, p, c)
end

M.T = T

return M
