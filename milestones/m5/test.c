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

typedef __externref_t externref;

void WASM_IMPORT(rt, invoke)(externref);
void WASM_IMPORT(rt, out_of_memory)(void);

// Useful for debugging.
void WASM_IMPORT(env, wasm_log)(void*);
void WASM_IMPORT(env, wasm_logi)(int);

void *malloc(size_t size);
void free(void *p);
                          
typedef uint32_t Handle;

struct freelist {
  Handle handle;
  struct freelist *next;
};

static struct freelist *freelist;

static Handle freelist_pop (void) {
  ASSERT(freelist != 0x0);
  struct freelist *head = freelist;
  Handle ret = head->handle;
  freelist = head->next;
  free(head);
  return ret;
}

static void freelist_push (Handle h) {
  struct freelist *head = malloc(sizeof(struct freelist));
  if (!head) {
    out_of_memory();
    __builtin_trap();
  }
  head->handle = h;
  head->next = freelist;
  freelist = head;
}

static externref objects[0];

__attribute__((noinline))
static void expand_table (void) {
  size_t old_size = __builtin_wasm_table_size(objects);
  size_t grow = (old_size >> 1) + 1;
  if (__builtin_wasm_table_grow(objects,
                                __builtin_wasm_ref_null_extern(),
                                grow) == -1) {
    out_of_memory();
    __builtin_trap();
  }
  size_t end = __builtin_wasm_table_size(objects);
  while (end != old_size) {
    freelist_push (--end);
  }
}

static Handle intern(externref obj) {
  if (!freelist) expand_table();
  Handle ret = freelist_pop();
  __builtin_wasm_table_set(objects, ret, obj);
  return ret;
}

static void release(Handle h) {
  if (h == -1) return;
  __builtin_wasm_table_set(objects, h, __builtin_wasm_ref_null_extern());
  freelist_push(h);
}

static externref handle_value(Handle h) {
  return h == -1
    ? __builtin_wasm_ref_null_extern()
    : __builtin_wasm_table_get(objects, h);
}

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

void WASM_EXPORT(free_obj)(struct obj* obj) {
  release(obj->callback_handle);
  free(obj);
}

void WASM_EXPORT(attach_callback)(struct obj* obj, externref callback) {
  release(obj->callback_handle);
  obj->callback_handle = intern(callback);
}

void WASM_EXPORT(invoke_callback)(struct obj* obj) {
  invoke(handle_value(obj->callback_handle));
}
