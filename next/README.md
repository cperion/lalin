# Lalin Next

`next/` is the isolated implementation root for the compiler redesign.
It does not import, modify, or register with the active compiler under `lua/lalin/`.

Layout:

```text
next/lua/                         isolated Lua source root
next/lua/lalin/compiler/schema.lua  complete compiler ASDL
next/tests/                       isolated tests
next/docs/                        redesign documentation
```

Run the isolated checks from the repository root:

```sh
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua' \
  luajit next/tests/asdl/test_runtime.lua

LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua' \
  luajit next/tests/compiler/test_schema.lua
```

Do not add compatibility imports or wire this tree into the active compiler during the redesign.
