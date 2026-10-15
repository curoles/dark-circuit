/* Test of RippleCarryAdder, and of CarrySaveAdder followed by RippleCarryAdder.
 *
 * 1. RippleCarryAdder WIDTH=4, all inputs.
 * 2. RippleCarryAdder default WIDTH=64, corner cases and random inputs.
 * 3. CarrySaveAdder WIDTH=4 then RippleCarryAdder adds ps + 2*sc, all inputs: a + b + c.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbRippleCarryAdder;
    localparam W  = 4;
    localparam WW = 64;

    integer i;
    integer seed;

    // 1. RippleCarryAdder WIDTH=4.
    reg  [W-1:0] a;
    reg  [W-1:0] b;
    reg          ci;
    wire [W-1:0] sum;
    wire         co;
    wire [W:0]   exp_sum;
    assign exp_sum = {1'b0, a} + {1'b0, b} + {{W{1'b0}}, ci};

    RippleCarryAdder #(.WIDTH(W)) u_ripple_carry_adder(.in1(a), .in2(b), .ci(ci), .co(co), .sum(sum));

    // 2. RippleCarryAdder with default WIDTH=64.
    reg  [WW-1:0] wa;
    reg  [WW-1:0] wb;
    reg           wci;
    wire [WW-1:0] wsum;
    wire          wco;
    wire [WW:0]   exp_wsum;
    assign exp_wsum = {1'b0, wa} + {1'b0, wb} + {{WW{1'b0}}, wci};

    RippleCarryAdder u_ripple_carry_adder_64(.in1(wa), .in2(wb), .ci(wci), .co(wco), .sum(wsum));

    // 3. CarrySaveAdder then RippleCarryAdder: a + b + c = ps + 2*sc.
    reg  [W-1:0] c;
    wire [W-1:0] ps;
    wire [W-1:0] sc;
    wire [W:0]   sum3;
    wire         co3;
    wire [W+1:0] exp_sum3;
    assign exp_sum3 = {2'b0, a} + {2'b0, b} + {2'b0, c};

    CarrySaveAdder   #(.WIDTH(W))   u_carry_save_adder(.in1(a), .in2(b), .in3(c), .ps(ps), .sc(sc));
    RippleCarryAdder #(.WIDTH(W+1)) u_ripple_carry_adder_csa(.in1({1'b0, ps}), .in2({sc, 1'b0}), .ci(1'b0),
                                                             .co(co3), .sum(sum3));

    task check64(input [WW-1:0] x, input [WW-1:0] y, input z);
        begin
            wa = x; wb = y; wci = z;
            #1;
            if ({wco, wsum} !== exp_wsum)
                $fatal(1, "RippleCarryAdder 64: in1=%h in2=%h ci=%b got co=%b sum=%h, expected %h",
                       wa, wb, wci, wco, wsum, exp_wsum);
        end
    endtask

    initial begin
        c = 0;
        wa = 0; wb = 0; wci = 0;

        // 1. All inputs of 4-bit adder.
        for (i = 0; i < 2**(2*W+1); i = i + 1) begin
            {ci, b, a} = i[2*W:0];
            #1;
            if ({co, sum} !== exp_sum)
                $fatal(1, "RippleCarryAdder: in1=%b in2=%b ci=%b got co=%b sum=%b", a, b, ci, co, sum);
        end

        // 2. 64-bit adder: carry through all bits, then random inputs.
        check64({WW{1'b1}}, {{(WW-1){1'b0}}, 1'b1}, 1'b0);
        check64({WW{1'b1}}, {WW{1'b0}}, 1'b1);
        check64({WW{1'b1}}, {WW{1'b1}}, 1'b1);
        check64({WW{1'b0}}, {WW{1'b0}}, 1'b0);
        check64({(WW/2){2'b01}}, {(WW/2){2'b10}}, 1'b1);
        seed = 1;
        for (i = 0; i < 1000; i = i + 1)
            check64({$random(seed), $random(seed)}, {$random(seed), $random(seed)}, i[0]);

        // 3. All inputs of CarrySaveAdder followed by RippleCarryAdder.
        ci = 0;
        for (i = 0; i < 2**(3*W); i = i + 1) begin
            {c, b, a} = i[3*W-1:0];
            #1;
            if ({co3, sum3} !== exp_sum3)
                $fatal(1, "CarrySaveAdder+RippleCarryAdder: a=%0d b=%0d c=%0d got %0d, expected %0d",
                       a, b, c, {co3, sum3}, exp_sum3);
        end

        $display("PASS");
        $finish;
    end
endmodule
