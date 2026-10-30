/* CRC-8 with the CCITT polynomial x^8 + x^2 + x + 1 (0x07), bit-serial, made of gates.
 *
 * One message bit per clock: while calc_crc is 1, din is the next bit, the most significant
 * bit of a byte first. No reflection and no output XOR: crc is the remainder itself. INIT is
 * the starting value, loaded by reset (synchronous, active low) and by init_crc, which wins
 * over calc_crc; with calc_crc 0 crc holds. The name gives only the polynomial: CRC-8
 * standards differ in INIT, reflection and output XOR. With INIT 0x00 this is CRC-8/SMBUS
 * (check value 0xF4 for the ASCII string "123456789").
 *
 * The LFSR: the feedback is crc[7] ^ din; the next value is crc shifted left by one, with the
 * feedback XORed into the bits of the polynomial: bit 0 (and the x^8 that leaves), 1 and 2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Crc8CcittLfsr #(
    parameter [7:0] INIT = 8'hFF    // starting value of the CRC
)(
    input  wire       clk,
    input  wire       rst_n,        // synchronous reset, active low: crc = INIT
    input  wire       din,          // the next message bit, while calc_crc
    input  wire       init_crc,     // crc = INIT at the rising edge (wins over calc_crc)
    input  wire       calc_crc,     // din goes into the CRC at the rising edge
    output wire [7:0] crc
);
    wire       fb;          // feedback: the bit that leaves, XOR the message bit
    wire [7:0] crc_calc;    // crc after din
    wire [7:0] crc_step;    // crc_calc, or crc held
    wire [7:0] crc_next;

    Xor2 #(1) u_xor2_fb  (.in1(crc[7]), .in2(din), .out(fb));

    assign crc_calc[0] = fb;
    Xor2 #(1) u_xor2_crc1(.in1(crc[0]), .in2(fb), .out(crc_calc[1]));
    Xor2 #(1) u_xor2_crc2(.in1(crc[1]), .in2(fb), .out(crc_calc[2]));
    assign crc_calc[7:3] = crc[6:2];

    Mux2 #(8) u_mux2_calc(.in0(crc), .in1(crc_calc), .sel(calc_crc), .out(crc_step));
    Mux2 #(8) u_mux2_init(.in0(crc_step), .in1(INIT), .sel(init_crc), .out(crc_next));

    DffSyncRst #(.WIDTH(8), .RST_VAL(INIT)) u_dff_sync_rst(
        .clk, .rst_n, .in(crc_next), .out(crc));

endmodule
