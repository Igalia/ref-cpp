# Externref in Clang/LLVM: Design Document

## Problem statement

### Externrefs in WebAssembly

Externref values are weird.

From a low-level perspective, externref values are unlike any other
value in LLVM.  They can't be stored to linear memory at all -- not to
the heap, not to data, not to the external stack.

WebAssembly has its own *internal* stack, of course, consisting of local
variables and temporary values inside function activations.  There, we
can have externref values, flowing into functions as parameters, out as
results, and within as mutable locals and ephemeral temporaries.  But
when compiling C++, we often find that a function needs to allocate with
automatic duration, and that goes out to the *external* stack in linear
memory.  Externrefs can't go there.

Externrefs can't be created by a WebAssembly program; they can only be
passed into it from the outside.  This can happen in four ways:

 * Returned from a call to an imported function.
```wasm
(func $foo (import "rt" "make_foo") (result externref))
(func $bar (result externref)
  (call $foo))
```
 * As an argument to an exported function.
```wasm
(func $take_foo (export "take_foo") (param externref) (result externref)
  (local.get 0))
```
 * Loaded from a table via `table.get`.  The table can be populated
externally, or the WebAssembly program can store externref values
there.
```wasm
(table $objects 0 externref)
(func $get_foo (result externref)
  (table.get $objects (i32.const 0)))
```
 * Loaded from a global of type `externref`.  As with tables, this
variable can be populated externally or internally.
```wasm
(global $the_foo (mut externref) (ref.null extern))
(func $get_the_foo (result externref)
  (global.get $the_foo))
```

### Externrefs don't exist in C

Let's assume that we would like to be able to make C programs that can
compile to these example WebAssembly snippets.  What should the C
programs look like?  How should they compile?

A first important thing to note is that there is no such C code "out
there" right now.  Unlike the original goal for emscripten, which was to
allow existing C and C++ programs to run in web browsers, there is no C
or C++ program out there now that deals in these externref values.  The
reason being, the low-level particularies of externrefs do not translate
well into C.

To illustrate this, assume the existence of an externref type in C.
Consider:

```c
struct a { int32_t b; externref c; };

struct a *a = malloc(sizeof a); // What is a->c ?
a->b = 42;
a->c = get_foo(); // Error!
```

What is the byte representation of an externref value?  All C++ types
can be written to memory, but we know nothing about externrefs, neither
from a semantics perspective nor from a low-level WebAssembly
perspective -- there are no operations that can tell you how to
represent it as bytes.

(We expect externref values to be implemented as GC-managed values in
WebAssembly implementations, as indeed they are in browsers.  But we
have no way of accessing the bits of the value.  We're careful not to
say "managed pointer" and "pointer address" here, because the GC-managed
value could be a tagged immediate without an associated address.)

## Externrefs are a problem for LLVM

Let's take another look at the first example.  If we were working with
`i32` values instead, we'd have:

```c
int foo(void);
int bar(void) {
  int ret = foo();
  return ret;
}
```

If we compile with -emit-llvm, we can see what clang does to produce
LLVM IR for this function:

```llvm
declare i32 @foo()

define i32 @bar() {
  %1 = alloca i32, align 4
  %2 = call i32 @foo()
  store i32 %2, i32* %1, align 4
  %3 = load i32, i32* %1, align 4
  ret i32 %3
}
```

What we can see is that the clang frontend will `alloca` some bytes for
each local.  Initializing `ret` stores a value to that location, and
referencing `ret` performs the corresponding memory load.  Clang relies
on the LLVM optimizer to turn these memory operations into SSA values
that don't need memory (the
[mem2reg](https://llvm.org/docs/Passes.html#mem2reg-promote-memory-to-register)
pass).

As a compilation strategy, this doesn't work for raw WebAssembly
externref values.  If we assume an `externref` type, and we have:

```c
externref foo(void);
externref bar(void) {
  externref ret = foo();
  return ret;
}
```

Then clang would lower it as

