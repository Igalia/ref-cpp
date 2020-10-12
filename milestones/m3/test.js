load('../lib.js');

class LinearMemory {
    constructor({initial = 256, maximum = 256}) {
        this.memory = new WebAssembly.Memory({ initial, maximum });
    }
    read_string(offset) {
        let view = new Uint8Array(this.memory.buffer);
        let bytes = []
        for (let byte = view[offset]; byte; byte = view[++offset])
            bytes.push(byte);
        return String.fromCharCode(...bytes);
    }
    log(str)      { console.log(`wasm log: ${str}`) }
    log_i(str, i) { console.log(`wasm log: ${str}: ${i}`) }
    env() {
        return {
            memory: this.memory,
            wasm_log: (off) => this.log(this.read_string(off)),
            wasm_log_i: (off, i) => this.log_i(this.read_string(off), i)
        }
    }
}

let finalizers = new FinalizationRegistry(f => { f(); });

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
        if (handle === -1) return;
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
function invoke(handle) {
    if (handle === -1) return;
    return table.ref(handle)();
}
function release(handle) {
    if (handle === -1) return;
    table.release(handle);
}
function out_of_memory() {
    print('error: out of linear memory');
    quit(1);
}

let nalloc = 0;
let nfinalized = 0;
let nmax = 0;
class WasmObject {
    constructor(wasm) {        
        this.wasm = wasm
        let obj = wasm.exports.make_obj();
        this.obj = obj;
        nalloc++;
        nmax = Math.max(nalloc - nfinalized, nmax);
        let free_obj = this.wasm.exports.free_obj;
        finalizers.register(this, () => { nfinalized++; free_obj(obj); }, this);
    }
    attachCallback(f) {
        let handle = table.intern(f);
        this.wasm.exports.attach_callback(this.obj, handle);
    }
    invokeCallback() {
        this.wasm.exports.invoke_callback(this.obj);
    }
}

let bytes = readBinaryFile("test.wasm");
let mod = new WebAssembly.Module(bytes);
let memory = new LinearMemory({ initial: 2, maximum: 10 });
let rt = { release, invoke, out_of_memory };
let imports = { env: memory.env(), rt }
let instance = new WebAssembly.Instance(mod, imports);

function test(n) {
    for (let i = 0; i < n; i++) {
        let obj = new WasmObject(instance);
        obj.attachCallback(() => print(`Callback after ${nalloc} allocated.`));
        if (i == 0) obj.invokeCallback();
    }
    print(`${nalloc} total allocated, ${nalloc - nfinalized} still live.`);
}

async function main() {
    await runTestLoop(1e2, test, 1e3);
    checkSame(nalloc - nfinalized, table.count(), "live object count");
    print(`Success; max ${nmax} objects live.`);
}
main()
