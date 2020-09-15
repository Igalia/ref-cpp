# Milestone 1: Cycles between WebAssembly and JavaScript are uncollectable

## Overview

This is the same as [m0](../m0/), but with the smallest of changes to
[`test.js`](./test.js):

```diff
--- ../m0/test.js	2020-09-14 13:27:24.924663561 +0200
+++ test.js	2020-09-14 13:29:06.658300401 +0200
@@ -103,7 +103,8 @@
 function test(n) {
     for (let i = 0; i < n; i++) {
         let obj = new WasmObject(instance);
-        obj.installCallback(() => print(`Callback after ${nalloc} allocated.`));
+        obj.installCallback(
+            () => print(`Callback from ${obj} after ${nalloc} allocated.`));
         if (i == 0) obj.invokeCallback();
     }
     print(`${nalloc} total allocated, ${nalloc - nfinalized} still live.`);
```

That is, our callback references the object.  Seems like an innocent
change, but it causes the test to fail because it causes a cycle.

Note that JavaScript garbage collectors are perfectly capable of
collecting cycles.  However, while this case exhibits what is logically
a cycle between the callback, the JS wrapper, and the C object, the
garbage collector sees only the JavaScript side of things: the side
table keeps the callback alive, which, as the callback captures the
wrapper, keeps the wrapper alive.

Because the allocated objects are never collected, this test will
eventually crash because it can't allocate any more memory.  In
practice, our example crashes because it runs out of linear memory.

This is a simplified representation of the use case that we are trying
to fix in this effort, and milestone 1 indicates the problem.

## Details

Running `make` will build `test.wasm` and run the test as in m0.  Note
however that it fails with an out-of-memory error, and therefore that
the default `test` target stops after `v8.test` fails.  You can verify
that it fails with JSC via `make jsc.test`, and SpiderMonkey via `make
spidermonkey.test`.

An example run:

```
$ make v8.test
~/src/llvm-project/build/bin/clang -Oz --target=wasm32 -nostdlib -c -o test.o test.c
~/src/llvm-project/build/bin/clang -Oz --target=wasm32 -nostdlib -c -o walloc.o walloc.c
~/src/llvm-project/build/bin/wasm-ld --no-entry --import-memory -o test.wasm test.o walloc.o
~/src/v8/out/x64.release/d8 --harmony-weak-refs --expose-gc test.js
Callback from [object Object] after 1 allocated.
1000 total allocated, 1000 still live.
Callback from [object Object] after 1001 allocated.
2000 total allocated, 2000 still live.
...
55000 total allocated, 55000 still live.
Callback from [object Object] after 55001 allocated.
56000 total allocated, 56000 still live.
Callback from [object Object] after 56001 allocated.
57000 total allocated, 57000 still live.
Callback from [object Object] after 57001 allocated.
error: out of linear memory
make: *** [Makefile:15: v8.test] Error 1
```

## Results

### We have a simple motivating example

Although this test program is small and synthetic, it exhibits a pattern
of object relationships in real programs.  There is reason to hope that
if we find a solution for the test program, that it will enable large
systems to be made more reliably.

### Cycles are easier to make than one might think

When constructing this test program, very experienced JS and WebAssembly
engineers spent way longer than they had planned, ensuring that the
leaks were present for the reasons we thought, and absent in ways that
we expect.  [Bug
1664463](https://bugzilla.mozilla.org/show_bug.cgi?id=1664463) is a good
example, but simply allowing finalizers to run was also an issue.  See
m0 for a longer discussion of those incidental points.

We are now more convinced that "don't do that" is not a good answer to
the cycle problem.  Firstly, because it's difficult to know when one
makes a cycle or not.  Secondly, because sometimes cycles lead to more
natural program structure.  Finally, the negative consequences of
uncollectable cycles in hybrid WebAssembly/JS environments have such
disastrous consequences that happen at unpredictable times that from a
system reliability point of view, if we can't avoid cycles in practice,
we must make them benign.

### In practice, the linear memory usually has the more strict limit

The failure mechanism of this test is a failure to grow linear memory.
We expect that this will be the failure mechanism for insufficiently
prompt GC and leaky systems, if a maximum is set on linear memory.
