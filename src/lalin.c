#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lalin_embedded_bc_bank.h"
#include "lalin_native_template_bank.h"

static void lalin_assert_native_template_bank_api_linked(void) {
  /* The generated native bank is a C-owned runtime artifact.  Lua reaches it
     through the exported lalin_native_bank_* FFI API and a typed
     NativeBankArtifact descriptor, not through registry debug metadata or the
     removed passive NativeEmbeddedTemplateBank import path. */
  (void)lalin_native_bank_artifact();
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
  lalin_assert_native_template_bank_api_linked();
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
