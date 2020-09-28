# Before starting

There are a few dependencies that we use as part of our test setup:
LLVM, wabt, and a JavaScript shell.  You should make sure to have them
installed before starting.

We assume that all of these projects are checked out in some root
directory bound to the `SRC` environment variable.  Like this:

```
export SRC=~/src
```

## LLVM

We use LLVM to compile (Ref) C++ to WebAssembly.  For the initial
milestones, upstream LLVM is sufficient, provided that it has support
for the WebAssembly target.  However as milestones proceed, we need the
Ref C++ extensions in our LLVM branch, which you can install like this:

```
cd $SRC
git clone https://github.com/pmatos/llvm-project
cd llvm-project
git checkout pmatos-reftypes
mkdir build && cd build
cmake -G 'Unix Makefiles' \
   -DLLVM_TARGETS_TO_BUILD='X86;WebAssembly' \
   -DLLVM_ENABLE_PROJECTS="clang;lld" \
   -DCMAKE_BUILD_TYPE=Debug \
   -DLLVM_ENABLE_ASSERTIONS=On \
   -DCMAKE_EXPORT_COMPILE_COMMANDS=On \
   -DLLVM_BUILD_32_BITS=Off \
   -DLLVM_ENABLE_BINDINGS=Off \
   ../llvm/

# Attention: linking takes a tremendous amount of memory. 
# If you don't need debug information in LLVM, use 
# -DCMAKE_BUILD_TYPE=Release
# The build will be faster and it will take considerably less memory.
make -j$(nproc)
```

You might need to run that last step a few times, until the linker
succeeds.  Once you're done, set the `LLVM` environment variable to the
build dir; usually this is sufficient:

```
export LLVM=$SRC/llvm-project/build/bin
export CC=$LLVM/clang
export LD=$LLVM/wasm-ld
```

You can check that your LLVM is built correctly by running
`$LLVM/llc --version`, which should output something like:

```
    LLVM (http://llvm.org/):
    LLVM version 12.0.0git
    DEBUG build with assertions.
    Default target: x86_64-unknown-linux-gnu
    Host CPU: skylake-avx512

    Registered Targets:
      wasm32 - WebAssembly 32-bit
      wasm64 - WebAssembly 64-bit
      x86    - 32-bit X86: Pentium-Pro and above
      x86-64 - 64-bit X86: EM64T and AMD64
```

We added the X86 targets assuming you're compiling on an x86 system;
it's useful to compare native and wasm compilation.

## wabt

Wabt (pronounced "wabbit") is the WebAssembly Binary Toolkit, and is
used for its `wat2wasm` tool, which translates a textual representation
of a WebAssembly module into a corresponding binary, suitable for
loading into a JavaScript shell.  Check it out and build it:

```
cd $SRC
git clone --recursive https://github.com/WebAssembly/wabt
cd wabt
make -j40 gcc-release
```

Then set `WABT`:

```
export WABT=$SRC/wabt/out/gcc/Release
```

You can check that everything is fine by running `$WABT/wat2wasm
--version`, which should print a version.

## A JavaScript shell

Ultimately we're targetting WebAssembly as deployed in web browsers, and
specifically in their JavaScript engines: V8 being the engine in Chrome,
and SpiderMonkey in Firefox.  However, the underlying "reference types"
WebAssembly feature used by our Ref C++ prototype is not yet included in
standard WebAssembly, so although it's present in both V8 and
SpiderMonkey, it's not on by default.  Therefore the easiest way to test
our milestones is with a standalone JavaScript "shell" -- a little
program that just includes the JavaScript / WebAssembly engine from a
web browser.

Since we use finalizers as part of some milestones, the best thing is to
build a fresh shell from upstream.  We won't include details here, but
if you have a V8 build you are looking for the `d8` binary:

```
# V8, checked out in ~/src/v8, built in out/x64.release
export D8=$SRC/v8/out/x64.release/d8
```

For Spidermonkey it's just `js`:

```
# SpiderMonkey, checked out in ~/src/mozilla-unified, built in +js-release
export SPIDERMONKEY=$SRC/mozilla-unified/+js-release/dist/bin/js
```

For JavaScriptCore it's `jsc`
```
# WebKit, checked out in ~/src/webkit, --jsc-only build in release mode
export JSC=$SRC/webkit/WebKitBuild/Release/bin/jsc
```

JavaScript shells doesn't have a standardized interface, but the
different implementations are close enough that our JavaScript code can
paper over the difference.  When you type "make" in a milestone, it will
test all shells.

## Summary

In the end if you have built the dependencies as described above, you
should be able to set the expected environment variables like:

```
export SRC=~/src
export LLVM=$SRC/llvm-project/build/bin
export CC=$LLVM/clang
export LD=$LLVM/wasm-ld
export WABT=$SRC/wabt/out/gcc/Release
export V8=$SRC/v8/out/x64.release/d8
export SPIDERMONKEY=$SRC/mozilla-unified/+js-release/dist/bin/js
export JSC=$SRC/webkit/WebKitBuild/Release/bin/jsc
```
