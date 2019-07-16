/**@file
* @author    Igor Lesik 2019
* @copyright Igor Lesik 2019
*
* References:
* - https://preserve.lehigh.edu/cgi/viewcontent.cgi?referer=&httpsredir=1&article=1714&context=etd
* - http://rtlery.com/components/barrel-shifter
*/

module BarrelShifter #(
    parameter WIDTH,
    parameter SHFT_WIDTH = `CLOG(WIDTH) // number of shift/rotate bits
)(
    input  wire [WIDTH-1:0] in,
    input  wire [SHFT_WIDTH-1:0] shift, // number of shifts
    input  wire shift_rotate,
    input  wire left_right,
    output wire [WIDTH-1:0] out
);

wire [WIDTH-1:0] ain; // "in" or reversed "in"

wire [WIDTH-1:0] sh; // result of shifting

// The direction of the rotate operation is implemented by reversing
// the input (and output) vector.
generate: reverse_vectors
    genvar i;
    for (i = 0; i < WIDTH; i = i + 1)
    begin: gen_reverse
        Mux mux_reverse_in_  #(.WIDTH(1))(.in1(in[i]), .in2(in[WIDTH-1-i]), .sel(left_right), .out(ain[i]));
        Mux mux_reverse_out_ #(.WIDTH(1))(.in1(sh[i]), .in2(sh[WIDTH-1-i]), .sel(left_right), .out(out[i]));
    end: gen_reverse
endgenerate



endmodule: BarrelShifter
