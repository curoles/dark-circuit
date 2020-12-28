/* 9-bit Fast Incrementor
 *
 */
module Incr9 (
    input  wire [8:0] in,
    output wire [8:0] out,
    output wire       cy
);

wire [2:0] nand_2_0;
wire [5:3] nand_5_3;
wire [8:6] nand_8_6;

wire all1_2_0;
wire all1_5_0;

wire [2:0] incr_5_3;
wire [2:0] incr_8_6;

assign nand_2_0 = ~(in[0] & in[1] & in[2]);
assign nand_5_3 = ~(in[3] & in[4] & in[5]);
assign nand_8_6 = ~(in[6] & in[7] & in[8]);

assign all1_2_0 = ~nand_2_0;
assign all1_5_0 = ~(nand_2_0 | nand_5_3);
assign       cy = ~(nand_2_0 | nand_5_3 | nand_8_6);

Incr3 u_incr3_2_0(.in(in[2:0]), .out(out[2:0]));
Incr3 u_incr3_5_3(.in(in[5:3]), .out(incr_5_3));
Incr3 u_incr3_8_6(.in(in[8:6]), .out(incr_8_6));

assign out[5:3] = all1_2_0 ? incr_5_3 : in[5:3];
assign out[8:6] = all1_5_0 ? incr_8_6 : in[8:6];

endmodule: Incr9
