/* Test of sequential gates common to all gate/cell flavors.
 *
 * Inputs change while clk is 0, away from the rising edge.
 * Stops at the first mismatch with $fatal.
 */
module TbGateSeq;
    localparam W = 3;
    localparam [W-1:0] RST_VAL = 3'b101;

    reg          clk;
    reg          rst_n;
    reg          en;
    reg  [W-1:0] d;
    reg  [W-1:0] held;
    wire [W-1:0] dff_q;
    wire [W-1:0] rst_q;
    wire [W-1:0] latch_q;
    integer i;

    Dff         #(.WIDTH(W))                   u_dff  (.clk(clk), .in(d), .out(dff_q));
    DffAsyncRst #(.WIDTH(W), .RST_VAL(RST_VAL)) u_rst  (.clk(clk), .rst_n(rst_n), .in(d), .out(rst_q));
    Latch       #(.WIDTH(W))                   u_latch(.in(d), .enable(en), .out(latch_q));

    initial begin
        clk = 0; rst_n = 1; en = 0; d = 0;
        #1;

        // Nothing is known before the first clock, reset or enable.
        if (dff_q   !== {W{1'bx}}) $fatal(1, "Dff: before first clock got=%b, expected x", dff_q);
        if (rst_q   !== {W{1'bx}}) $fatal(1, "DffAsyncRst: before reset got=%b, expected x", rst_q);
        if (latch_q !== {W{1'bx}}) $fatal(1, "Latch: before enable got=%b, expected x", latch_q);

        // Latch is transparent while enable is 1 ...
        en = 1;
        for (i = 0; i < 2**W; i = i + 1) begin
            d = i; #1;
            if (latch_q !== d) $fatal(1, "Latch: enable=1 in=%b got=%b", d, latch_q);
        end
        // ... and holds while enable is 0.
        en = 0; #1;
        held = d;
        for (i = 0; i < 2**W; i = i + 1) begin
            d = i; #1;
            if (latch_q !== held) $fatal(1, "Latch: enable=0 holds %b, in=%b got=%b", held, d, latch_q);
        end

        // Reset takes effect without clock.
        rst_n = 0; #1;
        if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: rst_n=0 got=%b, expected %b", rst_q, RST_VAL);

        // Dff captures every value on rising edge, DffAsyncRst stays in reset.
        for (i = 0; i < 2**W; i = i + 1) begin
            #2 d = i;
            #3 clk = 1;
            #1;
            if (dff_q !== d)       $fatal(1, "Dff: in=%b got=%b", d, dff_q);
            if (rst_q !== RST_VAL) $fatal(1, "DffAsyncRst: in reset, clock edge changed it to %b", rst_q);
            #4 clk = 0;
        end

        // Release reset between edges, then DffAsyncRst captures like Dff.
        #2 rst_n = 1;
        for (i = 0; i < 2**W; i = i + 1) begin
            #2 d = ~i;
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

        $display("PASS");
        $finish;
    end
endmodule
