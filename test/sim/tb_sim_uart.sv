/* Test of SimUartTx and SimUartRx: each checks the other, the Tx's line into the Rx.
 *
 * Per frame format (instances below): 1. N random bytes (the DATA_BITS low bits), each pushed
 * when the Tx's queue is empty, with a random gap of 0 to 2 idle bits (0: back to back); the
 * Rx must receive exactly them, with no framing or parity error. 2. A frame with a stop bit 0,
 * then (with parity) one with a wrong parity bit, then a good one: the Rx counts one framing
 * error and one parity error and still receives all three bytes. 3. The 8-bit instance with
 * ECHO sends a string: the Rx prints it and its text is the string. Every wait has a limit.
 * Formats: 16 clocks per bit 8N1 (the string), 4 clocks 8E2, 5 clocks 7O1, 7 clocks 5N2.
 * N is 200 on Verilator, 40 on Icarus. Stops at the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbSimUartCheck #(
    parameter CLKS_PER_BIT = 16,
    parameter DATA_BITS    = 8,
    parameter PARITY       = 0,
    parameter STOP_BITS    = 1,
    parameter ECHO         = 0
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
    localparam NBITS = 1 + DATA_BITS + (PARITY != 0 ? 1 : 0) + STOP_BITS;
    localparam [7:0] MASK = 8'((1 << DATA_BITS) - 1);
    localparam STRING = "Hello, UART\n";

    wire        line;
    logic [7:0] sent[$];
    integer     seed;
    bit         seen_back_to_back;

    SimUartTx #(.CLKS_PER_BIT(CLKS_PER_BIT), .DATA_BITS(DATA_BITS), .PARITY(PARITY),
                .STOP_BITS(STOP_BITS)) u_tx(.clk, .rst_n, .tx(line));
    SimUartRx #(.CLKS_PER_BIT(CLKS_PER_BIT), .DATA_BITS(DATA_BITS), .PARITY(PARITY),
                .STOP_BITS(STOP_BITS), .ECHO(ECHO)) u_rx(.clk, .rst_n, .rx(line));

    // Wait until the Tx sent everything and the Rx has n bytes.
    task automatic wait_received(input int n);
        int limit;
        limit = (n + 4) * (NBITS + 3) * CLKS_PER_BIT;
        while (!(u_tx.idle() && u_rx.received.size() == n)) begin
            @(posedge clk);
            limit = limit - 1;
            if (limit == 0)
                $fatal(1, "SimUart %0d%0d%0d/%0d: received %0d of %0d", DATA_BITS, PARITY,
                       STOP_BITS, CLKS_PER_BIT, u_rx.received.size(), n);
        end
    endtask

    task automatic check_received(input string what);
        if (u_rx.received.size() != sent.size())
            $fatal(1, "SimUart %0d/%0d %s: %0d bytes, sent %0d", DATA_BITS, CLKS_PER_BIT, what,
                   u_rx.received.size(), sent.size());
        foreach (sent[i])
            if (u_rx.received[i] !== sent[i])
                $fatal(1, "SimUart %0d/%0d %s: byte %0d is %h, sent %h", DATA_BITS,
                       CLKS_PER_BIT, what, i, u_rx.received[i], sent[i]);
    endtask

    initial begin
        logic [7:0] b;
        done              = 1'b0;
        seed              = CLKS_PER_BIT * 16 + DATA_BITS;
        seen_back_to_back = 1'b0;
        @(posedge rst_n);

        // 1. Random bytes, random gaps.
        for (int k = 0; k < N; k++) begin
            while (u_tx.queue.size() != 0)
                @(posedge clk);
            u_tx.gap = $unsigned($random(seed)) % 3;
            if (u_tx.gap == 0)
                seen_back_to_back = 1'b1;
            b = 8'($random(seed)) & MASK;
            u_tx.push(b);
            sent.push_back(b);
        end
        wait_received(N);
        check_received("random");
        if (u_rx.framing_errors != 0 || u_rx.parity_errors != 0)
            $fatal(1, "SimUart %0d/%0d: %0d framing, %0d parity errors on good frames",
                   DATA_BITS, CLKS_PER_BIT, u_rx.framing_errors, u_rx.parity_errors);
        if (!seen_back_to_back)
            $fatal(1, "SimUart %0d/%0d: no frames back to back", DATA_BITS, CLKS_PER_BIT);

        // 2. A framing error, a parity error, then a good frame: all received, counted.
        u_rx.clear();
        sent.delete();
        u_tx.gap = 0;
        u_tx.push_bad(8'h55 & MASK, 1'b1, 1'b0);
        sent.push_back(8'h55 & MASK);
        if (PARITY != 0) begin
            u_tx.push_bad(8'h0f & MASK, 1'b0, 1'b1);
            sent.push_back(8'h0f & MASK);
        end
        u_tx.push(8'h1a & MASK);
        sent.push_back(8'h1a & MASK);
        wait_received(sent.size());
        check_received("errors");
        if (u_rx.framing_errors != 1 || u_rx.parity_errors != (PARITY != 0 ? 1 : 0))
            $fatal(1, "SimUart %0d/%0d: %0d framing, %0d parity errors, expected 1, %0d",
                   DATA_BITS, CLKS_PER_BIT, u_rx.framing_errors, u_rx.parity_errors,
                   PARITY != 0 ? 1 : 0);

        // 3. A string, printed by the Rx.
        if (ECHO != 0) begin
            u_rx.clear();
            u_tx.send(STRING);
            wait_received(12);
            if (u_rx.got() != STRING)
                $fatal(1, "SimUart: text \"%s\", sent \"%s\"", u_rx.got(), STRING);
        end
        done = 1'b1;
    end
endmodule

module TbSimUart;
    logic clk;
    logic rst_n;
    wire  done_8n1, done_8e2, done_7o1, done_5n2;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbSimUartCheck #(.CLKS_PER_BIT(16), .DATA_BITS(8), .PARITY(0), .STOP_BITS(1), .ECHO(1))
        u_check_8n1(.clk, .rst_n, .done(done_8n1));
    TbSimUartCheck #(.CLKS_PER_BIT(4), .DATA_BITS(8), .PARITY(1), .STOP_BITS(2))
        u_check_8e2(.clk, .rst_n, .done(done_8e2));
    TbSimUartCheck #(.CLKS_PER_BIT(5), .DATA_BITS(7), .PARITY(2), .STOP_BITS(1))
        u_check_7o1(.clk, .rst_n, .done(done_7o1));
    TbSimUartCheck #(.CLKS_PER_BIT(7), .DATA_BITS(5), .PARITY(0), .STOP_BITS(2))
        u_check_5n2(.clk, .rst_n, .done(done_5n2));

    initial begin
        wait (done_8n1 && done_8e2 && done_7o1 && done_5n2);
        $display("PASS");
        $finish;
    end
endmodule
