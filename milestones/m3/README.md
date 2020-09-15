# Milestone 3: Move side table to WebAssembly

[ previous: [m2](../m2/); next: [m4](../m4/) ]

## Overview

In the previous milestones, the side table associating integer handles
with GC-managed data from JavaScript was maintained in the JavaScript
run-time.  However with the [widely-implemented reference types
proposal](https://github.com/WebAssembly/reference-types), it's now
possible to manage that table on the WebAssembly side, reducing the size
of the language-specific run-time.

Relative to the previous milestone, this milestone moves the
freelist/object table implementation into [`test.wat`](./test.wat).  The
algorithm is the same, with the object table itself being a WebAssembly
table holding `externref` values, and the freelist being a
singly-linked-list of malloc'd nodes.

For the rest, you can search the `test.wat` file for instances of
`externref` -- for example, `$attach_callback` now takes an externref as
an argument directly, and handles "interning" it into the object table
without involving JavaScript.

## Details

The difference from [m2](../m2) is that we moved the side-table
implementation into [`test.wat`](./test.wat) and removed it from
[`test.js`](./test.js).

This is the first example in which WebAssembly handles externref values,
so the [`Makefile`](./Makefile) arranges to enable the appropriate
feature flags in the various engines.

Running `make` will try to build `test.wasm` and run the test as in m2;
however, there is a linking error so we can't actually run this test.
See below.

## Results

### Handle and side-table mechanism implemented in terms of externref

In a future where C and C++ programs can reference externref values,
there are going to be many times where you want a C data structure to
reference a GC-managed value, but you can't put a GC-managed value
directly into linear memory.  Side tables and handles are the mechanism
by which this will work: the code that has an externref and needs a
handle will intern the object into a table, and store the integer handle
into memory instead.

This milestone shows the needed WebAssembly to do that.  We just have to
figure out how to get the compiler to emit it now :)

### Linking currently fails

Although we are able to make `test.o` from `test.wat`, even including
the externref features, it doesn't yet link with walloc.o:

```
wat2wasm --enable-all --relocatable -o test.o test.wat
clang -Oz --target=wasm32 -nostdlib -c -o walloc.o walloc.c
wasm-ld --no-entry --import-memory --allow-undefined -o test.wasm test.o walloc.o
wasm-ld: error: test.o: Invalid table element type
```

This is a bug in wasm-ld that we need to fix.
