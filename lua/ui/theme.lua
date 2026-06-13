local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Theme = T.Theme
local Env = T.Env

local M = {}

local function rgba(hex, alpha)
    alpha = alpha == nil and 0xff or alpha
    return hex * 0x100 + alpha
end

local function palette(values)
    return Theme.Palette(
        rgba(values[50]),
        rgba(values[100]),
        rgba(values[200]),
        rgba(values[300]),
        rgba(values[400]),
        rgba(values[500]),
        rgba(values[600]),
        rgba(values[700]),
        rgba(values[800]),
        rgba(values[900]),
        rgba(values[950])
    )
end

local palettes = {
    slate = palette { [50]=0xf8fafc, [100]=0xf1f5f9, [200]=0xe2e8f0, [300]=0xcbd5e1, [400]=0x94a3b8, [500]=0x64748b, [600]=0x475569, [700]=0x334155, [800]=0x1e293b, [900]=0x0f172a, [950]=0x020617 },
    gray = palette { [50]=0xf9fafb, [100]=0xf3f4f6, [200]=0xe5e7eb, [300]=0xd1d5db, [400]=0x9ca3af, [500]=0x6b7280, [600]=0x4b5563, [700]=0x374151, [800]=0x1f2937, [900]=0x111827, [950]=0x030712 },
    zinc = palette { [50]=0xfafafa, [100]=0xf4f4f5, [200]=0xe4e4e7, [300]=0xd4d4d8, [400]=0xa1a1aa, [500]=0x71717a, [600]=0x52525b, [700]=0x3f3f46, [800]=0x27272a, [900]=0x18181b, [950]=0x09090b },
    neutral = palette { [50]=0xfafafa, [100]=0xf5f5f5, [200]=0xe5e5e5, [300]=0xd4d4d4, [400]=0xa3a3a3, [500]=0x737373, [600]=0x525252, [700]=0x404040, [800]=0x262626, [900]=0x171717, [950]=0x0a0a0a },
    stone = palette { [50]=0xfafaf9, [100]=0xf5f5f4, [200]=0xe7e5e4, [300]=0xd6d3d1, [400]=0xa8a29e, [500]=0x78716c, [600]=0x57534e, [700]=0x44403c, [800]=0x292524, [900]=0x1c1917, [950]=0x0c0a09 },
    red = palette { [50]=0xfef2f2, [100]=0xfee2e2, [200]=0xfecaca, [300]=0xfca5a5, [400]=0xf87171, [500]=0xef4444, [600]=0xdc2626, [700]=0xb91c1c, [800]=0x991b1b, [900]=0x7f1d1d, [950]=0x450a0a },
    orange = palette { [50]=0xfff7ed, [100]=0xffedd5, [200]=0xfed7aa, [300]=0xfdba74, [400]=0xfb923c, [500]=0xf97316, [600]=0xea580c, [700]=0xc2410c, [800]=0x9a3412, [900]=0x7c2d12, [950]=0x431407 },
    amber = palette { [50]=0xfffbeb, [100]=0xfef3c7, [200]=0xfde68a, [300]=0xfcd34d, [400]=0xfbbf24, [500]=0xf59e0b, [600]=0xd97706, [700]=0xb45309, [800]=0x92400e, [900]=0x78350f, [950]=0x451a03 },
    yellow = palette { [50]=0xfefce8, [100]=0xfef9c3, [200]=0xfef08a, [300]=0xfde047, [400]=0xfacc15, [500]=0xeab308, [600]=0xca8a04, [700]=0xa16207, [800]=0x854d0e, [900]=0x713f12, [950]=0x422006 },
    lime = palette { [50]=0xf7fee7, [100]=0xecfccb, [200]=0xd9f99d, [300]=0xbef264, [400]=0xa3e635, [500]=0x84cc16, [600]=0x65a30d, [700]=0x4d7c0f, [800]=0x3f6212, [900]=0x365314, [950]=0x1a2e05 },
    green = palette { [50]=0xf0fdf4, [100]=0xdcfce7, [200]=0xbbf7d0, [300]=0x86efac, [400]=0x4ade80, [500]=0x22c55e, [600]=0x16a34a, [700]=0x15803d, [800]=0x166534, [900]=0x14532d, [950]=0x052e16 },
    emerald = palette { [50]=0xecfdf5, [100]=0xd1fae5, [200]=0xa7f3d0, [300]=0x6ee7b7, [400]=0x34d399, [500]=0x10b981, [600]=0x059669, [700]=0x047857, [800]=0x065f46, [900]=0x064e3b, [950]=0x022c22 },
    teal = palette { [50]=0xf0fdfa, [100]=0xccfbf1, [200]=0x99f6e4, [300]=0x5eead4, [400]=0x2dd4bf, [500]=0x14b8a6, [600]=0x0d9488, [700]=0x0f766e, [800]=0x115e59, [900]=0x134e4a, [950]=0x042f2e },
    cyan = palette { [50]=0xecfeff, [100]=0xcffafe, [200]=0xa5f3fc, [300]=0x67e8f9, [400]=0x22d3ee, [500]=0x06b6d4, [600]=0x0891b2, [700]=0x0e7490, [800]=0x155e75, [900]=0x164e63, [950]=0x083344 },
    sky = palette { [50]=0xf0f9ff, [100]=0xe0f2fe, [200]=0xbae6fd, [300]=0x7dd3fc, [400]=0x38bdf8, [500]=0x0ea5e9, [600]=0x0284c7, [700]=0x0369a1, [800]=0x075985, [900]=0x0c4a6e, [950]=0x082f49 },
    blue = palette { [50]=0xeff6ff, [100]=0xdbeafe, [200]=0xbfdbfe, [300]=0x93c5fd, [400]=0x60a5fa, [500]=0x3b82f6, [600]=0x2563eb, [700]=0x1d4ed8, [800]=0x1e40af, [900]=0x1e3a8a, [950]=0x172554 },
    indigo = palette { [50]=0xeef2ff, [100]=0xe0e7ff, [200]=0xc7d2fe, [300]=0xa5b4fc, [400]=0x818cf8, [500]=0x6366f1, [600]=0x4f46e5, [700]=0x4338ca, [800]=0x3730a3, [900]=0x312e81, [950]=0x1e1b4b },
    violet = palette { [50]=0xf5f3ff, [100]=0xede9fe, [200]=0xddd6fe, [300]=0xc4b5fd, [400]=0xa78bfa, [500]=0x8b5cf6, [600]=0x7c3aed, [700]=0x6d28d9, [800]=0x5b21b6, [900]=0x4c1d95, [950]=0x2e1065 },
    purple = palette { [50]=0xfaf5ff, [100]=0xf3e8ff, [200]=0xe9d5ff, [300]=0xd8b4fe, [400]=0xc084fc, [500]=0xa855f7, [600]=0x9333ea, [700]=0x7e22ce, [800]=0x6b21a8, [900]=0x581c87, [950]=0x3b0764 },
    fuchsia = palette { [50]=0xfdf4ff, [100]=0xfae8ff, [200]=0xf5d0fe, [300]=0xf0abfc, [400]=0xe879f9, [500]=0xd946ef, [600]=0xc026d3, [700]=0xa21caf, [800]=0x86198f, [900]=0x701a75, [950]=0x4a044e },
    pink = palette { [50]=0xfdf2f8, [100]=0xfce7f3, [200]=0xfbcfe8, [300]=0xf9a8d4, [400]=0xf472b6, [500]=0xec4899, [600]=0xdb2777, [700]=0xbe185d, [800]=0x9d174d, [900]=0x831843, [950]=0x500724 },
    rose = palette { [50]=0xfff1f2, [100]=0xffe4e6, [200]=0xfecdd3, [300]=0xfda4af, [400]=0xfb7185, [500]=0xf43f5e, [600]=0xe11d48, [700]=0xbe123c, [800]=0x9f1239, [900]=0x881337, [950]=0x4c0519 },
}

