-- Lua Interpreter VM — First source-byte parser/compiler slice

local moon = require("moonlift")
local host = require("moonlift.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")

local V = {}
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = moon.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ExpKind) do V["EXP_" .. k] = moon.int(v) end

local parser_error = host.region(V) [[
region parser_error(cu: ptr(CompileUnit), code: i32;
                    error: cont(err: CompileError))
entry start()
    let tok: Token = cu.lexer.current
    let err: CompileError = {
        code = code,
        pos = { offset = tok.start, line = tok.line, col = 0 },
        token = tok.kind
    }
    jump error(err = err)
end
end
]]

local exp_to_reg = host.region(V) [[
region exp_to_reg(cu: ptr(CompileUnit), e: ExpDesc;
                  reg: cont(r: u16), semantic_error: cont(err: CompileError), oom: cont())
entry start()
    if e.kind == @{EXP_VLOCAL} or e.kind == @{EXP_VNONRELOC} then
        jump reg(r = as(u16, e.info))
    end
    emit parser_error(cu, @{PERR_EXPECTED_EXPR}; error = bad)
end
block bad(err: CompileError)
    jump semantic_error(err = err)
end
end
]]

local parse_primary = host.region(V) [[
region parse_primary(cu: ptr(CompileUnit);
                     parsed: cont(e: ExpDesc),
                     syntax_error: cont(err: CompileError),
                     semantic_error: cont(err: CompileError),
                     limit_error: cont(err: CompileError),
                     oom: cont())
entry start()
    let tok: Token = cu.lexer.current
    if tok.kind == @{TOK_INT} then
        jump int_primary(tok = tok)
    end
    if tok.kind == @{TOK_NAME} then
        jump name_primary(tok = tok)
    end
    if tok.kind == @{KW_TRUE} then jump true_primary(tok = tok) end
    if tok.kind == @{KW_FALSE} then jump false_primary(tok = tok) end
    if tok.kind == @{KW_NIL} then jump nil_primary(tok = tok) end
    emit parser_error(cu, @{PERR_EXPECTED_EXPR}; error = syntax_bad)
end
block int_primary(tok: Token)
    emit reserve_reg(cu; reg = got_int_reg, limit_error = too_big)
end
block got_int_reg(r: u16)
    cu.tmp_reg = r
    let tok: Token = cu.lexer.current
    emit emit_load_integer(cu, r, as(i64, tok.bits);
        ok = int_loaded,
        limit_error = too_big,
        oom = out_of_mem)
end
block int_loaded()
    let tok: Token = cu.lexer.current
    emit lex_next(cu; token = after_int, lexical_error = syntax_bad, oom = out_of_mem)
end
block after_int(tok: Token)
    let e: ExpDesc = { kind = as(u16, @{EXP_VNONRELOC}), info = as(u32, cu.tmp_reg), aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump parsed(e = e)
end
block true_primary(tok: Token)
    emit reserve_reg(cu; reg = got_true_reg, limit_error = too_big)
end
block got_true_reg(r: u16)
    cu.tmp_reg = r
    emit emit_load_true(cu, r; ok = literal_loaded, limit_error = too_big, oom = out_of_mem)
end
block false_primary(tok: Token)
    emit reserve_reg(cu; reg = got_false_reg, limit_error = too_big)
end
block got_false_reg(r: u16)
    cu.tmp_reg = r
    emit emit_load_false(cu, r; ok = literal_loaded, limit_error = too_big, oom = out_of_mem)
end
block nil_primary(tok: Token)
    emit reserve_reg(cu; reg = got_nil_reg, limit_error = too_big)
end
block got_nil_reg(r: u16)
    cu.tmp_reg = r
    emit emit_load_nil(cu, r; ok = literal_loaded, limit_error = too_big, oom = out_of_mem)
end
block literal_loaded()
    emit lex_next(cu; token = after_literal, lexical_error = syntax_bad, oom = out_of_mem)
end
block after_literal(tok: Token)
    let e: ExpDesc = { kind = as(u16, @{EXP_VNONRELOC}), info = as(u32, cu.tmp_reg), aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump parsed(e = e)
end
block name_primary(tok: Token)
    emit resolve_local(cu, tok; found = local_found, missing = local_missing)
end
block local_found(reg: u16)
    cu.tmp_reg = reg
    emit lex_next(cu; token = after_name, lexical_error = syntax_bad, oom = out_of_mem)
end
block after_name(tok: Token)
    let e: ExpDesc = { kind = as(u16, @{EXP_VLOCAL}), info = as(u32, cu.tmp_reg), aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump parsed(e = e)
end
block local_missing()
    emit parser_error(cu, @{PERR_UNDECLARED_NAME}; error = sem_bad)
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local parse_term = host.region(V) [[
region parse_term(cu: ptr(CompileUnit);
                  parsed: cont(e: ExpDesc),
                  syntax_error: cont(err: CompileError),
                  semantic_error: cont(err: CompileError),
                  limit_error: cont(err: CompileError),
                  oom: cont())
entry start()
    emit parse_primary(cu;
        parsed = first_factor,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block first_factor(e: ExpDesc)
    cu.expr_tmp2 = e
    jump loop()
end
block loop()
    if cu.lexer.current.kind == @{TOK_STAR} then
        emit lex_next(cu; token = mul_consumed, lexical_error = syntax_bad, oom = out_of_mem)
    end
    if cu.lexer.current.kind == @{TOK_SLASH} then
        emit lex_next(cu; token = div_consumed, lexical_error = syntax_bad, oom = out_of_mem)
    end
    jump parsed(e = cu.expr_tmp2)
end
block mul_consumed(tok: Token)
    emit parse_primary(cu;
        parsed = mul_rhs,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block div_consumed(tok: Token)
    emit parse_primary(cu;
        parsed = div_rhs,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block mul_rhs(e: ExpDesc)
    cu.expr_tmp3 = e
    emit exp_to_reg(cu, cu.expr_tmp2; reg = mul_left, semantic_error = sem_bad, oom = out_of_mem)
end
block mul_left(r: u16)
    emit exp_to_reg(cu, cu.expr_tmp3; reg = mul_right, semantic_error = sem_bad, oom = out_of_mem)
end
block mul_right(r: u16)
    let left: u16 = as(u16, cu.expr_tmp2.info)
    emit emit_mul(cu, left, left, r; ok = mul_done, limit_error = too_big, oom = out_of_mem)
end
block mul_done()
    cu.expr_tmp2 = { kind = as(u16, @{EXP_VNONRELOC}), info = cu.expr_tmp2.info, aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump loop()
end
block div_rhs(e: ExpDesc)
    cu.expr_tmp3 = e
    emit exp_to_reg(cu, cu.expr_tmp2; reg = div_left, semantic_error = sem_bad, oom = out_of_mem)
end
block div_left(r: u16)
    emit exp_to_reg(cu, cu.expr_tmp3; reg = div_right, semantic_error = sem_bad, oom = out_of_mem)
end
block div_right(r: u16)
    let left: u16 = as(u16, cu.expr_tmp2.info)
    emit emit_div(cu, left, left, r; ok = div_done, limit_error = too_big, oom = out_of_mem)
end
block div_done()
    cu.expr_tmp2 = { kind = as(u16, @{EXP_VNONRELOC}), info = cu.expr_tmp2.info, aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump loop()
end
block syntax_bad(err: CompileError) jump syntax_error(err = err) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local parse_expr = host.region(V) [[
region parse_expr(cu: ptr(CompileUnit), limit: u8;
                  parsed: cont(e: ExpDesc),
                  syntax_error: cont(err: CompileError),
                  semantic_error: cont(err: CompileError),
                  limit_error: cont(err: CompileError),
                  oom: cont())
entry start()
    emit parse_term(cu;
        parsed = first_term,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block first_term(e: ExpDesc)
    cu.expr_tmp = e
    jump loop()
end
block loop()
    if cu.lexer.current.kind == @{TOK_PLUS} then
        emit lex_next(cu; token = plus_consumed, lexical_error = syntax_bad, oom = out_of_mem)
    end
    if cu.lexer.current.kind == @{TOK_MINUS} then
        emit lex_next(cu; token = minus_consumed, lexical_error = syntax_bad, oom = out_of_mem)
    end
    jump parsed(e = cu.expr_tmp)
end
block plus_consumed(tok: Token)
    emit parse_term(cu;
        parsed = plus_rhs,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block minus_consumed(tok: Token)
    emit parse_term(cu;
        parsed = minus_rhs,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block plus_rhs(e: ExpDesc)
    cu.expr_tmp2 = e
    emit exp_to_reg(cu, cu.expr_tmp; reg = plus_left, semantic_error = sem_bad, oom = out_of_mem)
end
block plus_left(r: u16)
    emit exp_to_reg(cu, cu.expr_tmp2; reg = plus_right, semantic_error = sem_bad, oom = out_of_mem)
end
block plus_right(r: u16)
    let left: u16 = as(u16, cu.expr_tmp.info)
    emit emit_add(cu, left, left, r; ok = plus_done, limit_error = too_big, oom = out_of_mem)
end
block plus_done()
    cu.expr_tmp = { kind = as(u16, @{EXP_VNONRELOC}), info = cu.expr_tmp.info, aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump loop()
end
block minus_rhs(e: ExpDesc)
    cu.expr_tmp2 = e
    emit exp_to_reg(cu, cu.expr_tmp; reg = minus_left, semantic_error = sem_bad, oom = out_of_mem)
end
block minus_left(r: u16)
    emit exp_to_reg(cu, cu.expr_tmp2; reg = minus_right, semantic_error = sem_bad, oom = out_of_mem)
end
block minus_right(r: u16)
    let left: u16 = as(u16, cu.expr_tmp.info)
    emit emit_sub(cu, left, left, r; ok = minus_done, limit_error = too_big, oom = out_of_mem)
end
block minus_done()
    cu.expr_tmp = { kind = as(u16, @{EXP_VNONRELOC}), info = cu.expr_tmp.info, aux = 0, t = 0, f = 0, value = { tag = 0, aux = 0, bits = 0 } }
    jump loop()
end
block syntax_bad(err: CompileError) jump syntax_error(err = err) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local parse_return_statement = host.region(V) [[
region parse_return_statement(cu: ptr(CompileUnit);
                              returned: cont(),
                              syntax_error: cont(err: CompileError),
                              semantic_error: cont(err: CompileError),
                              limit_error: cont(err: CompileError),
                              oom: cont())
entry start()
    emit lex_next(cu; token = after_return_kw, lexical_error = syntax_bad, oom = out_of_mem)
end
block after_return_kw(tok: Token)
    emit parse_expr(cu, as(u8, 0);
        parsed = return_expr,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block return_expr(e: ExpDesc)
    cu.expr_tmp = e
    emit exp_to_reg(cu, e; reg = return_reg, semantic_error = sem_bad, oom = out_of_mem)
end
block return_reg(r: u16)
    emit emit_return1(cu, r; ok = ret_done, limit_error = too_big, oom = out_of_mem)
end
block ret_done()
    jump returned()
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local parse_local_statement = host.region(V) [[
region parse_local_statement(cu: ptr(CompileUnit);
                             next: cont(),
                             syntax_error: cont(err: CompileError),
                             semantic_error: cont(err: CompileError),
                             limit_error: cont(err: CompileError),
                             oom: cont())
entry start()
    emit lex_next(cu; token = got_name, lexical_error = syntax_bad, oom = out_of_mem)
end
block got_name(tok: Token)
    if tok.kind ~= @{TOK_NAME} then
        emit parser_error(cu, @{PERR_EXPECTED_NAME}; error = syntax_bad)
    end
    cu.token_tmp = tok
    emit lex_next(cu; token = got_assign, lexical_error = syntax_bad, oom = out_of_mem)
end
block got_assign(tok: Token)
    if tok.kind ~= @{TOK_ASSIGN} then
        emit parser_error(cu, @{PERR_EXPECTED_ASSIGN}; error = syntax_bad)
    end
    emit lex_next(cu; token = expr_start, lexical_error = syntax_bad, oom = out_of_mem)
end
block expr_start(tok: Token)
    emit parse_expr(cu, as(u8, 0);
        parsed = local_expr,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block local_expr(e: ExpDesc)
    cu.expr_tmp = e
    emit exp_to_reg(cu, e; reg = local_reg, semantic_error = sem_bad, oom = out_of_mem)
end
block local_reg(r: u16)
    emit add_local(cu, cu.token_tmp, r; ok = local_done, limit_error = too_big)
end
block local_done()
    jump next()
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local parse_statement = host.region(V) [[
region parse_statement(cu: ptr(CompileUnit);
                       next: cont(),
                       returned: cont(),
                       syntax_error: cont(err: CompileError),
                       semantic_error: cont(err: CompileError),
                       limit_error: cont(err: CompileError),
                       oom: cont())
entry start()
    let tok: Token = cu.lexer.current
    if tok.kind == @{KW_RETURN} then
        emit parse_return_statement(cu;
            returned = stmt_returned,
            syntax_error = syntax_bad,
            semantic_error = sem_bad,
            limit_error = too_big,
            oom = out_of_mem)
    end
    if tok.kind == @{KW_LOCAL} then
        emit parse_local_statement(cu;
            next = stmt_next,
            syntax_error = syntax_bad,
            semantic_error = sem_bad,
            limit_error = too_big,
            oom = out_of_mem)
    end
    if tok.kind == @{TOK_SEMI} then
        emit lex_next(cu; token = semi_done, lexical_error = syntax_bad, oom = out_of_mem)
    end
    emit parser_error(cu, @{PERR_UNEXPECTED_TOKEN}; error = syntax_bad)
end
block semi_done(tok: Token)
    jump next()
end
block stmt_next()
    jump next()
end
block stmt_returned()
    jump returned()
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local parse_block = host.region(V) [[
region parse_block(cu: ptr(CompileUnit);
                   done: cont(),
                   did_return: cont(),
                   syntax_error: cont(err: CompileError),
                   semantic_error: cont(err: CompileError),
                   limit_error: cont(err: CompileError),
                   oom: cont())
entry start()
    jump loop()
end
block loop()
    if cu.lexer.current.kind == @{TOK_EOF} then jump done() end
    emit parse_statement(cu;
        next = stmt_next,
        returned = stmt_returned,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block stmt_next()
    jump loop()
end
block stmt_returned()
    jump did_return()
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

local compile_prepared_unit = host.region(V) [[
region compile_prepared_unit(cu: ptr(CompileUnit);
                             ok: cont(proto: ptr(Proto)),
                             syntax_error: cont(err: CompileError),
                             semantic_error: cont(err: CompileError),
                             limit_error: cont(err: CompileError),
                             oom: cont())
entry start()
    emit lex_next(cu; token = first_token, lexical_error = syntax_bad, oom = out_of_mem)
end
block first_token(tok: Token)
    emit parse_block(cu;
        done = block_done,
        did_return = after_return,
        syntax_error = syntax_bad,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block after_return()
    if cu.lexer.current.kind == @{TOK_SEMI} then
        emit lex_next(cu; token = return_tail, lexical_error = syntax_bad, oom = out_of_mem)
    end
    if cu.lexer.current.kind == @{TOK_EOF} then jump block_done() end
    emit parser_error(cu, @{PERR_UNEXPECTED_TOKEN}; error = syntax_bad)
end
block return_tail(tok: Token)
    jump after_return()
end
block block_done()
    emit close_func_builder(cu; ok = closed, oom = out_of_mem)
end
block closed(proto: ptr(Proto))
    jump ok(proto = proto)
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block too_big(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    parser_error = parser_error,
    exp_to_reg = exp_to_reg,
    parse_primary = parse_primary,
    parse_term = parse_term,
    parse_expr = parse_expr,
    parse_return_statement = parse_return_statement,
    parse_local_statement = parse_local_statement,
    parse_statement = parse_statement,
    parse_block = parse_block,
    compile_prepared_unit = compile_prepared_unit,
}
