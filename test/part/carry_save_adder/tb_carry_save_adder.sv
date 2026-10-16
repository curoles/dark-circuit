/* Exhaustive test of CarrySaveAdder.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbCarrySaveAdder;
    localparam W = 4;

    reg  [W-1:0] a;
    reg  [W-1:0] b;
    reg  [W-1:0] c;
    wire [W-1:0] ps;
    wire [W-1:0] sc;
    integer i;

    // a + b + c and ps + 2*sc, 2 bits wider to not overflow.
    wire [W+1:0] sum_abc;
    wire [W+1:0] sum_csa;
    assign sum_abc = {2'b0, a} + {2'b0, b} + {2'b0, c};
    assign sum_csa = {2'b0, ps} + {1'b0, sc, 1'b0};

    CarrySaveAdder #(.WIDTH(W)) u_carry_save_adder(.in1(a), .in2(b), .in3(c), .ps(ps), .sc(sc));

    initial begin
        for (i = 0; i < 2**(3*W); i = i + 1) begin
            {c, b, a} = i[3*W-1:0];
            #1;
            if (ps !== (a ^ b ^ c))
                $fatal(1, "CarrySaveAdder: in1=%b in2=%b in3=%b got ps=%b", a, b, c, ps);
            if (sc !== ((a & b) | (a & c) | (b & c)))
                $fatal(1, "CarrySaveAdder: in1=%b in2=%b in3=%b got sc=%b", a, b, c, sc);
            if (sum_csa !== sum_abc)
                $fatal(1, "CarrySaveAdder: in1+in2+in3=%0d, ps+2*sc=%0d", sum_abc, sum_csa);
        end
        $display("PASS");
        $finish;
    end
endmodule
