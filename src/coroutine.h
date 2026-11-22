#pragma once
// A coroutine: a function that can be suspended in the middle of its body and resumed later, with its locals as they
// were. STACKLESS, as in Lua: it has no stack of the processor, only the state the VM already keeps in members — a
// register file, a stack of call frames, the error handlers that are open, the instruction pointer. Resuming swaps that
// state into the VM, suspending swaps it back (VM::swap_exec_state), so it costs a handful of pointer exchanges and
// works the same natively and in WASM.
//
// The state lives in `st` while the coroutine is NOT running. While it runs, `st` holds the RESUMER's state instead —
// the swap is symmetric, which is why there is one function for both directions.
#include <memory>
#include <vector>

struct CoState; // the saved execution state, defined in vm.h with the VM types it is made of

struct Coroutine {
    int refcount = 1;
    enum Status : uint8_t { SUSPENDED, RUNNING, NORMAL, DEAD };
    Status status = SUSPENDED;
    bool started = false; // the body has been entered: the next resume continues instead of starting
    Value fn;             // the body, until it is first resumed
    std::unique_ptr<CoState> st;

    // What passes between a resume and a yield, on the side of the coroutine: `xfer` holds the values a yield hands to the
    // resumer; the next resume writes ITS values where the yield call would have put its results.
    std::vector<Value> xfer;
    int yield_base = -1; // index in the coroutine's register file of the first result slot of the pending yield
    int yield_cap = 0;   // how many result slots that call may write

    Coroutine();
    ~Coroutine(); // out of line: CoState is incomplete here, and the upvalues of a suspended frame must be closed

    Coroutine(const Coroutine&) = delete;
    Coroutine& operator=(const Coroutine&) = delete;

    static const char* status_name(Status s) {
        switch (s) {
        case SUSPENDED:
            return "suspended";
        case RUNNING:
            return "running";
        case NORMAL:
            return "normal";
        default:
            return "dead";
        }
    }
};

// Called when the last reference goes (Value::release_cold).
void coroutine_destroy(Coroutine* co);
