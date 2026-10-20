## The parser animation (docs/samples/parser) runs a copy of src/parser.cpp written in Ollin. This test
## holds that copy to the engine's parser: every tree and every refusal below was checked against the
## C++ parser's own output, so a drift in either one shows here. (tests/check_trace_source.sh checks the
## lines the copy names; this checks what it builds.)
##
## A tree is written as text: the kind, its plain fields as name:value, and the nodes it holds grouped
## by field. An apostrophe stands for a double quote, in the programs and in the trees alike.
import "tracer.ol"
import "../lib/trace_path_testlib.ol"

func check(text, want)
    var r = parseTrace(unquote(text))
    assert(r.error == nil, "'{text}' is refused: {r.error}")
    var got = sexp(r.tree).replace(QUOTE, "'")
    assert(got == want, "the tree of '{text}'" + NEWLINE + "  is  {got}" + NEWLINE + "  not {want}")
end

func refuses(text, want)
    var r = parseTrace(unquote(text))
    assert(r.tree == nil, "'{text}' should be refused")
    var got = "{r.errorLine}: {r.error}"
    assert(got == want, "'{text}' is refused with '{got}', not '{want}'")
end

## precedence: the tighter operator is built first
check("var total = 1 + 2 * 3",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['total'] (values " +
      "(BinaryExpr op:'+' (left (NumberExpr value:int 1)) (right (BinaryExpr op:'*' (left " +
      "(NumberExpr value:int 2)) (right (NumberExpr value:int 3)))))))))")
check("var x = (1 + 2) * 3",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'*' (left (BinaryExpr op:'+' (left (NumberExpr value:int 1)) (right " +
      "(NumberExpr value:int 2)))) (right (NumberExpr value:int 3)))))))")
check("var x = a - b - c",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'-' (left (BinaryExpr op:'-' (left (VarExpr name:'a')) (right (VarExpr " +
      "name:'b')))) (right (VarExpr name:'c')))))))")
check("var x = a or b and c",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'|' (left (VarExpr name:'a')) (right (BinaryExpr op:'&' (left (VarExpr " +
      "name:'b')) (right (VarExpr name:'c')))))))))")
check("var x = a | b ~ c & d",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'o' (left (VarExpr name:'a')) (right (BinaryExpr op:'x' (left (VarExpr " +
      "name:'b')) (right (BinaryExpr op:'b' (left (VarExpr name:'c')) (right (VarExpr " +
      "name:'d')))))))))))")
check("var x = a << 1 >> 2",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'r' (left (BinaryExpr op:'l' (left (VarExpr name:'a')) (right (NumberExpr " +
      "value:int 1)))) (right (NumberExpr value:int 2)))))))")
check("var x = a + b // c % d",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'+' (left (VarExpr name:'a')) (right (BinaryExpr op:'%' (left (BinaryExpr " +
      "op:'q' (left (VarExpr name:'b')) (right (VarExpr name:'c')))) (right (VarExpr " +
      "name:'d')))))))))")

## unary operators and the power
check("var x = -2 ^ 2",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(UnaryExpr op:'-' (operand (BinaryExpr op:'p' (left (NumberExpr value:int 2)) (right " +
      "(NumberExpr value:int 2)))))))))")
check("var x = 2 ^ 2 ^ 3",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'p' (left (NumberExpr value:int 2)) (right (BinaryExpr op:'p' (left " +
      "(NumberExpr value:int 2)) (right (NumberExpr value:int 3)))))))))")
check("var x = 2 ^ -1",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'p' (left (NumberExpr value:int 2)) (right (UnaryExpr op:'-' (operand " +
      "(NumberExpr value:int 1)))))))))")
check("var x = not a and b",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'&' (left (UnaryExpr op:'!' (operand (VarExpr name:'a')))) (right " +
      "(VarExpr name:'b')))))))")
check("var x = #list",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(UnaryExpr op:'#' (operand (VarExpr name:'list')))))))")
check("var x = ~mask",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(UnaryExpr op:'~' (operand (VarExpr name:'mask')))))))")
check("var x = - - a",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(UnaryExpr op:'-' (operand (UnaryExpr op:'-' (operand (VarExpr name:'a')))))))))")

## a comparison is one node, or a chain
check("var x = a == b",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'=' (left (VarExpr name:'a')) (right (VarExpr name:'b')))))))")
check("var x = a <> b",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BinaryExpr op:'N' (left (VarExpr name:'a')) (right (VarExpr name:'b')))))))")
check("var x = 1 < y < 10",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(ChainedCompareExpr ops:['<','<'] (operands (NumberExpr value:int 1) (VarExpr name:'y') " +
      "(NumberExpr value:int 10)))))))")
check("var x = a >= b <= c > d",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(ChainedCompareExpr ops:['G','L','>'] (operands (VarExpr name:'a') (VarExpr name:'b') " +
      "(VarExpr name:'c') (VarExpr name:'d')))))))")

## literals
check("var x = 1.5",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(NumberExpr value:float 1.5)))))")
check("var x = 0xff",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(NumberExpr value:int 255)))))")
check("var x = 'hi'",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(StringExpr value:'hi')))))")
check("var x = true",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(BoolExpr value:true)))))")
check("var x = nil",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(NilExpr)))))")
check("var x = ...",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(VarArgExpr)))))")
check("var x = [1, 2,]",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(ArrayExpr (elements (NumberExpr value:int 1) (NumberExpr value:int 2)))))))")
check("var x = \{a: 1, 'k': 2, [k]: 3, end: 4}",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(MapExpr (entries (MapEntry (key (StringExpr value:'a')) (value (NumberExpr value:int " +
      "1))) (MapEntry (key (StringExpr value:'k')) (value (NumberExpr value:int 2))) (MapEntry " +
      "(key (VarExpr name:'k')) (value (NumberExpr value:int 3))) (MapEntry (key (StringExpr " +
      "value:'end')) (value (NumberExpr value:int 4)))))))))")
check("var x = []",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(ArrayExpr)))))")
check("var x = \{}",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(MapExpr)))))")

