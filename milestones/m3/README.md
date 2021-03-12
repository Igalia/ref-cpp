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
freelist/object table implementation into the [`test.S`](./test.S)
WebAssembly file.  The algorithm is the same, with the object table
itself being a WebAssembly table holding `externref` values, and the
freelist being a singly-linked-list of malloc'd nodes.

For the rest, you can search the `test.S` file for instances of
`externref` -- for example, `attach_callback` now takes an externref as
an argument directly, and handles "interning" it into the object table
without involving JavaScript.

## Details

The difference from [m2](../m2) is that we moved the side-table
implementation into [`test.S`](./test.S) and removed it from
[`test.js`](./test.js).

This is the first example in which WebAssembly handles externref values,
so the [`Makefile`](./Makefile) arranges to enable the appropriate
feature flags in compiler and in the various engines.

Running `make` will build `test.wasm` and then run the test as in m2.

## Results

### LLVM support for reference-types, on assembly level

As part of this work, Paulo and Andy added support for `externref`,
instructions that operate on `externref` (`table.ref`, `table.set`,
etc), and support for table relocations to LLVM.  

Landed patches: <a href="https://reviews.llvm.org/D88815">D88815</a>, <a
href="https://reviews.llvm.org/D89797">D89797</a>, <a
href="https://reviews.llvm.org/D90608">D90608</a>, <a
href="https://reviews.llvm.org/D90948">D90948</a>, <a
href="https://reviews.llvm.org/D91604">D91604</a>, <a
href="https://reviews.llvm.org/D91635">D91635</a>, <a
href="https://reviews.llvm.org/D91637">D91637</a>, <a
href="https://reviews.llvm.org/D91849">D91849</a>, <a
href="https://reviews.llvm.org/D91870">D91870</a>, <a
href="https://reviews.llvm.org/D92215">D92215</a>, <a
href="https://reviews.llvm.org/D92315">D92315</a>, <a
href="https://reviews.llvm.org/D92320">D92320</a>, <a
href="https://reviews.llvm.org/D92321">D92321</a>, <a
href="https://reviews.llvm.org/D92323">D92323</a>, <a
href="https://reviews.llvm.org/D92840">D92840</a>, <a
href="https://reviews.llvm.org/D94075">D94075</a>, <a
href="https://reviews.llvm.org/D94677">D94677</a>, <a
href="https://reviews.llvm.org/D96001">D96001</a>, <a
href="https://reviews.llvm.org/D96770">D96770</a>, <a
href="https://reviews.llvm.org/D96872">D96872</a>, <a
href="https://reviews.llvm.org/D97761">D97761</a>, <a
href="https://reviews.llvm.org/D97843">D97843</a>, <a
href="https://reviews.llvm.org/D97923">D97923</a>.

Complete support only exists on the assembly ("MC") layer and in the
linker (`wasm-ld`); support on the IR level is ongoing, and will be
followed by frontends (`clang`).

### Handle and side-table mechanism implemented in terms of externref

In a future where C and C++ programs can reference externref values,
there are going to be many times where you want a C data structure to
reference a GC-managed value, but you can't put a GC-managed value
directly into linear memory.  Side tables and handles are the mechanism
by which this will work: the code that has an externref and needs a
handle will intern the object into a table, and store the integer handle
into memory instead.

This milestone shows the needed WebAssembly to do that.  We just have to
figure out how to get the compiler to emit it from C :)

### Side tables still lead to uncollectable cycles

Moving the side table to WebAssembly is convenient in some ways but
doesn't magically solve the cycle problem.  Running the tests still
fails, in the same way as in m2.
