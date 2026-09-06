#pragma once
#include <cstdint> // uint32_t/uint64_t, required by robin_hood.h
#include "robin_hood.h"
#include <string>
#include <utility>
#include <vector>

// The compiler's scoped name tables — the locals, the deferred locals, the constants and the
// import aliases. A block must SEE the names of the scope above it and forget its own at `end`,
// and there are two ways to do that:
//
//   CHAINED (default) — one small map per scope, looked up from the innermost outwards. Entering
//     a scope costs an empty map, leaving it costs its release. A name declared several scopes up
//     costs one extra lookup per level.
//   FLAT — a single map that every scope writes into, copied whole on entry and put back on exit.
//     Lookup is one probe whatever the depth; entering costs a copy of the ENTIRE enclosing scope.
//
// Measured on the compilation alone (callgrind): the copies of the flat form are 20,0 % of the
// work on tests/syntax.ol (a file with a very large top-level scope) and 6,4 % on
// docs/samples/voxel_world.ol, while the extra lookups the chain would add number 85 and 1 203
// respectively — noise. Hence the default. Nothing above the tables can tell which one is in use:
// both expose the same API, and the language behaves identically.
//
// Switch with `cmake -DOLLIN_SCOPED_TABLES=OFF` (or by defining the macro to 0).
#ifndef OLLIN_SCOPED_TABLES
#define OLLIN_SCOPED_TABLES 1
#endif

template <class V> class ChainedTable {
public:
    using Map = robin_hood::unordered_map<std::string, V>;
    // The whole stack, for a boundary a name does NOT cross: a function body sees the enclosing
    // locals as upvalues, never as locals. A state put aside stays SEARCHABLE through find_in,
    // so resolving an upvalue costs no copy.
    using State = std::vector<Map>;

    // An empty scope is stepped over instead of being probed: hashing the name has a cost even
    // when the map has nothing to answer, and a chain of blocks holds many empty scopes.
    static const V* find_in(const State& s, const std::string& k) {
        for (auto it = s.rbegin(); it != s.rend(); ++it) {
            if (it->empty())
                continue;
            auto e = it->find(k);
            if (e != it->end())
                return &e->second;
        }
        return nullptr;
    }
    static bool empty_in(const State& s) {
        for (const auto& f : s)
            if (!f.empty())
                return false;
        return true;
    }

    const V* find(const std::string& k) const {
        return find_in(frames_, k);
    }
    bool contains(const std::string& k) const {
        return find(k) != nullptr;
    }
    void set(const std::string& k, V v) {
        frames_.back()[k] = std::move(v);
    }
    // Reads a binding and removes it in ONE walk of the chain: the two were consecutive at the
    // only call site, which activates a deferred local. It may live in a scope further out than
    // the innermost one, which is why the walk exists at all.
    bool pop(const std::string& k, V& out) {
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it) {
            auto e = it->find(k);
            if (e != it->end()) {
                out = std::move(e->second);
                it->erase(e);
                return true;
            }
        }
        return false;
    }

    // A name bound in the CURRENT scope, remembering what that scope held so it can be put back.
    // The loop variable of a `for` is the only case: a loop has no scope of its own, so the
    // binding cannot be undone by leaving one.
    struct Shadow {
        std::string key;
        bool had = false;
        V old{};
    };
    Shadow bind_here(const std::string& k, V v) {
        Shadow sh{k, false, V{}};
        Map& scope = frames_.back();
        auto it = scope.find(k);
        sh.had = it != scope.end();
        if (sh.had)
            sh.old = it->second;
        scope[k] = std::move(v);
        return sh;
    }
    void unbind(const Shadow& sh) {
        if (sh.had)
            frames_.back()[sh.key] = sh.old;
        else
            frames_.back().erase(sh.key);
    }

    void enter() {
        frames_.emplace_back();
    }
    void leave() {
        frames_.pop_back();
    }
    State take() {
        State s = std::move(frames_);
        frames_.clear();
        frames_.emplace_back();
        return s;
    }
    void restore(State s) {
        frames_ = std::move(s);
    }

