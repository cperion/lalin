-- Moonlift VM — Closure/Vararg opcode handlers

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_closure = R([[
region op_closure(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_vararg = R([[
region op_vararg(]] .. H .. [[;
                 next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                 error: cont(code: i32),
                 oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_getvarg = R([[
region op_getvarg(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_varargprep = R([[
region op_varargprep(]] .. H .. [[;
                     next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                     oom: cont())
entry start()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_closure = op_closure,
    op_vararg = op_vararg, op_getvarg = op_getvarg, op_varargprep = op_varargprep,
}
