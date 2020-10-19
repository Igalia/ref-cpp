CC?=clang
LD?=wasm-ld
V8?=d8
JSC?=jsc
SPIDERMONKEY?=js

all: v8.test jsc.test spidermonkey.test

v8.test: JS?=$(V8) --harmony-weak-refs --expose-gc
jsc.test: JS?=$(JSC) --useWeakRefs=true
spidermonkey.test: JS?=$(SPIDERMONKEY)

.PHONY: %.test
%.test: test.js ../lib.js test.wasm
	$(JS) $<

test.wasm: test.o walloc.o
	$(LD) --no-entry --allow-undefined --import-memory -o $@ $^

walloc.o: walloc.c
	$(CC) -Oz --target=wasm32 -nostdlib -c -o $@ $<

test.o: test.S
	$(CC) -Oz --target=wasm32 -nostdlib -c -o $@ $<

# Alternately:
# test.o: test.wat
# 	$(WAT2WASM) --enable-all --relocatable -o $@ $<

.PHONY: clean
clean:
	rm -f test.o walloc.o test.wasm
