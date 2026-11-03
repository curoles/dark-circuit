/* The 5b/6b half of the 8b/10b line code (IEEE 802.3 clause 36; Widmer and Franaszek),
 * behavioral: the low five bits x (EDCBA) of a byte D.x.y to the 6-bit part abcdei of its code.
 *
 * The table is the standard's column for running disparity -1 (RD-), written as the standard
 * writes it (a first, so a is bit 5 here). The column for RD+ follows from one rule: a code
 * with two or four ones (disparity -2 or +2) is sent complemented at RD+, so that such codes
 * alternate and the running disparity stays -1 or +1; D.07 (111000) is balanced but alternates
 * too, against runs. Every other code is balanced, sent as it is, and keeps the running
 * disparity. K.28 has a 6-bit part of its own (001111); the other control codes (K.23.7,
 * K.27.7, K.29.7, K.30.7) use the data codes. alt7 tells the 3b/4b half to send a .7 as D.x.A7
 * instead of D.x.P7: at RD- for x = 17, 18, 20 and at RD+ for x = 11, 13, 14 (the codes ending
 * in 11 or 00, balanced: the running disparity there is rd_in), where P7 would make a run of
 * five equal bits, which only the commas may have.
 *
 *   x --> table (RD- column) --+--> neg --> XOR flip --> abcdei
 *   k AND x == 28 --> 001111 --+
 *   flip   = rd_in AND (ones(neg) != 3 OR x == 7)
 *   rd_out = rd_in XOR (ones(neg) != 3)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Enc5b6b (
    input  wire [4:0] x,        // EDCBA: the low five bits of the byte
    input  wire       k,        // a control code (only K.28 changes this half)
    input  wire       rd_in,    // running disparity before: 0 = -1, 1 = +1
    output wire [5:0] abcdei,   // the 6-bit part as the standard writes it: a is bit 5
    output wire       rd_out,   // running disparity after it
    output wire       alt7      // a .7 data code is sent as D.x.A7 (to Enc3b4b)
);
    logic [5:0] neg;            // the code at RD-
    wire        unbalanced;     // two or four ones: the running disparity changes
    wire        flip;           // sent complemented: RD+ and a code that alternates

    // The standard's 5b/6b table, column RD-; the RD+ column is the rule below.
    // @kb: rtl/lib/block/line_code/enc_8b10b/design
    always_comb begin
        case (x)
            5'd0:  neg = 6'b100111;
            5'd1:  neg = 6'b011101;
            5'd2:  neg = 6'b101101;
            5'd3:  neg = 6'b110001;
            5'd4:  neg = 6'b110101;
            5'd5:  neg = 6'b101001;
            5'd6:  neg = 6'b011001;
            5'd7:  neg = 6'b111000;
            5'd8:  neg = 6'b111001;
            5'd9:  neg = 6'b100101;
            5'd10: neg = 6'b010101;
            5'd11: neg = 6'b110100;
            5'd12: neg = 6'b001101;
            5'd13: neg = 6'b101100;
            5'd14: neg = 6'b011100;
            5'd15: neg = 6'b010111;
            5'd16: neg = 6'b011011;
            5'd17: neg = 6'b100011;
            5'd18: neg = 6'b010011;
            5'd19: neg = 6'b110010;
            5'd20: neg = 6'b001011;
            5'd21: neg = 6'b101010;
            5'd22: neg = 6'b011010;
            5'd23: neg = 6'b111010;
            5'd24: neg = 6'b110011;
            5'd25: neg = 6'b100110;
            5'd26: neg = 6'b010110;
            5'd27: neg = 6'b110110;
            5'd28: neg = 6'b001110;
            5'd29: neg = 6'b101110;
            5'd30: neg = 6'b011110;
            default: neg = 6'b101011;   // 31
        endcase
        if (k && x == 5'd28)
            neg = 6'b001111;            // K.28
    end

    assign unbalanced = $countones(neg) != 3;
    assign flip       = rd_in && (unbalanced || x == 5'd7);
    assign abcdei     = neg ^ {6{flip}};
    assign rd_out     = rd_in ^ unbalanced;

    assign alt7 = rd_in ? x == 5'd11 || x == 5'd13 || x == 5'd14
                        : x == 5'd17 || x == 5'd18 || x == 5'd20;

endmodule
