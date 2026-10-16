/* One-hot Multiplexer, sel[k] selects input in<k>.
 *
 * out = (sel[0] & in0) | (sel[1] & in1) | (sel[2] & in2)
 *     = Nand2(Aoi22(in0, sel[0], in1, sel[1]), Nand2(in2, sel[2])).
 */
module Mux1hot3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [2:0]       sel,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] aoi, nand2;

    Aoi22 #(WIDTH) u_aoi22    (.in1(in0), .in2({WIDTH{sel[0]}}), .in3(in1), .in4({WIDTH{sel[1]}}), .out(aoi));
    Nand2 #(WIDTH) u_nand2_2  (.in1(in2), .in2({WIDTH{sel[2]}}), .out(nand2));
    Nand2 #(WIDTH) u_nand2_out(.in1(aoi), .in2(nand2), .out(out));

endmodule
