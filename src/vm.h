#pragma once
#include "chunk.h"
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

std::string value_to_string(const Value& v);

// Heap bytes currently in use, cross-platform. Backs the mem() builtin and the engine's
// memory overlay.
uint64_t ollin_heap_bytes();

// A runtime error that has ALREADY been given its source line. The type is the mark: nothing has
// to guess from the text, and a nested run_goto cannot prefix a second location. `bare` keeps the
// message as it was thrown, which is what a script's catch receives.
struct OllinError : std::runtime_error {
    std::string bare;
    OllinError(const std::string& located, std::string bare_msg)
        : std::runtime_error(located), bare(std::move(bare_msg)) {
    }
};

// A script-level `throw` whose handler belongs to an ENCLOSING run_goto: the value has to cross a
// native frame (a callback handed to array.map, to a mouse handler…) as a C++ exception, since
// only the enclosing loop may unwind to that handler.
struct OllinThrow {
    Value value;
};

class VM {
    // CallCtx writes its return values into regs through the index it carries, the pointer it was
    // handed being invalidated by any call that grows the register file.
    friend struct CallCtx;

  public:
    void execute(Chunk chunk);
    std::string invoke_str(Value v);
    static VM* current();                                           // returns s_current_vm
    Value call_value(const Value& fn, const Value* args, int argc); // the generic form
    Value call_value(const Value& fn);
    Value call_value(const Value& fn, const Value& a);
    Value call_value(const Value& fn, const Value& a, const Value& b);
    Value call_value(const Value& fn, const Value& a, const Value& b, const Value& c, const Value& d);
    // Like call_value, but collects up to out_cap return values (native->Ollin multi-return);
    // returns how many were actually written to out.
    int call_value_multi(const Value& fn, const Value* args, int argc, Value* out, int out_cap);
    Value get_global(const std::string& name) const; // returns nil if not found
    void set_global(const std::string& name, const Value& value);
    // Runs after execute(): calls setup() once, then starts the render loop through
    // graphics.run(draw) when a draw() exists. Shared by the native and WASM entry points,
    // hence tolerant of a nil or non-map `graphics`.
    void run_entry_hooks();

    // Set by gfx_canvas to record that graphics.canvas() ran for this program (the VM is new
    // on every run). It lets run_entry_hooks create an IMPLICIT canvas at W×H when a draw()
    // exists but no canvas was created explicitly.
    void mark_gfx_canvas() {
        gfx_canvas_created_ = true;
    }
    bool gfx_canvas_created() const {
        return gfx_canvas_created_;
    }

  private:
    bool gfx_canvas_created_ = false;
    std::string err_line() const;     // "file:line" from current ip
    void run_goto(size_t stop_depth); // unified computed-goto dispatch loop
    // Whether the innermost handler may be unwound to BY THIS invocation. A handler opened below
    // the floor belongs to an enclosing run_goto: only that loop may resume the program, so the
    // error has to propagate out through the native frame in between.
    bool handler_can_run(size_t stop_depth) const {
        return !handler_stack.empty() && handler_stack.back().call_depth > stop_depth;
    }
    struct Handler {
        uint32_t catch_addr;
        uint8_t catch_reg;
        int reg_base;
        size_t regs_size;
        size_t call_depth;
    };

    struct Frame {
        uint32_t return_ip = 0;
        int reg_base = 0;
        int varargs_base = 0;       // = reg_base + fp.reg_count (where varargs live in regs)
        int n_varargs = 0;          // count of extra variadic args (0 if none)
        int return_dest = -1;       // >= 0: RETURN stores R[0] into regs[return_dest] (metamethod result)
        bool negate_result = false; // true: RETURN logically negates the result before return_dest
                                    // (used by <> through __eq, and by >/>=/</<= on the flipped side)
        std::unique_ptr<std::vector<Upvalue*>> upvals;
        std::unique_ptr<std::vector<Upvalue*>> open_upvals;
    };

