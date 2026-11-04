/* The 6b/5b half of the 8b/10b decoder (IEEE 802.3 clause 36), behavioral: the 6-bit part
 * abcdei of a received code to the five bits x (EDCBA) whose code it is, at either running
 * disparity, and whether it is K.28's part.
 *
 * x is the one whose code (LineCodePkg's table and rule, as the encoder sends it) matches; no
 * two codes of the table are equal, at either running disparity. Meant for valid parts only:
 * for any other 6-bit value x is 0 (Dec8b10b finds invalid codes by encoding x again).
 *
 *   abcdei --> == code6(i, 0, RD-) or code6(i, 0, RD+), for i = 0 .. 31 --> x
 *   abcdei --> == 001111 or 110000 (K.28) --> k28
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Dec6b5b (
    input  wire [5:0]  abcdei,  // as the standard writes it: a is bit 5
    output logic [4:0] x,       // EDCBA
    output wire        k28      // K.28's 6-bit part (x is 28 then)
);
    // @kb: rtl/lib/block/line_code/dec_8b10b/design
    always_comb begin
        x = '0;
        for (int i = 0; i < 32; i++)
            if (abcdei == LineCodePkg::code6(5'(i), 1'b0, 1'b0) ||
                abcdei == LineCodePkg::code6(5'(i), 1'b0, 1'b1))
                x = 5'(i);
        if (k28)
            x = 5'd28;
    end

    assign k28 = abcdei == LineCodePkg::code6(5'd28, 1'b1, 1'b0) ||
                 abcdei == LineCodePkg::code6(5'd28, 1'b1, 1'b1);

endmodule
