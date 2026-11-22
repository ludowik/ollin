#include "vm.h"
#include <algorithm>
#include <stdexcept>
#include <string>

// The coroutines of the VM: creating one, resuming it, yielding from it, and freeing it. What a coroutine is, and why a resume is a
// swap of the VM's execution state, is in coroutine.h. In a file of its own so that the hot loop's translation unit (vm.cpp) does not
// carry it: the code of the loop is sensitive to everything compiled next to it (see the note on -fira-region in CMakeLists.txt).

Coroutine::Coroutine() = default;

Coroutine::~Coroutine() {
    // A closure made inside a suspended coroutine may outlive it, and its upvalues still point into the register file that goes now.
    if (st)
        st->discard();
}

void coroutine_destroy(Coroutine* co) {
    delete co;
}

void CoState::close_all_upvalues() {
    for (VM::Frame& fr : call_stack) {
        if (!fr.open_upvals)
            continue;
        for (auto* uv : *fr.open_upvals)
            close_and_release(uv);
        fr.open_upvals->clear();
    }
}

void CoState::discard() {
    close_all_upvalues();
    call_stack.clear();
    handler_stack.clear();
    regs.clear();
    regs.shrink_to_fit();
}

void VM::swap_exec_state(CoState& s) {
    std::swap(regs, s.regs);
    std::swap(call_stack, s.call_stack);
    std::swap(handler_stack, s.handler_stack);
    std::swap(ip, s.ip);
    std::swap(va_low_, s.va_low);
}

Value VM::new_coroutine(const Value& fn) {
    if (!fn.is_func_val() && !fn.is_closure())
        throw std::runtime_error("coroutine.create: expected a function");
    std::unique_ptr<Coroutine> co(new Coroutine());
    co->fn = fn;
    co->st = std::make_unique<CoState>(); // the register file itself is reserved when the coroutine first runs: one never run costs nothing
    return Value::make_coroutine(co.release());
}

void VM::make_room(int end) {
    grow_regs((size_t)end);
    if (end > va_low_)
        lift_varargs_above(end);
}

std::vector<Value>& VM::resume_coroutine(const Value& co_value, const Value* args, int argc) {
    Coroutine* co = co_value.coptr;
    if (co->status != Coroutine::SUSPENDED)
        throw std::runtime_error(std::string("cannot resume a ") + Coroutine::status_name(co->status) + " coroutine");
    if (co_depth_ >= k_max_co_depth)
        throw std::runtime_error("coroutine nesting too deep (max 100)");
    ScopedInc depth(co_depth_);
    Value hold = co_value; // the coroutine runs to its next yield even if the caller's own reference was the last
    Coroutine* prev = current_co_;
    if (prev)
        prev->status = Coroutine::NORMAL;
    co->status = Coroutine::RUNNING;
    current_co_ = co;
    const int saved_nest = native_nest_;
    native_nest_ = 0;
    CoState& st = *co->st;
    swap_exec_state(st); // the coroutine's state is the VM's now, and st holds the resumer's
    auto leave = [&](Coroutine::Status status) {
        co->status = status;
        swap_exec_state(st); // st holds the coroutine's state again, the VM the resumer's
        native_nest_ = saved_nest;
        current_co_ = prev;
        if (prev)
            prev->status = Coroutine::RUNNING;
        if (status == Coroutine::DEAD)
            st.discard(); // a body that failed leaves frames with open upvalues, which are closed before the registers go
    };
    try {
        if (!co->fn.is_nil()) {
            regs.reserve(k_coroutine_regs); // this is the coroutine's own file now; it is never reallocated after this
            ClosureRef fuv;
            FuncIdx fi = resolve_func_val(co->fn, fuv, "runtime: call on non-function value");
            co->fn = Value{};
            ip = push_frame_copied(fi, args, argc, std::move(fuv), 0, -1);
        } else {
            // The resume's values are what the pending yield call returns: they go where its results would have. Every one of
            // them, however few slots the frame that called yield had: the room is made like a `...` tail makes it.
            if (argc > co->yield_cap)
                make_room(co->yield_base + argc);
            for (int i = 0; i < argc; ++i)
                regs[(size_t)co->yield_base + i] = args[i];
            if (argc == 0 && co->yield_cap > 0)
                regs[(size_t)co->yield_base] = Value{};
            last_results_ = argc;
        }
        run_goto(0);
        // The body returned: its values sit at the bottom of the file, last_results_ of them.
        co->xfer.clear();
        const int n = std::min(last_results_, (int)regs.size());
        for (int i = 0; i < n; ++i)
            co->xfer.push_back(regs[i]);
        leave(Coroutine::DEAD);
    } catch (const CoroutineYield&) {
        leave(Coroutine::SUSPENDED); // the values it yielded are in xfer already
    } catch (...) {
        leave(Coroutine::DEAD);
        throw;
    }
    return co->xfer;
}

void VM::yield_current(CallCtx& ctx) {
    if (!current_co_)
        throw std::runtime_error("yield outside a coroutine");
    // A native function (array.map, sort, __str…) that called Ollin code has a C++ frame in the way, which cannot be suspended.
    if (!can_yield(ctx))
        throw std::runtime_error("cannot yield across a native call (array.map, sort, __str…)");
    Coroutine* co = current_co_;
    co->yield_base = ctx.regs_base;
    co->yield_cap = ctx.result_cap;
    co->xfer.assign(ctx.args, ctx.args + ctx.argc);
    throw CoroutineYield{};
}
