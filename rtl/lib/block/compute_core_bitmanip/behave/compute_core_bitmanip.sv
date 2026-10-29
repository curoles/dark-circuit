/* One-operand bit manipulations, behavioral, combinational: out = op(in). They are the Zbb
 * SEXT.B, SEXT.H, ZEXT.H, ORC.B, REV8, CLZ, CTZ, CPOP; the two-operand Zbb (ANDN, MIN, ROL,
 * ...) are not here, they reuse an ALU's adder, logic and shifter.
 * WIDTH is a power of 2, 16 or more. CLZ and CTZ of 0 are WIDTH.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module ComputeCoreBitmanip import ComputeCoreBitmanipPkg::*; #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] in,
    input  bm_op_e          op,
    output wire [WIDTH-1:0] out
);
    // @kb: rtl/lib/block/compute_core_bitmanip/library_block
    `DC_STATIC_ASSERT(a_width_power_of_2, WIDTH >= 16 && (WIDTH & (WIDTH - 1)) == 0)

    localparam CW = $clog2(WIDTH) + 1;      // a count 0..WIDTH

    // Functions, not always_comb: Icarus warns about constant selects in always_* processes,
    // and a function can't read its own name there, so each builds a local and returns it.
    function automatic [CW-1:0] count(input [WIDTH-1:0] x, input bm_op_e o);
        logic [CW-1:0] n;
        n = '0;
        case (o)
            BM_CLZ: begin
                n = CW'(WIDTH);
                for (int k = 0; k < WIDTH; k++)
                    if (x[k])
                        n = CW'(WIDTH - 1 - k);     // a higher bit wins
            end
            BM_CTZ: begin
                n = CW'(WIDTH);
                for (int k = WIDTH - 1; k >= 0; k--)
                    if (x[k])
                        n = CW'(k);                 // a lower bit wins
            end
            default:                                // BM_CPOP
                for (int k = 0; k < WIDTH; k++)
                    n = n + CW'(x[k]);
        endcase
        return n;
    endfunction

    function automatic [WIDTH-1:0] result(input [WIDTH-1:0] x, input bm_op_e o);
        logic [WIDTH-1:0] r;
        r = '0;
        case (o)
            BM_SEXT_B: r = {{(WIDTH - 8){x[7]}}, x[7:0]};
            BM_SEXT_H: r = {{(WIDTH - 16){x[15]}}, x[15:0]};
            BM_ZEXT_H: r = {{(WIDTH - 16){1'b0}}, x[15:0]};
            BM_ORC_B:
                for (int i = 0; i < WIDTH / 8; i++)
                    r[8*i +: 8] = {8{|x[8*i +: 8]}};
            BM_REV8:
                for (int i = 0; i < WIDTH / 8; i++)
                    r[8*i +: 8] = x[WIDTH-8-8*i +: 8];
            default:                                // BM_CLZ, BM_CTZ, BM_CPOP
                r = WIDTH'(count(x, o));
        endcase
        return r;
    endfunction

    assign out = result(in, op);

endmodule
