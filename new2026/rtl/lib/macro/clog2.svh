`ifndef CLOG2_SVH_INCLUDED_
`define CLOG2_SVH_INCLUDED_

// Do NOT use this macro, use built-in $clog2() instead:
// - result of `CLOG2(x) has no parentheses, `CLOG2(8)+1 gives 3, not 4;
// - `CLOG2(x) gives -1 for x > 512.
// The macro is kept only for old code; define DARK_CIRCUIT_CLOG2_MACRO to enable it.
`ifdef DARK_CIRCUIT_CLOG2_MACRO

// Compile-Time log2 function.
//
`define CLOG2(x) \
    (x <=   1) ? 0 : \
    (x <=   2) ? 1 : \
    (x <=   4) ? 2 : \
    (x <=   8) ? 3 : \
    (x <=  16) ? 4 : \
    (x <=  32) ? 5 : \
    (x <=  64) ? 6 : \
    (x <= 128) ? 7 : \
    (x <= 256) ? 8 : \
    (x <= 512) ? 9 : \
    -1

`endif // DARK_CIRCUIT_CLOG2_MACRO

`endif
