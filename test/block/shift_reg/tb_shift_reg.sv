/* Test of ShiftReg block, behave or struct version.
 *
 * 1. WIDTH=32: load 0x1234567F, then shift zeros in 31 times.
 * 2. WIDTH=8: bit shifted into srl_in comes out of srl_out WIDTH-1 edges later.
 * 3. WIDTH=8: random loads and shifts checked against model.
 *
 * Inputs change on falling edge, outputs are checked after rising edge.
 * Stops at the first mismatch with $fatal.
 */
module TbShiftReg;
    localparam [31:0] INIT    = 32'h1234567F;
    localparam [15:0] PATTERN = 16'b1011_0010_1110_0101;

    wire        clk;

    reg         srl_prl32;
    reg         srl_in32;
    reg  [31:0] prl_in32;
    wire        srl_out32;
    wire [31:0] prl_out32;
    reg  [31:0] exp32;

    reg         srl_prl8;
    reg         srl_in8;
    reg  [7:0]  prl_in8;
    wire        srl_out8;
    wire [7:0]  prl_out8;
    reg  [7:0]  model8;

    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0] r;
    integer     t;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    ShiftReg #(.WIDTH(32)) u_shift_reg_32(.clk(clk), .srl_prl(srl_prl32), .srl_in(srl_in32),
                                          .prl_in(prl_in32), .srl_out(srl_out32), .prl_out(prl_out32));
    ShiftReg #(.WIDTH(8))  u_shift_reg_8 (.clk(clk), .srl_prl(srl_prl8), .srl_in(srl_in8),
                                          .prl_in(prl_in8), .srl_out(srl_out8), .prl_out(prl_out8));

    // One clock cycle of the 8-bit shift register with model check.
    task cycle8(input integer step, input sp, input si, input [7:0] pi);
        begin
            @(negedge clk);
            srl_prl8 = sp; srl_in8 = si; prl_in8 = pi;
            @(posedge clk);
            model8 = sp ? {model8[6:0], si} : pi;
            #1;
            if (prl_out8 !== model8 || srl_out8 !== model8[7])
                $fatal(1, "ShiftReg 8 step %0d: srl_prl=%b srl_in=%b prl_in=%h got prl_out=%h srl_out=%b, expected %h",
                       step, sp, si, pi, prl_out8, srl_out8, model8);
        end
    endtask

    initial begin
        srl_prl32 = 0; srl_in32 = 0; prl_in32 = 0;
        srl_prl8  = 0; srl_in8  = 0; prl_in8  = 0;
        model8 = 8'h00;

        // 1. Load INIT, then shift zeros in 31 times.
        @(negedge clk);
        prl_in32 = INIT;
        @(posedge clk); #1;
        if (prl_out32 !== INIT || srl_out32 !== INIT[31])
            $fatal(1, "ShiftReg 32: load got prl_out=%h srl_out=%b, expected %h", prl_out32, srl_out32, INIT);
        @(negedge clk);
        srl_prl32 = 1; srl_in32 = 0;
        for (i = 1; i < 32; i = i + 1) begin
            @(posedge clk); #1;
            exp32 = INIT << i;
            if (prl_out32 !== exp32 || srl_out32 !== exp32[31])
                $fatal(1, "ShiftReg 32: shift %0d got prl_out=%h srl_out=%b, expected %h", i, prl_out32, srl_out32, exp32);
        end

        // 2. Load 0, then shift PATTERN in; bit shifted in at edge t is srl_out after edge t+7.
        cycle8(1, 0, 0, 8'h00);
        for (i = 0; i < 16 + 7; i = i + 1) begin
            cycle8(100 + i, 1, (i < 16) ? PATTERN[i % 16] : 1'b0, 8'h00);
            t = i - 7;
            if (t >= 0 && srl_out8 !== PATTERN[t % 16])
                $fatal(1, "ShiftReg 8: srl_out=%b at edge %0d, expected pattern bit %0d=%b", srl_out8, i, t, PATTERN[t % 16]);
        end

        // 3. Random loads and shifts.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle8(1000 + i, r[0], r[1], r[15:8]);
        end

        $display("PASS");
        $finish;
    end
endmodule