    // Monomorphic inline cache for GET_INDEX, one slot per instruction. A hit needs the same
    // map, the same version (bumped on every mutation, see Map::version / g_map_epoch) and the
    // same interned key; it then answers without proto_chain_get.
    // `val` is a NON-owning pointer into the map. A hit implies the version is unchanged, so
    // the entry is still there and keeps the value alive. Owning a copy would retain the object
    // long after the script dropped it, and cost a retain/release on every fill.
    struct GetIndexCache {
        const Map* map = nullptr;
        uint64_t version = 0;
        const InternedStr* key = nullptr;
        const Value* val = nullptr;
    };
    std::vector<GetIndexCache> gicache_;

    // Member of an IMMUTABLE module map (string_module_, array_module_), through the same
    // per-site cache: these maps never change, so every pass after the first is a hit. A null
    // `key_sptr` means the key is not a string (indexing a string by integer, say) and the
    // lookup is done directly, uncached.
    const Value* module_member(const Value& mod, const Value& key, const InternedStr* key_sptr) {
        const Map* m = mod.mptr;
        if (!key_sptr)
            return m->find_ptr(key);
        GetIndexCache& c = gicache_[ip - 1];
        if (c.map == m && c.version == m->version && c.key == key_sptr)
            return c.val;
        const Value* slot = m->find_ptr(key);
        if (slot) {
            c.map = m;
            c.version = m->version;
            c.key = key_sptr;
            c.val = slot;
        }
        return slot;
    }

    Chunk owned_chunk;
    const Chunk* ch = nullptr;
    Value string_module_;
    // Array pseudo-methods, built once (see array_module.cpp). Engine-internal: NOT a global
    // module exposed to scripts.
    Value array_module_;
    uint32_t ip = 0;
    std::vector<Value> globals;
    std::vector<bool> globals_init;
    std::vector<Value> regs;
    std::vector<Frame> call_stack;
    std::vector<Handler> handler_stack;
    // How many values the last call or return produced. Consumed ONLY by SPREAD_RESULTS,
    // emitted right after a call in a multi-return destructuring, to nil out the targets beyond
    // what the call actually returned — otherwise they would read stale registers.
    int last_results_ = 1;

    static Value proto_chain_get(const Value& obj, const Value& key);

    // Rest of the prototype chain (a map's __class__, a class's __parent__). The caller has
    // already searched obj's OWN data, so this avoids looking the same key up twice
    // (see op_GET_INDEX).
    static Value proto_chain_rest(const Value& obj, const Value& key);

    static bool is_instance(const Value& v);

    uint32_t try_meta_binary(const Value& name, int dest, Value lhs, Value rhs, bool negate = false);
    // Instantiates `cls`: the instance lands in regs[base_reg], arguments in
    // regs[base_reg+arg_off+i]. done=true when no frame was pushed (no init, or a builtin one,
    // and the result is already written); otherwise returns the address of init's body.
    uint32_t instantiate_class(int base_reg, int arg_off, int argc, Value cls, bool& done);
    uint32_t try_meta_unary(const Value& name, int dest, Value lhs);
    void close_upvals();                    // the whole frame (return, throw) — the HOT path
    void close_upvals_above(int threshold); // a scope that ends, such as an iteration
    // Unwinds to handler `h`, shrinks regs back, writes the caught value into the catch
    // register and points `ip` at the catch body. Shared by op_THROW (a script-level throw) and
    // by the C++ catch(runtime_error).
    void unwind_to_handler(const Handler& h, Value thrown);
    void grow_regs(size_t needed); // grows by doubling, up to 4096, and never shrinks

