#ifndef LUA55_OPCODE_VALUE_TAGS_H
#define LUA55_OPCODE_VALUE_TAGS_H

#include <stdint.h>

/* Neutral scalar vocabulary shared by the legacy (V1) and native CPS (V2)
   generations. This header owns immutable value tags, object kinds,
   upvalue-cell states, the quotation identity, and the SET_TAG leaf.
   It shares no frame, heap, or ownership types between generations. */

enum {
    LUA55_VALUE_NIL = 0,
    LUA55_VALUE_FALSE = 1,
    LUA55_VALUE_TRUE = 2,
    LUA55_VALUE_INTEGER = 3,
    LUA55_VALUE_FLOAT = 4,
    LUA55_VALUE_SHORT_STRING = 5,
    LUA55_VALUE_LONG_STRING = 6,
    LUA55_VALUE_TABLE = 7,
    LUA55_VALUE_CLOSURE = 8,
};

enum {
    LUA55_UPVALUE_OPEN = 1,
    LUA55_UPVALUE_CLOSED = 2,
};

enum {
    LUA55_OBJECT_SHORT_STRING = 1,
    LUA55_OBJECT_LONG_STRING = 2,
    LUA55_OBJECT_TABLE = 3,
    LUA55_OBJECT_CLOSURE = 4,
    LUA55_OBJECT_BUILTIN = 5,
};

#define LUA55_QUOTE(opcode, variant) \
    ((uint32_t)((((uint32_t)(opcode)) << 16) | ((uint32_t)(variant))))

#define SET_TAG(value, value_tag) do { \
    (value)->tag = (value_tag);         \
    (value)->reserved = 0;              \
} while (0)

#endif
