/* Test of DelayLine and DelayLineT, behave or struct version.
 *
 * One random 8-bit input stream, a new value after every rising edge, into instances of every
 * kind: DEPTH 0 (a wire), 1 with reset to A5, 3 of 5 bits without reset, 3 of 1 bit with reset
 * (to 0), and DelayLineT of a struct, DEPTH 2. Reset at the start and once in the middle of the
 * run. The model keeps every input and the reset of every clock: out of a line of DEPTH d at
 * clock k is the input of clock k - d; with reset, RST_VAL if reset was on in any of the clocks
 * k - d .. k - 1 (each of their rising edges cleared the stages); without reset the stages keep
 * shifting through it (checked from clock d on, when they are filled). Checked before every
 * rising edge; 300 clocks. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbDelayLine;
    localparam N_CLOCKS = 300;
    localparam RESET_AT = 150;      // the reset in the middle: clocks 150 and 151

    typedef struct packed {
        logic       valid;
        logic [2:0] kind;
        logic [3:0] data;
    } item_t;

    wire         clk;
    logic        rst_n;
    logic [7:0]  in;
    wire  [7:0]  out_0;
    wire  [7:0]  out_1r;
    wire  [4:0]  out_3;
    wire         out_3r;
    item_t       out_t;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    DelayLine  #(.WIDTH(8), .DEPTH(0)) u_wire(.clk, .rst_n, .in, .out(out_0));
    DelayLine  #(.WIDTH(8), .DEPTH(1), .RESET(1), .RST_VAL(8'hA5)) u_one_reset(
        .clk, .rst_n, .in, .out(out_1r));
    DelayLine  #(.WIDTH(5), .DEPTH(3)) u_three(.clk, .rst_n, .in(in[4:0]), .out(out_3));
    DelayLine  #(.WIDTH(1), .DEPTH(3), .RESET(1)) u_three_reset(
        .clk, .rst_n, .in(in[7]), .out(out_3r));
    DelayLineT #(.T(item_t), .DEPTH(2)) u_typed(.clk, .rst_n, .in(item_t'(in)), .out(out_t));

    logic [7:0] hist   [N_CLOCKS];  // the input of every clock
    logic       resets [N_CLOCKS];  // reset on in that clock (rst_n = 0)

    // Out of a line of DEPTH d at clock k: the input of clock k - d, or rst when the line resets
    // and reset was on in one of the clocks k - d .. k - 1 (before clock 0: reset was on).
    function automatic logic [7:0] expect_out(input integer k, input integer d,
                                             input logic reset, input logic [7:0] rst);
        if (reset)
            for (int j = k - d; j < k; j++)
                if (j < 0 || resets[j])
                    return rst;
        return hist[k - d];
    endfunction

    // Expected outputs, each of its line's width (the 5-bit line delays in[4:0], the 1-bit in[7]).
    task automatic check(input integer k);
        logic [7:0] e1r;
        logic [4:0] e3;
        logic       e3r;
        logic [7:0] et;
        e1r = expect_out(k, 1, 1'b1, 8'hA5);
        e3  = 5'(expect_out(k, 3, 1'b0, 8'h00));
        e3r = 1'(expect_out(k, 3, 1'b1, 8'h00) >> 7);
        et  = expect_out(k, 2, 1'b0, 8'h00);
        if (out_0 !== in)
            $fatal(1, "DelayLine depth 0, clock %0d: %h, expected %h", k, out_0, in);
        if (out_1r !== e1r)
            $fatal(1, "DelayLine depth 1 reset, clock %0d: %h, expected %h", k, out_1r, e1r);
        if (k >= 3 && out_3 !== e3)
            $fatal(1, "DelayLine depth 3, clock %0d: %h, expected %h", k, out_3, e3);
        if (out_3r !== e3r)
            $fatal(1, "DelayLine depth 3 reset, clock %0d: %b, expected %b", k, out_3r, e3r);
        if (k >= 2 && out_t !== item_t'(et))
            $fatal(1, "DelayLineT depth 2, clock %0d: %h, expected %h", k, out_t, et);
    endtask

    initial begin
        rst_n = 1'b0;
        in    = '0;
        for (int k = 0; k < N_CLOCKS; k++) begin
            @(negedge clk);
            rst_n     = !(k < 2 || k == RESET_AT || k == RESET_AT + 1);
            in        = 8'($random);
            hist[k]   = in;
            resets[k] = !rst_n;
            #1;
            check(k);
        end
        $display("PASS");
        $finish;
    end
endmodule
