package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ui = require("ui")

local b = ui.build
local tw = ui.tw
local theme = ui.theme.default()
local env = ui.theme.env_for_width(320)

local function one(node)
    local out = ui.lower.root(node, theme, env)
    assert(#out == 1, "expected one scene")
    return out[1]
end

-- Visual-only changes must not perturb layout identity.
do
    local a = one(b.box { b.id("same"), tw.w_px(100), tw.h_px(20), tw.bg.slate[800] })
    local b_ = one(b.box { b.id("same"), tw.w_px(100), tw.h_px(20), tw.bg.sky[600] })
    assert(a.layout == b_.layout, "background color is decor, not layout")
    assert(a.decor ~= b_.decor, "background color changes decor")
end

-- Text paint is not text measurement.
do
    local a = one(b.text { b.id("label"), tw.text_base, tw.fg.white, "Hello" })
    local b_ = one(b.text { b.id("label"), tw.text_base, tw.fg.sky[400], "Hello" })
    assert(a.layout == b_.layout, "text fg is decor, not text metrics/layout")
    assert(a.decor ~= b_.decor, "text fg changes decor")
end

-- Cursor is interaction/decor, not layout.
do
    local a = one(b.box { b.id("hit"), tw.w_px(10), tw.h_px(10), tw.cursor_pointer })
    local b_ = one(b.box { b.id("hit"), tw.w_px(10), tw.h_px(10), tw.cursor_not_allowed })
    assert(a.layout == b_.layout, "cursor is not layout")
    assert(a.decor ~= b_.decor, "cursor changes decor")
end

print("ok test_ui_style_fact_boundaries")
