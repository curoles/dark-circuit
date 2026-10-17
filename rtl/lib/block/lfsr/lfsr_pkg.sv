/* Tap masks of Lfsr, shared by the behave and struct versions.
 *
 * Author: Igor Lesik
 */
package LfsrPkg;

    // Galois tap mask of a WIDTH-bit Lfsr, 0 when WIDTH is not supported.
    // Bit k of the mask is term x^(k+1) of the polynomial. Every mask was
    // checked to give the maximal period 2^WIDTH - 1.
    function automatic logic [31:0] lfsr_taps(input int width);
        case (width)
            4:       return 32'h0000_000C;  // x^4 + x^3 + 1
            8:       return 32'h0000_00B8;  // x^8 + x^6 + x^5 + x^4 + 1
            12:      return 32'h0000_0E08;  // x^12 + x^11 + x^10 + x^4 + 1
            16:      return 32'h0000_B400;  // x^16 + x^14 + x^13 + x^11 + 1
            32:      return 32'h8020_0003;  // x^32 + x^22 + x^2 + x + 1
            default: return 32'h0;
        endcase
    endfunction

endpackage
