/* The tables of the 8b/10b line code (IEEE 802.3 clause 36; Widmer and Franaszek), shared by
 * the encoder and decoder blocks of rtl/lib/block/line_code: one source, so they cannot
 * disagree.
 *
 * Each half has one table, the standard's column for running disparity -1 (RD-), written as
 * the standard writes it (a or f first, so at the top bit). The column for RD+ follows from one
 * rule: a code with disparity -2 or +2 is complemented at RD+, so that such codes alternate and
 * the running disparity stays -1 or +1; so are the balanced D.07 (111000) and D.x.3 (1100),
 * against runs, and every control code's 4-bit part (the K column holds, for y = 1, 2, 5, 6,
 * the complements of the balanced data codes, so that a comma ends with the right bits). Every
 * other code is balanced and the same at both. A .7 data code is D.x.P7, or D.x.A7 where P7
 * would make a run of five equal bits after the 6-bit part, which only the commas may have:
 * x = 17, 18, 20 at RD- and x = 11, 13, 14 at RD+ (balanced codes ending in 11 or 00).
 * Running disparity: 0 = -1, 1 = +1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package LineCodePkg;

    // The 5b/6b table, column RD-: the 6-bit part abcdei of x (EDCBA); k28: K.28's own part.
    function automatic logic [5:0] neg6(input logic [4:0] x, input logic k28);
        if (k28)
            return 6'b001111;
        case (x)
            5'd0:    return 6'b100111;
            5'd1:    return 6'b011101;
            5'd2:    return 6'b101101;
            5'd3:    return 6'b110001;
            5'd4:    return 6'b110101;
            5'd5:    return 6'b101001;
            5'd6:    return 6'b011001;
            5'd7:    return 6'b111000;
            5'd8:    return 6'b111001;
            5'd9:    return 6'b100101;
            5'd10:   return 6'b010101;
            5'd11:   return 6'b110100;
            5'd12:   return 6'b001101;
            5'd13:   return 6'b101100;
            5'd14:   return 6'b011100;
            5'd15:   return 6'b010111;
            5'd16:   return 6'b011011;
            5'd17:   return 6'b100011;
            5'd18:   return 6'b010011;
            5'd19:   return 6'b110010;
            5'd20:   return 6'b001011;
            5'd21:   return 6'b101010;
            5'd22:   return 6'b011010;
            5'd23:   return 6'b111010;
            5'd24:   return 6'b110011;
            5'd25:   return 6'b100110;
            5'd26:   return 6'b010110;
            5'd27:   return 6'b110110;
            5'd28:   return 6'b001110;
            5'd29:   return 6'b101110;
            5'd30:   return 6'b011110;
            default: return 6'b101011;      // 31
        endcase
    endfunction

    // The 3b/4b table, column RD-: the 4-bit part fghj of y (HGF), data or control code; alt7:
    // a .7 data code is D.x.A7.
    function automatic logic [3:0] neg4(input logic [2:0] y, input logic k, input logic alt7);
        case ({k, y})
            4'b0_000: return 4'b1011;
            4'b0_001: return 4'b1001;
            4'b0_010: return 4'b0101;
            4'b0_011: return 4'b1100;
            4'b0_100: return 4'b1101;
            4'b0_101: return 4'b1010;
            4'b0_110: return 4'b0110;
            4'b0_111: return alt7 ? 4'b0111 : 4'b1110;     // D.x.A7 : D.x.P7
            4'b1_000: return 4'b1011;
            4'b1_001: return 4'b0110;
            4'b1_010: return 4'b1010;
            4'b1_011: return 4'b1100;
            4'b1_100: return 4'b1101;
            4'b1_101: return 4'b0101;
            4'b1_110: return 4'b1001;
            default:  return 4'b0111;                       // K.x.7
        endcase
    endfunction

    // The 6-bit part of x at running disparity rd (the rule: complemented at RD+ when its
    // disparity is +-2, or for D.07).
    function automatic logic [5:0] code6(input logic [4:0] x, input logic k28, input logic rd);
        logic [5:0] n;
        n = neg6(x, k28);
        return (rd && ($countones(n) != 3 || x == 5'd7)) ? ~n : n;
    endfunction

    // The 4-bit part of y at running disparity rd (the rule: complemented at RD+ when its
    // disparity is +-2, for D.x.3, or for a control code).
    function automatic logic [3:0] code4(input logic [2:0] y, input logic k, input logic alt7,
                                         input logic rd);
        logic [3:0] n;
        n = neg4(y, k, alt7);
        return (rd && ($countones(n) != 2 || y == 3'd3 || k)) ? ~n : n;
    endfunction

    // A .7 data code after the 6-bit part of x, at running disparity rd there, is D.x.A7.
    function automatic logic alt7_of(input logic [4:0] x, input logic rd);
        return rd ? x == 5'd11 || x == 5'd13 || x == 5'd14
                  : x == 5'd17 || x == 5'd18 || x == 5'd20;
    endfunction

    // D.x.y may be sent as a control code: K.28.0 to K.28.7, K.23.7, K.27.7, K.29.7, K.30.7.
    function automatic logic valid_k(input logic [4:0] x, input logic [2:0] y);
        return x == 5'd28 ||
               (y == 3'd7 && (x == 5'd23 || x == 5'd27 || x == 5'd29 || x == 5'd30));
    endfunction

    // The running disparity after a received sub-block of N bits (6 or 4), the standard's
    // rule: +1 with more ones or for 000111 or 0011, -1 with more zeros or for 111000 or 1100,
    // else as before; so it recovers by itself after a bit error.
    function automatic logic rd_after6(input logic [5:0] s, input logic rd);
        if ($countones(s) != 3)
            return $countones(s) > 3;
        if (s == 6'b000111 || s == 6'b111000)
            return s == 6'b000111;
        return rd;
    endfunction

    function automatic logic rd_after4(input logic [3:0] s, input logic rd);
        if ($countones(s) != 2)
            return $countones(s) > 2;
        if (s == 4'b0011 || s == 4'b1100)
            return s == 4'b0011;
        return rd;
    endfunction

endpackage
