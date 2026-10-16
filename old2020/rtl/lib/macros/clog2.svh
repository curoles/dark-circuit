`ifndef CLOG2_SVH_INCLUDED_
`define CLOG2_SVH_INCLUDED_

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

`endif
