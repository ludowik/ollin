#include "vm.h"
#include <algorithm>
#include <stdexcept>
#include <string>

// The coroutines of the VM: creating one, resuming it, yielding from it, and freeing it. What a coroutine is, and why a resume is a
// swap of the VM's execution state, is in coroutine.h. In a file of its own so that the hot loop's translation unit (vm.cpp) does not
// carry it: the code of the loop is sensitive to everything compiled next to it (see the note on -fira-region in CMakeLists.txt).

// A coroutine's register file: 16 bytes a register, reserved once because a file never moves (run_goto keeps a pointer into it, and
// so does every open upvalue). A body that needs more is refused, not grown.
static constexpr size_t k_coroutine_regs = 1024;

Coroutine::Coroutine() = default;
Coroutine::~Coroutine() = default;

void CoState::close_all_upvalues() {
    for (VM::Frame& fr : call_stack) {
        if (!fr.open_upvals)
            continue;
        for (auto* uv : *fr.open_upvals) {
            if (!uv->closed) {
                uv->val = uv->file[uv->frame_base + uv->reg_idx];
                uv->closed = true;
            }
            if (--uv->refcount == 0)
                upvalue_pool().release(uv);
        }
        fr.open_upvals->clear();
    }
}

void coroutine_destroy(Coroutine* co) {
    // A closure made inside a suspended coroutine may outlive it, and its upvalues still point into the register file that goes now.
    if (co->st)
        co->st->close_all_upvalues();
    delete co;
}

void VM::swap_exec_state(CoState& s) {
    std::swap(regs, s.regs);
    std::swap(call_stack, s.call_stack);
    std::swap(handler_stack, s.handler_stack);
    std::swap(ip, s.ip);
    std::swap(last_results_, s.last_results);
    std::swap(va_low_, s.va_low);
    std::swap(max_regs_, s.max_regs);
    std::swap(native_nest_, s.native_nest);
}

Value VM::new_coroutine(const Value& fn) {
    if (!fn.is_func_val() && !fn.is_closure())
        throw std::runtime_error("coroutine.create: expected a function");
    std::unique_ptr<Coroutine> co(new Coroutine());
    co->fn = fn;
    co->st = std::make_unique<CoState>();
    co->st->regs.reserve(k_coroutine_regs);
    co->st->max_regs = k_coroutine_regs;
    return Value::make_coroutine(co.release());
}

int VM::resume_coroutine(Coroutine* co, const Value* args, int argc, Value* out, int out_cap) {
    if (co->status != Coroutine::SUSPENDED)
        throw std::runtime_error(std::string("cannot resume a ") + Coroutine::status_name(co->status) + " coroutine");
    // The caller's arguments live in the register file that is about to be swapped out, and its own reference may be the
    // only one: copies keep them, and so does `hold`, for as long as the coroutine runs.
    std::vector<Value> argv(args, args + argc);
    ++co->refcount;
    Value hold = Value::make_coroutine(co);
    Coroutine* prev = current_co_;
    if (prev)
        prev->status = Coroutine::NORMAL;
    co->status = Coroutine::RUNNING;
    current_co_ = co;
    CoState& st = *co->st;
    swap_exec_state(st); // the coroutine's state is the VM's now, and st holds the resumer's
    auto back_to_resumer = [&] {
        swap_exec_state(st); // st holds the coroutine's state again, the VM the resumer's
        current_co_ = prev;
        if (prev)
            prev->status = Coroutine::RUNNING;
    };
    int n = 0;
    try {
        if (!co->started) {
            co->started = true;
            ClosureRef fuv;
            FuncIdx fi = resolve_func_val(co->fn, fuv, "runtime: call on non-function value");
            co->fn = Value{};
            ip = push_frame_copied(fi, argv.data(), argc, std::move(fuv), 0, -1);
        } else {
            // The resume's values are what the pending yield call returns: they go where its results would have.
            int m = std::min(argc, co->yield_cap);
            for (int i = 0; i < m; ++i)
                regs[(size_t)co->yield_base + i] = argv[i];
            if (m == 0 && co->yield_cap > 0)
                regs[(size_t)co->yield_base] = Value{};
            last_results_ = m;
        }
        run_goto(0);
        // The body returned: its values sit at the bottom of the file, last_results_ of them.
        n = std::min({last_results_, (int)regs.size(), out_cap});
        for (int i = 0; i < n; ++i)
            out[i] = regs[i];
        co->status = Coroutine::DEAD;
        back_to_resumer();
        st.regs.clear();
        st.regs.shrink_to_fit();
        st.handler_stack.clear();
        return n;
    } catch (const CoroutineYield&) {
        n = std::min((int)co->xfer.size(), out_cap);
        for (int i = 0; i < n; ++i)
            out[i] = std::move(co->xfer[i]);
        co->xfer.clear();
        co->status = Coroutine::SUSPENDED;
        back_to_resumer();
        return n;
    } catch (...) {
        // An error the body did not catch: the coroutine is dead, and what its frames still hold is closed before it is freed.
        co->status = Coroutine::DEAD;
        back_to_resumer();
        st.close_all_upvalues();
        st.regs.clear();
        st.regs.shrink_to_fit();
        st.call_stack.clear();
        st.handler_stack.clear();
        throw;
    }
}

void VM::yield_current(CallCtx& ctx) {
    if (!current_co_)
        throw std::runtime_error("yield outside a coroutine");
    // A native function (array.map, sort, __str…) that called Ollin code has a C++ frame in the way, which cannot be suspended.
    // A call that did not come from the register file (regs_base < 0) is such a call too.
    if (native_nest_ != 0 || ctx.regs_base < 0)
        throw std::runtime_error("cannot yield across a native call (array.map, sort, __str…)");
    Coroutine* co = current_co_;
    co->yield_base = ctx.regs_base;
    co->yield_cap = ctx.result_cap;
    co->xfer.assign(ctx.args, ctx.args + ctx.argc);
    throw CoroutineYield{};
}
