/* Atomic operations on the library's request channels: the atop field of a request.
 *
 * A request with atop != ATOP_NONE is an atomic memory operation done where the memory is
 * shared (the point of coherence: in front of the memory, an L2, a slice of a last-level
 * cache), not in the core: AtomicUnit there reads the word, writes op(old, data) and
 * answers with the old word; caches above it pass atomics through (kb
 * rtl/lib/block/atomic/design). The values are those of AXI5's AWATOP by definition, so an
 * AXI adapter is wiring (it checks the equality with AxiPkg): bits [5:4] the kind
 * (00 not atomic, 01 AtomicStore, 10 AtomicLoad, 11 AtomicSwap or AtomicCompare), bit 3 the
 * endianness of the arithmetic (0: little), bits [2:0] the operation. This package does not
 * import AxiPkg: blocks stay free of a concrete bus.
 *
 *   atop       memory gets             answer   RISC-V
 *   ATOP_NONE  (an ordinary request)
 *   LD_ADD     old + data              old      AMOADD
 *   LD_CLR     old & ~data             old      AMOAND (the core sends ~rs2)
 *   LD_EOR     old ^ data              old      AMOXOR
 *   LD_SET     old | data              old      AMOOR
 *   LD_SMAX    signed max(old, data)   old      AMOMAX
 *   LD_SMIN    signed min              old      AMOMIN
 *   LD_UMAX    unsigned max            old      AMOMAXU
 *   LD_UMIN    unsigned min            old      AMOMINU
 *   SWAP       data                    old      AMOSWAP
 * Not used yet: AtomicStore (01_0ooo: the operation without an answer, for an AMO whose rd is
 * x0) and AtomicCompare (11_0001: a compare-and-swap).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package AtomicPkg;

    typedef logic [5:0] atop_t;     // as AXI5 AWATOP

    /* verilator lint_off UNUSEDPARAM */
    localparam atop_t ATOP_NONE    = 6'b00_0000;
    localparam atop_t ATOP_LD_ADD  = 6'b10_0000;
    localparam atop_t ATOP_LD_CLR  = 6'b10_0001;
    localparam atop_t ATOP_LD_EOR  = 6'b10_0010;
    localparam atop_t ATOP_LD_SET  = 6'b10_0011;
    localparam atop_t ATOP_LD_SMAX = 6'b10_0100;
    localparam atop_t ATOP_LD_SMIN = 6'b10_0101;
    localparam atop_t ATOP_LD_UMAX = 6'b10_0110;
    localparam atop_t ATOP_LD_UMIN = 6'b10_0111;
    localparam atop_t ATOP_SWAP    = 6'b11_0000;
    /* verilator lint_on UNUSEDPARAM */

    // The request is atomic: only the kind (bits [5:4]) is used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic is_atomic(input atop_t a);
    /* verilator lint_on UNUSEDSIGNAL */
        return a[5:4] != 2'b00;
    endfunction

endpackage
