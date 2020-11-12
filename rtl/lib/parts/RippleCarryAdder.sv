/*
 *
 *
 *
 *
 *
 *
 *
 * - [Fast Ripple-Carry Adders in Standard-Cell CMOS VLSI](https://www.computer.org/csdl/pds/api/csdl/proceedings/download-article/12OmNyfvpTj/pdf)
 * -[CMOS Binary Full Adder, A Survey of Possible Implementations](http://web.engr.uky.edu/~elias/projects/10.pdf)
 *
 *
 */
module RippleCarryAdder #(
    parameter WIDTH
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,
    output wire             co,
    output wire [WIDTH-1:0] sum
);

    wire [WIDTH:0] carry;
    assign carry[0] = ci;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : fa_gen
            FullAdderAOI fa_(
                .in1(in1[i]),
                .in2(in2[i]),
                .ci (carry[i]),
                .sum(sum[i]),
                .co (carry[i+1])
            );
        end
    endgenerate

endmodule
