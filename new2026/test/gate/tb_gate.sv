/* Exhaustive test of gates common to all gate/cell flavors.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbGate;
    localparam W = 3;

    reg  [W-1:0] a;
    reg  [W-1:0] b;
    reg  [W-1:0] c;
    reg  [W-1:0] d;
    reg          sel;
    wire [W-1:0] inv;
    wire [W-1:0] buff;
    wire [W-1:0] nand2;
    wire [W-1:0] nand3;
    wire [W-1:0] nor2;
    wire [W-1:0] nor3;
    wire [W-1:0] and2;
    wire [W-1:0] and3;
    wire [W-1:0] or2;
    wire [W-1:0] or3;
    wire [W-1:0] xor2;
    wire [W-1:0] xnor2;
    wire [W-1:0] xor3;
    wire [W-1:0] aoi21;
    wire [W-1:0] aoi22;
    wire [W-1:0] aoi31;
    wire [W-1:0] oai21;
    wire [W-1:0] oai22;
    wire [W-1:0] ind2;
    wire [W-1:0] ind3;
    wire [W-1:0] iind3;
    wire [W-1:0] mux2;
    integer i;

    Inv   #(W) u_inv  (.in(a), .out(inv));
    Buf   #(W) u_buf  (.in(a), .out(buff));
    Nand2 #(W) u_nand2(.in1(a), .in2(b), .out(nand2));
    Nand3 #(W) u_nand3(.in1(a), .in2(b), .in3(c), .out(nand3));
    Nor2  #(W) u_nor2 (.in1(a), .in2(b), .out(nor2));
    Nor3  #(W) u_nor3 (.in1(a), .in2(b), .in3(c), .out(nor3));
    And2  #(W) u_and2 (.in1(a), .in2(b), .out(and2));
    And3  #(W) u_and3 (.in1(a), .in2(b), .in3(c), .out(and3));
    Or2   #(W) u_or2  (.in1(a), .in2(b), .out(or2));
    Or3   #(W) u_or3  (.in1(a), .in2(b), .in3(c), .out(or3));
    Xor2  #(W) u_xor2 (.in1(a), .in2(b), .out(xor2));
    Xnor2 #(W) u_xnor2(.in1(a), .in2(b), .out(xnor2));
    Xor3  #(W) u_xor3 (.in1(a), .in2(b), .in3(c), .out(xor3));
    Aoi21 #(W) u_aoi21(.in1(a), .in2(b), .in3(c), .out(aoi21));
    Aoi22 #(W) u_aoi22(.in1(a), .in2(b), .in3(c), .in4(d), .out(aoi22));
    Aoi31 #(W) u_aoi31(.in1(a), .in2(b), .in3(c), .in4(d), .out(aoi31));
    Oai21 #(W) u_oai21(.in1(a), .in2(b), .in3(c), .out(oai21));
    Oai22 #(W) u_oai22(.in1(a), .in2(b), .in3(c), .in4(d), .out(oai22));
    Ind2  #(W) u_ind2 (.in1(a), .in2(b), .out(ind2));
    Ind3  #(W) u_ind3 (.in1(a), .in2(b), .in3(c), .out(ind3));
    Iind3 #(W) u_iind3(.in1(a), .in2(b), .in3(c), .out(iind3));
    Mux2  #(W) u_mux2 (.in1(a), .in2(b), .sel(sel), .out(mux2));

    initial begin
        for (i = 0; i < 2**(4*W+1); i = i + 1) begin
            {sel, d, c, b, a} = i;
            #1;
            if (inv   !== ~a)            $fatal(1, "Inv: a=%b got=%b", a, inv);
            if (buff  !== a)             $fatal(1, "Buf: a=%b got=%b", a, buff);
            if (nand2 !== ~(a & b))      $fatal(1, "Nand2: a=%b b=%b got=%b", a, b, nand2);
            if (nand3 !== ~(a & b & c))  $fatal(1, "Nand3: a=%b b=%b c=%b got=%b", a, b, c, nand3);
            if (nor2  !== ~(a | b))      $fatal(1, "Nor2: a=%b b=%b got=%b", a, b, nor2);
            if (nor3  !== ~(a | b | c))  $fatal(1, "Nor3: a=%b b=%b c=%b got=%b", a, b, c, nor3);
            if (and2  !== (a & b))       $fatal(1, "And2: a=%b b=%b got=%b", a, b, and2);
            if (and3  !== (a & b & c))   $fatal(1, "And3: a=%b b=%b c=%b got=%b", a, b, c, and3);
            if (or2   !== (a | b))       $fatal(1, "Or2: a=%b b=%b got=%b", a, b, or2);
            if (or3   !== (a | b | c))   $fatal(1, "Or3: a=%b b=%b c=%b got=%b", a, b, c, or3);
            if (xor2  !== (a ^ b))       $fatal(1, "Xor2: a=%b b=%b got=%b", a, b, xor2);
            if (xnor2 !== ~(a ^ b))      $fatal(1, "Xnor2: a=%b b=%b got=%b", a, b, xnor2);
            if (xor3  !== (a ^ b ^ c))   $fatal(1, "Xor3: a=%b b=%b c=%b got=%b", a, b, c, xor3);
            if (aoi21 !== ~((a & b) | c))
                $fatal(1, "Aoi21: a=%b b=%b c=%b got=%b", a, b, c, aoi21);
            if (aoi22 !== ~((a & b) | (c & d)))
                $fatal(1, "Aoi22: a=%b b=%b c=%b d=%b got=%b", a, b, c, d, aoi22);
            if (aoi31 !== ~((a & b & c) | d))
                $fatal(1, "Aoi31: a=%b b=%b c=%b d=%b got=%b", a, b, c, d, aoi31);
            if (oai21 !== ~((a | b) & c))
                $fatal(1, "Oai21: a=%b b=%b c=%b got=%b", a, b, c, oai21);
            if (oai22 !== ~((a | b) & (c | d)))
                $fatal(1, "Oai22: a=%b b=%b c=%b d=%b got=%b", a, b, c, d, oai22);
            if (ind2  !== ~(~a & b))
                $fatal(1, "Ind2: a=%b b=%b got=%b", a, b, ind2);
            if (ind3  !== ~(~a & b & c))
                $fatal(1, "Ind3: a=%b b=%b c=%b got=%b", a, b, c, ind3);
            if (iind3 !== ~(~a & ~b & c))
                $fatal(1, "Iind3: a=%b b=%b c=%b got=%b", a, b, c, iind3);
            if (mux2  !== (sel ? a : b)) $fatal(1, "Mux2: a=%b b=%b sel=%b got=%b", a, b, sel, mux2);
        end
        $display("PASS");
        $finish;
    end
endmodule
