/* Test of sequential gates common to all gate/cell flavors.
 *
 * Inputs change while clk is 0, away from the rising edge.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbGateSeq;
    localparam W = 3;
    localparam [W-1:0] RST_VAL = 3'b101;

    reg          clk;
    reg          rst_n;
    reg          en;
    reg          srst_n; // synchronous reset
    reg          en2;    // enable of flops with enable
    reg  [W-1:0] d;
    reg  [W-1:0] held;
    wire [W-1:0] dff_q;
    wire [W-1:0] rst_q;
    wire [W-1:0] latch_q;
    wire [W-1:0] srst_q;
    wire [W-1:0] srst_en_q;
    wire [W-1:0] rst_en_q;
    integer i;

    Dff         #(.WIDTH(W))                   u_dff  (.clk(clk), .in(d), .out(dff_q));
    DffAsyncRst #(.WIDTH(W), .RST_VAL(RST_VAL)) u_rst  (.clk(clk), .rst_n(rst_n), .in(d), .out(rst_q));
    Latch       #(.WIDTH(W))                   u_latch(.in(d), .enable(en), .out(latch_q));

    DffSyncRst    #(.WIDTH(W), .RST_VAL(RST_VAL)) u_srst   (.clk(clk), .rst_n(srst_n), .in(d), .out(srst_q));
    DffSyncRstEn  #(.WIDTH(W))                   u_srst_en(.clk(clk), .rst_n(srst_n), .en(en2), .in(d), .out(srst_en_q));
    DffAsyncRstEn #(.WIDTH(W), .RST_VAL(RST_VAL)) u_rst_en (.clk(clk), .rst_n(rst_n), .en(en2), .in(d), .out(rst_en_q));

    initial begin
        clk = 0; rst_n = 1; en = 0; srst_n = 1; en2 = 0; d = 0;
        #1;

        // Nothing is known before the first clock, reset or enable.
`ifndef VERILATOR  // 2-state simulator: flops start at 0, not x
        if (dff_q     !== {W{1'bx}}) $fatal(1, "Dff: before first clock got=%b, expected x", dff_q);
        if (rst_q     !== {W{1'bx}}) $fatal(1, "DffAsyncRst: before reset got=%b, expected x", rst_q);
        if (latch_q   !== {W{1'bx}}) $fatal(1, "Latch: before enable got=%b, expected x", latch_q);
        if (srst_q    !== {W{1'bx}}) $fatal(1, "DffSyncRst: before first clock got=%b, expected x", srst_q);
        if (srst_en_q !== {W{1'bx}}) $fatal(1, "DffSyncRstEn: before first clock got=%b, expected x", srst_en_q);
        if (rst_en_q  !== {W{1'bx}}) $fatal(1, "DffAsyncRstEn: before reset got=%b, expected x", rst_en_q);
`endif

        // Latch is transparent while enable is 1 ...
        en = 1;
        for (i = 0; i < 2**W; i = i + 1) begin
            d = i[W-1:0]; #1;
            if (latch_q !== d) $fatal(1, "Latch: enable=1 in=%b got=%b", d, latch_q);
        end
        // ... and holds while enable is 0.
        en = 0; #1;
        held = d;
        for (i = 0; i < 2**W; i = i + 1) begin
            d = i[W-1:0]; #1;
            if (latch_q !== held) $fatal(1, "Latch: enable=0 holds %b, in=%b got=%b", held, d, latch_q);
        end

        // Reset takes effect without clock.
        rst_n = 0; #1;
        if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: rst_n=0 got=%b, expected %b", rst_q, RST_VAL);

        // Dff captures every value on rising edge, DffAsyncRst stays in reset.
        for (i = 0; i < 2**W; i = i + 1) begin
            #2 d = i[W-1:0];
            #3 clk = 1;
            #1;
            if (dff_q !== d)       $fatal(1, "Dff: in=%b got=%b", d, dff_q);
            if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: in reset, clock edge changed it to %b", rst_q);
            #4 clk = 0;
        end

        // Release reset between edges, then DffAsyncRst captures like Dff.
        #2 rst_n = 1;
        for (i = 0; i < 2**W; i = i + 1) begin
            #2 d = ~i[W-1:0];
            #3 clk = 1;
            #1;
            if (dff_q !== d) $fatal(1, "Dff: in=%b got=%b", d, dff_q);
            if (rst_q !== d) $fatal(1, "DffAsyncRst: in=%b got=%b", d, rst_q);
            #4 clk = 0;
        end

        // Reset in the middle of a cycle while clk is 0 ...
        #2 rst_n = 0; #1;
        if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: reset while clk=0 got=%b, expected %b", rst_q, RST_VAL);
        #2 rst_n = 1;

        // ... and while clk is 1.
        #2 d = ~RST_VAL;
        #3 clk = 1;
        #1;
        if (rst_q !== ~RST_VAL) $fatal(1, "DffAsyncRst: in=%b got=%b", ~RST_VAL, rst_q);
        rst_n = 0; #1;
        if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: reset while clk=1 got=%b, expected %b", rst_q, RST_VAL);
        #3 clk = 0;

        // Flops with enable capture while en2 is 1.
        #2 rst_n = 1; srst_n = 1; en2 = 1; d = 3'b011;
        #3 clk = 1;
        #1;
        if (srst_q    !== d) $fatal(1, "DffSyncRst: in=%b got=%b", d, srst_q);
        if (srst_en_q !== d) $fatal(1, "DffSyncRstEn: en=1 in=%b got=%b", d, srst_en_q);
        if (rst_en_q  !== d) $fatal(1, "DffAsyncRstEn: en=1 in=%b got=%b", d, rst_en_q);
        #4 clk = 0;

        // Synchronous reset changes nothing until rising edge ...
        #2 srst_n = 0; #1;
        if (srst_q !== 3'b011 || srst_en_q !== 3'b011)
            $fatal(1, "DffSyncRst/En: srst_n=0 without clock got %b/%b, expected 011", srst_q, srst_en_q);
        // ... and resets on rising edge: DffSyncRst to RST_VAL, DffSyncRstEn to default 0.
        #2 clk = 1;
        #1;
        if (srst_q !== RST_VAL || srst_en_q !== 0)
            $fatal(1, "DffSyncRst/En: srst_n=0 at clock edge got %b/%b, expected %b/000", srst_q, srst_en_q, RST_VAL);
        #4 clk = 0;

        // Flops with enable hold while en2 is 0.
        #2 srst_n = 1; en2 = 0; d = 3'b110;
        #3 clk = 1;
        #1;
        if (srst_q    !== d)      $fatal(1, "DffSyncRst: after reset in=%b got=%b", d, srst_q);
        if (srst_en_q !== 3'b000) $fatal(1, "DffSyncRstEn: en=0 holds 000, got=%b", srst_en_q);
        if (rst_en_q  !== 3'b011) $fatal(1, "DffAsyncRstEn: en=0 holds 011, got=%b", rst_en_q);
        #4 clk = 0;
        #2 en2 = 1;
        #3 clk = 1;
        #1;
        if (srst_en_q !== d) $fatal(1, "DffSyncRstEn: en=1 in=%b got=%b", d, srst_en_q);
        if (rst_en_q  !== d) $fatal(1, "DffAsyncRstEn: en=1 in=%b got=%b", d, rst_en_q);
        #4 clk = 0;

        // Synchronous reset wins over en2=0.
        #2 en2 = 0; srst_n = 0;
        #3 clk = 1;
        #1;
        if (srst_en_q !== 0) $fatal(1, "DffSyncRstEn: srst_n=0 en=0 at clock edge got=%b, expected 000", srst_en_q);
        #4 clk = 0;

        // Asynchronous reset with en2=0 takes effect without clock.
        #2 srst_n = 1; rst_n = 0; #1;
        if (rst_en_q !== RST_VAL)
            $fatal(1, "DffAsyncRstEn: rst_n=0 en=0 got=%b, expected %b", rst_en_q, RST_VAL);

        $display("PASS");
        $finish;
    end
endmodule
