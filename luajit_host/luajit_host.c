// luajit_host.c — JIT compile + FFI-callable via trampoline
// v3: jit.compile_raw returns wrapped C-callable function pointer
#include "lj_obj.h"
#include "lj_jit.h"
#include "lj_ir.h"
#include "lj_iropt.h"
#include "lj_asm.h"
#include "lj_trace.h"
#include "lj_mcode.h"
#include "lj_gc.h"
#include "lj_state.h"
#include "lj_dispatch.h"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>

typedef struct { int o, t, op1, op2, i; } PackedIRIns;

// Compiled trace wrapper
typedef struct {
    uint8_t *mcode;
    size_t mcode_len;
    uint8_t *entry;   // trampoline entry
    int nresults;     // number of i32 results
} TraceWrap;

static TraceWrap **traces = NULL;
static int ntraces = 0;

static int cf_lj_jit_init(lua_State *L) {
    lj_trace_initstate(G(L));
    lj_dispatch_init_hotcount(G(L));
    lj_dispatch_update(G(L));
    jit_State *J = L2J(L);
    J->L = L;
    MCode *lim;
    lj_mcode_reserve(J, &lim);
    lua_pushboolean(L, 1);
    return 1;
}

// Trampoline: called as int(*)(void *stack, int arg1, int arg2, ...)
// The trace writes results to [RDX-offset], so we set RDX = stack+offset.
// The vmstate write to [R14-0xee8] is harmless — R14 points to valid GL.
// We just need to append a ret and make result readable.
static void make_callable(TraceWrap *tw) {
    uint8_t *raw = tw->mcode;
    size_t sz = tw->mcode_len;
    
    // Allocate RWX memory for trampoline + mcode
    size_t total = 128 + sz + 16;
    uint8_t *mem = mmap(NULL, total, PROT_READ|PROT_WRITE|PROT_EXEC,
                        MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return;
    
    // Trampoline: set up RDX = stack buffer passed as arg1 (RDI)
    // mov rdx, rdi   ; stack ptr from arg1
    // xor eax, eax   ; prep for return
    // call mcode
    // ret
    int pos = 0;
    uint8_t *tramp = mem;
    tramp[pos++] = 0x48; tramp[pos++] = 0x89; tramp[pos++] = 0xFA;  // mov rdx, rdi
    tramp[pos++] = 0x48; tramp[pos++] = 0x8D; tramp[pos++] = 0x42; tramp[pos++] = 0xF0;  // lea rax, [rdx-0x10] (result slot 0)
    tramp[pos++] = 0x50;  // push rax (save result ptr)
    tramp[pos++] = 0x31; tramp[pos++] = 0xC0;  // xor eax, eax
    
    // Copy mcode (the trace) after trampoline
    uint8_t *mcode_target = tramp + 64;  // leave space, align
    while ((uintptr_t)(mcode_target) % 16 != 0) mcode_target++;
    memcpy(mcode_target, raw, sz);
    
    // Patch the jmp at end to ret, AND nop out vmstate write at start
    // The vmstate write is: 41 c7 86 18 f1 ff ff 01 00 00 00 (mov [r14-0xee8], 1)
    // Nop it to avoid needing valid R14
    if (sz >= 11 && mcode_target[0] == 0x41 && mcode_target[1] == 0xc7) {
        for (int j = 0; j < 11; j++) mcode_target[j] = 0x90;
    }
    for (int i = (int)sz - 5; i >= 0; i--) {
        if (mcode_target[i] == 0xe9) {
            mcode_target[i] = 0xc3;  // ret
            for (int j = 1; j <= 4; j++) mcode_target[i+j] = 0x90;  // nop
            break;
        }
    }
    
    // Call into mcode
    int call_pos = pos;
    uint8_t *tramp_call = tramp + call_pos;
    int32_t rel = (int32_t)(mcode_target - (tramp_call + 5));
    tramp_call[0] = 0xE8;  // call rel32
    memcpy(tramp_call + 1, &rel, 4);
    pos = call_pos + 5;
    
    // After call: pop rcx (result ptr); mov eax, [rcx]; ret
    tramp[pos++] = 0x59;  // pop rcx (result pointer from stack)
    tramp[pos++] = 0x8B; tramp[pos++] = 0x01;  // mov eax, [rcx]
    tramp[pos++] = 0xC3;  // ret
    
    tw->entry = tramp;
    tw->mcode = mcode_target;  // for inspection
}

static int cf_ir_trace_compile_raw(lua_State *L) {
    jit_State *J = L2J(L);
    J->L = L;
    luaL_checktype(L, 1, LUA_TTABLE);
    int nir = (int)lua_objlen(L, 1);
    int nk  = (int)luaL_optinteger(L, 2, 0);
    int topslot = (int)luaL_optinteger(L, 3, 0);
    int nent = (int)luaL_optinteger(L, 4, 0);
    int nslots = (int)luaL_optinteger(L, 5, 0);
    int ni  = nir - nk;
    if (ni < 1) { lua_pushnil(L); lua_pushstring(L, "ni<1"); return 2; }

    PackedIRIns *d = malloc((size_t)nir * sizeof(PackedIRIns));
    for (int i=0;i<nir;i++){
        lua_rawgeti(L,1,i+1);
        lua_getfield(L,-1,"o"); d[i].o=(int)lua_tointeger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"t"); d[i].t=(int)lua_tointeger(L,-1); lua_pop(L,1);
        lua_getfield(L,-1,"op1");d[i].op1=(int)lua_tointeger(L,-1);lua_pop(L,1);
        lua_getfield(L,-1,"op2");d[i].op2=(int)lua_tointeger(L,-1);lua_pop(L,1);
        lua_getfield(L,-1,"i");  d[i].i=(int)lua_tointeger(L,-1);  lua_pop(L,1);
        lua_pop(L,1);
    }

    int total = REF_BIAS + ni + 64;
    IRIns *irbuf = calloc((size_t)total, sizeof(IRIns));
    irbuf[REF_NIL].o=IR_KPRI;   irbuf[REF_NIL].t.irt=IRT_NIL;
    irbuf[REF_TRUE].o=IR_KPRI;  irbuf[REF_TRUE].t.irt=IRT_TRUE;
    irbuf[REF_FALSE].o=IR_KPRI; irbuf[REF_FALSE].t.irt=IRT_FALSE;

    for (int i=0;i<nk;i++) {
        IRIns *ins=&irbuf[i];
        ins->o=(IROp1)d[i].o; ins->t.irt=(uint8_t)d[i].t;
        ins->op1=(IRRef1)d[i].op1; ins->op2=(IRRef1)d[i].op2;
        ins->i=d[i].i; ins->prev=0;
    }
    for (int i=0;i<ni;i++) {
        IRIns *ins=&irbuf[REF_BIAS+i];
        int idx=nk+i;
        ins->o=(IROp1)d[idx].o; ins->t.irt=(uint8_t)d[idx].t;
        ins->op1=(IRRef1)d[idx].op1; ins->op2=(IRRef1)d[idx].op2;
        ins->i=d[idx].i; ins->prev=0;
    }
    free(d);

    GCproto *pt = lj_mem_new(L, sizeof(GCproto));
    memset(pt,0,sizeof(GCproto)); pt->gct=(uint8_t)~LJ_TPROTO;

    GCtrace *T = lj_mem_new(L, sizeof(GCtrace));
    memset(T,0,sizeof(GCtrace));
    setgcrefp(T->startpt, pt);
    T->topslot=(uint8_t)topslot; T->traceno=1; T->link=1; T->linktype=LJ_TRLINK_ROOT;
    T->nins=REF_BIAS+ni; T->nk=REF_BIAS; T->ir=irbuf;
    T->nsnap=1; T->nsnapmap=1;
    T->snap=lj_mem_new(L, sizeof(SnapShot));
    T->snapmap=lj_mem_new(L, sizeof(SnapEntry));
    memset(T->snap,0,sizeof(SnapShot));
    memset(T->snapmap,0,sizeof(SnapEntry));
    T->snap[0].mapofs=0; T->snap[0].nent=(uint8_t)nent; T->snap[0].nslots=(uint8_t)nslots;

    if (J->sizetrace < 2) { J->sizetrace = 2; J->trace = lj_mem_newvec(L, 2, GCRef); }
    setgcrefp(J->trace[1], T);

    memset(&J->cur,0,sizeof(GCtrace));
    J->cur.traceno=1; J->cur.link=1; J->cur.linktype=LJ_TRLINK_ROOT;
    J->cur.ir=irbuf; J->cur.nins=REF_BIAS+ni; J->cur.nk=REF_BIAS;
    J->cur.nsnap=1; J->cur.nsnapmap=1;
    J->cur.snap=T->snap; J->cur.snapmap=T->snapmap;
    J->irtoplim=REF_BIAS+ni+64; J->irbotlim=0; J->loopref=0;
    J->parent=0;
    J->bc_min=NULL; J->bc_extent=0; J->pt=NULL; J->pc=NULL;
    J->curfinal=T; T->mcode=J->mctop;
    memset(&J->fold,0,sizeof(J->fold)); J->fold.ins.o=IR_NOP;
    memset(J->chain,0,sizeof(J->chain));

    lj_opt_fold(J);
    lj_opt_cse(J);
    lj_opt_dce(J);
    lj_opt_sink(J);

    T->nins=J->cur.nins; T->nk=J->cur.nk; T->ir=irbuf;
    lj_asm_trace(J, T);

    TraceWrap *tw = malloc(sizeof(TraceWrap));
    tw->mcode_len = T->szmcode;
    tw->mcode = malloc(tw->mcode_len);
    memcpy(tw->mcode, T->mcode, tw->mcode_len);
    tw->nresults = topslot;
    
    make_callable(tw);
    
    // Store for cleanup
    ntraces++;
    traces = realloc(traces, (size_t)ntraces * sizeof(TraceWrap*));
    traces[ntraces-1] = tw;

    lua_newtable(L);
    lua_pushlightuserdata(L, tw->entry); lua_setfield(L,-2,"entry");
    lua_pushinteger(L, (lua_Integer)tw->mcode_len); lua_setfield(L,-2,"size");
    lua_pushinteger(L, T->nins - T->nk); lua_setfield(L,-2,"nins");

    free(irbuf);
    lj_mem_free(G(L),pt,sizeof(GCproto));
    lj_mem_free(G(L),T,sizeof(GCtrace));
    return 1;
}

static const luaL_Reg jit_lib[]={
    {"init",cf_lj_jit_init},
    {"compile",cf_ir_trace_compile_raw},
    {NULL,NULL}
};

int main(int argc,char**argv){
    lua_State*L=luaL_newstate(); luaL_openlibs(L);
    lua_getglobal(L,"jit");
    if(lua_isnil(L,-1)){lua_pop(L,1);lua_newtable(L);lua_setglobal(L,"jit");lua_getglobal(L,"jit");}
    luaL_setfuncs(L,jit_lib,0); lua_pop(L,1);
    if(argc<2){printf("luajit_host — -e code\n");lua_close(L);return 0;}
    int s=0;
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-e")&&i+1<argc)s=luaL_dostring(L,argv[++i]);
        else s=luaL_dofile(L,argv[i]);
        if(s){fprintf(stderr,"%s\n",lua_tostring(L,-1));lua_pop(L,1);}
    }
    for(int i=0;i<ntraces;i++){
        TraceWrap *tw=traces[i];
        if(tw->entry)munmap(tw->entry,128+tw->mcode_len+16);
        free(tw->mcode);free(tw);
    }
    free(traces);
    lua_close(L);return s;
}
