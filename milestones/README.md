# Ref C++ Milestones

This folder holds milestone examples for different phases of the Ref C++
effort.

## Before starting

There are some dependencies that we use as part of our test setup.  You
should make sure to have them installed before starting; see [the
getting-started guide](./getting-started.md) to get things set up.  In
the end you should be able to run these commands:

```
$LLVM/llc --version
$CC --version
$LD --version
$WABT/wat2wasm --version
$D8 -h
$JSC -h
$SPIDERMONKEY -h
```

## [Milestone 0: Finalizers clean up WebAssembly resources of JavaScript wrappers](./m0/)

Here we define a basic C library which defines a simple `make_object`
facility and which includes extensions to export that interface to its
WebAssembly host.

We define a JavaScript run-time that tests this facility, wrapping the
raw pointers coming from the `make_object` calls in /wrapper objects/ on
the JavaScript side.

The exported interface also includes a facility to attach a callback to
the object.  We define a simple handle-and-side-table mechanism,
allowing C to refer to JavaScript callbacks by index.  The C code
exports a `dispose_object` interface that will release associated
resources from the side table, in addition to freeing linear memory
associated with an object.

Finally, we attach a finalizer to the JavaScript wrapper of the C
object, allowing the system to automatically call `dispose_object` on C
objects when their associated JavaScript wrappers become unreachable.

This test illustrates the handle-and-side-table pattern for references
from C to JavaScript.  It also shows that the finalizer facility can
clean up "external" resources associated with JavaScript objects,
e.g. calling `free` on allocations from linear memory.

However, this test also shows that the finalizers interface has a number
of pitfalls in practice.

## [Milestone 1: Cycles between WebAssembly and JavaScript are uncollectable](./m1/)

Here we have the same program as in milestone 0, but the callback
attached to the C object captures the JavaScript wrapper, preventing it
from being collected.

Note that JavaScript garbage collectors are perfectly capable of
collecting cycles.  However, while this case exhibits what is logically
a cycle between the callback, the JS wrapper, and the C object, the
garbage collector sees only the JavaScript side of things: the side
table keeps the callback alive, which, as the callback captures the
wrapper, keeps the wrapper alive.

Because the allocated objects are never collected, it will eventually
crash because it can't allocate any more memory.  In practice, our
example crashes because it runs out of linear memory.

This is a simplified representation of the use case that we are trying
to fix in this effort, and milestone 1 indicates the problem.

## [Milestone 2: Re-express test.c as raw WebAssembly](./m2/)

We would like to propose some language extensions to C and C++ to fix
the cycle problem shown by milestone 1.  To keep the discussion
concrete, we will first show the kind of WebAssembly that we would like
LLVM to produce, and test it to show that it solves the cycle problems.
This test will also allow us to examine different characteristics of the
proposed solution.

Therefore this milestone is the same as [milestone 0](../m0/), but with
the C program replaced with corresponding WebAssembly, and "compiled" by
wabt's `wat2wasm` instead of by LLVM's `llc`.

## [Milestone 3: Move side table to WebAssembly](./m3/)

In milestones 1 and 2, the C++ or WebAssembly library referred to
JavaScript objects by `i32` index.  The actual objects were stored in a
table managed by the JavaScript run-time.  Therefore to call a callback,
the WebAssembly would invoke an import from JavaScript, passing it an
`i32` index indicating which object in the table to invoke.

With `externref`, milestone 3 changes to manage this table on the
WebAssembly side of things, avoiding the need for the JS run-time to
manage the table.  Otherwise this milestone still has the same
uncollectable cycle characteristics as milestones 1 and 2.

## [Milestone 4: Collectable cycle: WebAssembly allocates GC-managed memory](./m4/)

The side table in milestones 1 is the essence of our uncollectable cycle
problem: it introduces a reference-counted edge in our object graph, but
the garbage collector doesn't understand how to traverse that edge and
instead sees the cycle as being referred to by the GC roots (the table
itself).

To fix this problem, we will have the WebAssembly module allocate its
data structures that should participate in GC on the GC-managed heap.
Since only JavaScript has the capability to allocate this memory, we'll
implement the allocation routine in the JS run-time, providing accessor
imports as well.

## [Milestone 5: Same as milestone 3, but with C++ compiled to LLVM](./m5/)

Having shown where we're going and that milestone 4 solves the cycle
problem, we need to return to the C++-to-WebAssembly problem: we are
lacking a way to represent `externref` values in C++, and support in the
LLVM compiler.  Although using milestone 3 doesn't solve the cycle
problem, it's a good intermediate step for getting `externref` into
LLVM.

## [Milestone 6: Same as milestone 4, but with C++ compiled to LLVM](./m6/)

This milestone represents a minimal solution to the cycle problem, but
from C++ instead of from raw WebAssembly.  Instead of using classes as
data abstractions, the C++ here will use the raw allocation and accessor
imports defined in milestone 4.

## [Milestone 7: Minimal Ref C++](./m7/)

In milestone 6, we solved the cycle problem, but at a low level of
abstraction.  Here we will attempt to raise the abstraction level,
defining lowerings of reference-typed classes à la Ref C++ to the same
primitives.  This milestone will result in idiomatic C++ that solves the
cycle problem.
