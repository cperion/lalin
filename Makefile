MOONLIFT  = target/release/moonlift
MOM       = target/release/mom
LUAJIT    = .vendor/LuaJIT/src
MOM_OBJS  = target/mom_objs

.PHONY: all clean mom-objs

all: $(MOONLIFT) $(MOM)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

mom-objs: $(MOONLIFT)
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	LUA_PATH="./lua/?.lua;./lua/?/init.lua" \
	$(CURDIR)/$(LUAJIT)/luajit scripts/emit_mom_objects.lua $(MOM_OBJS)
	ar rcs $(MOM_OBJS)/libmom_precompiled.a $(MOM_OBJS)/*.o

$(MOM): $(LUAJIT)/libluajit.a mom-objs
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin mom

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_lua.rs
	rm -rf $(MOM_OBJS)

run:
	$(MOONLIFT) $(FILE)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
