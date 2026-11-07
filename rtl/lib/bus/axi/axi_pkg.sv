/* AXI (AMBA AXI4 and AXI5) encodings, for the adapters between AXI and the library's channels.
 *
 * Only code in rtl/lib/bus/ uses this package: the library's blocks take no concrete bus, a
 * platform that wants AXI puts an adapter of bus/axi/ between a block's channel and the
 * bus. The values are from the AMBA AXI specification (ARM IHI 0022); check them against it
 * when the first adapter is written.
 *
 *   AxSIZE   bytes of a beat: 1 << size (as the library's size field)
 *   AxBURST  FIXED, INCR, WRAP
 *   AxLOCK   normal or exclusive (the exclusive monitor of a later LR/SC)
 *   xRESP    OKAY, EXOKAY, SLVERR, DECERR
 *   AWATOP   (AXI5) [5:4] kind: none, AtomicStore, AtomicLoad, AtomicSwap/Compare;
 *            [3] endianness of the arithmetic (0 little); [2:0] operation: ADD, CLR, EOR,
 *            SET, SMAX, SMIN, UMAX, UMIN (AtomicPkg's atop has the same values)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package AxiPkg;

    typedef logic [2:0] axsize_t;   // bytes of a beat: 1 << size
    typedef logic [1:0] axburst_t;
    typedef logic [1:0] xresp_t;
    typedef logic [5:0] awatop_t;

    /* verilator lint_off UNUSEDPARAM */
    localparam axburst_t AXI_BURST_FIXED  = 2'b00;
    localparam axburst_t AXI_BURST_INCR   = 2'b01;
    localparam axburst_t AXI_BURST_WRAP   = 2'b10;

    localparam logic     AXI_LOCK_NORMAL    = 1'b0;
    localparam logic     AXI_LOCK_EXCLUSIVE = 1'b1;

    localparam xresp_t   AXI_RESP_OKAY    = 2'b00;
    localparam xresp_t   AXI_RESP_EXOKAY  = 2'b01;
    localparam xresp_t   AXI_RESP_SLVERR  = 2'b10;
    localparam xresp_t   AXI_RESP_DECERR  = 2'b11;

    // AWATOP: the kind (bits [5:4]) and the operation (bits [2:0]).
    localparam logic [1:0] AXI_ATOP_KIND_NONE  = 2'b00;
    localparam logic [1:0] AXI_ATOP_KIND_STORE = 2'b01;   // AtomicStore: no answer
    localparam logic [1:0] AXI_ATOP_KIND_LOAD  = 2'b10;   // AtomicLoad: the old value back
    localparam logic [1:0] AXI_ATOP_KIND_SWAP  = 2'b11;   // AtomicSwap, AtomicCompare
    localparam logic [2:0] AXI_ATOP_ADD  = 3'b000;
    localparam logic [2:0] AXI_ATOP_CLR  = 3'b001;        // old & ~data
    localparam logic [2:0] AXI_ATOP_EOR  = 3'b010;
    localparam logic [2:0] AXI_ATOP_SET  = 3'b011;        // old | data
    localparam logic [2:0] AXI_ATOP_SMAX = 3'b100;
    localparam logic [2:0] AXI_ATOP_SMIN = 3'b101;
    localparam logic [2:0] AXI_ATOP_UMAX = 3'b110;
    localparam logic [2:0] AXI_ATOP_UMIN = 3'b111;
    localparam awatop_t    AXI_ATOP_NONE    = 6'b00_0000;
    localparam awatop_t    AXI_ATOP_SWAP    = 6'b11_0000;
    localparam awatop_t    AXI_ATOP_COMPARE = 6'b11_0001;
    /* verilator lint_on UNUSEDPARAM */

endpackage
