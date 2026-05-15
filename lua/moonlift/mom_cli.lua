-- CLI policy for the standalone `mom` binary.
-- Uses the native MOM pipeline (moon.native_dofile / moon.emit_object).
-- For .mlua files with Lua carrier code that MOM cannot handle yet,
-- falls back to moon.dofile (hosted-Lua pipeline).

local moon = require("moonlift")

local M = {}

local function usage(out)
    out:write([[usage:
  mom run [--call NAME] [--ret i32|void] [--arg-i32 N ...] FILE
  mom --emit-object -o OUT.o [--module-name NAME] FILE

The run path compiles the source through MOM and calls NAME (default: main).
The object path emits a relocatable object through moonlift_object_compile_binary.
]])
end

local function parse(argv)
    local opts = { mode = "run", call = "main", ret = "i32", args_i32 = {} }
    local i = 1
    if argv[i] == "run" then opts.mode = "run"; i = i + 1 end
    while i <= #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then
            opts.help = true
            return opts
        elseif a == "--emit-object" then
            opts.mode = "object"
        elseif a == "-o" then
            i = i + 1; opts.output = argv[i]
        elseif a == "--module-name" then
            i = i + 1; opts.module_name = argv[i]
        elseif a == "--call" then
            i = i + 1; opts.call = argv[i]
        elseif a == "--ret" then
            i = i + 1; opts.ret = argv[i]
        elseif a == "--arg-i32" then
            i = i + 1; opts.args_i32[#opts.args_i32 + 1] = tonumber(argv[i]) or error("--arg-i32 expects an integer")
        elseif a:sub(1, 1) == "-" then
            error("unknown option " .. a)
        elseif not opts.input then
            opts.input = a
        else
            error("unexpected argument " .. a)
        end
        i = i + 1
    end
    return opts
end

function M.run(argv)
    local ok, err = xpcall(function()
        argv = argv or {}
        local opts = parse(argv)
        if opts.help then usage(io.stdout); return 0 end
        if not opts.input then usage(io.stderr); return 2 end
        if opts.mode == "object" and not opts.output then error("--emit-object requires -o OUT.o") end

        local source_file = io.open(opts.input, "rb")
        if not source_file then error("unable to open " .. tostring(opts.input)) end
        local source = source_file:read("*a")
        source_file:close()

        if opts.mode == "object" then
            moon.host_mom.emit_object(source, opts.output, opts.module_name or opts.input:gsub("[/\\]", "_"):gsub("%.mlua$", ""))
            io.stdout:write(opts.output, "\n")
            return 0
        end

        -- Try native MOM path first.
        local ok_native, result = pcall(moon.native_loadstring, source)
        if ok_native then
            local compiled = result
            local ptr = compiled:get(opts.call)
            local ffi = require("ffi")
            local nargs = #opts.args_i32
            local function call_i32(ptr_sig, args)
                return ffi.cast(ptr_sig, ptr)(unpack(args, 1, #args))
            end
            if opts.ret == "void" then
                local sigs = {
                    [0] = "void (*)()",
                    [1] = "void (*)(int32_t)",
                    [2] = "void (*)(int32_t,int32_t)",
                    [3] = "void (*)(int32_t,int32_t,int32_t)",
                    [4] = "void (*)(int32_t,int32_t,int32_t,int32_t)",
                }
                call_i32(sigs[nargs] or error("too many args"), opts.args_i32)
            elseif opts.ret == "i32" then
                local sigs = {
                    [0] = "int32_t (*)()",
                    [1] = "int32_t (*)(int32_t)",
                    [2] = "int32_t (*)(int32_t,int32_t)",
                    [3] = "int32_t (*)(int32_t,int32_t,int32_t)",
                    [4] = "int32_t (*)(int32_t,int32_t,int32_t,int32_t)",
                }
                local r = call_i32(sigs[nargs] or error("too many args"), opts.args_i32)
                io.stdout:write(tostring(tonumber(r)), "\n")
            else
                error("unsupported --ret " .. tostring(opts.ret))
            end
            compiled:free()
            return 0
        end

        -- .mlua with Lua carrier — fall back to hosted-Lua pipeline.
        local mod = moon.dofile(opts.input)
        if type(mod) ~= "table" or not mod.compile then
            error("hosted fallback did not produce a module")
        end
        local compiled_hosted = mod:compile()
        local ptr_hosted = compiled_hosted.artifact:getpointer(opts.call)
        local ffi = require("ffi")
        local nargs = #opts.args_i32
        local function call_i32_hosted(ptr_sig, args)
            return ffi.cast(ptr_sig, ptr_hosted)(unpack(args, 1, #args))
        end
        if opts.ret == "void" then
            local sigs = {
                [0] = "void (*)()",
                [1] = "void (*)(int32_t)",
                [2] = "void (*)(int32_t,int32_t)",
                [3] = "void (*)(int32_t,int32_t,int32_t)",
                [4] = "void (*)(int32_t,int32_t,int32_t,int32_t)",
            }
            call_i32_hosted(sigs[nargs] or error("too many args"), opts.args_i32)
        elseif opts.ret == "i32" then
            local sigs = {
                [0] = "int32_t (*)()",
                [1] = "int32_t (*)(int32_t)",
                [2] = "int32_t (*)(int32_t,int32_t)",
                [3] = "int32_t (*)(int32_t,int32_t,int32_t)",
                [4] = "int32_t (*)(int32_t,int32_t,int32_t,int32_t)",
            }
            local r = call_i32_hosted(sigs[nargs] or error("too many args"), opts.args_i32)
            io.stdout:write(tostring(tonumber(r)), "\n")
        else
            error("unsupported --ret " .. tostring(opts.ret))
        end
        compiled_hosted.artifact:free()
        return 0
    end, debug.traceback)

    if ok then return err or 0 end
    io.stderr:write(tostring(err), "\n")
    return 1
end

return M