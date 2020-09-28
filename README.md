# Reference typing extensions for C++ ("Ref C++")

Welcome to the workspace for the Ref C++ effort.

## Goal

The goal is to prevent memory leaks for programs that need cycles
between C++ and JavaScript, for WebAssembly deployments in web browser
environments.

## Progress

See the [development milestones](./milestones/) page for ongoing work
towards Ref C++.

## The problem

Say you have a data provider written in C++.  You compile it to
WebAssembly with [emscripten](https://emscripten.org/).  You register a
JavaScript function with WebAssembly that will be called when the data
provider has new data.  The callback will refresh a data visualization,
say a chart, implemented as a DOM node provided by the browser.  But the
chart is interactive -- so it might need to reconfigure the data
provider in response to user action.  Now we have a cycle: the
WebAssembly module references JavaScript, and JavaScript references the
WebAssembly module.

If this system were composed only of JavaScript, we have no problem:
when no other part of the program references the cycle, the garbage
collector can reclaim its memory.

However, WebAssembly makes memory leaks hard to avoid comprehensively.
Having a cycle between JS and WebAssembly will leak memory except in
very special cases.

### WebAssembly references to JS are reference-counted in a side table

In fact, WebAssembly currently lacks the ability to reference JavaScript
objects at all.  The store associated with WebAssembly is just a raw
byte array ("linear memory").  You can't represent a JavaScript object,
managed by a garbage collector that WebAssembly doesn't know about, in
WebAssembly.

What you can do is maintain a side table on the JavaScript side
associating JavaScript objects used by WebAssembly with small integer
identifiers (`i32` values).  Then a C++ function that takes a JavaScript
object as an argument can take it as an `i32` index into that side
table.  When C++ is finished with a JS value, it calls into JavaScript
to let it know that the side table entry can be re-used.

To be concrete, here is a minimal implementation of the side table, with
WebAssembly as it exists today:

```c++
#define WASM_IMPORT(name) \
  __attribute__((import_module("imports"))) \
  __attribute__((import_name(#name))) \
  name

void WASM_IMPORT(release)(uint32_t handle_id);
```

The annotations tell LLVM that these functions will be imported from the
run-time.  On the C++ side, you would have a little wrapper to make sure
that C++ keeps the JS object alive as long as it needs:

```c++
class Handle {
  int32_t id_;
 public:
  explicit Handle(int32_t id) : id_(id) {}
  ~Handle() { release(id_); }
}
```

Then when you instantiate the WebAssembly module from JavaScript, you
provide the run-time support in the form of an imports object:

```js
class ObjectTable {
    constructor() {
        this.objects = [];
        this.freelist = [];
    }
    expand() {
        let len = this.objects.length;
        let grow = (len >> 1) + 1;
        let end = len + grow;
        this.objects.length = end;
        while (end != len)
            this.freelist.push(--end);
    }
    intern(obj) {
        if (!this.freelist.length)
            this.expand();
        let handle = this.freelist.pop();
        this.objects[handle] = obj;
        return handle;
    }
    release(handle) {
        this.objects[handle] = null;
        this.freelist.push(handle);
    }
    count() {
        return this.objects.length - this.freelist.length;
    }
    ref(handle) {
        return this.objects[handle];
    }
}

let table = new ObjectTable;

let imports = {
  release: handle => table.release(handle),
};
let bytes = fetch("https://example.com/data-provider.wasm");
let mod = WebAssembly.instantiateStreaming(bytes, { imports });
```

So that's referencing JavaScript objects from WebAssembly.  On the other
side, WebAssembly doesn't really have the notion of an object or a
resource that JavaScript could hold on to: if WebAssembly passes an
object to JavaScript that might need cleanup, what JavaScript would get
would be an `i32` identifier that might indicate an offset into linear
memory.  When JavaScript is done with that resource, it would need to
call into WebAssembly to "free" the resource.

*For a complete working example of this pattern, see [Milestone
0](./milestones/m0/).*

This strategy works well until you have a cycle.  In that case, the JS
code referencing WebAssembly will not be collected because the
WebAssembly reference to JS is via a side table, effectively via a
reference count.

In short, when WebAssembly and JavaScript reference each other, we have
a classic problem: cycles in graphs of reference-counted objects cause
memory leaks.

*In [Milestone 1](./milestones/m1/), we show that a simple change to
milestone 0 introduces a cycle, indeed causing memory leaks and
ultimately causing the program to crash.*

### Conventional solutions

#### Idea 1: Use weak refs to break cycles

The first conventional solution to the problem is "don't do that".
I.e., don't create cycles at all.

We would note firstly that this is an easy thing to say, but a hard
thing to put in practice.  It is especially hard to know when a closure
introduces a cycle
[[1]](./milestones/m0#reasoning-about-objects-referenced-from-closures-is-unspecified)
[[2]](./milestones/m0#spidermonkey-retains-too-much-data-for-closures-within-in-async-functions)
[[3]](./milestones/m1#cycles-are-easier-to-make-than-one-might-think).

However, assuming omniscient programmers, in our context this could mean
making the item in the JS side table referencing a JS object on behalf
of WebAssembly to be a *weak reference*.  Since the WebAssembly-to-JS
reference is no longer strong, the JavaScript side is alive only as long
as some live JS object references it.  When the JavaScript side becomes
collectable, the JS object will be collected, which might trigger a
[finalizer](https://tc39.es/proposal-weakrefs/) to to clean up the
WebAssembly side.

This solution works in a way but is not is not robust.  Premature
out-of-memory (OOM) is still quite possible even for "perfect" programs:

 1. [because the JavaScript garbage collector doesn't know about wasm allocations](./milestones/m0#gc-doesnt-run-often-enough)
 2. [because finalizers are allowed to run late](./milestones/m0#permissibly-late-finalization-can-cause-out-of-memory)
 3. [because finalizers can't run too early](./milestones/m0#users-need-to-be-careful-to-yield-to-allow-finalization-to-happen)

We focus on finalizers here, but weak references are also subject to
similar timing issues.

Furthermore, adopting the weak-ref approach forces the programmer to
reason globally about cycles.  This becomes difficult when different
teams are responsible for different parts of the object graph.  One nice
aspect about garbage-collection is that it is a cross-cutting solution
that doesn't require global coordination among different programming
teams in order to prevent memory leaks; we would be replacing a global
guaranteed system invariant with the need for periodic global reasoning.
This can work occasionally but it is not a scalable way to build a
system.

#### Idea 2: WebAssembly program exposes hooks to system GC

Another conventional solution would be to integrate the inter-object
edges contained in the reference-counted part of the graph with garbage
collection.  You could have the C++ objects expose a
`trace(TraceVisitor&)` method that could be called by the JavaScript
garbage collector.  However, garbage collectors in JavaScript would be
loathe to expose this interface to the web, which is effectively what
you'd be doing if you went down this route.

#### Idea 3: User application allocates GC-managed memory

The third solution would be to forgo reference-counting for the parts of
your object graph that might have cycles with garbage-collected objects.
Instead, you make that part of the graph also managed by the garbage
collector.  That is the approach we are going to take here: define a
facility to allow C++ to allocate data on the garbage-collected heap.
For good usability, we will also extend C++ to allow a subset of C++
types to allocate their instances using these new garbage-collected
primitives instead of in linear memory.

## WebAssembly and C++

Let's back up a bit.  WebAssembly is simply a target architecture to
which C++ and other source languages can be compiled.  It has
instructions like you would expect: `i32.add`, `i64.load`, and so on.
See the [specification](https://webassembly.github.io/spec/core/) for
full details.

The only data types that WebAssembly has are [`i32`, `i64`, `f32`, and
`f64`](https://webassembly.github.io/spec/core/syntax/types.html#value-types).
This means that when a C++ program is compiled to WebAssembly, there's
no notion of classes or objects or similar.

It's possible to implement "pure" modules in WebAssembly that only have
data with automatic storage duration, in the sense of the C++ standard.
In that case no external storage is needed.  However most programs need
to address memory; in that case the WebAssembly module will be
associated with a linear byte array that it can use as it likes.  That
means it has to implement `malloc`, implement its own stack storage for
mutable out-parameters, and so on.  Instructions that load and store to
memory do so by offset into the byte array.  Consequently, C++ pointers
are also compiled down as `i32` offsets into memory.

Any global state needed by the module, for example `malloc` metadata or
a stack pointer for stack allocations, is conventionally aliased to a
statically-allocated region of linear memory: for example you could have
the current stack pointer at byte offset 0, the current errno at offset
4, an offset to the current malloc freelist at offset 8, and so on.

The core of the C++-to-WebAssembly pipeline is implemented by LLVM,
using `--target=wasm32`.  (The 32 is to indicate that we can use 32-bit
offsets to address memory.)

Object files compiled by LLVM don't include any `libc` or anything, so
it's hard to directly use LLVM to produce tools that are useful in a web
context.

Emscripten is a project that fills this gap: it adds a C library, an
implementation of OpenGL in terms of WebGL, and so on.  Emscripten is
essentially a big ball of scripts around LLVM, plus some tweaked
versions of standard libraries.  It works remarkably well but we are
mostly going to ignore it in our work, because we need to solve a
problem at a lower level.

Note, Emscripten is essentially for compilation in a web or web-like
embedding like Node: the result is a `.wasm` file, along with a run-time
`.js` file that provides needed facilities to the WebAssembly module via
imports.  It's possible for WebAssembly to be embedded in non-web
contexts where there is no JS, but that's not what we're interested in
here.

Some useful reading: [a nice article on bare-bones compilation of C to
WebAssembly](https://surma.dev/things/c-to-webassembly/), and
[pictie](https://github.com/wingo/pictie), a simple example C++
application that can be used as a reference for how to use the
Emscripten toolchain.

## WebAssembly and GC

So, that's linear memory and pointers.  Compiling standalone C++
algorithms to WebAssembly is straightforward: it just works, it runs at
speed, and you can export some interfaces to JavaScript.

But what about WebAssembly and GC?  Well the designers of WebAssembly
want support for objects allocated not just in linear memory, but also
on a garbage-collected heap.  This is partly because many of them have a
soft spot for ML and similar languages.  It's also to ease the process
of passing values across the WebAssembly/JS boundary, for embeddings in
web browsers.  As you can imagine, the side table we implemented above
is costly.

The first [baby-step towards integration with
GC](https://github.com/WebAssembly/reference-types) is something that
used to be called `anyref`, and which has recently been renamed
`externref`.  It's essentially a new value type, indicating a reference
to a value from the "host" -- in our case, a JS value.  Functions can
take refs as arguments and return them as results, and refs can be local
variables, or indeed global variables.  However: refs cannot be stored
to linear memory.  Instead, they can be stored to *tables*.  Tables are
arrays that are statically declared to be part of a module, and have
items of uniform type.  With reference types, you can have a table of
`externref`, allowing us to move the side-table implementation from JS
to WebAssembly.

There is a problem though: how would you represent a value in C++ that
can be a local variable or a function parameter or result, but which
can't be stored in the heap?

This is an ongoing problem.  [LLVM support hasn't landed
yet](https://reviews.llvm.org/D66035).  It's part of our work items for
the year and this needs work.

*In the mean-time, to further the discussion, [Milestone
2](./milestones/m2/) translates our example C program to raw
WebAssembly.  [Milestone 3](./milestones/m3) then moves the side table
from the JS runtime to WebAssembly.  We are still actively working on
figuring out how to produce this WebAssembly from LLVM.*

We'll get to a design and implementation plan later in this document,
but for now assume that LLVM will support a magical `externref` type
that can be a function argument, return value, or local variable -- but
with lots of weird restrictions, notably that it cannot be stored to the
heap.  There will be `void __wasm_table_store(uint32_t idx, externref
obj)` and `externref __wasm_table_load(uint32_t idx)` intrinsics to
allow C++ to stash these values in a GC-traced side table.  General
references from the C++ heap to `externref` values will still need to
use the `Handle` mechanism described above, but happily we can access
the table directly from C++.

Our work will build on `externref` in LLVM, defining C++ language
extensions to allow C++ types to allocate their objects in GC-managed
memory.

## The basic idea: instances of some C++ classes are managed by GC

Let's return to the cycle problem.  Whether the side table of references
from WebAssembly to JS is managed on the JS side, as it is now, or on
the WebAssembly side, as it may be with LLVM+`externref`, we still have
the problem of reference-counting cycles.

We would like to solve this by making every object participating in the
cycle to be traced by the GC.  If every object in a cycle is GC-traced,
then the cycle will stay alive if and only if it has an outside
reference.

To make a C++ object traced by the GC, we will allocate its memory on
the GC-managed heap.  Like this:

```c++
externref WASM_IMPORT(gc_alloc)(uint32_t nbytes, uint32_t nrefs);
uint8_t WASM_IMPORT(gc_load_u8)(externref obj, uint32_t offset);
int8_t WASM_IMPORT(gc_load_s8)(externref obj, uint32_t offset);
// ... gc_load_{u,s}{16,32,64}, gc_load_f{32,64} ...
externref WASM_IMPORT(gc_load_ref)(externref obj, uint32_t idx);

void WASM_IMPORT(gc_store_u8)(externref obj, uint32_t offset, uint8_t val);
// ... gc_store_u{16,32,64}, gc_store_f{32,64} ...
void WASM_IMPORT(gc_store_ref)(externref obj, uint32_t idx, externref ref);
```

The corresponding run-time support would look like:

```js
class WasmObj {
  constructor(nbytes, nrefs) {
    let bytes = new ArrayBuffer(nbytes);
    this.view = new DataView(bytes);
    this.refs = new Array(nrefs);
  }
  loadU8(offset) { return this.view.getUint8(offset); }
  loadS8(offset) { return this.view.getInt8(offset); }
  // ... load{U,S}{16,32,64}, loadF{32,64} ...
  storeU8(offset, val) { this.view.setUint8(offset, val); }
  // ... store{U}{16,32,64}, storeF{32,64} ...

  loadRef(idx) { return this.refs[idx]; }
  storeRef(idx, obj) { this.refs[idx] = obj; }
}

let imports = {
  'gc_alloc': (nbytes, nrefs) => new WasmObj(nbytes, nrefs),

  'gc_load_u8': (obj, offset) => obj.loadU8(offset),
  'gc_load_s8': (obj, offset) => obj.loadS8(offset),
  // ... gc_load_{u,s}{16,32,64}, gc_load_f{32,64} ...
  'gc_load_ref': (obj, offset) => obj.loadRef(offset),

  'gc_store_u8': (obj, offset, val) => obj.storeU8(offset, val),
  // ... gc_store_{u}{16,32,64}, gc_store_f{32,64} ...
  'gc_store_ref': (obj, offset, ref) => obj.storeRef(offset, val),
};
```

### Raw WebAssembly proof-of-concept

[Milestone 4](./milestones/m4/) implements this proof of concept.  As
we don't yet have a compiler from C to WebAssembly that supports
`externref`, this example is written directly in WebAsembly.

Already, this proof-of-concept shows some interesting results.  One is
the existence proof that [JS can provide a GC-managed heap for C and C++
allocations](./milestones/m4#heap-provided-by-gc-capable-host).

Another result is that because GC-managed objects need no finalizers,
there is [no need to force programs to "yield" to allow finalizers to
run](./milestones/m4#no-need-to-break-up-main-loop-into-async-function).

Interestingly, we also find that [allocating C/C++ objects on GC heap
can have higher performance than linear memory plus
finalizers](./milestones/m4#lower-run-time-overhead-than-m0).

Finally we note that [the resulting system will be faster with the full
GC proposal](./milestones/m4#path-towards-gc-proposal), when it is no
longer necessary to call out to JavaScript for object allocation and
access.

### GC and C++ integration

Having proven that such a system can work well on the low-level, we
would like to target C++.  If we assume that LLVM has basic support for
externref, then what we'd like to do is to add annotations to
user-defined C++ types that are to be GC managed, and arrange for the
compiler to allocate their instances and allocate their members via the
imports defined above.  The language extension is defined in more detail
below, but it looks like this:

```c++
template<typename T>
ref class Stack {
  ref struct Node {
    T item;
    Node^ next;
  };
  Node^ first;
 public:
  Stack() {}

  void push(T item) {
    first = ref new Node(item, first);
  }
  T pop() {
    Node^ head = first;
    first = first->next;
    return head.item;
  }
};
```

Now if you're like us, you're cringing a bit: it's one thing to propose
some new primitives to allow C++ to allocate GC-managed memory, but it's
another to propose an entire language extension.  The rest of this
document discusses the feasibility of the language extension, but we
should keep in mind the points that our initial investigations have
shown:

 1. Systems with WebAssembly and JS should handle cycles
 2. Doing so with finalizers and weak references poses robustness problems
 3. Allocating GC-managed memory from WebAssembly is possible
 4. Allocating cycle-participating objects in GC-managed memory solves
    the cycle problem and has acceptable performance, even in the
    prototype phase
 5. There is the prospect in the medium-term of [WebAssembly being able
    to define, allocate, and access GC-managed struct types without
    calling out to
    imports](https://github.com/WebAssembly/gc/blob/master/proposals/gc/Overview.md),
    which would result in a high-performance system.

The attractiveness of a comprehensive, high-performance solution to the
cycle problem is such that it motivates us to imagine what a language
extension would look like, and how we could implement it.

## Inspiration: C++/CLI

The Ref C++ effort takes its inspiration from
[C++/CLI](https://en.wikipedia.org/wiki/C%2B%2B/CLI), which solved a
similar problem almost 20 years ago.  C++/CLI was an attempt to make C++
a first-class citizen in a .NET environment, whose "common language
infrastructure"
([CLI](https://en.wikipedia.org/wiki/Common_Language_Infrastructure))
specifies a system that's like WebAssembly plus garbage collection, a
standard object-oriented type system, and a large standard library.

Note that the problem we are solving with Ref C++ is easier than the
C++/CLI problem.  With C++/CLI, the goal was seamless interoperability
between C++ and C#; but in the case of WebAssembly and Ref C++, we are
just looking to solve the reference cycle problem.  Better
interoperability with JavaScript and the web platform is a worthy goal,
but its solution is already in progress in the context of [interface
types](https://github.com/WebAssembly/interface-types/blob/master/proposals/interface-types/Explainer.md),
[type
imports](https://github.com/WebAssembly/proposal-type-imports/blob/master/proposals/type-imports/Overview.md),
and similar proposals.  Ref C++ is tackling a lower-level problem.

Similarly, with Ref C++, we aren't looking to support an
already-existing VM out there that is specialized to the language needs
of an already-existing language, as was the case with the CLI and C#.
Whereas C++/CLI needs to have a story for interface classes, value
classes, enumerated types, multiple inheritance, virtual methods,
visibility, and so on, we don't have that problem.  Though we are using
the [reference types
proposal](https://github.com/WebAssembly/reference-types/blob/master/proposals/reference-types/Overview.md)
as a prototype for the future [garbage collection
proposal](https://github.com/WebAssembly/gc/blob/master/proposals/gc/Overview.md),
these WebAssembly extensions are under development and co-design, and do
not have a large API surface area.

What's left from C++/CLI to inspire this proposal is the basic treatment
of reference types: how to add support for automatic storage management
to a language designed for
[RAII](https://en.wikipedia.org/wiki/Resource_acquisition_is_initialization)
and linear memory.  With Ref C++, we think it's reasonable to assume
that extracting those core parts of C++/CLI will result in a coherent
language, at least in the beginning of the effort.  We can therefore
mostly skip over the language design phase, trusting that Herb Sutter
did a pretty good job with C++/CLI, and so our problem becomes one of
implementation rather than design.

The next section details the Ref C++ design, which as we note is mostly
taken from C++/CLI.  Before doing that, we should note that although the
CLI is still an important and active platform, the C++/CLI language,
while still available, is not a central part of it.  We don't really
know why at this point, but perhaps the reader will permit some
speculation.

One point is that between 2000 and 2005 or so, it seemed like .NET would
be the only way to develop on the Windows platform, and that bare-metal
applications would no longer really be supported.  Creating C++/CLI was
thus necessary to ensure the survival of C++ on Windows.  However this
all-managed vision did not come to pass.  The possibility of making
"native" applications never went away; indeed you can still program to
the Win32 API, or target the newer
[WinRT](https://en.wikipedia.org/wiki/Windows_Runtime) API.  Given a
choice, many C++ programmers chose to avoid the overhead of CLI, which
incidentally isn't as low-level as WebAssembly.  In our case we are
closer to the situation that C++ programmers feared in the early 2000s:
WebAssembly is the only realistic option for deploying C++ on the web.

Perhaps more importantly for our effort, though, is the fact that C++
programmers prefer libraries over language extensions.  Indeed, an
earlier version of a binding for WinRT targetting native deployments,
[C++/CX](https://en.wikipedia.org/wiki/C%2B%2B/CX), used a version of
C++/CLI's language extensions, but was superdeded by
[C++/WinRT](https://en.wikipedia.org/wiki/C%2B%2B/WinRT), which is a
library rather than an extension.  As Herb Sutter notes in the [C++/CLI
Rationale](http://www.gotw.ca/publications/C++CLIRationale.pdf), it's
important to make similar things look similar, but to make different
things look different; we are convinced the `Foo^` and `gcnew`
extensions are necessary for platforms including both linear memory and
a garbage collector, but we think they always have a cost relative to
core C++.  This cost is a risk that the Ref C++ project will need to
mitigate over time, especially by designing for patterns that keep the
core of an application in portable C++, and focusing on the use case
where users add a thin wrapper interface over the core, isolating the
Ref C++ extensions to the part of a codebase that interoperates with
JavaScript.

## Language extension

Ref C++ is:

 * standard C++
 * plus reference types: `ref class Foo {}`
 * plus handles (pointers to ref class): `Foo^ h = ref new Foo; Foo% ref = *f`
 * plus finalizers, in addition to destructors.

Let's go through these one by one.

### Ref C++ is standard C++

A Ref C++ program that doesn't use any extensions defined by Ref C++ is
the same as a standard C++ program.  In this prototype phase, we leave
the definition of what "standard C++" is to be a bit loose; as we are
implementing by extending LLVM, basically it means anything that LLVM
can compile.

Since we're taking an operational approach to defining what "standard
C++" means, we should specify that we are interested in the WebAssembly
context, so there are some limitations that the current toolchain and
indeed the current state of WebAssembly places on us; for example,
exceptions are poorly supported at the current time.  No divergence from
C++17 or C++20 is intended; any limitation that might currently be
present is simply a case of a not-yet-implemented feature and is
unrelated to the Ref C++ extension.

### Reference types

A class may be declared to be *reference-typed* if it is declared using
`ref class`, instead of `class`.

```c++
ref class Foo {};
```

We say that `Foo` is a *reference type*, or a *ref class*.  If we need
to make the distinction, we can call "normal" classes *linear classes*.

All subclasses of a ref class must themselves be declared using `ref
class`.  This makes it clear to the programmer which classes are
reference types and which are in linear memory.

Likewise there is `ref struct`, which is the same as `ref class` but
defaulting to having members being public.

### Handles

An instance of a ref class is allocated via `ref new` instead of `new`.
The result of `ref new` is a *handle* instead of a pointer; handle types
are declared with the sigil `^` instead of `*`.

```c++
Foo^ handle = ref new Foo;
```

It would be tempting to re-use `*` and `new`.  A predecessor to C++/CLI,
[Managed
C++](https://en.wikipedia.org/wiki/Managed_Extensions_for_C%2B%2B) took
this approach.  However handles are fundamentally unlike pointers in
some ways: you can't store them to the heap, you can't
`reinterpret_cast` them, even to `uintptr_t`, you can't compare them
with `<`, you can't use tagging strategies, and so on.  In the end it's
least surprising to use a separate data type.  See the [C++/CLI
Rationale](http://www.gotw.ca/publications/C++CLIRationale.pdf) for a
detailed discussion.

Attempting to `ref new Q` for a linear class `Q` is a compile-time
error.  Similarly, attempting to `new Foo` for a ref class `Foo` is a
compile-time error.

Members of a ref class instance can be accessed from a handle using the
usual `->` operator:

```c++
ref struct Bar { int x; };
Bar^ b = ref new Bar { 42 };
printf("%d\n", b->x); // prints "42"
```

Similarly, the result of unary `*` on a value of type `Foo^` is a value
of type `Foo%`, where `%` refers to a reference-typed value, but by
reference instead of by handle.  Most languages don't need to
distinguish between different kinds of references, but C++'s idioms
often involve implicit application of unary `*`, as in copy
constructors, so `Foo%` is to `Foo^` as `Q&` is to `Q*`.

It is only possible to create instances of reference types with dynamic
storage duration (i.e., heap-allocated).  It is only possible to refer
to instances of ref classes using handles (either `Foo^` or `Foo%`).
Handles can only have automatic storage duration (local variables,
function arguments, or function results).  `Foo^` handles (but not `Foo%`
handles) can also be members of ref classes:

```c++
template<typename T>
ref struct List { T head; List<T>^ tail; };
```

A later extension could add syntactic sugar to allow instances of ref
classes with automatic storage duration:

```c++
Bar b{42};
printf("%d\n", b.x); // prints "42"
```

Underneath this would translate to something like:

```c++
Bar^ b = ref new B{42};
printf("%d\n", b->x);
delete b;
```

Notably, these restrictions mean that (for example) `std::pair<int,
Foo^>` isn't possible, as the `std::pair` template expands to a linear
struct.  Generally speaking, if you need a handle that's not a
temporary, a local variable, a function argument, or a return value,
you'll need to use a side table.  Here's an implementation of a `Handle`
class encapsulating access to a side table, compiling down to uses of
the `table.size`, `table.grow`, `table.set`, and `table.get` WebAssembly
instructions:

```c++
// WebAssembly intrinsics to access tables
externref __wasm_null_externref(void);
uint32_t __wasm_table_size(uint32_t table_id);
uint32_t __wasm_table_grow_externref(uint32_t table_id, uint32_t new_size, externref init);
void __wasm_table_set_externref(uint32_t table_id, externref val);
externref __wasm_table_get_externref(uint32_t table_id, uint32_t id);

template<typename Foo>
class Handle {
  static const uint32_t externrefTableId = 42;
  static uint32_t nextId;
  static uint32_t tableSize = 0;
  static uint32_t intern(Foo^ obj) {
    uint32_t id = nextId++; // Poor man's freelist :)
    if (tableSize == 0) {
      tableSize = __wasm_table_size(externrefTableId);
    }
    if (tableSize <= nextId) {
      tableSize *= 2; tableSize++;
      __wasm_table_grow_externref(externrefTableId, tableSize,
                                   __wasm_null_externref());
    }
    __wasm_table_set_externref(externrefTableId, id, obj);
    return id;
  }
  static void ref(uint32_t id) {
    return __wasm_table_set_externref(externrefTableId, id);
  }
  static void release(uint32_t id) {
    __wasm_table_set_externref(externrefTableId, id, __wasm_null_externref());
    // FIXME: add id to free list.
  }

  uint32_t id_;
 public:
  Handle(Foo^ obj) id_(intern(obj)) {}
  ~Handle() { release(id_); }
  operator Foo^() { return ref(id_); }
};
```

We can choose to have implicit conversions, as in the above example, or
require explicit conversions; it's a library concern.  A use of `Handle`
would look like this:

```c++
void test(Foo^ arg) {
  std::pair<int, Handle<Foo>> p {42, arg};
  // ...
}
```

We admit that it can be confusing to say that a value of type `Foo^` is
a "handle", but then say that to hold a `Foo^` from linear memory, you
need to use the similarly-named `Handle`.  Better naming alternatives
are welcome, should this turn out to be a problem.

### Destructors and finalizers

One of the most pleasant parts about using C++ is the RAII idiom that
allows you to map resource acquisition and release to scopes, or in
general to value lifetimes.  You know when you go into a scope and
declare a `Bar x;`, that the destructor `Bar::~Bar` will be called when
control leaves the scope, to clean up resources associated with `x`.

Ref C++ keeps support for this idiom while relaxing restrictions on the
extent of an object's lifetime.  A ref class's destructor will still be
called in the same places that a linear class's destructor is called on
its instances: when automatic-storage-duration values go out of scope,
or when heap values are explicitly destroyed via `delete`.  Ref C++ also
adds a *finalizer* mechanism that complements destructors.

Note that many ref classes will be able to go without destructors or
finalizers at all.  Whereas a linear class almost always has some kind
of destructor, if only to release memory associated with its instances,
automatic storage management means that references between ref class
instances need no special acquire/release book-keeping code.  Of course,
occasionally a destructor is needed to free up external resources, like
file descriptors, and for that reason, Ref C++ allows ref classes to
have destructors that work just like linear class destructors.

When a ref class really needs a destructor, though, it often also needs
a finalizer, because a common pattern for using the result of `ref new
Foo` is to have all components that need the resulting `Foo^` to just
refer to it directly.  No reference-counting is needed, because that's
the garbage collector's job, and so no one will explicitly `delete` the
instance.  If the instance only has reference-typed fields, then usually
this is sufficient, but if the instance holds a refcount into a resource
from linear memory, the instance needs to release that reference via a
finalizer, to prevent leaks in linear memory.

Here we diverge a bit from C++/CLI, essentially for implementation
reasons.  No proposal for WebAssembly includes support for finalizers.
For the Web platform, we need to use the [WeakRefs proposal for
JavaScript](https://github.com/tc39/proposal-weakrefs), which exposes a
"post-mortem" interface: when the finalizer is run, the object is
already reclaimed.  With the `FinalizationRegistry` API defined in weak
refs, we can register an object to identify the resource to release (the
*held value*), but the held value can't be the finalizable object
itself, as `FinalizationRegistry` references the held value strongly.

Therefore, if we write the following class implementation with a
destructor and a finalizer, using the `!Foo()` syntax from C++/CLI, we
have:

```c++
ref struct Buf {
  uint8_t* bytes_;
  explicit Buf(size_t nbytes) : bytes_(new uint8_t[nbytes]) { }
  // The C++/CLI best practice is to make the destructor just
  // call the finalizer.
  ~Buf() { Buf::!Buf(); }
  // The finalizer.
  !Buf() { delete[] bytes_; }
};
```

In this example, we wouldn't be able to access `this` in `!Buf`, because
`!Buf` is called after the instance is collected.

What we can do is to have the finalizer effectively be a closure that
captures any member data that it references, effectively turning it into
a kind of static method that takes member data as arguments.  The
finalizer would not be able to call instance methods, as it has no
`this`.

It is important for a finalizer to capture only those fields that it
references, and no more.  Consider the following list implementation:

```c++
template<typename T>
ref struct PtrList {
  T* head;
  PtrList^ tail;
  PtrList(T* head, PtrList^ tail) : head(head), tail(tail) {}
  ~PtrList() { PtrList::!PtrList(); }
  !PtrList() { delete head; }
};

PtrList<int>^ foo(new int {42}, nullptr);
foo.tail = foo; // Create circular list
```

If the finalizer closed over `PtrList::tail`, then that would prevent
this circular list from being collected, even though we only attached
the finalizer so we could delete `PtrList::head`.  Therefore it should
be a language guarantee that finalizers only close over referenced
values, and that the above program is equivalent to:

```c++
void WASM_IMPORT(register_finalizer)(externref registry, externref obj,
                                     externref heldValue,
                                     externref unregisterToken);
void WASM_IMPORT(unregister_finalizer)(externref registry, externref obj);

template<typename T>
ref struct PtrList {
  ref struct Finalizer {
    T* head;
    void finalize() { delete head; }
  };

  ref class FinalizerSet {
    // FIXME: Specify how to obtain the registry from C++, and how
    // to make the JS run-time wire up calls to
    // FinalizerSet::invokeFinalizer() when objects are collected.
    externref registry_;
    void register(PtrList^ obj, Captured^ c) {
      register_finalizer(registry_, obj, captured, obj);
    }
    void unregister(PtrList^ obj) {
      unregister_finalizer(registry_, obj);
    }
    static void invokeFinalizer(externref held) {
      // FIXME: Specify conversion semantics between Foo^ and
      // the bottom type externref.
      Captured^ c = held;
      c->finalize();
    }
  };

  // For each class with finalizers, there is one FinalizationRegistry
  // instance on the JS side, wired up to call specific finalizer
  // routines.
  static FinalizerSet^ finalizers_;

  T* head;
  PtrList^ tail;
  Finalizer^ finalizer;
  PtrList(T* head, PtrList^ tail) : head(head), tail(tail), Finalizer{head} {
    finalizers_->register(this, finalizer);
  }
  ~PtrList() {
    finalizer->unregister(this);
    PtrList::!PtrList();
  }
  !PtrList() { finalizer->finalize(); }
};
```

In this example we unfortunately can't use `std::function` to represent
the finalizer as it's a linear class.  Probably there is some more
language design work to do here to be able to use [typed function
references](https://github.com/WebAssembly/function-references) from
C++, to allow C++ to robustly create reference-typed closures.

Note that the finalizer shown above captures closed-over fields by value
at time of construction, not by reference, because the finalizer can't
actually reference the instance.  It would be more consistent with the
idea of objects being state with identity if we captured by reference,
which we could do by performing assignment conversion on the mutable
state, either manually in the source or automatically in the compiler.
This would be a future extension.

### Limitations

In C++/CLI, you can refer to the address of a data member of a ref
instance:

```c++
ref class A { int i; };
void g(int* i) { *i = 42; }
void f(A^ a) { g(&a->i); }
```

Under the hood, this works by asking the garbage collector to pin the
location of `a` in memory, and by representing the address of `A::i` as
an `internal_pointer` data type.  This facility is unlikely to be
available to WebAssembly targets, and so we should assume that we simply
won't be able to take the address of data members of ref classes.
