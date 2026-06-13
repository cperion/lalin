local session = require("ui.session")
local backend = require("ui.backends.sdl3")

local M = {
    backend = backend,
    capabilities = backend.capabilities,
}

function M.new(opts)
    opts = opts or {}
    if opts.backend == nil then
        opts.backend = backend
    end
    if opts.register_text == nil then
        opts.register_text = true
    end
    return session.new(opts)
end

return M