private:
    std::vector<Map> frames_{1};
};

template <class V> class FlatTable {
public:
    using Map = robin_hood::unordered_map<std::string, V>;
    struct State {
        Map m;
        std::vector<Map> saved;
    };

    static const V* find_in(const State& s, const std::string& k) {
        auto it = s.m.find(k);
        return it == s.m.end() ? nullptr : &it->second;
    }
    static bool empty_in(const State& s) {
        return s.m.empty();
    }

    const V* find(const std::string& k) const {
        auto it = m_.find(k);
        return it == m_.end() ? nullptr : &it->second;
    }
    bool contains(const std::string& k) const {
        return m_.count(k) != 0;
    }
    void set(const std::string& k, V v) {
        m_[k] = std::move(v);
    }
    bool pop(const std::string& k, V& out) {
        auto it = m_.find(k);
        if (it == m_.end())
            return false;
        out = std::move(it->second);
        m_.erase(it);
        return true;
    }

    struct Shadow {
        std::string key;
        bool had = false;
        V old{};
    };
    Shadow bind_here(const std::string& k, V v) {
        Shadow sh{k, false, V{}};
        auto it = m_.find(k);
        sh.had = it != m_.end();
        if (sh.had)
            sh.old = it->second;
        m_[k] = std::move(v);
        return sh;
    }
    void unbind(const Shadow& sh) {
        if (sh.had)
            m_[sh.key] = sh.old;
        else
            m_.erase(sh.key);
    }

    void enter() {
        saved_.push_back(m_);
    }
    void leave() {
        m_ = std::move(saved_.back());
        saved_.pop_back();
    }
    State take() {
        State s{std::move(m_), std::move(saved_)};
        m_.clear();
        saved_.clear();
        return s;
    }
    void restore(State s) {
        m_ = std::move(s.m);
        saved_ = std::move(s.saved);
    }

private:
    Map m_;
    std::vector<Map> saved_;
};

#if OLLIN_SCOPED_TABLES
template <class V> using ScopeTable = ChainedTable<V>;
#else
template <class V> using ScopeTable = FlatTable<V>;
#endif

// A set of names is a table whose value carries nothing.
struct NoValue {};
using ScopeNames = ScopeTable<NoValue>;

// The four tables ENTER and LEAVE together: a name belongs to a scope, not to one table's idea
// of a scope. Driving them one by one meant four lines at each of the four sites, and a forgotten
// one would not fail to compile — it would silently corrupt the scope of everything that follows.
struct ScopeTables {
    ScopeTable<int> regs;    // locals, by register
    ScopeTable<int> pending; // registers reserved for locals not yet declared
    ScopeNames consts;
    ScopeTable<std::string> aliases; // import alias → the module it names

    struct State {
        ScopeTable<int>::State regs, pending;
        ScopeNames::State consts;
        ScopeTable<std::string>::State aliases;
    };

    void enter() {
        regs.enter();
        pending.enter();
        consts.enter();
        aliases.enter();
    }
    void leave() {
        regs.leave();
        pending.leave();
        consts.leave();
        aliases.leave();
    }
    State take() {
        return State{regs.take(), pending.take(), consts.take(), aliases.take()};
    }
    void restore(State s) {
        regs.restore(std::move(s.regs));
        pending.restore(std::move(s.pending));
        consts.restore(std::move(s.consts));
        aliases.restore(std::move(s.aliases));
    }
};

// Enters a scope and leaves it whatever the exit — a compile error is thrown as an exception,
// and the scope must be left then too.
class ScopeGuard {
public:
    explicit ScopeGuard(ScopeTables& t) : t_(t) {
        t_.enter();
    }
    ~ScopeGuard() {
        t_.leave();
    }
    ScopeGuard(const ScopeGuard&) = delete;
    ScopeGuard& operator=(const ScopeGuard&) = delete;

private:
    ScopeTables& t_;
};