local spacing = Theme.SpaceScale(
    0, 2, 4, 6, 8, 10, 12, 14,
    16, 20, 24, 28, 32, 36, 40, 44,
    48, 56, 64, 80, 96, 112, 128, 144,
    160, 176, 192, 208, 224, 240, 256, 288,
    320, 384, 1
)

local font_sizes = Theme.FontScale(12, 14, 16, 18, 20, 24, 30, 36, 48, 60)
local radii = Theme.RadiusScale(0, 2, 4, 6, 8, 12, 16, 24, 9999)
local borders = Theme.BorderScale(0, 1, 2, 4, 8)
local opacities = Theme.OpacityScale(0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100)
local fonts = Theme.Fonts(1, 2, 3, 4, 5)

function M.default(opts)
    opts = opts or {}
    return Theme.T(
        palettes.slate, palettes.gray, palettes.zinc, palettes.neutral, palettes.stone,
        palettes.red, palettes.orange, palettes.amber, palettes.yellow, palettes.lime,
        palettes.green, palettes.emerald, palettes.teal, palettes.cyan, palettes.sky,
        palettes.blue, palettes.indigo, palettes.violet, palettes.purple, palettes.fuchsia,
        palettes.pink, palettes.rose,
        opts.white or rgba(0xffffff),
        opts.black or rgba(0x000000),
        opts.transparent or 0,
        opts.spacing or spacing,
        opts.font_sizes or font_sizes,
        opts.radii or radii,
        opts.borders or borders,
        opts.opacities or opacities,
        opts.fonts or fonts
    )
end

M.dark = M.default

function M.env(opts)
    opts = opts or {}
    return Env.Class(
        opts.bp or Env.Lg,
        opts.scheme or Env.Dark,
        opts.motion or Env.MotionSafe,
        opts.density or Env.D1x
    )
end

function M.env_for_width(width, opts)
    opts = opts or {}
    local bp = Env.Sm
    if width >= 1536 then bp = Env.X2l
    elseif width >= 1280 then bp = Env.Xl
    elseif width >= 1024 then bp = Env.Lg
    elseif width >= 768 then bp = Env.Md
    end
    opts.bp = opts.bp or bp
    return M.env(opts)
end

M.palettes = palettes
M.spacing = spacing
M.font_sizes = font_sizes
M.radii = radii
M.borders = borders
M.opacities = opacities
M.fonts = fonts
M.T = T

return M
