local M = {}

local function usage(out)
    out:write(table.concat({
        "usage: lalin [--version] [-e chunk] [file [args...]]",
        "",
        "Runs with Lalin's Lua module graph embedded in the executable.",
        "",
    }, "\n"))
end

local function run_chunk(src, chunk_name, args)
    local loader, err = loadstring(src, chunk_name)
    if loader == nil then return nil, err end
    return pcall(loader, unpack(args or {}))
end

function M.main(argv)
    argv = argv or _G.arg or {}
    local cmd = argv[1]
    if cmd == nil or cmd == "-h" or cmd == "--help" then
        usage(io.stdout)
        return 0
    end
    if cmd == "--version" then
        local lalin = require("lalin")
        io.stdout:write("lalin ", tostring(lalin.VERSION or "dev"), "\n")
        return 0
    end
    if cmd == "-e" then
        local src = argv[2]
        if src == nil then
            io.stderr:write("lalin: -e requires a chunk\n")
            return 64
        end
        local args = {}
        for i = 3, #argv do args[#args + 1] = argv[i] end
        local ok, err = run_chunk(src, "=(lalin -e)", args)
        if not ok then
            io.stderr:write(tostring(err), "\n")
            return 70
        end
        return 0
    end
    local f, err = io.open(cmd, "rb")
    if f == nil then
        io.stderr:write("lalin: cannot open ", tostring(cmd), ": ", tostring(err), "\n")
        return 66
    end
    local src = f:read("*a")
    f:close()
    local args = {}
    for i = 2, #argv do args[#args + 1] = argv[i] end
    local ok, run_err = run_chunk(src, "@" .. tostring(cmd), args)
    if not ok then
        io.stderr:write(tostring(run_err), "\n")
        return 70
    end
    return 0
end

return M