    // Calls a builtin: builds the CallCtx, invokes it, updates last_results_ and returns the
    // number of values produced. It is the SINGLE entry point of the six builtin call sites, so
    // that result_cap is computed in exactly one place and a future site cannot get it wrong.
    // `results` are the result slots (the arguments), `cap` the number of safe slots.
    int invoke_builtin(Value::BuiltinFn fn, Value* results, int argc, int cap, int regs_base = -1);
    // A return that yields NO value still leaves nil where the caller reads its result. The slot
    // kept whatever was there, so `var a = g()` on a bare `return` came back with a neighbouring
    // register — a function value, measured. last_results_ stays 0, so print(g()) keeps its empty
    // line and f(g()) passes no argument: the multi-value model (Lua's) is untouched.
    // NOT inlined, and that is measured, not a guess: inlined into the three return handlers it
    // cost the `loop` benchmark +600k instructions (+1.9 %) for code that never calls it — the
    // register allocation of run_goto, shared by every handler, shifting. noinline brings loop
    // and map back to their reference counts and leaves fib 0.55 % below it.
    __attribute__((noinline)) void nil_result_slot(int slot) {
        if ((int)regs.size() <= slot)
            regs.resize(slot + 1);
        regs[slot] = Value();
    }
    // The values a multi-value return gathers, on the STACK up to eight: a heap vector per return
    // was one malloc and one free for what is nearly always one or two values. Beyond eight it
    // falls back to a vector, so nothing is capped.
    struct RetBuf {
        static constexpr int k_inline = 8;
        Value inl[k_inline];
        std::vector<Value> heap;
        Value* p = inl;
        explicit RetBuf(int n) {
            if (n > k_inline) {
                heap.resize(n);
                p = heap.data();
            }
        }
    };
    // The tail of a return, shared by RETURN_V and RETURN_SPREAD (see vm.cpp). Kept out of
    // run_goto for the same reason as nil_result_slot.
    uint32_t finish_return(Value* rvs, int total);

    // Register variant: results go to regs[result_base..] and `cap` is derived from the current
    // frame (varargs_base - result_base) — the error-prone computation, kept in one place.
    // Used by CALL_DYN and CALL_METHOD.
    int invoke_builtin_regs(Value::BuiltinFn fn, int result_base, int argc);

