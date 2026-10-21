/* One-hot Multiplexer, sel[k] selects input in<k>.
 *
 * out = (sel[0] & in0) | (sel[1] & in1) = ~Aoi22(in0, sel[0], in1, sel[1]).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mux1hot2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [1:0]       sel,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] aoi;

    Aoi22 #(WIDTH) u_aoi22(.in1(in0), .in2({WIDTH{sel[0]}}), .in3(in1), .in4({WIDTH{sel[1]}}), .out(aoi));
    Inv   #(WIDTH) u_inv  (.in(aoi), .out(out));

endmodule
