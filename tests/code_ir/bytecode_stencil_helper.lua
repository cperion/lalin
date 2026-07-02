package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local M = {}

function M.compile(T, artifacts, opts)
    opts = opts or {}
    if opts.ffi_preamble ~= nil and opts.ffi_preamble ~= "" then
        require("ffi").cdef(opts.ffi_preamble)
    end
    local BytecodeTrace = require("lalin.residual_luatrace")(T)
    return BytecodeTrace.realize_bc_artifacts(artifacts or {}, {
        stem = opts.stem,
        id = opts.id,
        target = opts.target,
        env = opts.env,
        bank = opts.bank,
    })
end

return M
