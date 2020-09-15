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

%.o: %.c
	$(CC) -Oz --target=wasm32 -nostdlib -c -o $@ $<

test.wasm: test.o
	$(LD) --no-entry --import-memory -o $@ $^

.PHONY: clean
clean:
	rm -f test.o test.wasm
