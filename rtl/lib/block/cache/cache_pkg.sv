/* Constants shared by the cache blocks.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package CachePkg;

    // Replacement policies of CacheReplacement: plain constants, not an enum (Icarus 13 gets
    // enum constants wrong on module ports, see the BTB). The tests of other blocks read the
    // package with the aggregate flist and do not use them.
    /* verilator lint_off UNUSEDPARAM */
    localparam int REPL_LRU    = 0;     // least recently used way (BitMatrixLru)
    localparam int REPL_RANDOM = 1;     // a pseudo-random way (Lfsr)
    /* verilator lint_on UNUSEDPARAM */

    // InsnDataCacheArbiter: who gets memory when both caches want it. The input prio decides
    // first; when it is PRIO_NONE, the parameter POLICY. Plain constants, as above.
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [1:0] PRIO_NONE       = 2'd0;
    localparam logic [1:0] PRIO_DATA       = 2'd1;  // the data cache
    localparam logic [1:0] PRIO_INSN       = 2'd2;  // the instruction cache
    localparam int         ARB_DATA_FIRST  = 0;
    localparam int         ARB_INSN_FIRST  = 1;
    localparam int         ARB_ROUND_ROBIN = 2;     // the side not served last
    /* verilator lint_on UNUSEDPARAM */

    // Cache-block operations (RISC-V Zicbom: cbo.clean, cbo.inval, cbo.flush) on the
    // library's request channels: the field cmo of a request, CMO_NONE for every other
    // request. A CBO is a store without strobes (it writes no byte) whose cmo says what each
    // cache on the way does with the line of its address: clean writes it back if dirty (a
    // write-through cache has nothing to write), inval drops it, flush does both. Bit 0:
    // clean, bit 1: invalidate. It goes on down (the level below may hold the line too) and
    // gets no answer; a level that holds no lines (a memory) takes it as the write it is.
    // Plain constants, as above. (kb rtl/lib/block/cache/cbo)
    typedef logic [1:0] cmo_t;
    /* verilator lint_off UNUSEDPARAM */
    localparam cmo_t CMO_NONE  = 2'b00;     // an ordinary request
    localparam cmo_t CMO_CLEAN = 2'b01;
    localparam cmo_t CMO_INVAL = 2'b10;
    localparam cmo_t CMO_FLUSH = 2'b11;     // clean, then invalidate
    /* verilator lint_on UNUSEDPARAM */

endpackage
