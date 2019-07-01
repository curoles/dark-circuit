`define REPEAT(n, d) `REPEAT_``n(d)

`define REPEAT_0(d)
`define REPEAT_1(d) d
`define REPEAT_2(d) `REPEAT_1(d)d
`define REPEAT_3(d) `REPEAT_2(d)d
`define REPEAT_4(d) `REPEAT_3(d)d
`define REPEAT_5(d) `REPEAT_4(d)d
`define REPEAT_6(d) `REPEAT_5(d)d
`define REPEAT_7(d) `REPEAT_6(d)d
`define REPEAT_8(d) `REPEAT_7(d)d
`define REPEAT_9(d) `REPEAT_8(d)d
