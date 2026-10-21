/* Test of PrgCounter block, behave or struct version.
 *
 * Two instances with byte address width 6: INSN_SIZE=4 (pc is 4 bits [5:2], wraps
 * around quickly) and INSN_SIZE=1 (pc is 6 bits [5:0]). Both get the same en and
 * jump, jump_addr of INSN_SIZE=4 is the top bits of jump_addr of INSN_SIZE=1.
 * Inputs change on falling edge, after every rising edge pc is compared with model.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPrgCounter;
    localparam AW = 6;

    wire          clk;
    reg           en;
    reg           jump;
    reg  [AW-1:0] jump_addr;
    wire [AW-1:2] pc4;
    wire [AW-1:0] pc1;

    reg  [AW-1:2] model4;
    reg  [AW-1:0] model1;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]   r;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    PrgCounter #(.ADDR_WIDTH(AW), .INSN_SIZE(4)) u_prg_counter_4(
        .clk(clk), .en(en), .jump(jump), .jump_addr(jump_addr[AW-1:2]), .pc(pc4));
    PrgCounter #(.ADDR_WIDTH(AW), .INSN_SIZE(1)) u_prg_counter_1(
        .clk(clk), .en(en), .jump(jump), .jump_addr(jump_addr), .pc(pc1));

    // One clock cycle: set inputs after falling edge, check after rising edge.
    task cycle(input integer step, input e, input j, input [AW-1:0] ja);
        begin
            @(negedge clk);
            en = e; jump = j; jump_addr = ja;
            @(posedge clk);
            if (j) begin
                model4 = ja[AW-1:2];
                model1 = ja;
            end else if (e) begin
                model4 = model4 + 1'b1;
                model1 = model1 + 1'b1;
            end
            #1;
            if (pc4 !== model4)
                $fatal(1, "PrgCounter INSN_SIZE=4 step %0d: en=%b jump=%b jump_addr=%h got pc=%h, expected %h",
                       step, e, j, ja[AW-1:2], pc4, model4);
            if (pc1 !== model1)
                $fatal(1, "PrgCounter INSN_SIZE=1 step %0d: en=%b jump=%b jump_addr=%h got pc=%h, expected %h",
                       step, e, j, ja, pc1, model1);
        end
    endtask

    initial begin
        en = 0; jump = 0; jump_addr = 0;

        // 1. Reset is a jump: rst=1 for 3 cycles, pc is rst_addr right after.
        cycle(0, 0, 1, 6'h24);
        cycle(1, 0, 1, 6'h24);
        cycle(2, 1, 1, 6'h24);
        // 2. Count up, pc of INSN_SIZE=4 wraps around.
        for (i = 0; i < 20; i = i + 1)
            cycle(100 + i, 1, 0, 0);
        // 3. en=0 holds.
        cycle(200, 0, 0, 6'h3F);
        cycle(201, 0, 0, 6'h3F);
        // 4. Jump while en=0, then hold, then count.
        cycle(300, 0, 1, 6'h10);
        cycle(301, 0, 0, 6'h00);
        cycle(302, 1, 0, 6'h00);
        // 5. Jump to the top address, then count: both wrap around to 0.
        cycle(400, 1, 1, 6'h3F);
        cycle(401, 1, 0, 6'h00);
        cycle(402, 1, 0, 6'h00);
        // 6. Random cycles, jump is rare.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle(1000 + i, r[0], r[3:1] == 0, r[AW+7:8]);
        end

        $display("PASS");
        $finish;
    end
endmodule
