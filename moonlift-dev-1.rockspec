rockspec_format = "3.0"
package = "moonlift"
version = "0.1.0-1"

source = {
    url = "git+https://github.com/cperion/moonlift.git",
    tag = "v0.1.0",
}

description = {
    summary = "Typed, jump-first compiled language. Native code via Cranelift, authored through a Lua-owned DSL.",
    detailed = [[
Moonlift is a typed, jump-first compiled language embedded in LuaJIT
that generates native code through Cranelift. Lua is the
metaprogramming layer; Moonlift is the monomorphic native output.

Author in the Lua-owned DSL: Lua parses products, protocols, bodies,
and fill maps as table values; the standard LLB substrate hosts staged heads,
fragments, formatting, managed use sessions, and fragment algebra; Moonlift
normalizes into typed ASDL and compiles to native machine code via Cranelift.
No source parser, no textual antiquote, no string quotes.
    ]],
    license = "MIT",
    homepage = "https://github.com/cperion/moonlift",
    maintainer = "Moonlift contributors",
}

dependencies = {
    "lua >= 5.1",
}

external_dependencies = {
    RUST = {
        header = "rustc",
        minimum = "1.75",
    },
}

build = {
    type = "command",

    build_command = "cargo build --release --lib",

    install_command = [[
        mkdir -p "$(PREFIX)/lib"
        mkdir -p "$(PREFIX)/bin"
        mkdir -p "$(PREFIX)/share/lua/$(LUA_VERSION)"
        cp target/release/libmoonlift.so "$(PREFIX)/lib/"
        cp scripts/moonfmt.lua "$(PREFIX)/bin/moonfmt"
        cp lua/llb.lua "$(PREFIX)/share/lua/$(LUA_VERSION)/"
        cp -r lua/moonlift "$(PREFIX)/share/lua/$(LUA_VERSION)/"
        cp -r lua/llpvm "$(PREFIX)/share/lua/$(LUA_VERSION)/"
    ]],
}
