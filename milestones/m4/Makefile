CC?=clang
LLC?=llc
LD?=wasm-ld
V8?=d8
JSC?=jsc
SPIDERMONKEY?=js

all: v8.test jsc.test spidermonkey.test

v8.test: JS?=$(V8) --expose-gc
jsc.test: JS?=$(JSC)
spidermonkey.test: JS?=$(SPIDERMONKEY)

.PHONY: %.test
%.test: test.js ../lib.js test.wasm
	$(JS) $<

test.wasm: test.o
	$(LD) --no-entry --allow-undefined --import-memory -o $@ $^

test.o: test.ll
	$(LLC) -O2 -mattr=+reference-types -filetype=obj -o $@ $<

# Alternately:
#test.o: test.wat
#	$(WAT2WASM) --enable-all --relocatable -o $@ $<
# or even
#test.o: test.S
#	$(CC) -Oz -mreference-types --target=wasm32 -nostdlib -c -o $@ $<

.PHONY: clean
clean:
	rm -f test.o test.wasm
