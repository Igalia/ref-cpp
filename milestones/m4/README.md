# Milestone 4: Collectable cycle: WebAssembly allocates GC-managed memory

## Overview

Here we make progress!  In the previous milestones, we had a cycle of
objects across the WebAssembly / JavaScript boundary that wasn't
traceable as such by the garbage collector.  In this milestone, we solve
this problem by moving the WebAssembly objects from linear memory to
GC-managed memory.

As the cycle now exists only in GC-managed memory, it is transparent to
the garbage collector, so we have solved the cycle problem.
Furthermore, there is no need for finalizers, removing an error-prone
component from the system.

In this example, as there is nothing else in WebAssembly that needs to
hold onto an object once it's allocated, so this example omits the side
table as well.  However we expect that in real programs, we would
occasionally need a side table for references to GC-managed data from
C++.  Such handles can refer to any member of a cycle, as long as the
holder of the handle doesn't participate in a cycle.

## Results

### Heap provided by GC-capable host

In this example, the `gc_alloc` function, provided by
[`test.js`](./test.js), allocates an object with slots to hold a fixed
number of reference-typed objects as well as a fixed number of bytes.

The `gc_alloc` facility models a heap that can create objects containing
both GC-managed and "raw" fields.  To WebAssembly, such a value is
opaque; we need to call out to accessors defined by the host (by
JavaScript) to initialize, reference, and modify object fields.

This approach to memory management was first prototyped in the [Schism
self-hosted implementation of Scheme](https://github.com/google/schism).

### Path towards GC proposal

Having to call out to the host to allocate objects and access their
fields is evidently suboptimal.  Future parts of the [GC
proposal](https://github.com/WebAssembly/gc/blob/master/proposals/gc/Overview.md)
allow for these operations to occur within WebAssembly, which will make
for more efficient systems with smaller demands on the host run-time.

### No need to break up main loop into async function

Because finalizers can only run asynchronously, they cause programs to
keep memory alive for longer than they would otherwise.  That's why we
had to break up the earlier test loop into an inner and an outer loop,
running garbage collection in the middle; see the [discussion in
milestone 0](../m0/) for more details.  Because this is no longer
necessary without finalizers, this program can be simpler on the
JavaScript side as well.

### Less telemetry

On the other hand, not having finalizers gives us less telemetry into
the total numbers of allocated objects.  While this can be added back,
if it is not needed, it is just overhead.

### WebKit out of date

The `jsc.test` target fails, presumably due to the recent change in
`ref.null` encoding.

### Lower run-time overhead than m0

It's not precisely a fair comparison, given that we don't have to
explicitly run GC, we don't do finalizers, and we don't need extra
turns, but this test takes less time for both V8 and SpiderMonkey than
the versions that have side tables, despite the need for indirect field
access via the `gc_ref_obj` family of functions.

### TODO: Impact on memory overhead

Would be nice to check the process size and compare to m0.  Also, we
should be able to run indefinitely without stopping.