    // Pushes a call frame, fills in defaults and varargs, returns fp.addr. `return_dest` is a
    // register of the CALLER, where a meta-method's single result goes, and -1 when unused.
    // A frame ALWAYS lays its results at its own base. There used to be a second, adjacent int
    // saying otherwise, for CALL_VARARGS alone — the one path that ran in a fresh window and
    // returned to the caller's static register. That path is gone (a `...` tail now lifts the
    // caller's varargs and calls in place, like every other call), and with it the axis: no site
    // named a result register, so the parameter, the Frame field and the two branches reading it
    // all described a case that no longer existed.
    // ⚠ NO default argument on `return_dest`, on purpose: a removed parameter once let a stale
    // `false` slide into it in SILENCE, a bool converting to int. Spelled out at every site, the
    // next signature change is a compile error wherever it lands instead of a wrong register.
    uint32_t push_frame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                        uint32_t return_ip, int return_dest);

    // THE CALLING CONVENTION, in one place. Every call ends at push_frame, but getting the
    // arguments to where it expects them used to be written out at each site, nine times over —
    // and each of those nine answered the same two questions:
    //
    //   where does the frame START?   at a register the caller reserved (the arguments are already
    //                                 in place there), or above everything a live frame occupies
    //   where do the ARGUMENTS come from?  already in place; or shifted to make room for a `self`;
    //                                      or copied in from outside the register file
    //
    // (A third question, where the RESULTS go, turned out not to vary at all: see push_frame.)
    //
    // The two helpers below name the two answers that are not "already in place". The in-place
    // case stays a direct push_frame call, deliberately: it is CALL_FUNC, CALL_DYN and
    // CALL_METHOD, thirty million calls in bench_fib, and CLAUDE.md records that wrapping this
    // path in named helpers cost +1,4 % and was reverted. Naming an axis must not add a layer to
    // the one path that cannot afford one.
    //
    // A frame born ABOVE everything, its arguments copied in from outside the register file — the
    // `__str` bridge, a meta-method, and the native-to-Ollin call all did this by hand. A `self`
    // is simply the first of those arguments.
    uint32_t push_frame_copied(uint8_t fi, const Value* args, int argc,
                               std::unique_ptr<std::vector<Upvalue*>> fuv, uint32_t return_ip, int return_dest);

    // A frame at a register the caller reserved, with `self` INSERTED at its base: the arguments
    // already sit at base + arg_off and slide to base + 1. Both callers — a constructor and a
    // method call — wrote the two directions of that slide themselves.
    uint32_t push_frame_self(int base, uint8_t fi, int argc, int arg_off, Value self,
                             std::unique_ptr<std::vector<Upvalue*>> fuv, uint32_t return_ip);
    // THE INVARIANT under all of it: no frame's window or vararg area ever overlaps another live
    // frame's. It is enforced by lifting the caller's varargs above whatever is about to be
    // written, which is what lift_varargs_above does — for EVERY live frame, never for the
    // immediate caller alone. FOUR callers, ONE mechanism, and each lifts
    // for the writes it is itself about to make: push_frame for the frame it is building;
    // push_frame_self before its slide, which is one slot WIDER than the block the caller laid
    // out and so reaches past it; CALL_VARARGS and CALL_METHOD before appending the caller's own
    // varargs to an argument block. Writing the lift a second time by hand is how the class path
    // came to overwrite a caller's `...` while the other paths were already safe — so a new call
    // path lifts through this function, never with a loop of its own.
    // `end` is one past the last register about to be written. It tests for itself, so a cold
    // caller may call it plainly; push_frame, on the hot path, pre-tests inline to skip the call.
    void lift_varargs_above(int end);

    // Appends the CURRENT frame's varargs at `dest` — a `...` tail, for a plain call as for a
    // method call — and returns how many were written. Both sites had the same five lines,
    // including the ordering that makes them correct (lift first, THEN read varargs_base), which
    // is exactly the shape of invariant that must not be written twice. noinline and out of
    // run_goto, like lift_varargs_above itself.
    int append_caller_varargs(int dest);

    // The lowest vararg area of any live frame, and k_no_varargs when there is none. It is the
    // O(1) filter in front of lift_varargs_above, whose walk is O(call depth). It may be too LOW
    // (a pop does not maintain it, so that op_RETURN pays nothing) but never too high: every
    // write to a varargs_base goes through push_frame or the lift, and both update it.
    static constexpr int k_no_varargs = 1 << 30;
    int va_low_ = k_no_varargs;

    [[gnu::always_inline]] inline double as_double(const Value& v) {
        if (v.is_integer())
            return (double)v.as_int();
        if (v.is_float())
            return v.as_float();
        // The SINGLE gate of all arithmetic and ordering comparisons: this is where the
        // boolean stays a type of its own. `true + 1` and `true < false` are therefore refused
        // without any opcode having to know about it.
        if (v.is_nil())
            throw std::runtime_error("runtime: expected number, got nil");
        if (v.is_bool())
            throw std::runtime_error("runtime: expected number, got boolean");
        throw std::runtime_error("runtime: expected number, got string");
    }
};

// The result slots are addressed through VM::regs and the index CallCtx carries, never through the
// `args` pointer: a builtin that calls Ollin code (an `__str`, a callback) may have grown the
// register file in between, and grow_regs reallocates it.
inline int CallCtx::ret(const Value& v) {
    if (result_cap <= 0)
        return 0;
    set_result(0, v);
    return 1;
}

inline void CallCtx::set_result(int i, const Value& v) {
    if (i < 0 || i >= result_cap)
        return;
    if (regs_base >= 0)
        vm->regs[(size_t)regs_base + i] = v;
    else
        args[i] = v;
}
