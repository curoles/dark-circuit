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

endpackage
