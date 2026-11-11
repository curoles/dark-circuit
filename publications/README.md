# Publications

Notes on the design of dark-circuit's blocks and cores: what was tried, what it cost, how it
was measured. Each links to the code and to the knowledge-base records (`kb/`) behind it.

| Date | Title | In short |
|---|---|---|
| 2026-11 | [Floating point on the integer registers: Zfinx in my RISC-V core](2026-11-fp-on-integer-registers.md) | All of RISC-V's single-precision FP on the x registers: hybrid blocks checked by TestFloat, a 16 ns FMA pipelined by hand to 5.1 ns, every result through a register, rs3 through a read port borrowed in EX; 23 % more area, the clock unchanged. |
| 2026-11 | [Half the answers wrong: a textbook floating-point multiplier against IEEE 754](2026-11-toy-vs-real-multiplier.md) | The multiplier every textbook draws, run on TestFloat's level-1 cases: 47.9 % wrong (exact only rounding toward zero, for normal numbers); what a fused multiply-add needs instead, the bugs only the reference found, and the cost: twice the area, the same clock once staged by hand. |
| 2026-11 | [The DMA wrote it, the cache kept the old copy: cbo.inval on my RISC-V core](2026-11-dma-and-cbo.md) | A stale line caught in a trace, then dropped by Zicbom: a CBO is a store of no bytes with its operation, carried down to where a lower cache will act on it; the testbench allows the old value or the new one until the CBO retires. |
| 2026-11 | [Atomics next to the memory: my core sends AMOADD as a load](2026-11-atomics-next-to-memory.md) | The read-modify-write of RISC-V's AMOs done in front of the memory, where every agent's accesses meet: the core sends a load with AXI5's operation code, the caches step aside, and the core gets simpler (0.4 % area, the clock unchanged). |
| 2026-11 | [The register port: a device is its registers, one clock per access](2026-11-register-port.md) | A twenty-line block turns a bus handshake into one-clock accesses: a read's side effect happens once by construction, the answer is a flop, ready comes from flops; the PLIC, the timer and the UART are wiring behind it. |
| 2026-11 | [Replay instead of refuse: getting 0.5 ns back](2026-11-replay-instead-of-refuse.md) | A cache that takes a request in its refill clock: the obvious guard cost 8 % of the clock, replaying the conflicting request costs nothing and keeps the 18-20 % fewer cycles. |
| 2026-11 | [EXPECT_REG: register expectations that live in the test binary of self-checking assembly tests](2026-11-expect-reg.md) | Expected register values as a table after the halting instruction, checked by the testbench against the retired results: a test that does not ask the CPU to grade its own exam. |
