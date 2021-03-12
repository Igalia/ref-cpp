CC?=clang
LD?=wasm-ld
V8?=d8
JSC?=jsc
SPIDERMONKEY?=js

all: v8.test jsc.test spidermonkey.test

v8.test: JS?=$(V8) --harmony-weak-refs --expose-gc --experimental-wasm-reftypes
jsc.test: JS?=$(JSC) --useWeakRefs=true --useWebAssemblyReferences=true
spidermonkey.test: JS?=$(SPIDERMONKEY)

.PHONY: %.test
%.test: test.js ../lib.js test.wasm
	$(JS) $<

test.wasm: test.o
	$(LD) --no-entry --allow-undefined --import-memory -o $@ $^

test.o: test.S
	$(CC) -Oz -mreference-types --target=wasm32 -nostdlib -c -o $@ $<

# Alternately:
# test.o: test.wat
# 	$(WAT2WASM) --enable-all --relocatable -o $@ $<

.PHONY: clean
clean:
	rm -f test.o walloc.o test.wasm
