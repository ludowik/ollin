## Shared by lexer_test.ol and parser_test.ol: the steps of a trace, each as the function and
## how its line begins, compared with the path that is expected.
func assertPath(steps, cpp, expected)
    var got = steps.map(func(s) return s.fn + "|" + cpp[s.fn].trimmed[s.at] end)
    for k, want in expected do
        assert(got[k] and got[k].startsWith(want), "step {k} should be '{want}', it is '{got[k]}'")
    end
    assert(#got == #expected, "{#got} steps, {#expected} expected")
end