```
%externref = type opaque ; ????

define %externref @bar() {
  %1 = alloca %externref ; ????
  %2 = call %externref @foo() ; OK
  store %externref %2, %externref* %1 ; ????
  %3 = load %externref, %externref* %1 ; ????
  ret %externref %3 ; OK
}
```

How could we `alloca` memory for a value whose representation is opaque?

How could we load and store values into that memory?

Externrefs are a problem for clang, in the sense that its strategy of
using `alloca` for locals assumes that all locals can be stored to
linear memory.

## Solutions

### Idea 1: Indirection

Externref values have an impedance mismatch with C and with LLVM.  One
way to fix this would be to introduce an indirection.

When externref values enter WebAssembly, via one of the four methods
described earlier, we arrange to make the compiler write them to a
table.  All values of type `externref` in the C program are transformed
to operate on indices into this table.

The table becomes a parallel store of externref values -- like
linear memory, but for externrefs.  Like the linear memory heap, some
values have static duration (the data section), some have automatic
duration (the stack), and some have dynamic duration (the heap).  The
compiler and the linker will need to be extended in the usual ways to
manage this heap, allocating static objects, determining a
`__heap_base`, a stack size, and so on.

The compiler will have to emit corresponding operations to free values
from the externref heap when their duration ends.  When a function
activation with `alloca`'d externrefs returns, we'd have to reset the
"externref stack pointer", and to avoid retaining garbage, also null out
the freed entries in the stack part of the externref heap.

To C, an externref would then be like a pointer -- but not a pointer to
linear memory.  Dereferencing it doesn't really make sense, because
we're hiding externref values from C; the whole point of the indirection
is to prevent raw externref values from leaking to C.  So maybe a
pointer to an opaque type.  But, it's a pointer that can't really be
cast to any other pointer; so, perhaps a pointer in a different address
space, using the `__attribute__((address_space(N)))` facility originally
introduced for OpenCL and other partitioned-heap languages.  While we're
doing that, we could use the `N` in the address space to indicate
precisely which table the externref is stored in; it might be a neat
trick.

If we look at our example program, it could compile as:

```llvm
%externref = type opaque
%indirect_externref = %externref *

declare %indirect_externref @foo()

define %indirect_externref @bar() {
  %1 = alloca %indirect_externref
  %2 = call %indirect_externref @foo()
  store %indirect_externref %2, %indirect_externref* %1
  %3 = load %indirect_externref, %indirect_externref* %1
  ret %indirect_externref %3
}
```

But, perhaps this is a bit magical.  Who actually produces the indirect
externrefs?  Who puts the externref values in a table?  Who is
responsible for freeing the values when their duration ends?

Perhaps it's more illustrative to consider clang as performing the
indirection at all function boundaries, not just imported functions.  In
that case, `foo` returns a raw externref value, and `bar` would have to
intern it, then reload it before returning.  We're putting a large
burden on the optimizer here, but let's see where this takes us:

```llvm
%externref = type opaque ; ???
%opaque = type opaque
%indirect_externref = %opaque *

; Push one value on the externref stack, initializing to
; (ref.null extern).  Return its index.
declare i32 @externref_alloca()

; Set the externref corresponding to a table index.
declare void @externref_store(i32 %0, %externref %1);

; Retrieve the externref corresponding to a table index.
declare %externref @externref_load(i32 %0);

; Free one value from the externref stack, popping the
; externref stack pointer.
declare void @externref_freea()

; @foo and @bar return raw (not indirected) externrefs.
declare %externref @foo()

define %externref @bar() {
  %1 = alloca %indirect_externref
  %2 = call %externref @foo()
  %3 = call i32 @externref_alloca()
  call @externref_store(%3, %2)
  %4 = bitcast i32 %3 to %indirect_externref
  store %indirect_externref %4, %indirect_externref* %1
  %5 = load %indirect_externref, %indirect_externref* %1
  %6 = bitcast %indirect_externref %5 to i32
  %7 = call @externref_load(%6)
  call @externref_freea()
  ret %externref %7
}
```

