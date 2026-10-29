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

endpackage
