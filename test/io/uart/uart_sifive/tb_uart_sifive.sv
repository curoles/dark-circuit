/* Test of UartSifive, end to end, with the behave or the struct library.
 *
 * The testbench is software on the register port: a task per access (a request at a falling
 * edge, held until taken; a read's answer at the next falling edge). The UART's tx goes into
 * SimUartRx, SimUartTx drives its rx; both at div + 1 clocks a bit. A program in phases:
 *  1. div, rxen; txen = 0: three bytes pushed stay in the FIFO, the line stays idle.
 *  2. txen: they go out, the first start bit within two bits (the write of div restarted the
 *     tick: it did not wait for the end of a period of the reset value), then a string longer
 *     than the FIFO, each byte written after reading txdata until full is 0 (full must be
 *     seen); SimUartRx receives all of it, no error.
 *  3. ie.rxwm, rxcnt 0: SimUartTx sends a string; at every irq software reads rxdata until
 *     empty; it gets the string.
 *  4. No reads while SimUartTx sends 10 bytes: the receive FIFO keeps the first 8 (the rest
 *     are dropped, SiFive's rule); with rxen = 0 two more bytes are not kept.
 *  5. ie.txwm, txcnt 1: the empty transmit FIFO asks for bytes (irq, ip 01); one byte held
 *     with txen = 0 ends that (irq 0).
 * Two configurations: div 31 (2 clocks a tick) with one stop bit, div 40 (2.5625 clocks a
 * tick, the fractional TickGen; still 41 clocks every bit) with two. Checks named model and
 * cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbUartSifiveCheck #(
    parameter RATE  = 31,           // the value of div (not DIV: that is div's address)
    parameter NSTOP = 0
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
    import UartSifivePkg::*;

    localparam CLKS  = RATE + 1;                     // clocks of a bit
    localparam STOPS = NSTOP + 1;
    localparam FRAME = CLKS * (1 + 8 + STOPS);      // clocks of a frame

    logic        req_valid;
    wire         req_ready;
    logic        req_we;
    logic [11:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    wire         rsp_valid;
    wire  [31:0] rsp_rdata;
    wire         tx, rx, irq;
    logic [31:0] v;
    string       got;
    string       hello;                             // sent by the UART
    string       abc;                               // received by it
    bit          seen_full, seen_irq;

    UartSifive u_uart_sifive(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .tx, .rx, .irq);
    SimUartRx #(.CLKS_PER_BIT(CLKS), .STOP_BITS(STOPS), .ECHO(0)) u_line_rx(
        .clk, .rst_n, .rx(tx));
    SimUartTx #(.CLKS_PER_BIT(CLKS), .STOP_BITS(STOPS)) u_line_tx(.clk, .rst_n, .tx(rx));

    // One register access, as software does it.
    task automatic access(input logic we, input int addr, input logic [31:0] wdata,
                          output logic [31:0] rdata);
        @(negedge clk);
        req_valid = 1'b1;
        req_we    = we;
        req_addr  = 12'(addr);
        req_wdata = wdata;
        req_wstrb = 4'hf;
        @(posedge clk);
        while (!req_ready)
            @(posedge clk);
        @(negedge clk);
        req_valid = 1'b0;
        rdata     = rsp_rdata;
        if (!we && rsp_valid !== 1'b1)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: no answer to a read of %h", RATE,
                                           addr))
    endtask

    task automatic wr(input int addr, input logic [31:0] data);
        logic [31:0] unused;
        access(1'b1, addr, data, unused);
    endtask

    task automatic rd(input int addr, output logic [31:0] data);
        access(1'b0, addr, '0, data);
    endtask

    // n clocks.
    task automatic idle_clocks(input int n);
        repeat (n) @(posedge clk);
    endtask

    // Every byte of rxdata until empty, appended to got.
    task automatic drain;
        logic [31:0] d;
        rd(RXDATA, d);
        while (!d[FLAG_BIT]) begin
            got = $sformatf("%s%c", got, d[7:0]);
            rd(RXDATA, d);
        end
    endtask

    function automatic logic [31:0] txctrl(input bit en, input logic [CNT_BITS-1:0] cnt);
        logic [31:0] c;
        c                        = '0;
        c[EN_BIT]                = en;
        c[NSTOP_BIT]             = NSTOP != 0;
        c[CNT_LSB +: CNT_BITS]   = cnt;
        return c;
    endfunction

    function automatic logic [31:0] rxctrl(input bit en, input logic [CNT_BITS-1:0] cnt);
        logic [31:0] c;
        c                        = '0;
        c[EN_BIT]                = en;
        c[CNT_LSB +: CNT_BITS]   = cnt;
        return c;
    endfunction

    initial begin
        int limit;
        done      = 1'b0;
        seen_full = 1'b0;
        seen_irq  = 1'b0;
        got       = "";
        hello     = "Hello, dark-circuit!";
        abc       = "abcdefghijklmnop";
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        @(posedge rst_n);

        // 1. txen = 0 keeps the bytes.
        wr(DIV, RATE);
        wr(RXCTRL, rxctrl(1, 3'd0));
        wr(TXCTRL, txctrl(0, 3'd0));
        wr(TXDATA, 32'("H"));
        wr(TXDATA, 32'("i"));
        wr(TXDATA, 32'("!"));
        idle_clocks(3 * FRAME);
        if (u_line_rx.received.size() != 0 || tx !== 1'b1)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: sent with txen 0: \"%s\"", RATE,
                                           u_line_rx.got()))

        // 2. txen: the three, then hello, waiting for room.
        wr(TXCTRL, txctrl(1, 3'd0));
        limit = 2 * CLKS;
        while (tx && limit > 0) begin
            @(posedge clk);
            limit--;
        end
        if (tx !== 1'b0)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: no start bit two bits after txen",
                                           RATE))
        for (int i = 0; i < hello.len(); i++) begin
            logic [7:0] c;
            c = hello[i];
            rd(TXDATA, v);
            while (v[FLAG_BIT]) begin
                seen_full = 1'b1;
                rd(TXDATA, v);
            end
            wr(TXDATA, {24'h0, c});
        end
        limit = (hello.len() + 4) * FRAME;
        while (u_line_rx.received.size() < 3 + hello.len() && limit > 0) begin
            @(posedge clk);
            limit--;
        end
        if (u_line_rx.got() != $sformatf("Hi!%s", hello) || u_line_rx.framing_errors != 0)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: the line got \"%s\", %0d errors",
                                           RATE, u_line_rx.got(), u_line_rx.framing_errors))

        // 3. Receive by interrupt.
        wr(IE, 32'(1 << RXWM_BIT));
        u_line_tx.send(abc);
        limit = (abc.len() + 4) * FRAME;
        while (got.len() < abc.len() && limit > 0) begin
            @(posedge clk);
            limit--;
            if (irq) begin
                seen_irq = 1'b1;
                drain();
            end
        end
        if (got != abc)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: rxdata gave \"%s\"", RATE, got))

        // 4. The receive FIFO keeps 8 bytes; nothing without rxen.
        wr(IE, 0);
        got = "";
        u_line_tx.send("0123456789");
        while (!u_line_tx.idle())
            @(posedge clk);
        idle_clocks(2 * CLKS);
        drain();
        wr(RXCTRL, rxctrl(0, 3'd0));
        u_line_tx.send("XY");
        while (!u_line_tx.idle())
            @(posedge clk);
        idle_clocks(2 * CLKS);
        drain();
        if (got != "01234567")
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: kept \"%s\"", RATE, got))

        // 5. The transmit watermark.
        wr(TXCTRL, txctrl(1, 3'd1));
        wr(IE, 32'(1 << TXWM_BIT));
        rd(IP, v);
        if (irq !== 1'b1 || v != 32'(1 << TXWM_BIT))
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: txwm irq %b ip %h", RATE, irq, v))
        wr(TXCTRL, txctrl(0, 3'd1));
        wr(TXDATA, 32'("z"));
        @(negedge clk);
        if (irq !== 1'b0)
            `DC_TEST_FAIL(model, $sformatf("UartSifive %0d: txwm irq with a byte", RATE))

        if (!seen_full || !seen_irq)
            `DC_TEST_FAIL(cover, $sformatf("UartSifive %0d: full %b irq %b", RATE, seen_full,
                                           seen_irq))
        done = 1'b1;
    end
endmodule

module TbUartSifive;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_31, done_40;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbUartSifiveCheck #(.RATE(31), .NSTOP(0)) u_check_31(.clk, .rst_n, .done(done_31));
    TbUartSifiveCheck #(.RATE(40), .NSTOP(1)) u_check_40(.clk, .rst_n, .done(done_40));

    initial begin
        wait (done_31 && done_40);
        $display("PASS");
        $finish;
    end
endmodule
