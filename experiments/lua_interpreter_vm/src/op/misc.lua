-- Moonlift VM — Misc opcode handlers (LEN, CONCAT, CLOSE, TBC, JMP, ERRNNIL)

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_len = R([[
region op_len(]] .. H .. [[;
              ]] .. B.STUB_CALL_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_concat = R([[
region op_concat(]] .. H .. [[;
                 ]] .. B.STUB_CALL_CONTS .. [[)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_close = R([[
region op_close(]] .. H .. [[;
                next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                oom: cont())
entry start()
    let close_idx: index = base + as(index, a)
    emit close_upvalues(L, close_idx;
        done = closed,
        oom = out_of_mem)
end
block closed()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_tbc = R([[
region op_tbc(]] .. H .. [[;
              next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
              error: cont(code: i32),
              oom: cont())
entry start()
    L.tbc_head = base + as(index, a)
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_jmp = R([[
region op_jmp(]] .. H .. [[;
              do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
entry start()
    let new_pc: index = as(index, as(i32, pc) + sbx)
    jump do_jump(frame = frame, pc = new_pc, base = base, top = top)
end
end
]])

local op_errnnil = R([[
region op_errnnil(]] .. H .. [[;
                  next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
                  error: cont(code: i32),
                  oom: cont())
entry start()
    let val: Value = L.stack[base + as(index, a)]
    if val.tag == @{TAG_NIL} then
        jump error(code = @{ERR_RUNTIME})
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_len = op_len, op_concat = op_concat,
    op_close = op_close, op_tbc = op_tbc,
    op_jmp = op_jmp, op_errnnil = op_errnnil,
}
