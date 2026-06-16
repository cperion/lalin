MOONLIFT  = target/release/moonlift
LUAJIT    = .vendor/LuaJIT/src
MOONLIB   = target/release/libmoonlift.so

.PHONY: all clean run bench

all: $(MOONLIFT)

$(LUAJIT)/libluajit.a:
	$(MAKE) -C $(LUAJIT) CFLAGS="-fPIC"
	ln -sf libluajit.a $(LUAJIT)/libluajit-5.1.a

$(MOONLIFT): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --bin moonlift

$(MOONLIB): $(LUAJIT)/libluajit.a
	LUAJIT_LIB=$(CURDIR)/$(LUAJIT)/libluajit-5.1.a \
	LUAJIT_INCLUDE=$(CURDIR)/$(LUAJIT) \
	cargo build --release --lib

clean:
	$(MAKE) -C $(LUAJIT) clean
	cargo clean
	rm -f $(LUAJIT)/libluajit-5.1.a src/embedded_hosted_lua.rs

run:
	$(MOONLIFT) $(FILE)

bench:
	luajit benchmarks/bench_json_stack_decode.lua
