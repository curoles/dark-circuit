# Publications

Notes on the design of dark-circuit's blocks and cores: what was tried, what it cost, how it
was measured. Each links to the code and to the knowledge-base records (`kb/`) behind it.

| Date | Title | In short |
|---|---|---|
| 2026-11 | [Replay instead of refuse: getting 0.5 ns back](2026-11-replay-instead-of-refuse.md) | A cache that takes a request in its refill clock: the obvious guard cost 8 % of the clock, replaying the conflicting request costs nothing and keeps the 18-20 % fewer cycles. |
