
module incr16 (
    input  wire [15:0] in,
    output wire [15:0] out,
    output wire        cy
);

wire [ 3: 0] all1_3_0;
wire [ 7: 4] all1_7_4;
wire [11: 8] all1_11_8;
wire [15:12] all1_15_12;

wire [ 3: 0] incr_3_0;
wire [ 7: 4] incr_7_4;
wire [11: 8] incr_11_8;
wire [15:12] incr_15_12;

assign all1_3_0   = ~(in[ 3] & in[ 2] & in[ 1] & in[ 0]);
assign all1_7_4   = ~(in[ 7] & in[ 6] & in[ 5] & in[ 4]);
assign all1_11_8  = ~(in[11] & in[10] & in[ 9] & in[ 8]);
assign all1_15_12 = ~(in[15] & in[14] & in[13] & in[12]);

incr4 u_incr_3_0  (.in(in[ 3: 0]), .out(incr_3_0));
incr4 u_incr_7_4  (.in(in[ 7: 4]), .out(incr_7_4));
incr4 u_incr_11_8 (.in(in[11: 8]), .out(incr_11_8));
incr4 u_incr_15_12(.in(in[15:12]), .out(incr_15_12));

assign out[ 3: 0] = incr_3_0;
assign out[ 7: 4] = ~all1_3_0                          ? incr_7_4   : in[7:4];
assign out[11: 8] = ~(all1_3_0 | all1_7_4)             ? incr_11_8  : in[11:8];
assign out[15:12] = ~(all1_3_0 | all1_7_4 | all1_11_8) ? incr_15_12 : in[15:12];
assign         cy = ~(all1_3_0 | all1_7_4 | all1_11_8 | all1_15_12);

endmodule: incr16
