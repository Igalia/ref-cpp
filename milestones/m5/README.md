# Milestone 5: C manages side table of JavaScript objects

[ previous: [m4](../m4/); next: [m6](../m6/) ]

## Overview

Having shown where we're going and that milestone 4 solves the cycle
problem, we need to return to the C++-to-WebAssembly problem: we are
lacking a way to represent `externref` values in C++, and support in the
LLVM compiler.  As a first step in this direction, we're going to
translate milestone 3's test program back to an extended version of C
that has rudimentary support for reference types.

See the [Externref and LLVM](./externref-and-llvm.md) design document
for the high-level overview on how we are going to extend LLVM to
support `externref`.

## Details

The difference from [m3](../m3) is that instead of
[`test.wat`](../m3/test.wat), we have [`test.c`](./test.c).

Running `make` will build `test.wasm` and run the test as in m3.

## Results

No results yet; this milestone is in progress.
