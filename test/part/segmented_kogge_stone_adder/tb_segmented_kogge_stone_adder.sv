/* Test of SegmentedKoggeStoneAdder: sum and carry of every bit, segment by segment, for WIDTH
 * 5 and 32.
 *
 * The model walks the bits from 0 up: a bit that starts a segment (bit 0, or cut set) takes
 * ci, any other the carry out of the bit below; it gives the sum bit and its carry out.
 * WIDTH 5: exhaustive, every in1, in2, ci and cut. WIDTH 32: cut masks of packed SIMD (lanes
 * of 8, 16, 32 bits), operands that carry through whole segments, random cut masks and
 * operands. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbSegmentedKoggeStoneAdder;
`ifdef VERILATOR
    localparam int RANDOM_CASES = 100000;
`else
    localparam int RANDOM_CASES = 300;
`endif

    logic [4:0]  a5;
    logic [4:0]  b5;
    logic [4:0]  cut5;
    logic [4:0]  carry5;
    logic [4:0]  sum5;
    logic [31:0] a32;
    logic [31:0] b32;
    logic [31:0] cut32;
    logic [31:0] carry32;
    logic [31:0] sum32;
    logic        ci;

    SegmentedKoggeStoneAdder #(.WIDTH(5)) u_adder_5(
        .in1(a5), .in2(b5), .ci, .cut(cut5), .carry(carry5), .sum(sum5));
    SegmentedKoggeStoneAdder #(.WIDTH(32)) u_adder_32(
        .in1(a32), .in2(b32), .ci, .cut(cut32), .carry(carry32), .sum(sum32));

    // The model: {carry, sum} of WIDTH bits (at most 32), bit by bit.
    function automatic logic [63:0] model(input int width, input logic [31:0] x,
                                          input logic [31:0] y, input logic c_in,
                                          input logic [31:0] cuts);
        logic [31:0] s;
        logic [31:0] c;
        logic        cin;
        s = '0;
        c = '0;
        for (int i = 0; i < width; i++) begin
            cin  = (i == 0 || cuts[i]) ? c_in : c[i-1];
            s[i] = x[i] ^ y[i] ^ cin;
            c[i] = (x[i] & y[i]) | (x[i] & cin) | (y[i] & cin);
        end
        return {c, s};
    endfunction

    task automatic check32;
        logic [63:0] exp;
        #1;
        exp = model(32, a32, b32, ci, cut32);
        if (sum32 !== exp[31:0] || carry32 !== exp[63:32])
            $fatal(1, "SegmentedKoggeStoneAdder 32: %h + %h + %b cut %h -> sum %h carry %h, expected %h %h",
                   a32, b32, ci, cut32, sum32, carry32, exp[31:0], exp[63:32]);
    endtask

    initial begin
        // The model's 32 bits of sum and carry; WIDTH 5 uses 5 of each.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [63:0] exp;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [31:0] lanes [3];
        lanes[0] = 32'h0101_0100;   // 8-bit lanes: cuts at 8, 16, 24
        lanes[1] = 32'h0001_0000;   // 16-bit lanes: cut at 16
        lanes[2] = 32'h0000_0000;   // one 32-bit lane

        // WIDTH 5: everything.
        for (int x = 0; x < 32; x++)
            for (int y = 0; y < 32; y++)
                for (int c = 0; c < 2; c++)
                    for (int k = 0; k < 32; k++) begin
                        a5   = 5'(x);
                        b5   = 5'(y);
                        ci   = c[0];
                        cut5 = 5'(k);
                        #1;
                        exp = model(5, 32'(a5), 32'(b5), ci, 32'(cut5));
                        if (sum5 !== exp[4:0] || carry5 !== exp[36:32])
                            $fatal(1, "SegmentedKoggeStoneAdder 5: %h + %h + %b cut %b -> sum %h carry %b, expected %h %b",
                                   a5, b5, ci, cut5, sum5, carry5, exp[4:0], exp[36:32]);
                    end

        // WIDTH 32: the lanes of packed SIMD, carries through whole segments.
        for (int l = 0; l < 3; l++)
            for (int c = 0; c < 2; c++) begin
                cut32 = lanes[l];
                ci    = c[0];
                a32 = '1;            b32 = '0;           check32();
                a32 = '1;            b32 = 32'h0101_0101; check32();
                a32 = 32'h7f7f_7f7f; b32 = 32'h0101_0101; check32();
                a32 = 32'h8080_8080; b32 = 32'h8080_8080; check32();
            end

        // WIDTH 32: random cuts and operands, and random operands on the lane cuts.
        for (int n = 0; n < RANDOM_CASES; n++) begin
            a32   = $urandom();
            b32   = $urandom();
            ci    = 1'($urandom() % 2);
            cut32 = (n % 2 == 0) ? $urandom() : lanes[n % 3];
            check32();
        end
        $display("PASS");
        $finish;
    end
endmodule