## a string with holes
check("var x = 'n = \{n}!'",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(InterpExpr literals:['n = ','!'] (exprs (VarExpr name:'n')))))))")
check("var x = '\{a} and \{b}'",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(InterpExpr literals:['',' and ',''] (exprs (VarExpr name:'a') (VarExpr name:'b')))))))")
check("var x = '\{x:.2f}'",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(InterpExpr literals:['',''] (exprs (CallExpr callee:'__fmt' optional:false (args " +
      "(VarExpr name:'x') (StringExpr value:'.2f')))))))))")

## calls, fields and indexes chain after a primary
check("var x = f(1, 2 + 3)",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(CallExpr callee:'f' optional:false (args (NumberExpr value:int 1) (BinaryExpr op:'+' " +
      "(left (NumberExpr value:int 2)) (right (NumberExpr value:int 3)))))))))")
check("var x = f?()",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(CallExpr callee:'f' optional:true)))))")
check("var x = a.b.c",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(IndexExpr (obj (IndexExpr (obj (VarExpr name:'a')) (key (StringExpr value:'b')))) (key " +
      "(StringExpr value:'c')))))))")
check("var x = a[1][2]",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(IndexExpr (obj (IndexExpr (obj (VarExpr name:'a')) (key (NumberExpr value:int 1)))) " +
      "(key (NumberExpr value:int 2)))))))")
check("var x = a.m(1).c",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(IndexExpr (obj (MethodCallExpr method:'m' is_super:false optional:false (receiver " +
      "(VarExpr name:'a')) (args (NumberExpr value:int 1)))) (key (StringExpr value:'c')))))))")
check("var x = a.m?()",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(MethodCallExpr method:'m' is_super:false optional:true (receiver (VarExpr " +
      "name:'a')))))))")
check("var x = f(1)(2)",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(ExprCallExpr optional:false (callee (CallExpr callee:'f' optional:false (args " +
      "(NumberExpr value:int 1)))) (args (NumberExpr value:int 2)))))))")
check("var x = (a + b).c",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(IndexExpr (obj (BinaryExpr op:'+' (left (VarExpr name:'a')) (right (VarExpr " +
      "name:'b')))) (key (StringExpr value:'c')))))))")
check("var x = 's'.len",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(IndexExpr (obj (StringExpr value:'s')) (key (StringExpr value:'len')))))))")

## functions are values
check("var f = func(a, b) return a + b end",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['f'] (values " +
      "(FuncExpr params:['a','b'] variadic:false (body (ReturnStmt spread_varargs:false (values " +
      "(BinaryExpr op:'+' (left (VarExpr name:'a')) (right (VarExpr name:'b')))))))))))")
check("var f = func(a, ...) return a, ... end",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['f'] (values " +
      "(FuncExpr params:['a'] variadic:true (body (ReturnStmt spread_varargs:true (values " +
      "(VarExpr name:'a')))))))))")
check("var f = func(a, b = 2) end",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['f'] (values " +
      "(FuncExpr params:['a','b'] variadic:false (defaults (NumberExpr value:int 2)))))))")

## declarations
check("var a, b = 1, 2",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['a','b'] (values " +
      "(NumberExpr value:int 1) (NumberExpr value:int 2)))))")
check("global g = 5",
      "(Program (stmts (VarDeclStmt is_global:true is_constant:false names:['g'] (values " +
      "(NumberExpr value:int 5)))))")
check("const K = 10",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:true names:['K'] (values " +
      "(NumberExpr value:int 10)))))")
check("var x",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'])))")

## a statement that starts with a name is read as an expression, then decided
check("a = 1",
      "(Program (stmts (AssignStmt name:'a' op:'' (value (NumberExpr value:int 1)))))")
check("a += 1",
      "(Program (stmts (AssignStmt name:'a' op:'+' (value (NumberExpr value:int 1)))))")
check("a %= 2",
      "(Program (stmts (AssignStmt name:'a' op:'%' (value (NumberExpr value:int 2)))))")
check("a.b = 1",
      "(Program (stmts (IndexAssignStmt obj:'' op:EQUALS (obj_expr (VarExpr name:'a')) (key " +
      "(StringExpr value:'b')) (value (NumberExpr value:int 1)))))")
check("a[1] = 2",
      "(Program (stmts (IndexAssignStmt obj:'' op:EQUALS (obj_expr (VarExpr name:'a')) (key " +
      "(NumberExpr value:int 1)) (value (NumberExpr value:int 2)))))")
check("a.b.c = 3",
      "(Program (stmts (IndexAssignStmt obj:'' op:EQUALS (obj_expr (IndexExpr (obj (VarExpr " +
      "name:'a')) (key (StringExpr value:'b')))) (key (StringExpr value:'c')) (value " +
      "(NumberExpr value:int 3)))))")
check("a[i][j] = 4",
      "(Program (stmts (IndexAssignStmt obj:'' op:EQUALS (obj_expr (IndexExpr (obj (VarExpr " +
      "name:'a')) (key (VarExpr name:'i')))) (key (VarExpr name:'j')) (value (NumberExpr " +
      "value:int 4)))))")
check("a.b += 1",
      "(Program (stmts (IndexAssignStmt obj:'' op:PLUS_EQUAL (obj_expr (VarExpr name:'a')) (key " +
      "(StringExpr value:'b')) (value (NumberExpr value:int 1)))))")
check("a, b.c, d[1] = f()",
      "(Program (stmts (MultiAssignStmt (targets (VarExpr name:'a') (IndexExpr (obj (VarExpr " +
      "name:'b')) (key (StringExpr value:'c'))) (IndexExpr (obj (VarExpr name:'d')) (key " +
      "(NumberExpr value:int 1)))) (values (CallExpr callee:'f' optional:false)))))")
check("f(1)",
      "(Program (stmts (ExprStmt (expr (CallExpr callee:'f' optional:false (args (NumberExpr " +
      "value:int 1)))))))")
check("a.m(1)",
      "(Program (stmts (ExprStmt (expr (MethodCallExpr method:'m' is_super:false optional:false " +
      "(receiver (VarExpr name:'a')) (args (NumberExpr value:int 1)))))))")
check("x",
      "(Program (stmts (ExprStmt (expr (VarExpr name:'x')))))")

## statements
check("if x then y = 1 end",
      "(Program (stmts (IfStmt (cond (VarExpr name:'x')) (then_body (AssignStmt name:'y' op:'' " +
      "(value (NumberExpr value:int 1)))))))")
check("if x then y = 1 elseif z then y = 2 else y = 3 end",
      "(Program (stmts (IfStmt (cond (VarExpr name:'x')) (then_body (AssignStmt name:'y' op:'' " +
      "(value (NumberExpr value:int 1)))) (else_ifs (ElseIfClause (cond (VarExpr name:'z')) " +
      "(body (AssignStmt name:'y' op:'' (value (NumberExpr value:int 2)))))) (else_body " +
      "(AssignStmt name:'y' op:'' (value (NumberExpr value:int 3)))))))")
check("if x then end",
      "(Program (stmts (IfStmt (cond (VarExpr name:'x')))))")
check("while x < 10 do x += 1 end",
      "(Program (stmts (WhileStmt (cond (BinaryExpr op:'<' (left (VarExpr name:'x')) (right " +
      "(NumberExpr value:int 10)))) (body (AssignStmt name:'x' op:'+' (value (NumberExpr " +
      "value:int 1)))))))")
check("do end",
      "(Program (stmts (DoStmt)))")
check("while true do break end",
      "(Program (stmts (WhileStmt (cond (BoolExpr value:true)) (body (BreakStmt)))))")
check("while true do continue end",
      "(Program (stmts (WhileStmt (cond (BoolExpr value:true)) (body (ContinueStmt)))))")
check("for i = 1, 10 do print(i) end",
      "(Program (stmts (ForIterStmt var1:'i' var2:'' (iter_expr (RangeExpr incl_left:true " +
      "incl_right:true (start (NumberExpr value:int 1)) (end (NumberExpr value:int 10)))) (body " +
      "(ExprStmt (expr (CallExpr callee:'print' optional:false (args (VarExpr name:'i')))))))))")
check("for i = 1, 10, 2 do end",
      "(Program (stmts (ForIterStmt var1:'i' var2:'' (iter_expr (RangeExpr incl_left:true " +
      "incl_right:true (start (NumberExpr value:int 1)) (end (NumberExpr value:int 10)) (step " +
      "(NumberExpr value:int 2)))))))")
check("for k, v in m do end",
      "(Program (stmts (ForIterStmt var1:'k' var2:'v' (iter_expr (VarExpr name:'m')))))")
check("throw 'boom'",
      "(Program (stmts (ThrowStmt (value (StringExpr value:'boom')))))")

## functions
check("func f() end",
      "(Program (stmts (FuncDeclStmt name:'f' params:[] variadic:false is_static:false)))")
check("func f(a, b = 1, c) end",
      "(Program (stmts (FuncDeclStmt name:'f' params:['a','b','c'] variadic:false " +
      "is_static:false (defaults (NumberExpr value:int 1)))))")
check("func f(a, ...) return a, ... end",
      "(Program (stmts (FuncDeclStmt name:'f' params:['a'] variadic:true is_static:false (body " +
      "(ReturnStmt spread_varargs:true (values (VarExpr name:'a')))))))")
check("func f() return end",
      "(Program (stmts (FuncDeclStmt name:'f' params:[] variadic:false is_static:false (body " +
      "(ReturnStmt spread_varargs:false)))))")
check("func f() return ... end",
      "(Program (stmts (FuncDeclStmt name:'f' params:[] variadic:false is_static:false (body " +
      "(ReturnStmt spread_varargs:true)))))")
check("func obj.method(a) return a end",
      "(Program (stmts (IndexAssignStmt obj:'obj' op:EQUALS (key (StringExpr value:'method')) " +
      "(value (FuncExpr params:['a'] variadic:false (body (ReturnStmt spread_varargs:false " +
      "(values (VarExpr name:'a')))))))))")
check("func f() if x then return end end",
      "(Program (stmts (FuncDeclStmt name:'f' params:[] variadic:false is_static:false (body " +
      "(IfStmt (cond (VarExpr name:'x')) (then_body (ReturnStmt spread_varargs:false)))))))")

## several statements and a block of them
check("var x = 1" + NEWLINE + "var y = 2" + NEWLINE + "print(x + y)",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['x'] (values " +
      "(NumberExpr value:int 1))) (VarDeclStmt is_global:false is_constant:false names:['y'] " +
      "(values (NumberExpr value:int 2))) (ExprStmt (expr (CallExpr callee:'print' " +
      "optional:false (args (BinaryExpr op:'+' (left (VarExpr name:'x')) (right (VarExpr " +
      "name:'y')))))))))")
check("func fib(n)" + NEWLINE + "    if n < 2 then" + NEWLINE + "        return n" + NEWLINE + "    end" + NEWLINE + "    return fib(n - 1) + fib(n - 2)" + NEWLINE + "end",
      "(Program (stmts (FuncDeclStmt name:'fib' params:['n'] variadic:false is_static:false " +
      "(body (IfStmt (cond (BinaryExpr op:'<' (left (VarExpr name:'n')) (right (NumberExpr " +
      "value:int 2)))) (then_body (ReturnStmt spread_varargs:false (values (VarExpr " +
      "name:'n'))))) (ReturnStmt spread_varargs:false (values (BinaryExpr op:'+' (left " +
      "(CallExpr callee:'fib' optional:false (args (BinaryExpr op:'-' (left (VarExpr name:'n')) " +
      "(right (NumberExpr value:int 1)))))) (right (CallExpr callee:'fib' optional:false (args " +
      "(BinaryExpr op:'-' (left (VarExpr name:'n')) (right (NumberExpr value:int 2)))))))))))))")
check("var s = 0" + NEWLINE + "for i = 1, 10 do" + NEWLINE + "    if i % 2 == 0 then" + NEWLINE + "        s += i" + NEWLINE + "    elseif i == 7 then" + NEWLINE + "        continue" + NEWLINE + "    else" + NEWLINE + "        break" + NEWLINE + "    end" + NEWLINE + "end",
      "(Program (stmts (VarDeclStmt is_global:false is_constant:false names:['s'] (values " +
      "(NumberExpr value:int 0))) (ForIterStmt var1:'i' var2:'' (iter_expr (RangeExpr " +
      "incl_left:true incl_right:true (start (NumberExpr value:int 1)) (end (NumberExpr " +
      "value:int 10)))) (body (IfStmt (cond (BinaryExpr op:'=' (left (BinaryExpr op:'%' (left " +
      "(VarExpr name:'i')) (right (NumberExpr value:int 2)))) (right (NumberExpr value:int " +
      "0)))) (then_body (AssignStmt name:'s' op:'+' (value (VarExpr name:'i')))) (else_ifs " +
      "(ElseIfClause (cond (BinaryExpr op:'=' (left (VarExpr name:'i')) (right (NumberExpr " +
      "value:int 7)))) (body (ContinueStmt)))) (else_body (BreakStmt)))))))")

## what the parser refuses, on which line, and with which message
refuses("var x =" + NEWLINE, "2: unexpected token ''")
refuses("if x print(x) end" + NEWLINE, "1: unexpected token 'print'")
refuses("var x = (1 + 2" + NEWLINE, "2: unexpected token ''")
refuses("1 = 2" + NEWLINE, "1: a statement cannot begin with '=' — such a line continues the expression above; give the value a name instead")
refuses("+ 1" + NEWLINE, "1: a statement cannot begin with '+' — such a line continues the expression above; give the value a name instead")
refuses(";" + NEWLINE, "1: ';' is not valid syntax — statements are terminated by newlines")
refuses("const K" + NEWLINE, "1: const 'K' must be initialized")
refuses("a.b() = 1" + NEWLINE, "1: invalid assignment target")
refuses("f(1) = 2" + NEWLINE, "1: invalid assignment target")
refuses("a, 1 = 2, 3" + NEWLINE, "1: invalid assignment target")
refuses("func f(1) end" + NEWLINE, "1: unexpected token '1'")
refuses("func f()" + NEWLINE + "    return 1" + NEWLINE + "    print(2)" + NEWLINE + "end" + NEWLINE, "3: 'print' after 'return': a return ends its block, so nothing can follow it")
refuses("while x print() end" + NEWLINE, "1: unexpected token 'print'")
refuses("var x = [1 2]" + NEWLINE, "1: expected ',' between array elements, got '2'")
refuses("var x = \{a 1}" + NEWLINE, "1: unexpected token '1'")
refuses("var x = \{1: 2}" + NEWLINE, "1: expected string, identifier, or [expr] key in map literal")
refuses("x = )" + NEWLINE, "1: unexpected token ')'")
refuses("for i in do end" + NEWLINE, "1: unexpected token 'do'")
refuses("func a.b.c() end" + NEWLINE, "1: unexpected token '.'")
refuses("var 5 = 1" + NEWLINE, "1: unexpected token '5'")
refuses("else" + NEWLINE, "1: unexpected token 'else'")
refuses("var x = 99999999999999999999" + NEWLINE, "1: numeric literal out of range: 99999999999999999999")
refuses("var x = f(1," + NEWLINE, "2: unexpected token ''")
refuses("var x = a." + NEWLINE, "2: expected a field name, got ''")
refuses("var x = 1 +" + NEWLINE, "2: unexpected token ''")
## what this trace does not follow ends it on the step that reaches it, with no error and no tree, instead
## of showing something wrong: the steps up to there are kept
func notCovered(text, what)
    var r = parseTrace(unquote(text))
    var last = r.steps[#r.steps]
    assert(last.stop == what and last.event and last.note.startsWith("The parser now reads"), "'{text}': the last step should say it")
    assert(r.error == nil and r.tree == nil, "'{text}' is not a refusal")
    for st in r.steps do
        assert(st == last or st.stop == nil, "'{text}': only the last step stops")
    end
end

notCovered("try x = 1 catch e y = 2 end", "a try block")
notCovered("import 'lib'", "an import")
notCovered("class A end", "a class")
notCovered("enum E A end", "an enum")
notCovered("switch x case 1 y = 1 end", "a switch")
notCovered("var x = ref a", "a ref")
notCovered("var x = super.m()", "a super call")
notCovered("var x = [1; 3]", "a range")
notCovered("var x = ]1; 3]", "an open-left range")

## the lines before the construct are followed as usual, here inside a block
var inner = parseTrace(unquote("if x then" + NEWLINE + "    var y = 1" + NEWLINE + "    class A end" + NEWLINE + "end"))
assert(inner.steps[#inner.steps].stop == "a class" and #inner.steps > 40, "a class inside an if: {#inner.steps} steps")

## the trace itself, line by line. `break` is the shortest statement: parse() asks parse_one_stmt() for a
## statement, whose switch sends it to break_stmt(); the result goes back up, and parse() finds the end.
## Each step is given as the function and how its line begins, so the test does not depend on where
## the lines sit in parser.cpp.
func followsPath(text, expected)
    assertPath(parseTrace(unquote(text)).steps, PCPP, expected)
end

followsPath("break", [
    "parse|Program prog;", "parse|while (true)", "parse|if (check(TokenType::EOF_T))",
    "parse|prog.stmts.push_back(parse_one_stmt());",
    "parse_one_stmt|if (depth_ >= 256)", "parse_one_stmt|DepthGuard guard(depth_);",
    "parse_one_stmt|if (only_continues_expr(peek().type))", "parse_one_stmt|switch (peek().type)",
    "parse_one_stmt|return break_stmt();",
    "break_stmt|int line = peek().line;", "break_stmt|advance();", "break_stmt|auto s = std::make_unique<BreakStmt>();",
    "break_stmt|s->line = line;", "break_stmt|s->file_idx = current_file_idx_;", "break_stmt|return s;",
    "parse_one_stmt|return break_stmt();", "parse|prog.stmts.push_back(parse_one_stmt());",
    "parse|if (check(TokenType::EOF_T))", "parse|break;", "parse|prog.source_files =", "parse|return prog;"])

## every line the trace names exists, a refusal is the last step, and the position never goes back
func checkTrace(text)
    var r = parseTrace(unquote(text))
    var count = #r.tokens
    var before = 1
    for k, s in r.steps do
        assert(s.p0 == before and s.p1 >= s.p0 and s.p1 <= count, "the position jumps at step {k}")
        before = s.p1
        assert(PCPP.has(s.fn), "step {k} runs a function that is not shown: {s.fn}")
        assert(s.at >= 1 and s.at + s.span <= #PCPP[s.fn].lines, "step {k} runs a line that does not exist")
        assert(s.stack.startsWith("parse") and s.stack.find(s.fn), "step {k} is not on top of its own call stack")
        assert(s.event == (s.p1 > s.p0 or #s.fx > 0 or s.err <> nil), "step {k} is wrongly flagged as an event")
    end
    if r.error then
        assert(r.steps[#r.steps].err == r.error and r.tree == nil, "the refusal is not the last step")
    else
        var last = r.steps[#r.steps]
        assert(last.fn == "parse" and PCPP["parse"].trimmed[last.at].startsWith("return prog;"), "the parse does not end in parse()")
    end
    return r
end

## the effects of the steps, replayed on nothing, build the tree the parse ended with: that is what the
## animation does, and no node is left over when the program is accepted
func size(node)
    var n = 1
    for k in node.kids do
        n += size(k)
    end
    return n
end

func replays(text)
    var r = checkTrace(text)
    var nodes = {}
    for s in r.steps do
        for e in s.fx do
            applyEffect(nodes, e)
        end
    end
    assert(sexp(nodes[1]) == sexp(r.tree), "the replay of '{text}' builds another tree")
    assert(nodes.len() == size(nodes[1]), "'{text}' leaves nodes that nothing holds")
end

replays("var total = 1 + 2 * 3")
replays("a.b = 1")
replays("a[i] += f(x, 'n = \{x}')")
replays("func f(a, ...)" + NEWLINE + "    if a then return ... end" + NEWLINE + "end")
replays("for k, v in m do while x < 1 do x += 1 end end")
replays("var x = \{a: [1, 2], 'b': func() end}")
replays("a, b = f()")
checkTrace("if x print(x) end")
checkTrace("var x = (1 + 2")

## a refusal is recorded on the line that makes it, with the line of the program it names
var refused = checkTrace("var ok = 1" + NEWLINE + "var 3 = 2")
var last = refused.steps[#refused.steps]
assert(last.errLine == 2 and last.err == "unexpected token '3'" and last.fn == "decl_stmt" and last.event)

## a token knows the line it is on, and the parser reads them in order
var lines = parseTrace("a" + NEWLINE + "b" + NEWLINE + "c")
assert(lines.tokens[3].lexeme == "c" and lines.tokens[3].line == 3)

## precedence climbs down level by level: the stack of the first leaf shows the nine levels
var leaf = parseTrace("1")
var deepest = ""
for s in leaf.steps do
    if s.fn == "primary" then
        deepest = s.stack
        break
    end
end
assert(deepest == "parse > parse_one_stmt > expr_stmt > expr > binary_level(0..5) > comparison > binary_level(6..9) > unary > power > primary",
       deepest)

print("parser trace ok")
