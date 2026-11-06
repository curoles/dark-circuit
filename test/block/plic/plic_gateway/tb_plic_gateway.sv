/* Test of PlicGateway, behave or struct version, level and edge triggered.
 *
 * Model: a state machine of three states, unlike the RTL's two flops: IDLE, PENDING (ip=1),
 * SERVICE; a request (src, or its rising edge) in IDLE or in the cycle of a complete in
 * SERVICE goes to PENDING, a claim in PENDING to SERVICE, a complete in SERVICE to IDLE;
 * everything else is ignored. Inputs change after the rising edge, ip is compared with the
 * model before the next one. Stimulus: directed sequences of the cases below, then random
 * src, claims and completes (src in bursts, claims and completes mostly when they make
 * sense): 4000 cycles on Verilator, 600 on Icarus. Every case must happen (checks named
 * cover): a request, a claim, a complete, a request taken in the cycle of its complete, a
 * request ignored while active, a complete ignored while pending, a claim ignored while not
 * pending, a level that falls before the claim (it stays pending). Checks named model (ip
 * differs from the model) and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPlicGatewayCheck #(
    parameter EDGE_TRIGGERED = 0
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 4000;
`else
    localparam N_RANDOM = 600;
`endif

    typedef enum logic [1:0] { IDLE, PENDING, SERVICE } state_e;

    logic   src;
    logic   claim;
    logic   complete;
    wire    ip;
    state_e state;          // the model
    logic   src_q;          // src one cycle earlier (the model's edge)
    integer seed;
    // Coverage: how often each case happened.
    integer n_request, n_claim, n_complete, n_take_at_complete, n_ignored_request;
    integer n_ignored_complete, n_ignored_claim, n_level_fell;

    PlicGateway #(.EDGE_TRIGGERED(EDGE_TRIGGERED)) u_plic_gateway(
        .clk, .rst_n, .src, .claim, .complete, .ip);

    // The model's request: src, or its rising edge.
    wire set = EDGE_TRIGGERED ? (src && !src_q) : src;

    // The model's step at the rising edge, from the inputs of the cycle before.
    always @(posedge clk)
        if (!rst_n) begin
            state <= IDLE;
            src_q <= 1'b0;
        end else begin
            src_q <= src;
            case (state)
                IDLE: begin
                    if (set) begin
                        state     <= PENDING;
                        n_request <= n_request + 1;
                    end
                    if (claim)
                        n_ignored_claim <= n_ignored_claim + 1;
                end
                PENDING: begin
                    if (claim) begin
                        state   <= SERVICE;
                        n_claim <= n_claim + 1;
                    end
                    if (complete)
                        n_ignored_complete <= n_ignored_complete + 1;
                    if (set)
                        n_ignored_request <= n_ignored_request + 1;
                    if (!EDGE_TRIGGERED && !src)
                        n_level_fell <= n_level_fell + 1;
                end
                SERVICE: begin
                    if (complete) begin
                        n_complete <= n_complete + 1;
                        if (set) begin
                            state              <= PENDING;
                            n_take_at_complete <= n_take_at_complete + 1;
                            n_request          <= n_request + 1;
                        end else
                            state <= IDLE;
                    end else if (set)
                        n_ignored_request <= n_ignored_request + 1;
                    if (claim)
                        n_ignored_claim <= n_ignored_claim + 1;
                end
                default: state <= IDLE;
            endcase
        end

    // Before every rising edge: ip is the model's.
    always @(negedge clk)
        if (rst_n && ip !== (state == PENDING))
            `DC_TEST_FAIL(model, $sformatf("PlicGateway EDGE_TRIGGERED=%0d: ip %b in state %0d",
                                           EDGE_TRIGGERED, ip, state))

    // One cycle of inputs, set after the rising edge.
    task automatic cycle(input logic s, input logic cl, input logic co);
        src      = s;
        claim    = cl;
        complete = co;
        @(posedge clk);
        #1;
    endtask

    // A request: src 1 for a cycle (an edge, or a level), then src back to 0.
    task automatic request();
        cycle(1'b0, 1'b0, 1'b0);
        cycle(1'b1, 1'b0, 1'b0);
        cycle(1'b0, 1'b0, 1'b0);
    endtask

    initial begin
        done = 1'b0;
        {n_request, n_claim, n_complete, n_take_at_complete} = '0;
        {n_ignored_request, n_ignored_complete, n_ignored_claim, n_level_fell} = '0;
        seed = 11 + EDGE_TRIGGERED;
        {src, claim, complete} = '0;
        @(posedge rst_n);
        @(posedge clk);
        #1;
        // A claim while idle, a request, a complete before the claim, a second request while
        // pending, the claim, a request while in service, the complete.
        cycle(1'b0, 1'b1, 1'b0);
        request();
        cycle(1'b0, 1'b0, 1'b1);
        request();
        cycle(1'b0, 1'b1, 1'b0);
        request();
        cycle(1'b0, 1'b0, 1'b1);
        // A request in the cycle of the complete: src rises with complete.
        request();
        cycle(1'b0, 1'b1, 1'b0);
        cycle(1'b0, 1'b0, 1'b0);
        cycle(1'b1, 1'b0, 1'b1);
        cycle(1'b0, 1'b1, 1'b0);
        cycle(1'b0, 1'b0, 1'b1);
        // A level held at 1 through claim and complete: the next request at once.
        cycle(1'b1, 1'b0, 1'b0);
        cycle(1'b1, 1'b1, 1'b0);
        cycle(1'b1, 1'b0, 1'b1);
        cycle(1'b1, 1'b1, 1'b0);
        cycle(1'b0, 1'b0, 1'b1);
        // Random: src in bursts, claims and completes now and then.
        for (int i = 0; i < N_RANDOM; i++) begin
            logic s;
            s = ($random(seed) % 8 == 0) ? !src : src;
            cycle(s, ($random(seed) % 4) == 0, ($random(seed) % 5) == 0);
        end
        cycle(1'b0, 1'b0, 1'b0);
        if (n_request == 0 || n_claim == 0 || n_complete == 0 || n_take_at_complete == 0 ||
            n_ignored_request == 0 || n_ignored_complete == 0 || n_ignored_claim == 0 ||
            (!EDGE_TRIGGERED && n_level_fell == 0))
            `DC_TEST_FAIL(cover, $sformatf({
                "PlicGateway EDGE_TRIGGERED=%0d: request %0d claim %0d complete %0d ",
                "take at complete %0d; ignored: request %0d complete %0d claim %0d; ",
                "level fell %0d"},
                EDGE_TRIGGERED, n_request, n_claim, n_complete, n_take_at_complete,
                n_ignored_request, n_ignored_complete, n_ignored_claim, n_level_fell))
        done = 1'b1;
    end
endmodule

module TbPlicGateway;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_level;
    wire  done_edge;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbPlicGatewayCheck #(.EDGE_TRIGGERED(0)) u_check_level(.clk, .rst_n, .done(done_level));
    TbPlicGatewayCheck #(.EDGE_TRIGGERED(1)) u_check_edge (.clk, .rst_n, .done(done_edge));

    initial begin
        wait (done_level && done_edge);
        $display("PASS");
        $finish;
    end
endmodule
