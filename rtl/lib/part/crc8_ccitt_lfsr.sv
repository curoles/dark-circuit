module Crc8CcittLfsr #(
    localparam WIDTH = 8,
    parameter INIT = WIDTH'hFF
)(
    input wire clk,
    input wire rst_n,
    input wire din,
    input wire init_crc,
    input wire calc_crc,
    output wire [WIDTH-1:0] crc
);

    wire [WIDTH-1:0] crc_val, crc_calc, crc_next;
    wire init;
    wire crc7_xor_din;

    assign init = !rst_n || init_crc;
    Mux2 #(.WIDTH) u_init_vs_crc_mux(.sel(init), .in1(INIT), .in2(crc_val), .out(crc_next));

    Mux2 #(.WIDTH) u_calc_mux(.sel(calc_crc), .in1(crc_calc), .in2(crc_val), .out(crc_val));

    Dff #(.WIDTH) u_dff(.clk, .in(crc_next), .out(crc));
    
    Xor2 u_crc7_xor_din(.in1(crc[7]), in2(din), .out(crc7_xor_din));

    assign crc_calc[0] = crc7_xor_din;
    Xor2 u_crc1(.in1(crc7_xor_din), in2(crc[0]), .out(crc_calc[1]));
    Xor2 u_crc1(.in1(crc7_xor_din), in2(crc[1]), .out(crc_calc[2]));
    assign crc_calc[3] = crc[2];
    assign crc_calc[4] = crc[3];
    assign crc_calc[5] = crc[4];
    assign crc_calc[6] = crc[5];
    assign crc_calc[7] = crc[6];

endmodule
