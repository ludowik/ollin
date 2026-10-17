## A copy of src/parser.cpp that RECORDS every line it runs. parseTrace(source) lexes a program with
## the lexer of the other example, then runs the engine's parsing rules on its tokens one C++ line at a
## time, and returns the steps the animation replays — each step is the line the parser is on, and what
## that line did to the tree — together with the tree itself.
## tests/parser_trace_test.ol checks that the tree is exactly the one the C++ parser builds, and
## tests/check_trace_source.sh that every line named below is the line of parser.cpp it claims to be.
##
## Each call `self.run(function, index, "start of the line", {extras})` records one step: `index`
## counts the lines of that function in cpp_source.ol (generated from parser.cpp), and the text is the
## beginning of the line, so a parser.cpp that moved on is noticed instead of lighting up the wrong
## line. The helpers peek(), advance(), check(), match(), expect() and the predicates are stepped
## OVER, as a debugger's "next" would: their effect shows on the line that calls them. A line that
## calls a function of the parser is lit twice: when it calls, and when the result comes back.
##
## What is NOT covered, and stops the trace with an error instead of showing something wrong: try,
## import, class, enum and switch statements, `ref`, `super`, and ranges. They are the same recursive
## descent as what is covered, and the example's programs do not use them.
##
## A step is a map:
##   fn, at, span   the function and the line (and how many more lines the statement covers)
##   also           a second line to mark, the `case` label a switch jumped through
##   stack          the calls in progress: "parse > parse_one_stmt > decl_stmt"
##   p0, p1         the parser's position (peek() is token number p) before and after the line
##   fx             what the line did to the tree: see applyEffect
##   ret            the node the line hands back to its caller
##   w              the locals worth watching, as [name, value] pairs
##   err, errLine   the refusal, and the line of the program it names
##   note           a sentence, on the lines that deserve one
##   event          true when the line consumed a token, changed the tree, or failed
##
## The tree is made of nodes {id, kind, attrs, kids, parent, slot}, one kind per node struct of
## ast.h. A node's `attrs` are its plain fields (a name, an operator), its `kids` the nodes it holds,
## each under the name of the field that holds it. Nodes are only ever changed by applyEffect, so the
## view can replay the steps and get the tree as it was.

import "../lexer/tracer.ol"
import "cpp_source.ol"

## What every kind of node holds, in the order of its fields in ast.h: the plain fields (`fmt` says
## how the tests write them) and the names of the fields that hold other nodes.
const SHAPES = {
    Program: {attrs: [], slots: ["stmts"]},
    VarDeclStmt: {attrs: [{key: "is_global", fmt: "bool", value: false}, {key: "is_constant", fmt: "bool", value: false},
                          {key: "names", fmt: "list"}], slots: ["values"]},
    ExprStmt: {attrs: [], slots: ["expr"]},
    AssignStmt: {attrs: [{key: "name", fmt: "str", value: ""}, {key: "op", fmt: "str", value: ""}], slots: ["value"]},
    IndexAssignStmt: {attrs: [{key: "obj", fmt: "str", value: ""}, {key: "op", fmt: "tok", value: "EQUALS"}],
                      slots: ["obj_expr", "key", "value"]},
    WhileStmt: {attrs: [], slots: ["cond", "body"]},
    DoStmt: {attrs: [], slots: ["body"]},
    IfStmt: {attrs: [], slots: ["cond", "then_body", "else_ifs", "else_body"]},
    ElseIfClause: {attrs: [], slots: ["cond", "body"]},
    BreakStmt: {attrs: [], slots: []},
    ContinueStmt: {attrs: [], slots: []},
    ThrowStmt: {attrs: [], slots: ["value"]},
    FuncDeclStmt: {attrs: [{key: "name", fmt: "str", value: ""}, {key: "params", fmt: "list"},
                           {key: "variadic", fmt: "bool", value: false}, {key: "is_static", fmt: "bool", value: false}],
                   slots: ["defaults", "body"]},
    ReturnStmt: {attrs: [{key: "spread_varargs", fmt: "bool", value: false}], slots: ["values"]},
    MultiAssignStmt: {attrs: [], slots: ["targets", "values"]},
    ForIterStmt: {attrs: [{key: "var1", fmt: "str", value: ""}, {key: "var2", fmt: "str", value: ""}],
                  slots: ["iter_expr", "body"]},
    BoolExpr: {attrs: [{key: "value", fmt: "bool", value: false}], slots: []},
    NumberExpr: {attrs: [{key: "value", fmt: "num", value: 0}], slots: []},
    StringExpr: {attrs: [{key: "value", fmt: "str", value: ""}], slots: []},
    VarExpr: {attrs: [{key: "name", fmt: "str", value: ""}], slots: []},
    NilExpr: {attrs: [], slots: []},
    VarArgExpr: {attrs: [], slots: []},
    BinaryExpr: {attrs: [{key: "op", fmt: "str", value: ""}], slots: ["left", "right"]},
    UnaryExpr: {attrs: [{key: "op", fmt: "str", value: ""}], slots: ["operand"]},
    ChainedCompareExpr: {attrs: [{key: "ops", fmt: "list"}], slots: ["operands"]},
    CallExpr: {attrs: [{key: "callee", fmt: "str", value: ""}, {key: "optional", fmt: "bool", value: false}],
               slots: ["args"]},
    ExprCallExpr: {attrs: [{key: "optional", fmt: "bool", value: false}], slots: ["callee", "args"]},
    MethodCallExpr: {attrs: [{key: "method", fmt: "str", value: ""}, {key: "is_super", fmt: "bool", value: false},
                             {key: "optional", fmt: "bool", value: false}], slots: ["receiver", "args"]},
    IndexExpr: {attrs: [], slots: ["obj", "key"]},
    ArrayExpr: {attrs: [], slots: ["elements"]},
    MapExpr: {attrs: [], slots: ["entries"]},
    MapEntry: {attrs: [], slots: ["key", "value"]},
    FuncExpr: {attrs: [{key: "params", fmt: "list"}, {key: "variadic", fmt: "bool", value: false}],
               slots: ["defaults", "body"]},
    InterpExpr: {attrs: [{key: "literals", fmt: "list"}], slots: ["exprs"]},
    RangeExpr: {attrs: [{key: "incl_left", fmt: "bool", value: true}, {key: "incl_right", fmt: "bool", value: true}],
                slots: ["start", "end", "step"]}
}

## The precedence table: one entry per level, loosest first, each a list of [token, operator character].
## The comparison keeps its rank as an empty entry (level 5), as in parser.cpp.
const LEVELS = [
    [["OR", "|"]], [["AND", "&"]], [["PIPE", "o"]], [["TILDE", "x"]], [["AMP", "b"]], [],
    [["LSHIFT", "l"], ["RSHIFT", "r"]], [["PLUS", "+"], ["MINUS", "-"]],
    [["STAR", "*"], ["SLASH", "/"], ["SLASH_SLASH", "q"], ["PERCENT", "%"]]
]
const CMP_LEVEL = 5
const N_LEVELS = 9

const CMP_CHARS = {EQUAL_EQUAL: "=", GREATER_EQUAL: "G", LESS_EQUAL: "L", NOT_EQUAL: "N", GREATER: ">", LESS: "<"}
const ASSIGN_OPS = {EQUALS: "", PLUS_EQUAL: "+", MINUS_EQUAL: "-", STAR_EQUAL: "*", SLASH_EQUAL: "/",
                    PERCENT_EQUAL: "%"}
const BLOCK_ENDS = {END: true, ELSE: true, ELSEIF: true, CATCH: true, CASE: true, EOF_T: true}

## The statements parse_one_stmt sends to their own function, by the token that starts them, and the
## ones this trace does not cover.
const DISPATCH = {
    WHILE: "while_stmt", DO: "do_stmt", IF: "if_stmt", BREAK: "break_stmt", CONTINUE: "continue_stmt",
    THROW: "throw_stmt", FOR: "for_stmt", FUNC: "func_decl_stmt", RETURN: "return_stmt"
}
const DECLARATIONS = {VAR: [false, false], GLOBAL: [true, false], CONSTANT: [false, true]}
const NOT_COVERED = {TRY: "try", IMPORT: "import", CLASS: "class", ENUM: "enum", SWITCH: "switch"}

## ── the tree ─────────────────────────────────────────────────────────────────

func newNode(id, kind)
    var attrs = {}
    for a in SHAPES[kind].attrs do
        if a.fmt == "list" then
            attrs[a.key] = []
        else
            attrs[a.key] = a.value
        end
    end
    return {id: id, kind: kind, attrs: attrs, kids: [], parent: 0, slot: ""}
end

func detach(nodes, child)
    if child.parent <> 0 then
        var keep = []
        for k in nodes[child.parent].kids do
            if k.id <> child.id then
                keep.push(k)
            end
        end
        nodes[child.parent].kids = keep
        child.parent = 0
        child.slot = ""
    end
end

## The only way a node changes. An effect is one of
##   {op: "new", id, kind}               a node is made
##   {op: "set", id, key, value}         a field gets a value
##   {op: "add", id, key, value}         a value is pushed on a field that is a list
##   {op: "put", child, parent, slot}    a node goes into a field of another (out of the one it was in)
##   {op: "free", id}                    a node nobody holds any more is destroyed
func applyEffect(nodes, e)
    if e.op == "new" then
        nodes[e.id] = newNode(e.id, e.kind)
    elseif e.op == "set" then
        nodes[e.id].attrs[e.key] = e.value
    elseif e.op == "add" then
        nodes[e.id].attrs[e.key].push(e.value)
    elseif e.op == "put" then
        var child = nodes[e.child]
        detach(nodes, child)
        child.parent = e.parent
        child.slot = e.slot
        nodes[e.parent].kids.push(child)
    else
        detach(nodes, nodes[e.id])
        nodes.delete(e.id)
    end
end

## A tree written as text, for the tests: the kind, the fields as `name:value`, then the held nodes
## grouped by field. The C++ parser's tree is written the same way by the tool the tests were checked
## with, so two trees are equal when their texts are.
func fieldText(fmt, v)
    if fmt == "bool" or fmt == "tok" then
        return "{v}"
    elseif fmt == "str" then
        return QUOTE + "{v}".replace(NEWLINE, "\n") + QUOTE
    elseif fmt == "num" then
        if typeof(v) == "int" then
            return "int {v}"
        end
        return "float {v}"
    end
    var items = []
    for x in v do
        items.push(QUOTE + "{x}" + QUOTE)
    end
    return "[" + items.join(",") + "]"
