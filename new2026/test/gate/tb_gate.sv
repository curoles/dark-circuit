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
    reg  [1:0]   sel2;
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
    wire [W-1:0] mux2i;
    wire [W-1:0] mux3;
    wire [W-1:0] mux4;
    wire [W-1:0] ha_sum;
    wire [W-1:0] ha_co;
    wire [W-1:0] fa_sum;
    wire [W-1:0] fa_co;
    wire [W-1:0] maj3;
    wire [W-1:0] benc_s;
    wire [W-1:0] benc_a;
    wire [W-1:0] benc_x2;
    wire [W-1:0] bml_pp;
    integer i;

    // Bml needs 5 inputs: its M1 is input a rotated by one bit,
    // so every bit still sees 5 independent input bits.
    wire [W-1:0] a_rot;
    assign a_rot = {a[0], a[W-1:1]};

    // Expected Bml output, from the BML cell structure.
    wire [W-1:0] bml_m1_sel_n;
    wire [W-1:0] bml_m0_sel_n;
    wire [W-1:0] bml_exp;
    assign bml_m1_sel_n = ~((~b & a_rot) | (~c & ~a_rot));
    assign bml_m0_sel_n = ~((~b & d) | (~c & ~d));
    assign bml_exp = ~((~a & bml_m1_sel_n) | (a & bml_m0_sel_n));

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
    Mux2  #(W) u_mux2 (.in0(a), .in1(b), .sel(sel2[0]), .out(mux2));
    Mux2i #(W) u_mux2i(.in0(a), .in1(b), .sel(sel2[0]), .out(mux2i));
    Mux3  #(W) u_mux3 (.in0(a), .in1(b), .in2(c), .sel(sel2), .out(mux3));
    Mux4  #(W) u_mux4 (.in0(a), .in1(b), .in2(c), .in3(d), .sel(sel2), .out(mux4));
    HalfAdder #(W) u_half_adder(.in1(a), .in2(b), .sum(ha_sum), .co(ha_co));
    FullAdder #(W) u_full_adder(.in1(a), .in2(b), .ci(c), .sum(fa_sum), .co(fa_co));
    Maj3  #(W) u_maj3 (.in1(a), .in2(b), .in3(c), .out(maj3));
    Benc  #(W) u_benc (.M0(a), .M1(b), .M2(c), .S(benc_s), .A(benc_a), .X2(benc_x2));
    Bml   #(W) u_bml  (.X2(a), .A(b), .S(c), .M0(d), .M1(a_rot), .PP(bml_pp));

    initial begin
        for (i = 0; i < 2**(4*W+2); i = i + 1) begin
            {sel2, d, c, b, a} = i;
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
            if (mux2  !== (sel2[0] ? b : a))
                $fatal(1, "Mux2: in0=%b in1=%b sel=%b got=%b", a, b, sel2[0], mux2);
            if (mux2i !== ~(sel2[0] ? b : a))
                $fatal(1, "Mux2i: in0=%b in1=%b sel=%b got=%b", a, b, sel2[0], mux2i);
            if (mux3  !== ((sel2 == 0) ? a : (sel2 == 1) ? b : c))
                $fatal(1, "Mux3: in0=%b in1=%b in2=%b sel=%b got=%b", a, b, c, sel2, mux3);
            if (mux4  !== ((sel2 == 0) ? a : (sel2 == 1) ? b : (sel2 == 2) ? c : d))
                $fatal(1, "Mux4: in0=%b in1=%b in2=%b in3=%b sel=%b got=%b", a, b, c, d, sel2, mux4);
            if (ha_sum !== (a ^ b) || ha_co !== (a & b))
                $fatal(1, "HalfAdder: a=%b b=%b got sum=%b co=%b", a, b, ha_sum, ha_co);
            if (fa_sum !== (a ^ b ^ c) || fa_co !== ((a & b) | (c & (a | b))))
                $fatal(1, "FullAdder: a=%b b=%b ci=%b got sum=%b co=%b", a, b, c, fa_sum, fa_co);
            if (maj3 !== ((a & b) | (a & c) | (b & c)))
                $fatal(1, "Maj3: a=%b b=%b c=%b got=%b", a, b, c, maj3);
            if (benc_s  !== ~(c & ~(b & a)) ||
                benc_a  !== ~(~c & (b | a)) ||
                benc_x2 !== ~(b ^ a))
                $fatal(1, "Benc: M0=%b M1=%b M2=%b got S=%b A=%b X2=%b", a, b, c, benc_s, benc_a, benc_x2);
            if (bml_pp !== bml_exp)
                $fatal(1, "Bml: X2=%b A=%b S=%b M0=%b M1=%b got=%b", a, b, c, d, a_rot, bml_pp);
        end
        $display("PASS");
        $finish;
    end
endmodule
