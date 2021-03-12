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

function invoke(callback) {
    return callback()
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
        this.wasm.exports.attach_callback(this.obj, f);
    }
    invokeCallback() {
        this.wasm.exports.invoke_callback(this.obj);
    }
}

let bytes = readBinaryFile("test.wasm");
let mod = new WebAssembly.Module(bytes);
let memory = new LinearMemory({ initial: 2, maximum: 10 });
let rt = { invoke, out_of_memory };
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
