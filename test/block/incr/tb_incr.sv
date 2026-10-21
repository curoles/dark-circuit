/* Test of Incr block, behave or struct version.
 *
 * Exhaustive for every instance:
 *   WIDTH=16, GROUP=4  old Incr16
 *   WIDTH=9,  GROUP=3  old Incr9
 *   WIDTH=7,  GROUP=3  last group is shorter
 *   WIDTH=5,  GROUP=8  one group, shorter than GROUP
 *   WIDTH=1,  GROUP=4
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbIncr;
    reg  [15:0] in;
    wire [15:0] out16;
    wire        co16;
    wire [8:0]  out9;
    wire        co9;
    wire [6:0]  out7;
    wire        co7;
    wire [4:0]  out5;
    wire        co5;
    wire        out1;
    wire        co1;
    integer i;

    Incr #(.WIDTH(16), .GROUP(4)) u_incr_16(.in(in),       .out(out16), .co(co16));
    Incr #(.WIDTH(9),  .GROUP(3)) u_incr_9 (.in(in[8:0]),  .out(out9),  .co(co9));
    Incr #(.WIDTH(7),  .GROUP(3)) u_incr_7 (.in(in[6:0]),  .out(out7),  .co(co7));
    Incr #(.WIDTH(5),  .GROUP(8)) u_incr_5 (.in(in[4:0]),  .out(out5),  .co(co5));
    Incr #(.WIDTH(1),  .GROUP(4)) u_incr_1 (.in(in[0]),    .out(out1),  .co(co1));

    initial begin
        for (i = 0; i < (1 << 16); i = i + 1) begin
            in = i[15:0];
            #1;
            if ({co16, out16} !== {1'b0, in} + 17'd1)
                $fatal(1, "Incr 16: in=%h got co=%b out=%h", in, co16, out16);
            if ({co9, out9} !== {1'b0, in[8:0]} + 10'd1)
                $fatal(1, "Incr 9: in=%h got co=%b out=%h", in[8:0], co9, out9);
            if ({co7, out7} !== {1'b0, in[6:0]} + 8'd1)
                $fatal(1, "Incr 7: in=%h got co=%b out=%h", in[6:0], co7, out7);
            if ({co5, out5} !== {1'b0, in[4:0]} + 6'd1)
                $fatal(1, "Incr 5: in=%h got co=%b out=%h", in[4:0], co5, out5);
            if ({co1, out1} !== {1'b0, in[0]} + 2'd1)
                $fatal(1, "Incr 1: in=%b got co=%b out=%b", in[0], co1, out1);
        end

        $display("PASS");
        $finish;
    end
endmodule
