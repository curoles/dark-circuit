/* Test of UartRx: SimUartTx's line into it, with glitches.
 *
 * A tick every T clocks, so a bit is 16 * T clocks (SimUartTx's CLKS_PER_BIT). N frames of
 * random bytes, each pushed when SimUartTx's queue is empty, with a gap of 0 to 3 idle bits;
 * one in 12 has a stop bit 0 (a framing error), one in 12 a wrong parity bit (with parity).
 * Glitches: the line inverted for one clock (one sample at most, of the three of a bit), at
 * least 8 * T clocks apart, inside frames and on the idle line (only far from the next start
 * bit, more than 20 * T clocks of the gap left: a glitch just before a start bit could start
 * the frame early). UartRx must give every frame, in order: its byte, frame_err for a stop
 * bit 0, parity_err for a wrong parity bit, nothing for a glitch. Every case must happen: a
 * glitch inside a frame, one on the idle line, a framing error, a parity error (with parity).
 * Formats: T 1 8N1, T 3 7E2, T 2 5O1, T 1 6N2. N is 300 on Verilator, 60 on Icarus. Stops at
 * the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbUartRxCheck import UartPkg::*; #(
    parameter T         = 1,        // clocks of a tick
    parameter DATA_BITS = 8,
    parameter PARITY    = 0,
    parameter STOP_BITS = 1
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N = 300;
`else
    localparam N = 60;
`endif
    localparam [7:0] MASK  = 8'((1 << DATA_BITS) - 1);
    localparam NBITS = 1 + DATA_BITS + (PARITY != 0 ? 1 : 0) + STOP_BITS;

    int         tick_n;             // clocks since the last tick
    wire        tick;
    data_bits_t data_bits;
    parity_e    parity;
    wire        line;               // SimUartTx's line
    logic       glitch;             // inverts the line for one clock
    wire        rx;
    wire        out_valid;
    wire  [7:0] out_data;
    wire        frame_err;
    wire        parity_err;
    logic [9:0] expected[$];        // {parity_err, frame_err, data} of every frame sent
    logic [9:0] got[$];
    int         since_glitch;       // clocks since the last glitch
    int         n_glitch_frame, n_glitch_idle, n_frame_err, n_parity_err;
    integer     seed;

    always @(posedge clk)
        if (!rst_n) tick_n <= 0;
        else        tick_n <= (tick_n == T - 1) ? 0 : tick_n + 1;
    assign tick      = tick_n == T - 1;
    assign data_bits = data_bits_t'(DATA_BITS - 5);
    assign parity    = parity_e'(PARITY);
    assign rx        = line ^ glitch;

    SimUartTx #(.CLKS_PER_BIT(16 * T), .DATA_BITS(DATA_BITS), .PARITY(PARITY),
                .STOP_BITS(STOP_BITS)) u_tx(.clk, .rst_n, .tx(line));
    UartRx u_uart_rx(.clk, .rst_n, .tick, .data_bits, .parity, .rx, .out_valid, .out_data,
                     .frame_err, .parity_err);

    always @(posedge clk)
        if (rst_n && out_valid)
            got.push_back({parity_err, frame_err, out_data});

    // Glitches, changed at the falling edge: one clock long, sampled once. Not in the last bit
    // of a frame: the receiver is idle in the second half of the stop bit, and a glitch there
    // could start a false frame just before a start bit that follows at once.
    initial begin
        integer gseed;
        gseed          = 64 * T + DATA_BITS;
        glitch         = 1'b0;
        since_glitch   = 0;
        n_glitch_frame = 0;
        n_glitch_idle  = 0;
        @(posedge rst_n);
        forever begin
            @(negedge clk);
            glitch       = 1'b0;
            since_glitch = since_glitch + 1;
            if (since_glitch > 8 * T && $unsigned($random(gseed)) % (16 * T) == 0) begin
                if (u_tx.busy && u_tx.bit_n < NBITS - 1) begin
                    glitch         = 1'b1;
                    n_glitch_frame = n_glitch_frame + 1;
                    since_glitch   = 0;
                end else if (!u_tx.busy && u_tx.idle_left > 20 * T) begin
                    glitch        = 1'b1;
                    n_glitch_idle = n_glitch_idle + 1;
                    since_glitch  = 0;
                end
            end
        end
    end

    initial begin
        int         limit;
        logic [7:0] b;
        bit         bad_stop;
        bit         bad_parity;
        done         = 1'b0;
        seed         = 32 * T + DATA_BITS;
        n_frame_err  = 0;
        n_parity_err = 0;
        @(posedge rst_n);
        for (int k = 0; k < N; k++) begin
            while (u_tx.queue.size() != 0)
                @(posedge clk);
            u_tx.gap   = $unsigned($random(seed)) % 4;
            b          = 8'($random(seed)) & MASK;
            bad_stop   = $unsigned($random(seed)) % 12 == 0;
            bad_parity = PARITY != 0 && $unsigned($random(seed)) % 12 == 0;
            u_tx.push_bad(b, bad_stop, bad_parity);
            expected.push_back({bad_parity, bad_stop, b});
            if (bad_stop)   n_frame_err  = n_frame_err + 1;
            if (bad_parity) n_parity_err = n_parity_err + 1;
        end
        limit = (N + 4) * (NBITS + 4) * 16 * T;
        while (!u_tx.idle() || got.size() < N) begin
            @(posedge clk);
            limit = limit - 1;
            if (limit == 0)
                $fatal(1, "UartRx %0d/%0d: got %0d of %0d frames", DATA_BITS, T, got.size(), N);
        end
        repeat (32 * T) @(posedge clk);             // nothing more may come
        if (got.size() != N)
            $fatal(1, "UartRx %0d/%0d: %0d frames, sent %0d", DATA_BITS, T, got.size(), N);
        foreach (expected[i])
            if (got[i] !== expected[i])
                $fatal(1, "UartRx %0d/%0d: frame %0d {perr, ferr, data} %h, expected %h",
                       DATA_BITS, T, i, got[i], expected[i]);
        if (n_glitch_frame == 0 || n_glitch_idle == 0 || n_frame_err == 0 ||
            (PARITY != 0 && n_parity_err == 0))
            $fatal(1, "UartRx %0d/%0d: glitches in frames %0d, idle %0d, framing %0d, parity %0d",
                   DATA_BITS, T, n_glitch_frame, n_glitch_idle, n_frame_err, n_parity_err);
        done = 1'b1;
    end
endmodule

module TbUartRx;
    logic clk;
    logic rst_n;
    wire  done_8n1, done_7e2, done_5o1, done_6n2;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbUartRxCheck #(.T(1), .DATA_BITS(8), .PARITY(0), .STOP_BITS(1)) u_check_8n1(
        .clk, .rst_n, .done(done_8n1));
    TbUartRxCheck #(.T(3), .DATA_BITS(7), .PARITY(1), .STOP_BITS(2)) u_check_7e2(
        .clk, .rst_n, .done(done_7e2));
    TbUartRxCheck #(.T(2), .DATA_BITS(5), .PARITY(2), .STOP_BITS(1)) u_check_5o1(
        .clk, .rst_n, .done(done_5o1));
    TbUartRxCheck #(.T(1), .DATA_BITS(6), .PARITY(0), .STOP_BITS(2)) u_check_6n2(
        .clk, .rst_n, .done(done_6n2));

    initial begin
        wait (done_8n1 && done_7e2 && done_5o1 && done_6n2);
        $display("PASS");
        $finish;
    end
endmodule
