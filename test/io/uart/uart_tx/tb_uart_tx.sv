/* Test of UartTx: its line into SimUartRx.
 *
 * A tick every T clocks, so a bit is 16 * T clocks (SimUartRx's CLKS_PER_BIT). N random bytes
 * (the data bits of the format), each offered on the input channel after 0 to 3 idle clocks
 * and held until taken: often while a frame is still sent (it waits for in_ready). SimUartRx
 * must receive exactly them, with no framing or parity error. Every case must happen: a byte
 * that waited for the frame before it. Formats: T 1 8N1, T 3 7E2, T 2 5O1, T 1 6N2. N is 200
 * on Verilator, 40 on Icarus. Stops at the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbUartTxCheck import UartPkg::*; #(
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
    localparam N = 200;
`else
    localparam N = 40;
`endif
    localparam [7:0] MASK  = 8'((1 << DATA_BITS) - 1);
    localparam NBITS = 1 + DATA_BITS + (PARITY != 0 ? 1 : 0) + STOP_BITS;

    int         tick_n;             // clocks since the last tick
    wire        tick;
    data_bits_t data_bits;
    parity_e    parity;
    logic       in_valid;
    wire        in_ready;
    logic [7:0] in_data;
    wire        tx;
    wire        busy;
    logic [7:0] sent[$];
    integer     seed;
    bit         seen_waited;

    always @(posedge clk)
        if (!rst_n) tick_n <= 0;
        else        tick_n <= (tick_n == T - 1) ? 0 : tick_n + 1;
    assign tick      = tick_n == T - 1;
    assign data_bits = data_bits_t'(DATA_BITS - 5);
    assign parity    = parity_e'(PARITY);

    UartTx u_uart_tx(.clk, .rst_n, .tick, .data_bits, .parity, .stop2(STOP_BITS == 2),
                     .in_valid, .in_ready, .in_data, .tx, .busy);
    SimUartRx #(.CLKS_PER_BIT(16 * T), .DATA_BITS(DATA_BITS), .PARITY(PARITY),
                .STOP_BITS(STOP_BITS), .ECHO(0)) u_rx(.clk, .rst_n, .rx(tx));

    initial begin
        int limit;
        done        = 1'b0;
        seed        = 16 * T + DATA_BITS;
        seen_waited = 1'b0;
        in_valid    = 1'b0;
        in_data     = '0;
        @(posedge rst_n);
        for (int k = 0; k < N; k++) begin
            repeat ($unsigned($random(seed)) % 4)
                @(negedge clk);
            // Offer a byte at a falling edge; it is taken at the next rising edge with ready.
            @(negedge clk);
            in_valid = 1'b1;
            in_data  = 8'($random(seed)) & MASK;
            if (!in_ready)
                seen_waited = 1'b1;
            while (!in_ready)
                @(negedge clk);
            sent.push_back(in_data);
            @(negedge clk);
            in_valid = 1'b0;
        end
        limit = (NBITS + 2) * 16 * T * 4;
        while (busy || u_rx.received.size() != N) begin
            @(posedge clk);
            limit = limit - 1;
            if (limit == 0)
                $fatal(1, "UartTx %0d/%0d: received %0d of %0d", DATA_BITS, T,
                       u_rx.received.size(), N);
        end
        foreach (sent[i])
            if (u_rx.received[i] !== sent[i])
                $fatal(1, "UartTx %0d/%0d: byte %0d received %h, sent %h", DATA_BITS, T, i,
                       u_rx.received[i], sent[i]);
        if (u_rx.framing_errors != 0 || u_rx.parity_errors != 0)
            $fatal(1, "UartTx %0d/%0d: %0d framing, %0d parity errors", DATA_BITS, T,
                   u_rx.framing_errors, u_rx.parity_errors);
        if (!seen_waited)
            $fatal(1, "UartTx %0d/%0d: no byte waited for a frame", DATA_BITS, T);
        done = 1'b1;
    end
endmodule

module TbUartTx;
    logic clk;
    logic rst_n;
    wire  done_8n1, done_7e2, done_5o1, done_6n2;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbUartTxCheck #(.T(1), .DATA_BITS(8), .PARITY(0), .STOP_BITS(1)) u_check_8n1(
        .clk, .rst_n, .done(done_8n1));
    TbUartTxCheck #(.T(3), .DATA_BITS(7), .PARITY(1), .STOP_BITS(2)) u_check_7e2(
        .clk, .rst_n, .done(done_7e2));
    TbUartTxCheck #(.T(2), .DATA_BITS(5), .PARITY(2), .STOP_BITS(1)) u_check_5o1(
        .clk, .rst_n, .done(done_5o1));
    TbUartTxCheck #(.T(1), .DATA_BITS(6), .PARITY(0), .STOP_BITS(2)) u_check_6n2(
        .clk, .rst_n, .done(done_6n2));

    initial begin
        wait (done_8n1 && done_7e2 && done_5o1 && done_6n2);
        $display("PASS");
        $finish;
    end
endmodule