There are a few things that pop out at us in this unoptimized code
listing.

 1. We now have a double indirection: one, that the %indirect_externref
    starts life in memory, and must be lifted to SSA values; and two,
    that the raw externref values themselves are also indirected into
    their own heap.

 2. Unlike `alloca`, we need to insert explicit `wasm_freea` calls on
    exit paths, and presumably on unwinds as well.

 3. There are three types here; we need the "opaque" type to indicate
    that %indirect_externref values can't be usefully dereferenced.

 4. For heap data with dynamic duration, it's not immediately clear
    where the compiler should insert `wasm_free` calls.

 5. You can do pointer arithmetic on %indirect_externref values.  This
    is not a good thing!

 6. How would you go about defining your own externref tables, or
    accessing values in those tables?  Would such values be
    doubly-indirected?

 7. We can use address spaces, but I am not sure what it buys us besides
    ensuring that %indirect_externref values aren't interpreted by the
    optimizer as aliasing anything on the linear heap.

### Idea 2: Restrictions and builtins

Let's back up here a bit.  WebAssembly has instructions to operate on
the linear heap, and (with reference types) on tables.  LLVM treats C
pointers as denoting locations on the linear heap; there is very little
impedance mismatch here betwen C, LLVM, and WebAssembly.

But with tables, why would we want to use pointers to denote externrefs?
We can't dereference the pointers, and arithmetic makes no sense.  The
externref values we're pointing to don't have a linear representation,
and it seems like clang's need to `alloca` local variable storage is a
tail-wagging-the-dog situation: it is what is causing us problems.

What if, instead, we treat externrefs as a new class of value.  There is
no code out there that uses them right now, so this is an option open to
us.  You can't take their address, you can't dereference them, in fact
you can't do anything on them other than use them as function
parameters, return values, and locals.  They have nothing to do with
tables.

With this approach, if we wanted to store an externref value to a
table, we'd call a builtin to do so.  If we need the null value, we call
a builtin.

If we need to store an externref to the heap -- well, you just can't do
that.  It's a restriction.  We require the user program to build its own
side table if needed.  We'd need explicit support in the compiler for
working with tables, so that the user could implement their side table,
but that's fine.

There is an open question about how we would represent raw externref
values in LLVM, but we also have that issue with the indirect strategy,
at the boundaries where values are stored and loaded.

Finally, we return to the `alloca` problem.  The reason clang takes this
approach is that locals are mutable; it needs to do a pass to determine
where to place phi variables.  We should adapt to this.  Locals of type
`externref` should be allocated not with standard `alloca`, but rather
something like `externref_alloca`.  The front-end would insert the
corresponding `externref_free` calls as well.  Therefore the IR coming
out of the front-end for our example would look like:

```llvm
define %externref @bar() {
  %1 = call %externref @foo()
  %2 = call i32 @externref_alloca()
  call @externref_store(%2, %1)
  %3 = call @externref_load(%2)
  call @externref_freea()
  ret %externref %3
}
```

We would then add a `mem2reg`-like optimizer pass that could reason
about `externref_alloca` and friends, allowing minimal optimization to
result in:

```llvm
define %externref @bar() {
  %1 = call %externref @foo()
  ret %externref %1
}
```

In summary, we would need to:
 1. Add an opaque type for `externref` to LLVM
 2. Add the externref alloca transformation to the C / C++ front-end
 3. Add front-end restrictions on where externrefs can be stored
 4. Add a mem2reg optimization pass for the externref stack

### Synthesis?

These two ideas approach each other from opposite directions.  If we
start from the perspective that externref values should be tightly
integrated with C, we arrive at the indirect approach.  If we start from
the code that we would like to generate, we arrive at the restrictive
approach; but we still need some run-time indirection facilities for
handling the `alloca` transformation.  But if we do support automatic
storage duration, why not add more transformations, for example to
support static durations?  And if we want good code, we already need a
`mem2reg` pass for the externref heap; could this result in good code
coming from the indirect side?

We don't know the answer, but we think that the incremental way to start
is to begin with the restrictive approach.  If the indirect approach is
possible (and a good idea), it can be reached next.
