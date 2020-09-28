# Milestone 2: Re-express test.c as raw WebAssembly test.wat

[ previous: [m1](../m1/); next: [m3](../m3/) ]

## Overview

In [Milestone 1](../m1/), we showed that using side tables and
finalizers for WebAssembly<->JavaScript references caused memory leaks
if the object graph had a cycle traversing the language boundary.  We
also showed that such cycles were easy to make, and hard to debug.

We would like to propose some language extensions to C and C++ to fix
this problem.  To keep the discussion concrete, we will first show the
kind of WebAssembly that we would like LLVM to produce, and test it to
show that it solves the cycle problems.  This test will also allow us to
examine different characteristics of the proposed solution.

Therefore this milestone is the same as [milestone 0](../m0/), but with
the C program replaced with corresponding WebAssembly, and "compiled" by
wabt's `wat2wasm` instead of by LLVM's `llc`.

The [test.wat](./test.wat) was originally produced by running wabt's
`wasm2wat` on the result of compiling m1's (or m0's; they are the same)
[test.c](../m1/test.c).  It was then cleaned up manually.

## Details

The difference from [m0](../m0) is that we translated the former
[`test.c`](../m0/test.c) into [`test.wat`](./test.wat).

Running `make` will build `test.wasm` and run the test as in m0.  An
example run:

```
$ make v8.test
~/src/wabt/out/gcc/Debug//wat2wasm --enable-all --relocatable -o test.o test.wat
~/src/llvm-project/build/bin/clang -Oz --target=wasm32 -nostdlib -c -o walloc.o walloc.c
~/src/llvm-project/build/bin/wasm-ld --no-entry --allow-undefined --import-memory -o test.wasm test.o walloc.o
~/src/v8/out/x64.release/d8 --harmony-weak-refs --expose-gc test.js
Callback after 1 allocated.
1000 total allocated, 1000 still live.
Callback after 1001 allocated.
2000 total allocated, 1000 still live.
...
99000 total allocated, 1000 still live.
Callback after 99001 allocated.
100000 total allocated, 1000 still live.
checking expected live object count: 0
Success; max 1000 objects live.
```

## Results

### Toolchain support for linking C and wat

The object file format of WebAssembly files, as produced by clang and
consumed by LLD, is just the standard binary WebAssembly format, with a
few conventions, plus a couple of "custom sections".  See full details
over at [the tool-conventions Linking
document](https://github.com/WebAssembly/tool-conventions/blob/master/Linking.md).

By default, the `wat2wasm` tool from `wabt` doesn't produce these
sections.  It does have a `--relocatable` option, however, that was
intended for this purpose, but it had a few bugs that made it unusable.
These were fixed in
[#1535](https://github.com/WebAssembly/wabt/pull/1535),
[#1537](https://github.com/WebAssembly/wabt/pull/1537), and
[#1539](https://github.com/WebAssembly/wabt/pull/1539) from us, and
[#1527](https://github.com/WebAssembly/wabt/pull/1527) from an external
contributor.  All of these changes are now in the main upstream branch.
