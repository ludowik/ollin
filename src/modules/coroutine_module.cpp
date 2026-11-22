#include "module_utils.h"
#include "vm.h"
#include <vector>

// The `coroutine` module: create a function that can be suspended, and resume it. The suspending itself is the `yield` keyword
// (the parser turns it into a call of the internal builtin __yield, in core_module.cpp); the machinery is VM::resume_coroutine
// and VM::yield_current, and coroutine.h says what a coroutine is.

namespace {

Coroutine* coroutine_arg(const CallCtx& ctx, int i, const char* fn) {
    if (ctx.argc <= i || !ctx.args[i].is_coroutine())
        throw std::runtime_error(std::string(fn) + ": expected a coroutine");
    return ctx.args[i].coptr;
}

// coroutine.create(f): a suspended coroutine whose body is f. Nothing runs until it is resumed.
int co_create(CallCtx& ctx) {
    if (ctx.argc != 1)
        throw std::runtime_error("coroutine.create: expected (function)");
    return ctx.ret(ctx.vm->new_coroutine(ctx.args[0]));
}

// coroutine.resume(co, ...): runs it until it yields or returns, and gives back the values it yielded or returned. The values
// after `co` are the body's arguments the first time and what the pending yield returns afterwards.
int co_resume(CallCtx& ctx) {
    Coroutine* co = coroutine_arg(ctx, 0, "coroutine.resume");
    // The arguments are read BEFORE anything runs: the result slots overlap them, and the body may use the register file.
    std::vector<Value> args(ctx.args + 1, ctx.args + ctx.argc);
    Value keep = ctx.args[0]; // the call's own reference to the coroutine may be the last
    std::vector<Value> out;
    ctx.vm->resume_coroutine(co, args.data(), (int)args.size(), out);
    int n = (int)out.size();
    if (n == 0) {
        // No value: the slot where the call's result is read must say nil, not what the arguments left in it.
        ctx.set_result(0, Value{});
        return 0;
    }
    n = ctx.vm->result_room(ctx, n);
    for (int i = 0; i < n; ++i)
        ctx.set_result(i, out[i]);
    return n;
}

// coroutine.status(co): "suspended", "running", "normal" (it resumed another one that has not finished) or "dead".
int co_status(CallCtx& ctx) {
    Coroutine* co = coroutine_arg(ctx, 0, "coroutine.status");
    return ctx.ret(Value(std::string(Coroutine::status_name(co->status))));
}

// coroutine.running(): the coroutine that runs this call, or nil in the main program.
int co_running(CallCtx& ctx) {
    Coroutine* co = ctx.vm->running_coroutine();
    if (!co)
        return ctx.ret(Value{});
    ++co->refcount;
    return ctx.ret(Value::make_coroutine(co));
}

// coroutine.isYieldable(): whether a yield here would work.
int co_is_yieldable(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(ctx.vm->can_yield()));
}

} // namespace

Value make_coroutine_module() {
    return MapBuilder()
        .fn("create", co_create)
        .fn("resume", co_resume)
        .fn("status", co_status)
        .fn("running", co_running)
        .fn("isYieldable", co_is_yieldable)
        .done();
}
