#pragma once
#include <string>
#include <unordered_map>
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
    using Value = V;
    using Map = std::unordered_map<std::string, V>;

    const V* find(const std::string& k) const {
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it) {
            auto e = it->find(k);
            if (e != it->end())
                return &e->second;
        }
        return nullptr;
    }
    bool contains(const std::string& k) const {
        return find(k) != nullptr;
    }
    void set(const std::string& k, V v) {
        frames_.back()[k] = std::move(v);
    }
    // Removes the binding wherever it lives: a deferred local is activated from the scope that
    // reserved it, which is not always the innermost one.
    void erase(const std::string& k) {
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it)
            if (it->erase(k) != 0)
                return;
    }
    bool empty() const {
        for (const auto& f : frames_)
            if (!f.empty())
                return false;
        return true;
    }
    Map& innermost() {
        return frames_.back();
    }

    void enter() {
        frames_.emplace_back();
    }
    void leave() {
        frames_.pop_back();
    }

    // The whole stack, for a boundary a name does NOT cross: a function body sees the enclosing
    // locals as upvalues, never as locals.
    using State = std::vector<Map>;
    State take() {
        State s = std::move(frames_);
        frames_.clear();
        frames_.emplace_back();
        return s;
    }
    void restore(State s) {
        frames_ = std::move(s);
    }

    // A state put aside stays SEARCHABLE: the enclosing function's names are read from here to
    // resolve an upvalue, without the copy that keeping a second table would cost.
    static const V* find_in(const State& s, const std::string& k) {
        for (auto it = s.rbegin(); it != s.rend(); ++it) {
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

private:
    std::vector<Map> frames_{1};
};

template <class V> class FlatTable {
public:
    using Value = V;
    using Map = std::unordered_map<std::string, V>;

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
    void erase(const std::string& k) {
        m_.erase(k);
    }
    bool empty() const {
        return m_.empty();
    }
    Map& innermost() {
        return m_;
    }

    void enter() {
        saved_.push_back(m_);
    }
    void leave() {
        m_ = std::move(saved_.back());
        saved_.pop_back();
    }

    struct State {
        Map m;
        std::vector<Map> saved;
    };
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

    static const V* find_in(const State& s, const std::string& k) {
        auto it = s.m.find(k);
        return it == s.m.end() ? nullptr : &it->second;
    }
    static bool empty_in(const State& s) {
        return s.m.empty();
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
