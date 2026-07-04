#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lalin_embedded_bc_bank.h"
#include "lalin_native_template_bank.h"

static void lalin_install_native_template_bank_debug_metadata(lua_State *L) {
  const LalinNativeEmbeddedTemplateBank *bank = lalin_native_embedded_template_bank();
  if (bank == NULL) return;

  /* Debug/inspection metadata only.  Runtime native compilation imports the
     generated Lua ASDL bridge as NativeEmbeddedTemplateBank; the raw C view is
     not an install hook and intentionally does not publish old machine-code
     bank registry keys. */
  lua_pushstring(L, bank->bank_id ? bank->bank_id : "");
  lua_setfield(L, LUA_REGISTRYINDEX, "lalin.native_template_bank.raw_id");
  lua_pushinteger(L, (lua_Integer)bank->entry_count);
  lua_setfield(L, LUA_REGISTRYINDEX, "lalin.native_template_bank.raw_count");
  lua_pushinteger(L, (lua_Integer)bank->manifest_total_count);
  lua_setfield(L, LUA_REGISTRYINDEX, "lalin.native_template_bank.manifest_total_count");
}

static void lalin_push_argv(lua_State *L, int argc, char **argv) {
  int i;
  lua_newtable(L);
  for (i = 1; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }
  lua_setglobal(L, "arg");
}

int main(int argc, char **argv) {
  int status;
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    fputs("lalin: failed to create LuaJIT state\n", stderr);
    return 70;
  }

  luaL_openlibs(L);
  lalin_install_embedded_bc_bank(L);
  lalin_install_native_template_bank_debug_metadata(L);
  lalin_push_argv(L, argc, argv);

  lua_getglobal(L, "require");
  lua_pushliteral(L, "lalin.cli");
  if (lua_pcall(L, 1, 1, 0) != 0) {
    fprintf(stderr, "lalin: failed to load CLI: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 70;
  }

  lua_getfield(L, -1, "main");
  lua_getglobal(L, "arg");
  if (lua_pcall(L, 1, 1, 0) != 0) {
    fprintf(stderr, "lalin: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 70;
  }

  status = (int)lua_tointeger(L, -1);
  lua_close(L);
  return status;
}
