# Publications

Notes on the design of dark-circuit's blocks and cores: what was tried, what it cost, how it
was measured. Each links to the code and to the knowledge-base records (`kb/`) behind it.

| Date | Title | In short |
|---|---|---|
| 2026-11 | [The register port: a device is its registers, one clock per access](2026-11-register-port.md) | A twenty-line block turns a bus handshake into one-clock accesses: a read's side effect happens once by construction, the answer is a flop, ready comes from flops; the PLIC, the timer and the UART are wiring behind it. |
| 2026-11 | [Replay instead of refuse: getting 0.5 ns back](2026-11-replay-instead-of-refuse.md) | A cache that takes a request in its refill clock: the obvious guard cost 8 % of the clock, replaying the conflicting request costs nothing and keeps the 18-20 % fewer cycles. |
| 2026-11 | [EXPECT_REG: register expectations that live in the test binary of self-checking assembly tests](2026-11-expect-reg.md) | Expected register values as a table after the halting instruction, checked by the testbench against the retired results: a test that does not ask the CPU to grade its own exam. |
