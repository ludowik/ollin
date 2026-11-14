# How the lexer works

The tracer (`tracer.ol`) is a copy of `src/lexer.cpp` that records every line it runs. Two checks keep it honest:
`lexer_test.ol` (the tokens are exactly the ones the C++ lexer gives) and `tests/check_trace_source.sh` (every line named in the
tracer is the line of `lexer.cpp` it claims to be).

## Verified once against the engine

`lexer.cpp` was built with gcov and run on every program of the repository: the number of times each line ran matched the
number of steps on it, except where the tracer shows a line differently on purpose. A call line is lit twice (when it calls and
when it gets the result back), a `case` label is marked beside the statement it leads to, and a brace has no step.

The format of a step, and the player, are described in `../lib/README.md`.
