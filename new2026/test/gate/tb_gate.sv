/* Exhaustive test of gates common to all gate/cell flavors.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbGate;
    localparam W = 4;

    reg  [W-1:0] a;
    reg  [W-1:0] b;
    reg          sel;
    wire [W-1:0] inv;
    wire [W-1:0] nand2;
    wire [W-1:0] nor2;
    wire [W-1:0] and2;
    wire [W-1:0] mux2;
    integer i;

    Inv   #(W) u_inv  (.in(a), .out(inv));
    Nand2 #(W) u_nand2(.in1(a), .in2(b), .out(nand2));
    Nor2  #(W) u_nor2 (.in1(a), .in2(b), .out(nor2));
    And2  #(W) u_and2 (.in1(a), .in2(b), .out(and2));
    Mux2  #(W) u_mux2 (.in1(a), .in2(b), .sel(sel), .out(mux2));

    initial begin
        for (i = 0; i < 2**(2*W+1); i = i + 1) begin
            {sel, b, a} = i;
            #1;
            if (inv   !== ~a)            $fatal(1, "Inv: a=%b got=%b", a, inv);
            if (nand2 !== ~(a & b))      $fatal(1, "Nand2: a=%b b=%b got=%b", a, b, nand2);
            if (nor2  !== ~(a | b))      $fatal(1, "Nor2: a=%b b=%b got=%b", a, b, nor2);
            if (and2  !== (a & b))       $fatal(1, "And2: a=%b b=%b got=%b", a, b, and2);
            if (mux2  !== (sel ? a : b)) $fatal(1, "Mux2: a=%b b=%b sel=%b got=%b", a, b, sel, mux2);
        end
        $display("PASS");
        $finish;
    end
endmodule
