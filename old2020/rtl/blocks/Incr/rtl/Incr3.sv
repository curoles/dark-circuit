/* 3-bit Incrementor block to be used in building Nx3 Fast Incrementor.
 *
 *
 */
module Incr3 (
    input  wire [2:0] in,
    output wire [2:0] out
);

assign out[0] = ~in[0];
assign out[1] = ~(~( in[0] & ~in[1]) &
                  ~(~in[0] &  in[1]));
assign out[2] = ~(~( in[0] &  in[1] & ~in[2]) &
                  ~(         ~in[1] &  in[2]) &
                  ~(~in[0] &  in[1] &  in[2]));

endmodule: Incr3
