/* The 4b/3b half of the 8b/10b decoder (IEEE 802.3 clause 36), behavioral: the 4-bit part
 * fghj of a received code to the three bits y (HGF) whose code it is, for a data or a control
 * code (k, which the 6-bit part decides), at the running disparity rd_in after the 6-bit part.
 *
 * y is the one whose code (LineCodePkg's table and rule, as the encoder sends it, P7 or A7 for
 * a .7) matches, at rd_in first: data codes are all different at either running disparity, but
 * control codes are not (K.x.2 at RD- is K.x.5 at RD+, K.x.1 at RD- is K.x.6 at RD+); after
 * K.28's part, unbalanced, rd_in follows from the received bits alone, so a valid control code
 * decodes right. Meant for valid parts only: for any other 4-bit value y is 0 (Dec8b10b finds
 * invalid codes by encoding y again).
 *
 *   fghj --> == code4(i, k, P7 or A7, NOT rd_in), then the same at rd_in (it wins) --> y
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Dec4b3b (
    input  wire [3:0]  fghj,    // as the standard writes it: f is bit 3
    input  wire        k,       // a control code: the K column
    input  wire        rd_in,   // running disparity after the 6-bit part: 0 = -1, 1 = +1
    output logic [2:0] y        // HGF
);
    // @kb: rtl/lib/block/line_code/dec_8b10b/design
    always_comb begin
        y = '0;
        for (int r = 0; r < 2; r++)
            for (int i = 0; i < 8; i++)
                for (int a = 0; a < 2; a++)
                    if (fghj == LineCodePkg::code4(3'(i), k, a == 1, r == 0 ? !rd_in : rd_in))
                        y = 3'(i);
    end

endmodule
