/* Test of EdgeDetector: every EDGE (falling, rising, any) with RST_VAL 0 and 1.
 *
 * in changes after the rising edge of clk, randomly; reset (rst_n=0) is two clocks at the
 * start and every 200 clocks, with in random also then. The model keeps in of the clock
 * before (RST_VAL after a clock in reset) and gives the edge of its kind; the check is in
 * every clock, before the next rising edge. In the end every instance must have seen
 * edge_detected 1 and 0, and in at the level that is not RST_VAL right after reset. 2000
 * clocks. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbEdgeDetectorCheck #(
    parameter EDGE    = 0,
    parameter RST_VAL = 1'b0
)(
    input  wire  clk,
    input  wire  rst_n,
    input  wire  in,
    input  wire  check,         // compare now: before the next rising edge
    output logic done           // every case happened
);
    wire    edge_detected;
    logic   prev;               // model: in of the clock before, RST_VAL after reset
    logic   was_reset;          // the clock before was in reset
    logic   exp;
    integer n_one;              // coverage
    integer n_zero;
    integer n_after_reset;      // in not at RST_VAL right after reset

    EdgeDetector #(.EDGE(EDGE), .RST_VAL(RST_VAL)) u_edge_detector(
        .clk, .rst_n, .in, .edge_detected);

    always @(posedge clk) begin
        prev      <= rst_n ? in : RST_VAL;
        was_reset <= !rst_n;
    end

    // A loop in initial, not always @(posedge check): blocking assignments of a testbench.
    initial begin
        done          = 1'b0;
        n_one         = 0;
        n_zero        = 0;
        n_after_reset = 0;
        forever begin
            @(posedge check);
            case (EDGE)
                0:       exp = !in && prev;
                1:       exp = in && !prev;
                default: exp = in != prev;
            endcase
            if (edge_detected !== exp)
                $fatal(1, "EdgeDetector EDGE=%0d RST_VAL=%b: in %b, before %b: got %b, expected %b",
                       EDGE, RST_VAL, in, prev, edge_detected, exp);
            if (exp)
                n_one = n_one + 1;
            else
                n_zero = n_zero + 1;
            if (was_reset && in != RST_VAL)
                n_after_reset = n_after_reset + 1;
            done = n_one > 0 && n_zero > 0 && n_after_reset > 0;
        end
    end
endmodule

module TbEdgeDetector;
    localparam N_CLOCKS = 2000;

    logic        clk;
    logic        rst_n;
    logic        in;
    logic        check;
    wire  [5:0]  done;
    integer      seed;
    // Random word, only bit 0 is used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] rnd;
    /* verilator lint_on UNUSEDSIGNAL */

    TbEdgeDetectorCheck #(.EDGE(0), .RST_VAL(1'b0)) u_check_f0(
        .clk, .rst_n, .in, .check, .done(done[0]));
    TbEdgeDetectorCheck #(.EDGE(1), .RST_VAL(1'b0)) u_check_r0(
        .clk, .rst_n, .in, .check, .done(done[1]));
    TbEdgeDetectorCheck #(.EDGE(2), .RST_VAL(1'b0)) u_check_a0(
        .clk, .rst_n, .in, .check, .done(done[2]));
    TbEdgeDetectorCheck #(.EDGE(0), .RST_VAL(1'b1)) u_check_f1(
        .clk, .rst_n, .in, .check, .done(done[3]));
    TbEdgeDetectorCheck #(.EDGE(1), .RST_VAL(1'b1)) u_check_r1(
        .clk, .rst_n, .in, .check, .done(done[4]));
    TbEdgeDetectorCheck #(.EDGE(2), .RST_VAL(1'b1)) u_check_a1(
        .clk, .rst_n, .in, .check, .done(done[5]));

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
        in    = 1'b0;
        check = 1'b0;
        seed  = 1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            #5 clk = 1'b1;
            // After the edge: in and rst_n of the next clock.
            #1;
            rnd   = $random(seed);
            in    = rnd[0];
            rst_n = k % 200 >= 2;          // two clocks of reset every 200
            #2 check = 1'b1;
            #1 check = 1'b0;
            #1 clk = 1'b0;
        end
        if (!(&done))
            $fatal(1, "EdgeDetector: a case did not happen: done %b", done);
        $finish;
    end
endmodule
