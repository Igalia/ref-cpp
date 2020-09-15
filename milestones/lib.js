let readBinaryFile = (()=> {
    if (typeof read !== 'undefined')
        return f => read(f, 'binary');
    if (typeof readFile !== 'undefined')
        return f => readFile(f);
    let fs = require('fs');
    return f => fs.readFileSync(f);
})();

let maybeGC = (()=> {
    // Engines will detect finalizable objects when they run GC.  They
    // run GC according to a number of heuristics, principally among
    // them how much GC-managed allocation has happened since the last
    // GC.  These heuristics are not informed how much off-heap
    // allocation has occured; see
    // https://github.com/tc39/proposal-weakrefs/issues/87.  In
    // practice, all engines will fail our tests, because they don't
    // detect finalizable objects soon enough.  Therefore to make these
    // tests reliable, we insert explicit GC calls.  This bodes poorly
    // for the role of finalizers in robust systems.  V8 does not expose
    // `gc` by default, though it will if you pass --expose-gc.
    if (typeof gc !== 'undefined')
        return gc;
    print('warning: no gc() exposed; no promptness guarantee for finalization');
    return ()=>{};
})();

let callLater = (()=> {
    // Note that d8's `setTimeout` ignores the timeout argument; it just
    // queues `f` without any delay.
    if (typeof setTimeout !== 'undefined')
        return f=>setTimeout(f, 0);
    if (typeof enqueueJob !== 'undefined')
        return f=>enqueueJob(f);
    return f=>f();
})();

let maybeDrainTasks = (()=> {
    // Weirdly, SpiderMonkey's (nonstandard) enqueueJob has higher
    // priority than finalization tasks.  We need to explicitly drain
    // tasks there to get finalizers to run.
    if (typeof drainJobQueue !== 'undefined')
        return drainJobQueue;
    return ()=>{};
})();

// Finalizers run in their own task.  This microsleep is a simple way to
// force the engine to go to the next turn.
async function microsleep() {
    await new Promise((resolve, reject) => callLater(resolve));
}

async function allowFinalizersToRun() {
    maybeGC();
    maybeDrainTasks();
    await microsleep();
}

// We are testing garbage collection and finalizers, for which async
// functions are a natural fit.  However we avoid putting the test
// itself in an async function, because of a gnarly SpiderMonkey
// limitation (https://bugzilla.mozilla.org/show_bug.cgi?id=1542660).
// Basically, in SpiderMonkey, any closure in an async function captures
// *all* local variables, potentially introducing cycles and preventing
// finalization.
async function runTestLoop(n, f, ...args) {
    for (let i = 0; i < n; i++) {
        f(...args);
        await allowFinalizersToRun();
    }
}

function checkSame(expected, actual, what) {
    print(`checking expected ${what}: ${expected}`);
    if (expected !== actual)
        throw new Error(`unexpected ${what}: ${actual}`);
}
