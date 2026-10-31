/* Test of NocLinkWire.
 *
 * Random flits into src_fwd and random credits into dst_bwd, new ones after every rising edge,
 * into links of DELAY 0, 1 and 3 (3 VCs, 8 bits of data); reset at the start and once in the
 * middle of the run. The model keeps the inputs and the reset of every clock: at clock k the
 * link's outputs are its inputs of clock k - DELAY; a valid bit is 0 if reset was on in one of
 * the clocks k - DELAY .. k - 1 (each of their rising edges cleared it); a flit or a credit's vc
 * is checked while it is valid. Checked before every rising edge; 300 clocks. Stops at the
 * first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocLinkWireCheck #(
    parameter DELAY = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    input  wire  [31:0] rnd,            // random bits of this clock, the same for every link
    output logic done
);
    localparam NUM_VCS    = 3;
    localparam DATA_WIDTH = 8;
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS);
    localparam N_CLOCKS   = 300;

    typedef `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH) link_fwd_t;
    typedef `DC_NOC_LINK_BWD_T(VC_WIDTH)             link_bwd_t;

    link_fwd_t src_fwd;
    link_bwd_t src_bwd;
    link_fwd_t dst_fwd;
    link_bwd_t dst_bwd;

    NocLinkWire #(.DELAY(DELAY), .NUM_VCS(NUM_VCS), .DATA_WIDTH(DATA_WIDTH)) u_link(
        .clk, .rst_n, .src_fwd, .src_bwd, .dst_fwd, .dst_bwd);

    link_fwd_t fwd_hist [N_CLOCKS];     // the inputs of every clock
    link_bwd_t bwd_hist [N_CLOCKS];
    logic      resets   [N_CLOCKS];     // reset on in that clock

    // A valid bit at clock k: the one of clock k - DELAY, 0 when reset was on in one of the
    // clocks k - DELAY .. k - 1 (before clock 0: reset was on).
    function automatic logic expect_valid(input integer k, input logic v);
        for (int j = k - DELAY; j < k; j++)
            if (j < 0 || resets[j])
                return 1'b0;
        return v;
    endfunction

    // The inputs of DELAY clocks ago, read whole (Icarus: no field of an element of an array of
    // structs).
    link_fwd_t fwd_then;
    link_bwd_t bwd_then;

    initial begin
        done = 1'b0;
        for (int k = 0; k < N_CLOCKS; k++) begin
            @(negedge clk);
            #1;                         // after the top drives rst_n and rnd
            src_fwd     = link_fwd_t'(rnd);
            dst_bwd     = link_bwd_t'(rnd >> 16);
            fwd_hist[k] = src_fwd;
            bwd_hist[k] = dst_bwd;
            resets[k]   = !rst_n;
            #1;
            if (k >= DELAY) begin
                fwd_then = fwd_hist[k - DELAY];
                bwd_then = bwd_hist[k - DELAY];
                if (dst_fwd.valid !== expect_valid(k, fwd_then.valid) ||
                    (dst_fwd.valid && dst_fwd.flit !== fwd_then.flit))
                    $fatal(1, "NocLinkWire %0d, clock %0d: flit %b %h, expected %b %h", DELAY, k,
                           dst_fwd.valid, dst_fwd.flit, expect_valid(k, fwd_then.valid),
                           fwd_then.flit);
                if (src_bwd.valid !== expect_valid(k, bwd_then.valid) ||
                    (src_bwd.valid && src_bwd.vc !== bwd_then.vc))
                    $fatal(1, "NocLinkWire %0d, clock %0d: credit %b %0d, expected %b %0d", DELAY,
                           k, src_bwd.valid, src_bwd.vc, expect_valid(k, bwd_then.valid),
                           bwd_then.vc);
            end else if (dst_fwd.valid !== 1'b0 || src_bwd.valid !== 1'b0)
                $fatal(1, "NocLinkWire %0d, clock %0d: valid %b %b before the stages filled",
                       DELAY, k, dst_fwd.valid, src_bwd.valid);
        end
        done = 1'b1;
    end
endmodule

module TbNocLinkWire;
    localparam RESET_AT = 150;          // the reset in the middle: clocks 150 and 151

    wire         clk;
    logic        rst_n;
    logic [31:0] rnd;
    wire         done_0;
    wire         done_1;
    wire         done_3;
    integer      k;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocLinkWireCheck #(.DELAY(0)) u_check_0(.clk, .rst_n, .rnd, .done(done_0));
    TbNocLinkWireCheck #(.DELAY(1)) u_check_1(.clk, .rst_n, .rnd, .done(done_1));
    TbNocLinkWireCheck #(.DELAY(3)) u_check_3(.clk, .rst_n, .rnd, .done(done_3));

    // Reset and the random bits of each clock, right after its falling edge.
    initial begin
        rst_n = 1'b0;
        rnd   = '0;
        k     = 0;
        forever begin
            @(negedge clk);
            rst_n = !(k < 2 || k == RESET_AT || k == RESET_AT + 1);
            rnd   = $random;
            k     = k + 1;
        end
    end

    initial begin
        wait (done_0 && done_1 && done_3);
        $display("PASS");
        $finish;
    end
endmodule
