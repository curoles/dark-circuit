/* Operations of ComputeCoreBitmanip: the one-operand bit manipulations of Zbb.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package ComputeCoreBitmanipPkg;

    typedef enum logic [2:0] {
        BM_SEXT_B = 0,  // in[7:0] sign-extended
        BM_SEXT_H = 1,  // in[15:0] sign-extended
        BM_ZEXT_H = 2,  // in[15:0] zero-extended
        BM_ORC_B  = 3,  // every byte: all ones if it is not 0, else 0
        BM_REV8   = 4,  // the bytes in reverse order
        BM_CLZ    = 5,  // number of leading zeros, WIDTH for 0
        BM_CTZ    = 6,  // number of trailing zeros, WIDTH for 0
        BM_CPOP   = 7   // number of ones
    } bm_op_e;

endpackage