end

func sexp(node)
    var out = "(" + node.kind
    for a in SHAPES[node.kind].attrs do
        out = out + " " + a.key + ":" + fieldText(a.fmt, node.attrs[a.key])
    end
    for slot in SHAPES[node.kind].slots do
        var group = []
        for k in node.kids do
            if k.slot == slot then
                group.push(sexp(k))
            end
        end
        if #group > 0 then
            out = out + " (" + slot + " " + group.join(" ") + ")"
        end
    end
    return out + ")"
end

## ── the text of parser.cpp ───────────────────────────────────────────────────

global PCPP = loadCpp(PARSER_CPP_SOURCE)

## Where each `case` label of Parser::parse_one_stmt is, by the token it names, and its `default:`.
func loadParserCases()
    var at = {}
    for i, l in PCPP["parse_one_stmt"].trimmed do
        if l.startsWith("case TokenType::") then
            at[l.substr(17, #l).split(":")[1]] = i
        elseif l == "default:" then
            at["default"] = i
        end
    end
    return at
end

global PCASE = loadParserCases()

## The dispatch table above must name statement functions the switch really calls, on the line after
## each label: checked when the file is loaded, since the calls are made from the table.
func checkDispatch()
    for ty, fn in DISPATCH do
        var line = PCPP["parse_one_stmt"].trimmed[PCASE[ty] + 1]
        if not line.startsWith("return {fn}(") then
            throw "parse_one_stmt: the case of {ty} does not call {fn}: {line}"
        end
    end
end

checkDispatch()

## ── the parser ───────────────────────────────────────────────────────────────

func isKeywordType(ty)
    for word, t in KEYWORDS do
        if t == ty then
            return true
        end
    end
    return false
end

func isCmp(ty)
    return CMP_CHARS.has(ty)
end

func isBinaryOp(ty)
    for level in LEVELS do
        for op in level do
            if op[1] == ty then
                return true
            end
        end
    end
    return isCmp(ty) or ty == "CARET"
end

## A token that can only CONTINUE an expression: a binary operator, a field access, a call, an index.
func onlyContinuesExpr(ty)
    if ty == "MINUS" or ty == "NOT" or ty == "TILDE" or ty == "HASH" then
        return false
    elseif ty == "DOT" or ty == "QUESTION" or ty == "LPAREN" or ty == "LBRACKET" then
        return true
    end
    return isBinaryOp(ty) or ASSIGN_OPS.has(ty)
end

## What a value is called in the watch line.
func shownValue(v)
    if typeof(v) == "map" and v.has("kind") then
        return v.kind
    end
    return "{v}"
end

class ParseTracer
    ## `toks` is the token stream, each token {type, lexeme, line}; `result` collects the steps.
    func init(toks, result)
        self.toks = toks
        self.pos = 1           ## peek() is token number pos
        self.mark = 1          ## where pos was when the last step was recorded
        self.result = result
        self.frames = []       ## the calls in progress: {name, arg, w}
        self.stackText = ""
        self.pending = []      ## the effects of the line about to be recorded
        self.nodes = {}
        self.nextId = 1
        self.root = nil
    end

    ## ── the C++ helpers, stepped over ────────────────────────────────────────

    func peek()
        return self.toks[self.pos]
    end

    func check(ty)
        return self.toks[self.pos].type == ty
    end

    func advance()
        var t = self.toks[self.pos]
        self.pos += 1
        return t
    end

    func match(ty)
        if not self.check(ty) then
            return false
        end
        self.advance()
        return true
    end

    func atName()
        var ty = self.peek().type
        return ty == "IDENTIFIER" or (isKeywordType(ty) and ty <> "TRUE" and ty <> "FALSE" and ty <> "NIL")
    end

    func atOptionalCall()
        return self.check("QUESTION") and self.toks[self.pos + 1].type == "LPAREN"
    end

    func atBlockTerminator()
        return BLOCK_ENDS.has(self.peek().type)
    end

    ## expect(): the token when it is the one asked for, the refusal — recorded on the calling line — if
    ## not. The caller records its own step afterwards, with the effects of the line.
    func need(fn, index, start, ty)
        var t = self.peek()
        if t.type <> ty then
            self.fail(fn, index, start, "unexpected token '{t.lexeme}'",
                      {note: "expect(TokenType::{ty}) asks for a {ty}, and the next token is a {t.type}: the program is refused."})
        end
        self.pos += 1
        return t
    end

    ## expect_name(what): a plain name, which may be a keyword where no keyword can be meant.
    func needName(fn, index, start, what)
        var t = self.peek()
        if not self.atName() then
            self.fail(fn, index, start, "expected {what}, got '{t.lexeme}'")
        end
        self.pos += 1
        return t
    end

    ## expect(ty) alone on its line.
    func expectLine(fn, index, start, ty, extra)
        self.need(fn, index, start, ty)
        self.run(fn, index, start, extra)
    end

    ## ── the calls in progress ────────────────────────────────────────────────

    func enter(name, arg, w)
        self.frames.push({name: name, arg: arg, w: w or []})
        self.rewriteStack()
    end

    func leave()
        self.frames.pop()
        self.rewriteStack()
    end

    ## The calls, with the levels of a run of binary_level calls folded into one: "binary_level(0..4)".
    func rewriteStack()
        var parts = []
        var levels = nil
        for f in self.frames do
            if f.name == "binary_level" then
                if levels and levels.last + 1 == f.arg then
                    levels.last = f.arg
                else
                    levels = {first: f.arg, last: f.arg}
                    parts.push(levels)
                end
            else
                levels = nil
                parts.push(f.name)
            end
        end
        var text = []
        for p in parts do
            if typeof(p) == "map" then
                if p.first == p.last then
                    text.push("binary_level({p.first})")
                else
                    text.push("binary_level({p.first}..{p.last})")
                end
            else
                text.push(p)
            end
        end
        self.stackText = text.join(" > ")
    end

    ## Gives a local of the call in progress a value to show in the watch line.
    func local(name, value)
        var f = self.frames[#self.frames]
        var w = []
        var found = false
        for pair in f.w do
            if pair[1] == name then
                w.push([name, shownValue(value)])
                found = true
            else
                w.push(pair)
            end
        end
        if not found then
            w.push([name, shownValue(value)])
        end
        f.w = w
    end

    ## ── the tree ─────────────────────────────────────────────────────────────

    func effect(e)
        applyEffect(self.nodes, e)
        self.pending.push(e)
    end

    func make(kind)
        var id = self.nextId
        self.nextId += 1
        self.effect({op: "new", id: id, kind: kind})
        return self.nodes[id]
    end

    func set(node, key, value)
        self.effect({op: "set", id: node.id, key: key, value: value})
    end

    func add(node, key, value)
        self.effect({op: "add", id: node.id, key: key, value: value})
    end

    ## A node goes into the field `slot` of `parent`.
    func put(parent, slot, child)
        self.effect({op: "put", child: child.id, parent: parent.id, slot: slot})
    end

    func free(node)
        self.effect({op: "free", id: node.id})
    end

    ## ── recording ────────────────────────────────────────────────────────────

    ## Records the line `index` of function `fn`, which the parser has just run. `start` is how that
    ## line begins: checked here, and by tests/check_trace_source.sh for every call.
    func run(fn, index, start, extra)
        var trimmed = PCPP[fn].trimmed
        if not trimmed[index].startsWith(start) then
            throw "{fn} line {index} is not '{start}': {trimmed[index]}"
        end
        var f = extra or {}
        f.fn = fn
        f.at = index
        f.span = f.span or 0
        f.stack = self.stackText
        f.p0 = self.mark
        f.p1 = self.pos
        f.fx = self.pending
        f.w = self.frames[#self.frames].w
        if f.ret then
            f.ret = f.ret.id
        end
        f.event = f.p1 > f.p0 or #f.fx > 0 or f.err <> nil
        self.mark = self.pos
        self.pending = []
        self.result.steps.push(f)
        return f
    end

    ## The refusal: recorded on the line that makes it, then the whole parse stops.
    func failAt(fn, index, start, line, msg, extra)
        var f = extra or {}
        f.err = msg
        f.errLine = line
        self.run(fn, index, start, f)
        throw "parse error"
    end

    func fail(fn, index, start, msg, extra)
        self.failAt(fn, index, start, self.peek().line, msg, extra)
    end

    ## A construct this trace does not cover.
    func notCovered(what)
        throw "not covered by this trace: {what}"
    end

    ## ── the lists of a statement ─────────────────────────────────────────────

    ## parse_body_until(out, stops): statements into the field `slot` of `parent`, up to a token of `stops`.
    func parseBodyUntil(parent, slot, stops)
        self.enter("parse_body_until", nil, [])
        self.run("parse_body_until", 2, "while (true)")
        while true do
            var done = self.check("EOF_T")
            self.run("parse_body_until", 3, "if (check(TokenType::EOF_T))")
            if done then
                self.run("parse_body_until", 4, "return;")
                break
            end
            var stopped = false
            var k = 1
            while true do
                var more = k <= #stops
                self.run("parse_body_until", 5, "for (TokenType t : stops)")
                if not more then
                    break
                end
                self.local("t", stops[k])
                var hit = self.check(stops[k])
                self.run("parse_body_until", 6, "if (check(t))")
                if hit then
                    stopped = true
                    break
                end
                k += 1
            end
            if stopped then
                self.run("parse_body_until", 7, "return;",
                         {note: "The next token, {self.peek().type}, ends the block: the statements stop here."})
                break
            end
            self.run("parse_body_until", 8, "out.push_back(parse_one_stmt());")
            var st = self.parseOneStmt()
            self.put(parent, slot, st)
            self.run("parse_body_until", 8, "out.push_back(parse_one_stmt());", {ret: st})
        end
        self.leave()
    end

    ## parse_expr_list(out): one expression, then one more after each comma.
    func parseExprList(parent, slot)
        self.enter("parse_expr_list", nil, [])
        self.run("parse_expr_list", 2, "out.push_back(expr());")
        var e = self.expr()
        self.put(parent, slot, e)
        self.run("parse_expr_list", 2, "out.push_back(expr());", {ret: e})
        while true do
            var comma = self.match("COMMA")
            self.run("parse_expr_list", 3, "while (match(TokenType::COMMA))")
            if not comma then
                break
            end
            self.run("parse_expr_list", 4, "out.push_back(expr());")
            e = self.expr()
            self.put(parent, slot, e)
            self.run("parse_expr_list", 4, "out.push_back(expr());", {ret: e})
        end
        self.leave()
    end

    ## parse_call_args(out): the arguments of a call whose '(' is already read, ')' included.
    func parseCallArgs(parent, slot)
        self.enter("parse_call_args", nil, [])
        var empty = self.check("RPAREN")
        self.run("parse_call_args", 2, "if (!check(TokenType::RPAREN))")
        if not empty then
            self.run("parse_call_args", 3, "parse_expr_list(out);")
            self.parseExprList(parent, slot)
            self.run("parse_call_args", 3, "parse_expr_list(out);")
        end
        self.expectLine("parse_call_args", 4, "expect(TokenType::RPAREN);", "RPAREN",
                        {note: "The ')' closes the call."})
        self.leave()
    end

    ## parse_params(params, defaults, variadic): "(" [ params ] ")", into the fields of `owner`.
    func parseParams(owner)
        self.enter("parse_params", nil, [])
        self.expectLine("parse_params", 3, "expect(TokenType::LPAREN);", "LPAREN")
        while true do
            var more = not self.check("RPAREN") and not self.check("EOF_T")
            self.run("parse_params", 4, "while (!check(TokenType::RPAREN)")
            if not more then
                break
            end
            var dots = self.match("DOT_DOT_DOT")
            self.run("parse_params", 5, "if (match(TokenType::DOT_DOT_DOT))")
            if dots then
                self.set(owner, "variadic", true)
                self.run("parse_params", 6, "variadic = true;")
                self.run("parse_params", 7, "break;")
                break
            end
            var name = self.need("parse_params", 9, "params.push_back(expect(", "IDENTIFIER")
            self.add(owner, "params", name.lexeme)
            self.run("parse_params", 9, "params.push_back(expect(")
            var hasDefault = self.match("EQUALS")
            self.run("parse_params", 10, "defaults.push_back(match(TokenType::EQUALS)", {span: 0})
            if hasDefault then
                var d = self.expr()
                self.put(owner, "defaults", d)
                self.run("parse_params", 10, "defaults.push_back(match(TokenType::EQUALS)", {ret: d})
            end
            var last = self.check("RPAREN")
            self.run("parse_params", 11, "if (!check(TokenType::RPAREN))")
            if not last then
                self.expectLine("parse_params", 12, "expect(TokenType::COMMA);", "COMMA")
            end
        end
        self.expectLine("parse_params", 14, "expect(TokenType::RPAREN);", "RPAREN")
        self.leave()
    end

    ## ── Parser::parse and parse_one_stmt ─────────────────────────────────────

    func parse()
        self.enter("parse", nil, [])
        var prog = self.make("Program")
        self.root = prog
        self.run("parse", 2, "Program prog;",
                 {note: "The parser starts a Program, an empty list of statements, and fills it from the tokens."})
        self.run("parse", 3, "while (true)")
        while true do
            var done = self.check("EOF_T")
            self.run("parse", 4, "if (check(TokenType::EOF_T))")
            if done then
                self.run("parse", 5, "break;", {note: "EOF_T: every token has been read, the program is complete."})
                break
            end
            self.run("parse", 6, "prog.stmts.push_back(parse_one_stmt());")
            var st = self.parseOneStmt()
            self.put(prog, "stmts", st)
            self.run("parse", 6, "prog.stmts.push_back(parse_one_stmt());", {ret: st})
        end
        self.run("parse", 8, "prog.source_files =")
        self.run("parse", 9, "return prog;", {ret: prog})
        self.leave()
    end

    func parseOneStmt()
        self.enter("parse_one_stmt", nil, [])
        self.run("parse_one_stmt", 2, "if (depth_ >= 256)",
                 {note: "depth_ counts the statements and expressions being parsed inside each other: a runaway nesting is refused before it can overflow the stack."})
        self.run("parse_one_stmt", 4, "DepthGuard guard(depth_);")
        var ty = self.peek().type
        var continues = onlyContinuesExpr(ty)
        self.run("parse_one_stmt", 10, "if (only_continues_expr(peek().type))")
        if continues then
            self.fail("parse_one_stmt", 11, "fail(std::string(",
                      "a statement cannot begin with '{self.peek().lexeme}' — such a line continues the expression above; give the value a name instead",
                      {span: 1})
        end
        var st = nil
        if ty == "SEMICOLON" then
            self.run("parse_one_stmt", 13, "switch (peek().type)", {also: PCASE["SEMICOLON"]})
            self.fail("parse_one_stmt", 17, "fail(", "';' is not valid syntax — statements are terminated by newlines")
        end
        if NOT_COVERED.has(ty) then
            self.notCovered(NOT_COVERED[ty])
        end
        var note = "peek() is {ty}: the switch has no case for it, so the statement is an expression."
        if DISPATCH.has(ty) or DECLARATIONS.has(ty) or ty == "IDENTIFIER" then
            note = "peek() is {ty}: the switch jumps to its case."
        end
        if DISPATCH.has(ty) then
            self.run("parse_one_stmt", 13, "switch (peek().type)", {also: PCASE[ty], note: note})
            var fn = DISPATCH[ty]
            var at = PCASE[ty] + 1
            self.run("parse_one_stmt", at, "return {fn}();")
            st = self.statement(fn)
            self.run("parse_one_stmt", at, "return {fn}();", {ret: st})
        elseif DECLARATIONS.has(ty) then
            self.run("parse_one_stmt", 13, "switch (peek().type)", {also: PCASE[ty], note: note})
            var at = PCASE[ty] + 1
            var flags = DECLARATIONS[ty]
            self.run("parse_one_stmt", at, "return decl_stmt(")
            st = self.declStmt(flags[1], flags[2])
            self.run("parse_one_stmt", at, "return decl_stmt(", {ret: st})
        elseif ty == "IDENTIFIER" then
            self.run("parse_one_stmt", 13, "switch (peek().type)", {also: PCASE["IDENTIFIER"], note: note})
            st = self.identifierStmt()
        else
            self.run("parse_one_stmt", 13, "switch (peek().type)", {also: PCASE["default"], note: note})
            self.run("parse_one_stmt", 70, "break;")
            self.run("parse_one_stmt", 72, "return expr_stmt();")
            st = self.exprStmt()
            self.run("parse_one_stmt", 72, "return expr_stmt();", {ret: st})
        end
        self.leave()
        return st
    end

    ## The statement functions that have no argument.
    func statement(fn)
        if fn == "while_stmt" then
            return self.whileStmt()
        elseif fn == "do_stmt" then
            return self.doStmt()
        elseif fn == "if_stmt" then
            return self.ifStmt()
        elseif fn == "break_stmt" then
            return self.simpleStmt("break_stmt", "BreakStmt")
        elseif fn == "continue_stmt" then
            return self.simpleStmt("continue_stmt", "ContinueStmt")
        elseif fn == "throw_stmt" then
            return self.throwStmt()
        elseif fn == "for_stmt" then
            return self.forStmt()
        elseif fn == "func_decl_stmt" then
            return self.funcDeclStmt()
        end
        return self.returnStmt()
    end

    ## The case of an identifier: an assignment, a multiple assignment or an expression statement.
    func identifierStmt()
        var line = self.peek().line
        self.local("line", line)
        self.run("parse_one_stmt", 58, "int line = peek().line;",
                 {note: "A statement that starts with a name is parsed as an expression first; what follows tells which statement it was."})
        self.run("parse_one_stmt", 59, "auto e = expr();")
        var e = self.expr()
        self.local("e", e)
        self.run("parse_one_stmt", 59, "auto e = expr();", {ret: e})
        var assign = ASSIGN_OPS.has(self.peek().type)
        self.run("parse_one_stmt", 60, "if (is_assign_op(peek().type))")
        if assign then
            self.run("parse_one_stmt", 61, "return finish_assign_from_expr(")
            var st = self.finishAssign(e, line)
            self.run("parse_one_stmt", 61, "return finish_assign_from_expr(", {ret: st})
            return st
        end
        var comma = self.check("COMMA")
        self.run("parse_one_stmt", 62, "if (check(TokenType::COMMA))")
        if comma then
            self.run("parse_one_stmt", 63, "return multi_assign_stmt(")
            var st = self.multiAssignStmt(e, line)
            self.run("parse_one_stmt", 63, "return multi_assign_stmt(", {ret: st})
            return st
        end
        var st = self.make("ExprStmt")
        self.put(st, "expr", e)
        self.run("parse_one_stmt", 64, "auto st = std::make_unique<ExprStmt>(",
                 {note: "Nothing follows the expression: it is a statement of its own, an ExprStmt."})
        self.run("parse_one_stmt", 65, "st->line = line;")
        self.run("parse_one_stmt", 66, "st->file_idx = current_file_idx_;")
        self.run("parse_one_stmt", 67, "return st;", {ret: st})
        return st
    end

    ## ── the statements ───────────────────────────────────────────────────────

    func exprStmt()
        self.enter("expr_stmt", nil, [])
        var line = self.peek().line
        self.run("expr_stmt", 2, "int line = peek().line;")
        self.run("expr_stmt", 3, "auto e = expr();")
        var e = self.expr()
        self.run("expr_stmt", 3, "auto e = expr();", {ret: e})
        var s = self.make("ExprStmt")
        self.put(s, "expr", e)
        self.run("expr_stmt", 4, "auto s = std::make_unique<ExprStmt>(")
        self.run("expr_stmt", 5, "s->line = line;")
        self.run("expr_stmt", 6, "s->file_idx = current_file_idx_;")
        self.run("expr_stmt", 7, "return s;", {ret: s})
        self.leave()
        return s
    end

    ## Turns an already parsed target and the assignment operator into a statement.
    func finishAssign(target, line)
        self.enter("finish_assign_from_expr", nil, [])
        self.local("line", line)
        var opt = self.advance().type
        self.local("opt", opt)
        self.run("finish_assign_from_expr", 2, "TokenType opt = advance().type;")
        self.run("finish_assign_from_expr", 3, "auto value = expr();")
        var value = self.expr()
        self.local("value", value)
        self.run("finish_assign_from_expr", 3, "auto value = expr();", {ret: value})
        var isVar = target.kind == "VarExpr"
        self.run("finish_assign_from_expr", 4, "if (auto* ve = dynamic_cast<VarExpr*>(target.get()))")
        if isVar then
            var s = self.make("AssignStmt")
            self.run("finish_assign_from_expr", 5, "auto s = std::make_unique<AssignStmt>();",
                     {note: "The target is a plain name: the statement is an AssignStmt."})
            self.run("finish_assign_from_expr", 6, "s->line = line;")
            self.run("finish_assign_from_expr", 7, "s->file_idx = current_file_idx_;")
            self.set(s, "name", target.attrs.name)
            self.run("finish_assign_from_expr", 8, "s->name = ve->name;")
            var op = ASSIGN_OPS[opt]
            var cases = {PLUS_EQUAL: 10, MINUS_EQUAL: 13, STAR_EQUAL: 16, SLASH_EQUAL: 19, PERCENT_EQUAL: 22}
            self.run("finish_assign_from_expr", 9, "switch (opt)")
            if cases.has(opt) then
                self.set(s, "op", op)
                self.run("finish_assign_from_expr", cases[opt] + 1, "s->op = '", {also: cases[opt]})
                self.run("finish_assign_from_expr", cases[opt] + 2, "break;")
            else
                self.run("finish_assign_from_expr", 26, "s->op = '", {also: 25})
                self.run("finish_assign_from_expr", 27, "break;")
            end
            self.put(s, "value", value)
            self.run("finish_assign_from_expr", 29, "s->value = std::move(value);")
            self.free(target)
            self.run("finish_assign_from_expr", 30, "return s;",
                     {ret: s, note: "The VarExpr that was the target is not needed any more: only its name was kept."})
            self.leave()
            return s
        end
        var isIndex = target.kind == "IndexExpr"
        self.run("finish_assign_from_expr", 32, "if (auto* ie = dynamic_cast<IndexExpr*>(target.get()))")
        if isIndex then
            var s = self.make("IndexAssignStmt")
            self.run("finish_assign_from_expr", 33, "auto s = std::make_unique<IndexAssignStmt>();",
                     {note: "The target is a field or an index, a.b or a[i]: the statement is an IndexAssignStmt."})
            self.run("finish_assign_from_expr", 34, "s->line = line;")
            self.run("finish_assign_from_expr", 35, "s->file_idx = current_file_idx_;")
            for k in target.kids do
                if k.slot == "obj" then
                    self.put(s, "obj_expr", k)
                end
            end
            self.run("finish_assign_from_expr", 36, "s->obj_expr = std::move(ie->obj);")
            for k in target.kids do
                if k.slot == "key" then
                    self.put(s, "key", k)
                end
            end
            self.run("finish_assign_from_expr", 37, "s->key = std::move(ie->key);")
            self.set(s, "op", opt)
            self.run("finish_assign_from_expr", 38, "s->op = opt;")
            self.put(s, "value", value)
            self.run("finish_assign_from_expr", 39, "s->value = std::move(value);")
            self.free(target)
            self.run("finish_assign_from_expr", 40, "return s;",
                     {ret: s, note: "The IndexExpr that was the target gave its two parts away and is destroyed."})
            self.leave()
            return s
        end
        self.failAt("finish_assign_from_expr", 42, "fail_at(line, ", line, "invalid assignment target")
    end

    ## var / global / const: one rule, the keyword only choosing the flags.
    func declStmt(isGlobal, isConstant)
        self.enter("decl_stmt", nil, [["is_global", isGlobal], ["is_constant", isConstant]])
        var line = self.peek().line
        self.local("line", line)
        self.run("decl_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("decl_stmt", 3, "advance();")
        var s = self.make("VarDeclStmt")
        self.run("decl_stmt", 4, "auto s = std::make_unique<VarDeclStmt>();",
                 {note: "A declaration starts a VarDeclStmt: the names come first, then the values."})
        self.set(s, "is_global", isGlobal)
        self.run("decl_stmt", 5, "s->is_global = is_global;")
        self.set(s, "is_constant", isConstant)
        self.run("decl_stmt", 6, "s->is_constant = is_constant;")
        self.run("decl_stmt", 7, "s->line = line;")
        self.run("decl_stmt", 8, "s->file_idx = current_file_idx_;")
        var name = self.need("decl_stmt", 9, "s->names.push_back(expect(", "IDENTIFIER")
        self.add(s, "names", name.lexeme)
        self.run("decl_stmt", 9, "s->names.push_back(expect(")
        while true do
            var comma = self.match("COMMA")
            self.run("decl_stmt", 10, "while (match(TokenType::COMMA))")
            if not comma then
                break
            end
            name = self.need("decl_stmt", 11, "s->names.push_back(expect(", "IDENTIFIER")
            self.add(s, "names", name.lexeme)
            self.run("decl_stmt", 11, "s->names.push_back(expect(")
        end
        var noValue = isConstant and not self.check("EQUALS")
        self.run("decl_stmt", 14, "if (is_constant && !check(TokenType::EQUALS))")
        if noValue then
            self.failAt("decl_stmt", 15, "fail_at(line, ", line, "const '{s.attrs.names[1]}' must be initialized")
        end
        var equals = self.match("EQUALS")
        self.run("decl_stmt", 16, "if (match(TokenType::EQUALS))",
                 {note: "match() reads the token only if it is the one asked for: here, whether a value follows the names."})
        if equals then
            self.run("decl_stmt", 17, "parse_expr_list(s->values);")
            self.parseExprList(s, "values")
            self.run("decl_stmt", 17, "parse_expr_list(s->values);")
        end
        self.run("decl_stmt", 18, "return s;", {ret: s})
        self.leave()
        return s
    end

    func whileStmt()
        self.enter("while_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("while_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("while_stmt", 3, "advance();")
        var s = self.make("WhileStmt")
        self.run("while_stmt", 4, "auto s = std::make_unique<WhileStmt>();")
        self.run("while_stmt", 5, "s->line = line;")
        self.run("while_stmt", 6, "s->file_idx = current_file_idx_;")
        self.run("while_stmt", 7, "s->cond = expr();")
        var cond = self.expr()
        self.put(s, "cond", cond)
        self.run("while_stmt", 7, "s->cond = expr();", {ret: cond})
        self.expectLine("while_stmt", 8, "expect(TokenType::DO);", "DO")
        self.run("while_stmt", 9, "parse_body_until(s->body,")
        self.parseBodyUntil(s, "body", ["END"])
        self.run("while_stmt", 9, "parse_body_until(s->body,")
        self.expectLine("while_stmt", 10, "expect(TokenType::END);", "END")
        self.run("while_stmt", 11, "return s;", {ret: s})
        self.leave()
        return s
    end

    func doStmt()
        self.enter("do_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("do_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("do_stmt", 3, "advance();")
        var s = self.make("DoStmt")
        self.run("do_stmt", 4, "auto s = std::make_unique<DoStmt>();")
        self.run("do_stmt", 5, "s->line = line;")
        self.run("do_stmt", 6, "s->file_idx = current_file_idx_;")
        self.run("do_stmt", 7, "parse_body_until(s->body,")
        self.parseBodyUntil(s, "body", ["END"])
        self.run("do_stmt", 7, "parse_body_until(s->body,")
        self.expectLine("do_stmt", 8, "expect(TokenType::END);", "END")
        self.run("do_stmt", 9, "return s;", {ret: s})
        self.leave()
        return s
    end

    func ifStmt()
        self.enter("if_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("if_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("if_stmt", 3, "advance();")
        var s = self.make("IfStmt")
        self.run("if_stmt", 4, "auto s = std::make_unique<IfStmt>();")
        self.run("if_stmt", 5, "s->line = line;")
        self.run("if_stmt", 6, "s->file_idx = current_file_idx_;")
        self.run("if_stmt", 7, "s->cond = expr();")
        var cond = self.expr()
        self.put(s, "cond", cond)
        self.run("if_stmt", 7, "s->cond = expr();", {ret: cond})
        self.expectLine("if_stmt", 8, "expect(TokenType::THEN);", "THEN")
        self.run("if_stmt", 9, "parse_body_until(s->then_body,")
        self.parseBodyUntil(s, "then_body", ["ELSE", "ELSEIF", "END"])
        self.run("if_stmt", 9, "parse_body_until(s->then_body,")
        while true do
            var more = self.match("ELSEIF")
            self.run("if_stmt", 12, "while (match(TokenType::ELSEIF))")
            if not more then
                break
            end
            var ei = self.make("ElseIfClause")
            self.run("if_stmt", 13, "ElseIfClause ei;")
            self.run("if_stmt", 14, "ei.cond = expr();")
            var c = self.expr()
            self.put(ei, "cond", c)
            self.run("if_stmt", 14, "ei.cond = expr();", {ret: c})
            self.expectLine("if_stmt", 15, "expect(TokenType::THEN);", "THEN")
            self.run("if_stmt", 16, "parse_body_until(ei.body,")
            self.parseBodyUntil(ei, "body", ["ELSE", "ELSEIF", "END"])
            self.run("if_stmt", 16, "parse_body_until(ei.body,")
            self.put(s, "else_ifs", ei)
            self.run("if_stmt", 17, "s->else_ifs.push_back(std::move(ei));")
        end
        var hasElse = self.match("ELSE")
        self.run("if_stmt", 19, "if (match(TokenType::ELSE))")
        if hasElse then
            self.run("if_stmt", 20, "parse_body_until(s->else_body,")
            self.parseBodyUntil(s, "else_body", ["END"])
            self.run("if_stmt", 20, "parse_body_until(s->else_body,")
        end
        self.expectLine("if_stmt", 22, "expect(TokenType::END);", "END")
        self.run("if_stmt", 23, "return s;", {ret: s})
        self.leave()
        return s
    end

    ## break and continue: one token, one node.
    func simpleStmt(fn, kind)
        self.enter(fn, nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run(fn, 2, "int line = peek().line;")
        self.advance()
        self.run(fn, 3, "advance();")
        var s = self.make(kind)
        self.run(fn, 4, "auto s = std::make_unique<")
        self.run(fn, 5, "s->line = line;")
        self.run(fn, 6, "s->file_idx = current_file_idx_;")
        self.run(fn, 7, "return s;", {ret: s})
        self.leave()
        return s
    end

    func throwStmt()
        self.enter("throw_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("throw_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("throw_stmt", 3, "advance();")
        self.run("throw_stmt", 4, "auto s = std::make_unique<ThrowStmt>(expr());")
        var e = self.expr()
        var s = self.make("ThrowStmt")
        self.put(s, "value", e)
        self.run("throw_stmt", 4, "auto s = std::make_unique<ThrowStmt>(expr());", {ret: s})
        self.run("throw_stmt", 5, "s->line = line;")
        self.run("throw_stmt", 6, "s->file_idx = current_file_idx_;")
        self.run("throw_stmt", 7, "return s;", {ret: s})
        self.leave()
        return s
    end

    func funcDeclStmt()
        self.enter("func_decl_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("func_decl_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("func_decl_stmt", 3, "advance();")
        var name = self.need("func_decl_stmt", 4, "std::string name = expect(", "IDENTIFIER").lexeme
        self.local("name", name)
        self.run("func_decl_stmt", 4, "std::string name = expect(")
        var dot = self.match("DOT")
        self.run("func_decl_stmt", 7, "if (match(TokenType::DOT))")
        if dot then
            var field = self.needName("func_decl_stmt", 8, "std::string field = expect_name(", "a field name").lexeme
            self.local("field", field)
            self.run("func_decl_stmt", 8, "std::string field = expect_name(")
            var fe = self.make("FuncExpr")
            self.run("func_decl_stmt", 9, "auto fe = std::make_unique<FuncExpr>();")
            self.run("func_decl_stmt", 10, "parse_params(fe->params,")
            self.parseParams(fe)
            self.run("func_decl_stmt", 10, "parse_params(fe->params,")
            self.run("func_decl_stmt", 11, "parse_body_until(fe->body,")
            self.parseBodyUntil(fe, "body", ["END"])
            self.run("func_decl_stmt", 11, "parse_body_until(fe->body,")
            self.expectLine("func_decl_stmt", 12, "expect(TokenType::END);", "END")
            var ia = self.make("IndexAssignStmt")
            self.run("func_decl_stmt", 13, "auto ia = std::make_unique<IndexAssignStmt>();",
                     {note: "func obj.field() is sugar for obj.field = func() ... end: the parser builds that assignment."})
            self.run("func_decl_stmt", 14, "ia->line = line;")
            self.run("func_decl_stmt", 15, "ia->file_idx = current_file_idx_;")
            self.set(ia, "obj", name)
            self.run("func_decl_stmt", 16, "ia->obj = std::move(name);")
            var key = self.make("StringExpr")
            self.set(key, "value", field)
            self.put(ia, "key", key)
            self.run("func_decl_stmt", 17, "ia->key = std::make_unique<StringExpr>(")
            self.set(ia, "op", "EQUALS")
            self.run("func_decl_stmt", 18, "ia->op = TokenType::EQUALS;")
            self.put(ia, "value", fe)
            self.run("func_decl_stmt", 19, "ia->value = std::move(fe);")
            self.run("func_decl_stmt", 20, "return ia;", {ret: ia})
            self.leave()
            return ia
        end
        self.run("func_decl_stmt", 22, "return finish_func_decl(line,")
        var s = self.finishFuncDecl(line, name)
        self.run("func_decl_stmt", 22, "return finish_func_decl(line,", {ret: s})
        self.leave()
        return s
    end

    func finishFuncDecl(line, name)
        self.enter("finish_func_decl", nil, [["line", line], ["name", name]])
        var s = self.make("FuncDeclStmt")
        self.run("finish_func_decl", 2, "auto s = std::make_unique<FuncDeclStmt>();")
        self.run("finish_func_decl", 3, "s->line = line;")
        self.run("finish_func_decl", 4, "s->file_idx = current_file_idx_;")
        self.set(s, "name", name)
        self.run("finish_func_decl", 5, "s->name = std::move(name);")
        self.run("finish_func_decl", 6, "parse_params(s->params,")
        self.parseParams(s)
        self.run("finish_func_decl", 6, "parse_params(s->params,")
        self.run("finish_func_decl", 7, "parse_body_until(s->body,")
        self.parseBodyUntil(s, "body", ["END"])
        self.run("finish_func_decl", 7, "parse_body_until(s->body,")
        self.expectLine("finish_func_decl", 8, "expect(TokenType::END);", "END")
        self.run("finish_func_decl", 9, "return s;", {ret: s})
        self.leave()
        return s
    end

    func returnStmt()
        self.enter("return_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("return_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("return_stmt", 3, "advance();")
        var s = self.make("ReturnStmt")
        self.run("return_stmt", 4, "auto s = std::make_unique<ReturnStmt>();")
        self.run("return_stmt", 5, "s->line = line;")
        self.run("return_stmt", 6, "s->file_idx = current_file_idx_;")
        var some = not self.atBlockTerminator() and not self.check("SEMICOLON")
        self.run("return_stmt", 8, "if (!at_block_terminator() &&")
        if some then
            var dots = self.check("DOT_DOT_DOT")
            self.run("return_stmt", 9, "if (check(TokenType::DOT_DOT_DOT))")
            if dots then
                self.advance()
                self.run("return_stmt", 10, "advance();")
                self.set(s, "spread_varargs", true)
                self.run("return_stmt", 11, "s->spread_varargs = true;")
            else
                self.run("return_stmt", 13, "s->values.push_back(expr());")
                var e = self.expr()
                self.put(s, "values", e)
                self.run("return_stmt", 13, "s->values.push_back(expr());", {ret: e})
                while true do
                    var comma = self.match("COMMA")
                    self.run("return_stmt", 14, "while (match(TokenType::COMMA))")
                    if not comma then
                        break
                    end
                    var spread = self.match("DOT_DOT_DOT")
                    self.run("return_stmt", 15, "if (match(TokenType::DOT_DOT_DOT))")
                    if spread then
                        self.set(s, "spread_varargs", true)
                        self.run("return_stmt", 16, "s->spread_varargs = true;")
                        self.run("return_stmt", 17, "break;")
                        break
                    end
                    self.run("return_stmt", 19, "s->values.push_back(expr());")
                    e = self.expr()
                    self.put(s, "values", e)
                    self.run("return_stmt", 19, "s->values.push_back(expr());", {ret: e})
                end
            end
        end
        var stray = not self.atBlockTerminator()
        self.run("return_stmt", 28, "if (!at_block_terminator())",
                 {note: "A return ends its block, as in Lua: only a token that closes a block may follow it."})
        if stray then
            self.fail("return_stmt", 29, "fail(",
                      "'{self.peek().lexeme}' after 'return': a return ends its block, so nothing can follow it")
        end
        self.run("return_stmt", 30, "return s;", {ret: s})
        self.leave()
        return s
    end

    ## a, b = f(): the first target is already parsed, and the comma that follows it gave the statement away.
    func multiAssignStmt(first, line)
        self.enter("multi_assign_stmt", nil, [["line", line]])
        var s = self.make("MultiAssignStmt")
        self.run("multi_assign_stmt", 2, "auto s = std::make_unique<MultiAssignStmt>();")
        self.run("multi_assign_stmt", 3, "s->line = line;")
        self.run("multi_assign_stmt", 4, "s->file_idx = current_file_idx_;")
        self.put(s, "targets", first)
        self.run("multi_assign_stmt", 6, "s->targets.push_back(std::move(first));")
        while true do
            var comma = self.match("COMMA")
            self.run("multi_assign_stmt", 7, "while (match(TokenType::COMMA))")
            if not comma then
                break
            end
            self.run("multi_assign_stmt", 8, "s->targets.push_back(expr());")
            var e = self.expr()
            self.put(s, "targets", e)
            self.run("multi_assign_stmt", 8, "s->targets.push_back(expr());", {ret: e})
        end
        var i = 1
        var targets = []
        for k in s.kids do
            targets.push(k)
        end
        while true do
            var more = i <= #targets
            self.run("multi_assign_stmt", 9, "for (auto& t : s->targets)")
            if not more then
                break
            end
            var good = targets[i].kind == "VarExpr" or targets[i].kind == "IndexExpr"
            self.run("multi_assign_stmt", 10, "if (!is_lvalue(t.get()))")
            if not good then
                self.failAt("multi_assign_stmt", 11, "fail_at(line,", line, "invalid assignment target")
            end
            i += 1
        end
        self.expectLine("multi_assign_stmt", 13, "expect(TokenType::EQUALS);", "EQUALS")
        self.run("multi_assign_stmt", 14, "parse_expr_list(s->values);")
        self.parseExprList(s, "values")
        self.run("multi_assign_stmt", 14, "parse_expr_list(s->values);")
        self.run("multi_assign_stmt", 15, "return s;", {ret: s})
        self.leave()
        return s
    end

    func forStmt()
        self.enter("for_stmt", nil, [])
        var line = self.peek().line
        self.local("line", line)
        self.run("for_stmt", 2, "int line = peek().line;")
        self.advance()
        self.run("for_stmt", 3, "advance();")
        var firstVar = self.need("for_stmt", 4, "std::string first_var = expect(", "IDENTIFIER").lexeme
        self.local("first_var", firstVar)
        self.run("for_stmt", 4, "std::string first_var = expect(")
        var var2 = ""
        self.run("for_stmt", 6, "std::string var2;")
        self.run("for_stmt", 7, "std::unique_ptr<Expr> iter_e;")
        var iter = nil
        var numeric = self.match("EQUALS")
        self.run("for_stmt", 8, "if (match(TokenType::EQUALS))")
        if numeric then
            var range = self.make("RangeExpr")
            self.run("for_stmt", 10, "auto range = std::make_unique<RangeExpr>();",
                     {note: "for i = a, b is sugar for for i in [a;b]: the parser builds that range."})
            self.run("for_stmt", 11, "range->line = line;")
            self.set(range, "incl_left", true)
            self.run("for_stmt", 12, "range->incl_left = true;")
            self.set(range, "incl_right", true)
            self.run("for_stmt", 13, "range->incl_right = true;")
            self.run("for_stmt", 14, "range->start = expr();")
            var a = self.expr()
            self.put(range, "start", a)
            self.run("for_stmt", 14, "range->start = expr();", {ret: a})
            self.expectLine("for_stmt", 15, "expect(TokenType::COMMA);", "COMMA")
            self.run("for_stmt", 16, "range->end = expr();")
            var b = self.expr()
            self.put(range, "end", b)
            self.run("for_stmt", 16, "range->end = expr();", {ret: b})
            var step = self.match("COMMA")
            self.run("for_stmt", 17, "if (match(TokenType::COMMA))")
            if step then
                self.run("for_stmt", 18, "range->step = expr();")
                var c = self.expr()
                self.put(range, "step", c)
                self.run("for_stmt", 18, "range->step = expr();", {ret: c})
            end
            iter = range
            self.run("for_stmt", 19, "iter_e = std::move(range);")
        else
            var second = self.match("COMMA")
            self.run("for_stmt", 22, "if (match(TokenType::COMMA))")
            if second then
                var2 = self.need("for_stmt", 23, "var2 = expect(", "IDENTIFIER").lexeme
                self.local("var2", var2)
                self.run("for_stmt", 23, "var2 = expect(")
            end
            self.expectLine("for_stmt", 24, "expect(TokenType::IN);", "IN")
            self.run("for_stmt", 25, "iter_e = expr();")
            iter = self.expr()
            self.run("for_stmt", 25, "iter_e = expr();", {ret: iter})
        end
        self.expectLine("for_stmt", 28, "expect(TokenType::DO);", "DO")
        var s = self.make("ForIterStmt")
        self.run("for_stmt", 29, "auto s = std::make_unique<ForIterStmt>();")
        self.run("for_stmt", 30, "s->line = line;")
        self.run("for_stmt", 31, "s->file_idx = current_file_idx_;")
        self.set(s, "var1", firstVar)
        self.run("for_stmt", 32, "s->var1 = std::move(first_var);")
        self.set(s, "var2", var2)
        self.run("for_stmt", 33, "s->var2 = std::move(var2);")
        self.put(s, "iter_expr", iter)
        self.run("for_stmt", 34, "s->iter_expr = std::move(iter_e);")
        self.run("for_stmt", 35, "parse_body_until(s->body,")
        self.parseBodyUntil(s, "body", ["END"])
        self.run("for_stmt", 35, "parse_body_until(s->body,")
        self.expectLine("for_stmt", 36, "expect(TokenType::END);", "END")
        self.run("for_stmt", 37, "return s;", {ret: s})
        self.leave()
        return s
    end

    ## ── the expressions ──────────────────────────────────────────────────────

    func expr()
        self.enter("expr", nil, [])
        self.run("expr", 2, "if (depth_ >= 256)")
        self.run("expr", 4, "DepthGuard guard(depth_);")
        self.run("expr", 5, "return binary_level(0);",
                 {note: "An expression starts at level 0, the loosest, and goes down level by level to the tightest before it comes back up."})
        var e = self.binaryLevel(0)
        self.run("expr", 5, "return binary_level(0);", {ret: e})
        self.leave()
        return e
    end

    ## The binary operators of one precedence level: first everything that binds tighter, then as many
    ## operators of this level as follow, each with a right side parsed one level tighter.
    func binaryLevel(level)
        self.enter("binary_level", level, [["level", level]])
        var cmp = level == CMP_LEVEL
        self.run("binary_level", 2, "if (level == CMP_LEVEL)",
                 {note: "Level {level}. Levels 0 to 8 each handle their own operators and leave the tighter ones to the level below: that is how precedence works."})
        if cmp then
            self.run("binary_level", 3, "return comparison();")
            var c = self.comparison()
            self.run("binary_level", 3, "return comparison();", {ret: c})
            self.leave()
            return c
        end
        var bottom = level == N_LEVELS
        self.run("binary_level", 4, "if (level == N_LEVELS)")
        if bottom then
            self.run("binary_level", 5, "return unary();")
            var u = self.unary()
            self.run("binary_level", 5, "return unary();", {ret: u})
            self.leave()
            return u
        end
        var ops = LEVELS[level + 1]
        self.run("binary_level", 6, "const BinLevel& lv = LEVELS[level];")
        self.run("binary_level", 7, "auto left = binary_level(level + 1);")
        var left = self.binaryLevel(level + 1)
        self.local("left", left)
        self.run("binary_level", 7, "auto left = binary_level(level + 1);", {ret: left})
        self.run("binary_level", 8, "while (true)")
        while true do
            var found = nil
            self.run("binary_level", 9, "const BinOp* found = nullptr;")
            var i = 1
            while true do
                var more = i <= #ops and found == nil
                self.run("binary_level", 10, "for (int i = 0; i < lv.n && !found; i++)")
                if not more then
                    break
                end
                var hit = self.check(ops[i][1])
                self.run("binary_level", 11, "if (check(lv.ops[i].tok))")
                if hit then
                    found = ops[i]
                    self.run("binary_level", 12, "found = &lv.ops[i];")
                end
                i += 1
            end
            var none = found == nil
            self.run("binary_level", 13, "if (!found)")
            if none then
                self.run("binary_level", 14, "return left;",
                     {ret: left, note: "No operator of level {level} follows: the left side goes back up as it is."})
                self.leave()
                return left
            end
            self.advance()
            self.run("binary_level", 15, "advance();",
                     {note: "'{found[2]}' is an operator of level {level}: it is read, then its right side is parsed one level tighter."})
            self.run("binary_level", 16, "left = std::make_unique<BinaryExpr>(found->op,")
            var right = self.binaryLevel(level + 1)
            var node = self.make("BinaryExpr")
            self.set(node, "op", found[2])
            self.put(node, "left", left)
            self.put(node, "right", right)
            left = node
            self.local("left", left)
            self.run("binary_level", 16, "left = std::make_unique<BinaryExpr>(found->op,", {ret: node})
        end
    end

    ## A comparison, which can be chained: a < b < c.
    func comparison()
        self.enter("comparison", nil, [])
        self.run("comparison", 2, "auto first = binary_level(CMP_LEVEL + 1);")
        var first = self.binaryLevel(CMP_LEVEL + 1)
        self.local("first", first)
        self.run("comparison", 2, "auto first = binary_level(CMP_LEVEL + 1);", {ret: first})
        var cmp = isCmp(self.peek().type)
        self.run("comparison", 3, "if (!is_cmp_token(peek().type))")
        if not cmp then
            self.run("comparison", 4, "return first;", {ret: first})
            self.leave()
            return first
        end
        var op1 = CMP_CHARS[self.advance().type]
        self.local("op1", op1)
        self.run("comparison", 8, "char op1 = cmp_char(advance().type);")
        self.run("comparison", 9, "auto second = binary_level(CMP_LEVEL + 1);")
        var second = self.binaryLevel(CMP_LEVEL + 1)
        self.local("second", second)
        self.run("comparison", 9, "auto second = binary_level(CMP_LEVEL + 1);", {ret: second})
        var again = isCmp(self.peek().type)
        self.run("comparison", 10, "if (!is_cmp_token(peek().type))")
        if not again then
            var node = self.make("BinaryExpr")
            self.set(node, "op", op1)
            self.put(node, "left", first)
            self.put(node, "right", second)
            self.run("comparison", 11, "return std::make_unique<BinaryExpr>(op1,",
                     {ret: node, note: "One comparison makes a plain BinaryExpr."})
            self.leave()
            return node
        end
        var chain = self.make("ChainedCompareExpr")
        self.run("comparison", 13, "auto chain = std::make_unique<ChainedCompareExpr>();",
                 {note: "A second comparison follows: a < b < c is one node holding all the operands."})
        self.add(chain, "ops", op1)
        self.run("comparison", 14, "chain->ops.push_back(op1);")
        self.put(chain, "operands", first)
        self.run("comparison", 15, "chain->operands.push_back(std::move(first));")
        self.put(chain, "operands", second)
        self.run("comparison", 16, "chain->operands.push_back(std::move(second));")
        self.run("comparison", 17, "while (is_cmp_token(peek().type))")
        while isCmp(self.peek().type) do
            var op = CMP_CHARS[self.advance().type]
            self.add(chain, "ops", op)
            self.run("comparison", 18, "chain->ops.push_back(cmp_char(advance().type));")
            self.run("comparison", 19, "chain->operands.push_back(binary_level(CMP_LEVEL + 1));")
            var more = self.binaryLevel(CMP_LEVEL + 1)
            self.put(chain, "operands", more)
            self.run("comparison", 19, "chain->operands.push_back(binary_level(CMP_LEVEL + 1));", {ret: more})
            self.run("comparison", 17, "while (is_cmp_token(peek().type))")
        end
        self.run("comparison", 21, "return chain;", {ret: chain})
        self.leave()
        return chain
    end

    ## Unary operators, then a power.
    func unary()
        self.enter("unary", nil, [])
        ## token, operator, the line that tests it, the line that reads it (none for `match`), the line that returns
        var table = [["MINUS", "-", 2, 3, 4], ["NOT", "!", 6, 7, 8], ["TILDE", "~", 10, 11, 12], ["HASH", "#", 14, 0, 18]]
        for entry in table do
            var hit = self.check(entry[1])
            if entry[4] == 0 then
                self.run("unary", entry[3], "if (match(TokenType::{entry[1]}))")
            else
                self.run("unary", entry[3], "if (check(TokenType::{entry[1]}))")
            end
            if hit then
                self.advance()
                if entry[4] > 0 then
                    self.run("unary", entry[4], "advance();",
                             {note: "'{self.toks[self.pos - 1].lexeme}' is a unary operator: it applies to what follows, which is parsed by a call to unary() again."})
                end
                self.run("unary", entry[5], "return std::make_unique<UnaryExpr>('")
                var operand = self.unary()
                var node = self.make("UnaryExpr")
                self.set(node, "op", entry[2])
                self.put(node, "operand", operand)
                self.run("unary", entry[5], "return std::make_unique<UnaryExpr>('", {ret: node})
                self.leave()
                return node
            end
        end
        var isRef = self.check("REF")
        self.run("unary", 20, "if (check(TokenType::REF))")
        if isRef then
            self.notCovered("ref")
        end
        self.run("unary", 22, "return power();")
        var p = self.power()
        self.run("unary", 22, "return power();", {ret: p})
        self.leave()
        return p
    end

    ## A primary, and the power that may follow it. '^' binds tighter than unary minus.
    func power()
        self.enter("power", nil, [])
        self.run("power", 2, "auto left = primary();")
        var left = self.primary()
        self.local("left", left)
        self.run("power", 2, "auto left = primary();", {ret: left})
        var caret = self.check("CARET")
        self.run("power", 3, "if (!check(TokenType::CARET))")
        if not caret then
            self.run("power", 4, "return left;", {ret: left})
            self.leave()
            return left
        end
        self.advance()
        self.run("power", 5, "advance();")
        self.run("power", 7, "return std::make_unique<BinaryExpr>('p'")
        var right = self.unary()
        var node = self.make("BinaryExpr")
        self.set(node, "op", "p")
        self.put(node, "left", left)
        self.put(node, "right", right)
        self.run("power", 7, "return std::make_unique<BinaryExpr>('p'",
                 {ret: node, note: "'^' is read here, between a primary and a unary: so it binds tighter than a minus sign, and 2 ^ 2 ^ 3 groups to the right."})
        self.leave()
        return node
    end

    ## What may follow a primary: an index, a field, a method call, a call.
    func parsePostfix(base)
        self.enter("parse_postfix", nil, [["base", base]])
        var node = base
        while true do
            var more = self.check("LBRACKET") or self.check("DOT") or self.check("LPAREN") or self.atOptionalCall()
            self.run("parse_postfix", 2, "while (check(TokenType::LBRACKET)")
            if not more then
                break
            end
            var bracket = self.check("LBRACKET")
            self.run("parse_postfix", 3, "if (check(TokenType::LBRACKET))")
            if bracket then
                self.advance()
                self.run("parse_postfix", 4, "advance();")
                self.run("parse_postfix", 5, "auto key = expr();")
                var key = self.expr()
                self.run("parse_postfix", 5, "auto key = expr();", {ret: key})
                self.expectLine("parse_postfix", 6, "expect(TokenType::RBRACKET);", "RBRACKET")
                var ie = self.make("IndexExpr")
                self.run("parse_postfix", 7, "auto ie = std::make_unique<IndexExpr>();")
                self.put(ie, "obj", node)
                self.run("parse_postfix", 8, "ie->obj = std::move(base);")
                self.put(ie, "key", key)
                self.run("parse_postfix", 9, "ie->key = std::move(key);")
                node = ie
                self.local("base", node)
                self.run("parse_postfix", 10, "base = std::move(ie);")
            else
                var dot = self.check("DOT")
                self.run("parse_postfix", 11, "} else if (check(TokenType::DOT))")
                if dot then
                    self.advance()
                    self.run("parse_postfix", 12, "advance();")
                    var field = self.needName("parse_postfix", 13, "std::string field = expect_name(", "a field name")
                    self.run("parse_postfix", 13, "std::string field = expect_name(")
                    var optM = self.atOptionalCall()
                    self.run("parse_postfix", 14, "bool opt_m = at_optional_call();")
                    var isCall = self.check("LPAREN") or optM
                    self.run("parse_postfix", 15, "if (check(TokenType::LPAREN) || opt_m)")
                    if isCall then
                        self.run("parse_postfix", 16, "if (opt_m)")
                        if optM then
                            self.advance()
                            self.run("parse_postfix", 17, "advance();")
                        end
                        self.advance()
                        self.run("parse_postfix", 18, "advance();")
                        var mc = self.make("MethodCallExpr")
                        self.run("parse_postfix", 19, "auto mc = std::make_unique<MethodCallExpr>();",
                                 {note: "A name, a dot, another name and a '(': a method call."})
                        self.put(mc, "receiver", node)
                        self.run("parse_postfix", 20, "mc->receiver = std::move(base);")
                        self.set(mc, "method", field.lexeme)
                        self.run("parse_postfix", 21, "mc->method = std::move(field);")
                        self.run("parse_postfix", 22, "mc->is_super = false;")
                        self.set(mc, "optional", optM)
                        self.run("parse_postfix", 23, "mc->optional = opt_m;")
                        self.run("parse_postfix", 24, "parse_call_args(mc->args);")
                        self.parseCallArgs(mc, "args")
                        self.run("parse_postfix", 24, "parse_call_args(mc->args);")
                        node = mc
                        self.local("base", node)
                        self.run("parse_postfix", 25, "base = std::move(mc);")
                    else
                        var ie = self.make("IndexExpr")
                        self.run("parse_postfix", 27, "auto ie = std::make_unique<IndexExpr>();",
                                 {note: "A name and a dot with no '(' after the field: a field read, an IndexExpr whose key is the field's name as a string."})
                        self.put(ie, "obj", node)
                        self.run("parse_postfix", 28, "ie->obj = std::move(base);")
                        var key = self.make("StringExpr")
                        self.set(key, "value", field.lexeme)
                        self.put(ie, "key", key)
                        self.run("parse_postfix", 29, "ie->key = std::make_unique<StringExpr>(")
                        node = ie
                        self.local("base", node)
                        self.run("parse_postfix", 30, "base = std::move(ie);")
                    end
                else
                    var opt = false
                    self.run("parse_postfix", 33, "bool opt = false;")
                    var q = self.check("QUESTION")
                    self.run("parse_postfix", 34, "if (check(TokenType::QUESTION))")
                    if q then
                        self.advance()
                        self.run("parse_postfix", 35, "advance();")
                        opt = true
                        self.run("parse_postfix", 36, "opt = true;")
                    end
                    self.advance()
                    self.run("parse_postfix", 38, "advance();")
                    var call = self.make("ExprCallExpr")
                    self.run("parse_postfix", 39, "auto call = std::make_unique<ExprCallExpr>();",
                             {note: "A '(' after an expression: a call through that expression."})
                    self.put(call, "callee", node)
                    self.run("parse_postfix", 40, "call->callee = std::move(base);")
                    self.set(call, "optional", opt)
                    self.run("parse_postfix", 41, "call->optional = opt;")
                    self.run("parse_postfix", 42, "parse_call_args(call->args);")
                    self.parseCallArgs(call, "args")
                    self.run("parse_postfix", 42, "parse_call_args(call->args);")
                    node = call
                    self.local("base", node)
                    self.run("parse_postfix", 43, "base = std::move(call);")
                end
            end
        end
        self.run("parse_postfix", 46, "return base;", {ret: node})
        self.leave()
        return node
    end

    ## A number, a string, a name, a call, a literal, a parenthesis: the leaves and the brackets.
    func primary()
        self.enter("primary", nil, [])
        var number = self.check("NUMBER")
        self.run("primary", 2, "if (check(TokenType::NUMBER))",
                 {note: "primary() tries each kind of token in turn: the first test that matches decides."})
        if number then
            var tok = self.advance()
            self.run("primary", 3, "Token tok = advance();")
            self.run("primary", 4, "NumLit n;")
            var value = string.number(tok.lexeme)
            var fits = value <> nil
            self.run("primary", 6, "if (!number_from_lexeme(tok.lexeme, n))")
            if not fits then
                self.failAt("primary", 7, "fail_at(tok.line,", tok.line, "numeric literal out of range: {tok.lexeme}")
            end
            self.run("primary", 8, "if (n.is_int)")
            var node = self.make("NumberExpr")
            self.set(node, "value", value)
            if typeof(value) == "int" then
                self.run("primary", 9, "return std::make_unique<NumberExpr>(n.i);",
                         {ret: node, note: "A NUMBER token becomes a NumberExpr: a leaf of the tree, with its value."})
            else
                self.run("primary", 10, "return std::make_unique<NumberExpr>(n.d);",
                         {ret: node, note: "A NUMBER token becomes a NumberExpr: a leaf of the tree, with its value."})
            end
            self.leave()
            return node
        end
        var str = self.check("STRING")
        self.run("primary", 12, "if (check(TokenType::STRING))")
        if str then
            var tok = self.advance()
            var node = self.make("StringExpr")
            self.set(node, "value", tok.lexeme)
            self.run("primary", 13, "return parse_postfix(std::make_unique<StringExpr>(advance().lexeme));")
            var r = self.parsePostfix(node)
            self.run("primary", 13, "return parse_postfix(std::make_unique<StringExpr>(advance().lexeme));", {ret: r})
            self.leave()
            return r
        end
        var interp = self.check("INTERP_START")
        self.run("primary", 14, "if (check(TokenType::INTERP_START))")
        if interp then
            return self.interpolation()
        end
        var isTrue = self.check("TRUE")
        self.run("primary", 31, "if (check(TokenType::TRUE))")
        if isTrue then
            self.advance()
            self.run("primary", 32, "advance();")
            var node = self.make("BoolExpr")
            self.set(node, "value", true)
            self.run("primary", 33, "return std::make_unique<BoolExpr>(true);", {ret: node})
            self.leave()
            return node
        end
        var isFalse = self.check("FALSE")
        self.run("primary", 35, "if (check(TokenType::FALSE))")
        if isFalse then
            self.advance()
            self.run("primary", 36, "advance();")
            var node = self.make("BoolExpr")
            self.run("primary", 37, "return std::make_unique<BoolExpr>(false);", {ret: node})
            self.leave()
            return node
        end
        var ident = self.check("IDENTIFIER")
        self.run("primary", 39, "if (check(TokenType::IDENTIFIER))")
        if ident then
            return self.identifier()
        end
        var isNil = self.check("NIL")
        self.run("primary", 73, "if (check(TokenType::NIL))")
        if isNil then
            self.advance()
            self.run("primary", 74, "advance();")
            var node = self.make("NilExpr")
            self.run("primary", 75, "return std::make_unique<NilExpr>();", {ret: node})
            self.leave()
            return node
        end
        var dots = self.check("DOT_DOT_DOT")
        self.run("primary", 77, "if (check(TokenType::DOT_DOT_DOT))")
        if dots then
            self.advance()
            self.run("primary", 78, "advance();")
            var node = self.make("VarArgExpr")
            self.run("primary", 79, "return std::make_unique<VarArgExpr>();", {ret: node})
            self.leave()
            return node
        end
        var isFunc = self.check("FUNC")
        self.run("primary", 81, "if (check(TokenType::FUNC))")
        if isFunc then
            self.advance()
            self.run("primary", 82, "advance();")
            var fe = self.make("FuncExpr")
            self.run("primary", 83, "auto fe = std::make_unique<FuncExpr>();")
            self.run("primary", 84, "parse_params(fe->params,")
            self.parseParams(fe)
            self.run("primary", 84, "parse_params(fe->params,")
            self.run("primary", 85, "parse_body_until(fe->body,")
            self.parseBodyUntil(fe, "body", ["END"])
            self.run("primary", 85, "parse_body_until(fe->body,")
            self.expectLine("primary", 86, "expect(TokenType::END);", "END")
            self.run("primary", 87, "return parse_postfix(std::move(fe));")
            var r = self.parsePostfix(fe)
            self.run("primary", 87, "return parse_postfix(std::move(fe));", {ret: r})
            self.leave()
            return r
        end
        var brace = self.check("LBRACE")
        self.run("primary", 89, "if (check(TokenType::LBRACE))")
        if brace then
            return self.mapLiteral()
        end
        var bracket = self.check("LBRACKET")
        self.run("primary", 111, "if (check(TokenType::LBRACKET))")
        if bracket then
            return self.arrayLiteral()
        end
        var closing = self.check("RBRACKET")
        self.run("primary", 124, "if (check(TokenType::RBRACKET))")
        if closing then
            self.notCovered("an open-left range")
        end
        var paren = self.match("LPAREN")
        self.run("primary", 129, "if (match(TokenType::LPAREN))")
        if paren then
            self.run("primary", 130, "auto e = expr();",
                     {note: "A '(': whatever is inside is a whole expression, parsed from the loosest level again."})
            var e = self.expr()
            self.run("primary", 130, "auto e = expr();", {ret: e})
            self.expectLine("primary", 131, "expect(TokenType::RPAREN);", "RPAREN")
            self.run("primary", 133, "return parse_postfix(std::move(e));")
            var r = self.parsePostfix(e)
            self.run("primary", 133, "return parse_postfix(std::move(e));", {ret: r})
            self.leave()
            return r
        end
        self.fail("primary", 135, "fail(", "unexpected token '{self.peek().lexeme}'",
                  {note: "No kind of primary starts with this token: the parser gives up."})
    end

    ## The branch of primary() for a name: a variable, or a call.
    func identifier()
        var name = self.advance().lexeme
        self.local("name", name)
        self.run("primary", 40, "std::string name = advance().lexeme;")
        var isSuper = name == "super"
        self.run("primary", 42, "if (name ==")
        if isSuper then
            self.notCovered("super")
        end
        var optCall = self.atOptionalCall()
        self.run("primary", 60, "bool opt_call = at_optional_call();")
        self.run("primary", 61, "if (opt_call)")
        if optCall then
            self.advance()
            self.run("primary", 62, "advance();")
        end
        var paren = self.match("LPAREN")
        self.run("primary", 63, "if (match(TokenType::LPAREN))")
        if paren then
            var call = self.make("CallExpr")
            self.run("primary", 64, "auto call = std::make_unique<CallExpr>();",
                     {note: "A name followed by '(': a call to a function by name."})
            self.set(call, "callee", name)
            self.run("primary", 65, "call->callee = name;")
            self.set(call, "optional", optCall)
            self.run("primary", 66, "call->optional = opt_call;")
            self.run("primary", 67, "parse_call_args(call->args);")
            self.parseCallArgs(call, "args")
            self.run("primary", 67, "parse_call_args(call->args);")
            self.run("primary", 68, "return parse_postfix(std::move(call));")
            var r = self.parsePostfix(call)
            self.run("primary", 68, "return parse_postfix(std::move(call));", {ret: r})
            self.leave()
            return r
        end
        var node = self.make("VarExpr")
        self.set(node, "name", name)
        self.run("primary", 71, "return parse_postfix(std::make_unique<VarExpr>(name));",
                 {note: "A name with no '(' after it: a variable, a VarExpr leaf."})
        var r = self.parsePostfix(node)
        self.run("primary", 71, "return parse_postfix(std::make_unique<VarExpr>(name));", {ret: r})
        self.leave()
        return r
    end

    ## The branch of primary() for a string with holes: "text {expr} text".
    func interpolation()
        var node = self.make("InterpExpr")
        self.run("primary", 15, "auto node = std::make_unique<InterpExpr>();",
                 {note: "A string with holes arrives as INTERP_START, the expressions of the holes between INTERP_MID tokens, and INTERP_END."})
        self.run("primary", 16, "node->line = peek().line;")
        self.run("primary", 17, "node->file_idx = peek().file_idx;")
        self.add(node, "literals", self.advance().lexeme)
        self.run("primary", 18, "node->literals.push_back(advance().lexeme);")
        self.run("primary", 19, "while (true)")
        while true do
            self.run("primary", 20, "node->exprs.push_back(expr());")
            var e = self.expr()
            self.put(node, "exprs", e)
            self.run("primary", 20, "node->exprs.push_back(expr());", {ret: e})
            var mid = self.check("INTERP_MID")
            self.run("primary", 21, "if (check(TokenType::INTERP_MID))")
            if mid then
                self.add(node, "literals", self.advance().lexeme)
                self.run("primary", 22, "node->literals.push_back(advance().lexeme);")
            else
                var last = self.need("primary", 24, "Token end = expect(", "INTERP_END")
                self.run("primary", 24, "Token end = expect(")
                self.add(node, "literals", last.lexeme)
                self.run("primary", 25, "node->literals.push_back(end.lexeme);")
                self.run("primary", 26, "break;")
                break
            end
        end
        self.run("primary", 29, "return parse_postfix(std::move(node));")
        var r = self.parsePostfix(node)
        self.run("primary", 29, "return parse_postfix(std::move(node));", {ret: r})
        self.leave()
        return r
    end

    ## The branch of primary() for a map literal { key: value, ... }.
    func mapLiteral()
        self.advance()
        self.run("primary", 90, "advance();")
        var mapNode = self.make("MapExpr")
        self.run("primary", 91, "auto map = std::make_unique<MapExpr>();")
        while true do
            var more = not self.check("RBRACE") and not self.check("EOF_T")
            self.run("primary", 92, "while (!check(TokenType::RBRACE)")
            if not more then
                break
            end
            var entry = self.make("MapEntry")
            self.run("primary", 93, "std::unique_ptr<Expr> key;")
            var key = nil
            var plain = self.check("STRING") or self.atName()
            self.run("primary", 94, "if (check(TokenType::STRING) || at_name())")
            if plain then
                key = self.make("StringExpr")
                self.set(key, "value", self.advance().lexeme)
                self.run("primary", 95, "key = std::make_unique<StringExpr>(advance().lexeme);")
            else
                var computed = self.check("LBRACKET")
                self.run("primary", 96, "} else if (check(TokenType::LBRACKET))")
                if computed then
                    self.advance()
                    self.run("primary", 97, "advance();")
                    self.run("primary", 98, "key = expr();")
                    key = self.expr()
                    self.run("primary", 98, "key = expr();", {ret: key})
                    self.expectLine("primary", 99, "expect(TokenType::RBRACKET);", "RBRACKET")
                else
                    self.fail("primary", 101, "fail(",
                              "expected string, identifier, or [expr] key in map literal")
                end
            end
            self.expectLine("primary", 103, "expect(TokenType::COLON);", "COLON")
            self.run("primary", 104, "auto val = expr();")
            var val = self.expr()
            self.run("primary", 104, "auto val = expr();", {ret: val})
            self.put(entry, "key", key)
            self.put(entry, "value", val)
            self.put(mapNode, "entries", entry)
            self.run("primary", 105, "map->entries.push_back(")
            self.separator("primary", 106, "expect_separator(TokenType::RBRACE,", "RBRACE", "map entries")
        end
        self.expectLine("primary", 108, "expect(TokenType::RBRACE);", "RBRACE")
        self.run("primary", 109, "return parse_postfix(std::move(map));")
        var r = self.parsePostfix(mapNode)
        self.run("primary", 109, "return parse_postfix(std::move(map));", {ret: r})
        self.leave()
        return r
    end

    ## The branch of primary() for an array literal [a, b, c].
    func arrayLiteral()
        self.advance()
        self.run("primary", 112, "advance();")
        var range = self.looksLikeRange()
        self.run("primary", 113, "if (looks_like_range())")
        if range then
            self.notCovered("a range")
        end
        var arr = self.make("ArrayExpr")
        self.run("primary", 116, "auto arr = std::make_unique<ArrayExpr>();")
        while true do
            var more = not self.check("RBRACKET") and not self.check("EOF_T")
            self.run("primary", 117, "while (!check(TokenType::RBRACKET)")
            if not more then
                break
            end
            self.run("primary", 118, "arr->elements.push_back(expr());")
            var e = self.expr()
            self.put(arr, "elements", e)
            self.run("primary", 118, "arr->elements.push_back(expr());", {ret: e})
            self.separator("primary", 119, "expect_separator(TokenType::RBRACKET,", "RBRACKET", "array elements")
        end
        self.expectLine("primary", 121, "expect(TokenType::RBRACKET);", "RBRACKET")
        self.run("primary", 122, "return parse_postfix(std::move(arr));")
        var r = self.parsePostfix(arr)
        self.run("primary", 122, "return parse_postfix(std::move(arr));", {ret: r})
        self.leave()
        return r
    end

    ## looks_like_range(): a SEMICOLON at depth 0 before a COMMA or a closing bracket.
    func looksLikeRange()
        var depth = 0
        for i = self.pos, #self.toks do
            var ty = self.toks[i].type
            if ty == "LBRACKET" or ty == "LPAREN" or ty == "LBRACE" then
                depth += 1
            elseif ty == "RBRACKET" or ty == "RPAREN" or ty == "RBRACE" then
                if depth == 0 then
                    return false
                end
                depth -= 1
            elseif depth == 0 then
                if ty == "SEMICOLON" then
                    return true
                elseif ty == "COMMA" or ty == "EOF_T" then
                    return false
                end
            end
        end
        return false
    end

    ## expect_separator(closing, what): the comma between two items of a literal is mandatory, except
    ## right before the closing bracket.
    func separator(fn, index, start, closing, what)
        var comma = self.match("COMMA")
        if not (comma or self.check(closing) or self.check("EOF_T")) then
            self.fail(fn, index, start, "expected ',' between {what}, got '{self.peek().lexeme}'")
        end
        self.run(fn, index, start)
    end
end

## ── the whole parse ──────────────────────────────────────────────────────────

## The tokens the C++ parser would receive: the final stream of the lexer, each with the line it is on.
func parserTokens(lexed)
    var out = []
    for tok in lexed.tokens do
        out.push({type: tok.type, lexeme: tok.lexeme, line: lexed.steps[tok.step].line, from: tok.from, to: tok.to})
    end
    return out
end

## Runs the parser on a program. Returns {steps, tokens, tree, error, errorLine, nodes, nodeCount, source,
## lexed}: the tree is the Program node, nil when the parse failed; `error` is the refusal, nil when
## there is none; `nodes` are the nodes alive at the end, `nodeCount` how many were ever made.
func parseTrace(source)
    var lexed = trace(source)
    var result = {steps: [], tokens: [], tree: nil, error: nil, errorLine: nil, source: source, lexed: lexed}
    if lexed.error then
        result.error = lexed.error
        return result
    end
    result.tokens = parserTokens(lexed)
    var t = ParseTracer(result.tokens, result)
    try
        t.parse()
        result.tree = t.root
    catch e
        if e <> "parse error" then
            throw e
        end
        var last = result.steps[#result.steps]
        result.error = last.err
        result.errorLine = last.errLine
    end
    result.nodes = t.nodes
    result.nodeCount = t.nextId - 1
    return result
end
