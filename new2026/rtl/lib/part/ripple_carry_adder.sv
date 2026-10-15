/* Ripple Carry Adder: {co, sum} = in1 + in2 + ci.
 *
 * Chain of full adders, carry ripples from bit 0 to bit WIDTH-1.
 *
 * - [Fast Ripple-Carry Adders in Standard-Cell CMOS VLSI](https://www.computer.org/csdl/pds/api/csdl/proceedings/download-article/12OmNyfvpTj/pdf)
 * - [CMOS Binary Full Adder, A Survey of Possible Implementations](http://web.engr.uky.edu/~elias/projects/10.pdf)
 */
module RippleCarryAdder #(
    parameter WIDTH = 64
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,  // carry in
    output wire             co,  // carry out
    output wire [WIDTH-1:0] sum
);
    // split_var: Verilator treats bits separately, no false loop through carry.
    wire [WIDTH:0] carry /*verilator split_var*/;

    assign carry[0] = ci;
    assign co = carry[WIDTH];

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        FullAdder #(1) u_full_adder(.in1(in1[i]), .in2(in2[i]), .ci(carry[i]),
                                    .sum(sum[i]), .co(carry[i+1]));
    end
    endgenerate

endmodule
