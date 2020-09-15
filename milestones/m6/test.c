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

typedef void __attribute__((wasm_externref)) externref;

void WASM_IMPORT(rt, invoke)(externref);
externref WASM_IMPORT(rt, gc_alloc)(size_t nobjs, size_t nbytes);
externref WASM_IMPORT(rt, gc_ref_obj)(externref obj, size_t i);
void WASM_IMPORT(rt, gc_set_obj)(externref obj, size_t i, externref val);

// Useful for debugging.
void WASM_IMPORT(env, wasm_log)(void*);
void WASM_IMPORT(env, wasm_logi)(int);

struct externref WASM_EXPORT(make_obj)() {
  externref ret = gc_alloc(1, 0);
  gc_set_obj(ret, 0, __builtin_wasm_ref_null(externref));
  return ret;
}

void WASM_EXPORT(attach_callback)(externref obj, externref callback) {
  gc_set_obj(obj, 0, callback);
}

void WASM_EXPORT(invoke_callback)(externref obj) {
  invoke(gc_ref_obj(obj, 0));
}
