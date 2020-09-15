#include <stdint.h>

typedef __SIZE_TYPE__ size_t;

#define WASM_EXPORT(name) \
  __attribute__((export_name(#name))) \
  name
#define WASM_IMPORT(mod, name) \
  __attribute__((import_module(#mod))) \
  __attribute__((import_name(#name))) \
  name

#define ASSERT(x) do { if (!(x)) __builtin_trap(); } while (0)

void WASM_IMPORT(rt, release)(uintptr_t);
void WASM_IMPORT(rt, invoke)(int32_t);
void WASM_IMPORT(rt, out_of_memory)(void);

// Useful for debugging.
void WASM_IMPORT(env, wasm_log)(void*);
void WASM_IMPORT(env, wasm_logi)(int);

void *malloc(size_t size);
void free(void *p);
                          
struct obj {
  uintptr_t callback_handle;
};

struct obj* WASM_EXPORT(make_obj)() {
  struct obj* obj = malloc(sizeof(struct obj));
  if (!obj) {
    out_of_memory();
    __builtin_trap();
  }
  obj->callback_handle = -1;
  return obj;
}

void WASM_EXPORT(free_obj)(struct obj* obj)
{
  release(obj->callback_handle);
  free(obj);
}

void WASM_EXPORT(attach_callback)(struct obj* obj, uintptr_t callback_handle)
{
  release(obj->callback_handle);
  obj->callback_handle = callback_handle;
}

void WASM_EXPORT(invoke_callback)(struct obj* obj)
{
  invoke(obj->callback_handle);
}
