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

let nalloc = 0;
class WasmObject {
    constructor(wasm) {        
        this.wasm = wasm
        let obj = wasm.exports.make_obj();
        nalloc++;
        this.obj = obj;
    }
    attachCallback(f) {
        this.wasm.exports.attach_callback(this.obj, f);
    }
    invokeCallback() {
        this.wasm.exports.invoke_callback(this.obj);
    }
}

function gc_alloc(nobjs, nbytes) {
    return {
        objs: nobjs ? new Array(nobjs) : null,
        bytes: nbytes ? new ArrayBuffer(nbytes) : null
    };
}
function gc_ref_obj(obj, i) { return obj.objs[i]; }
function gc_set_obj(obj, i, val) { obj.objs[i] = val; }
// Room here for gc_ref_u8, gc_set_f32, etc for obj.bytes.

function invoke(cb) { return cb(); }

let bytes = readBinaryFile("test.wasm");
let mod = new WebAssembly.Module(bytes);
let memory = new LinearMemory({ initial: 2, maximum: 10 });
let rt = { gc_alloc, gc_ref_obj, gc_set_obj, invoke };
let imports = { env: memory.env(), rt }
let instance = new WebAssembly.Instance(mod, imports);

function test(n) {
    for (let i = 0; i < n; i++) {
        let obj = new WasmObject(instance);
        obj.attachCallback(() => print(`Callback after ${nalloc} allocated.`));
        if (i == 0) obj.invokeCallback();
    }
    print(`${nalloc} total allocated.`);
}

function runTestSyncLoop(n, f, ...args) {
    for (let i = 0; i < n; i++) {
        f(...args);
    }
}

function main() {
    runTestSyncLoop(1e2, test, 1e3);
    print(`Success.`);
}
main()
