

/**
 *
 *
 */
module Encoder8_3(
    input  wire [8-1:0]  in,
    output wire [3-1:0]  out
);

localparam SIZE = 3;
localparam WIDTH = 1 << SIZE;

assign out = enc(in);

function [SIZE-1:0] enc(input [WIDTH-1:0] d);
    casex (d)
        8'b1xxxxxxx: enc = 3'd7;
        8'b01xxxxxx: enc = 3'd6;
        8'b001xxxxx: enc = 3'd5;
        8'b0001xxxx: enc = 3'd4;
        8'b00001xxx: enc = 3'd3;
        8'b000001xx: enc = 3'd2;
        8'b0000001x: enc = 3'd1;
        default:     enc = 3'd0;
    endcase
endfunction

endmodule
