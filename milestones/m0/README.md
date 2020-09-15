# Milestone 0: Finalizers clean up WebAssembly resources of JavaScript wrappers

## Overview

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

## Results

### Success on all JS engines

The test as written runs successfully on V8, JSC, and SpiderMonkey, at
least as of September 2020.

### Reasoning about objects referenced from closures is unspecified

The `FinalizationRegistry` facility specifies that if the "held" value
passed to the finalizer callback references the finalizable object, the
object will never be finalized.  The registry holds a strong reference
onto "held" values.

In our case, the "held" value is a closure to call when the object
becomes finalizable.  However, the set of objects referenced by a
closure is not specified by JavaScript.  Does the callback capture the
newly constructed `this` or not?  `this` doesn't appear in its text, so
you would think not; but while developing this test case, we ran into
[cases where `this` was indeed
captured](https://bugzilla.mozilla.org/show_bug.cgi?id=1664463).  We
believe that we have avoided these cases, but it is hard to say.

### GC doesn't run often enough

Engines will run garbage collection according to a number of heuristics,
principally among them how much GC-managed allocation has happened since
the last GC.  These heuristics are not informed how much off-heap
allocation has occured; see
https://github.com/tc39/proposal-weakrefs/issues/87 for a discussion.
In practice, without the explicit calls to `gc()`, all engines will fail
our tests, because they don't detect finalizable objects soon enough.

Therefore to make these tests reliable, we insert explicit GC calls.
This bodes poorly for the role of finalizers in robust systems.

### Permissibly late finalization can cause out-of-memory

If no object is finalized, then this test will run out of linear memory.
(Remove the finalizer and you will see.)  However, we have no useful
guarantee about when finalizers run; this is related to the previous
point.  The interesting thing to note is the failure mode, that late
finalization -- for whatever reason, perhaps because the program didn't
yield to the next microtask -- can result in out-of-memory conditions,
which we imagine would apply to real programs as well.

### Users need to be careful to yield to allow finalization to happen

Related again to the previous point, users need to structure their
programs carefully to allow finalizers to run.  Our test runs the
allocation benchmark in a nested loop, yielding to the scheduler within
the outer loop.  See
https://github.com/tc39/proposal-weakrefs/issues/78#issuecomment-485838979
for a related issue.

### SpiderMonkey retains too much data for closures within in async functions

Note that in SpiderMonkey, you can't use the obvious idiom of making the
test an async function, because the callback closure ends up retaining
all local variables.  See [bug
1664463](https://bugzilla.mozilla.org/show_bug.cgi?id=1664463).  We have
worked around this bug in the test.
