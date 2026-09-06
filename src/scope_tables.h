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

// Every table of the compiler keyed by an identifier. The NODE variant is deliberate: its VALUES
// keep their address when the table grows, which is what lets a lookup hand out a pointer that
// survives other work — the flat variant moves them, and every holder would have to know it, a
// mistake that reads a displaced entry in silence. ITERATORS are not covered by this, in either
// variant: a table that rehashes moves its positions, so an iterator held across an insertion
// must become a copy of the value (see visit(CallExpr)).
template <class V> using NameMap = robin_hood::unordered_node_map<std::string, V>;
// A set of names. Nothing is ever pointed INTO a set, so the flat variant is fine here.
using NameSet = robin_hood::unordered_set<std::string>;

// A name bound in ONE map, remembering what that map held so it can be put back. The loop
// variable of a `for` is the only case: a loop has no scope of its own, so the binding cannot be
// undone by leaving one. Both table forms bind in the map they call current, and only that
// differs — hence one pair of helpers instead of two copies.
template <class V> struct NameShadow {
    std::string key;
    bool had = false;
    V old{};
};

template <class V> NameShadow<V> shadow_in(NameMap<V>& m, const std::string& k, V v) {
    NameShadow<V> sh{k, false, V{}};
    auto it = m.find(k);
    sh.had = it != m.end();
    if (sh.had) {
        sh.old = std::move(it->second);
        it->second = std::move(v);
        return sh;
    }
    m.emplace(k, std::move(v));
    return sh;
}

template <class V> void unshadow_in(NameMap<V>& m, const NameShadow<V>& sh) {
    if (sh.had)
        m[sh.key] = sh.old;
    else
        m.erase(sh.key);
}

template <class V> class ChainedTable {
public:
    using Map = NameMap<V>;

    // An empty scope is stepped over instead of being probed: hashing the name has a cost even
    // when the map has nothing to answer, and a chain of blocks holds many empty scopes.
    const V* find(const std::string& k) const {
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it) {
            if (it->empty())
                continue;
            auto e = it->find(k);
            if (e != it->end())
                return &e->second;
        }
        return nullptr;
    }
    bool empty() const {
        for (const auto& f : frames_)
            if (!f.empty())
                return false;
        return true;
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

    using Shadow = NameShadow<V>;
    Shadow bind_here(const std::string& k, V v) {
        return shadow_in(frames_.back(), k, std::move(v));
    }
    void unbind(const Shadow& sh) {
        unshadow_in(frames_.back(), sh);
    }

    void enter() {
        frames_.emplace_back();
    }
    void leave() {
        frames_.pop_back();
    }
private:
    std::vector<Map> frames_{1};
};

template <class V> class FlatTable {
public:
    using Map = NameMap<V>;

    const V* find(const std::string& k) const {
        auto it = m_.find(k);
        return it == m_.end() ? nullptr : &it->second;
    }
    bool empty() const {
        return m_.empty();
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

    using Shadow = NameShadow<V>;
    Shadow bind_here(const std::string& k, V v) {
        return shadow_in(m_, k, std::move(v));
    }
    void unbind(const Shadow& sh) {
        unshadow_in(m_, sh);
    }

    void enter() {
        saved_.push_back(m_);
    }
    void leave() {
        m_ = std::move(saved_.back());
        saved_.pop_back();
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
