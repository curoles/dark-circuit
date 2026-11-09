/* Test of UartSifiveRegs, with the behave or the struct library.
 *
 * The testbench is the requester and the FIFOs: tx_full, rx_empty, rx_data and ip change at
 * random in every clock. A model of the registers (the fields as numbers, merged byte by byte
 * as the strobes say). A request in most clocks, held until taken: reads and writes of every
 * register with random strobes (often all), and of reserved addresses (0x1c, above 0x1c, a
 * register's offset with a high address bit set). In every clock: the fields, tx_push with
 * tx_data (a write of txdata's byte 0, in the clock it is taken, also when the FIFO is full),
 * rx_pop (a read of rxdata, in the clock it is taken), div_wr (a write of div, any bytes, in
 * the clock it is taken), rsp_valid and rsp_rdata (a read answers
 * one clock later with the value of the clock it was taken: full, empty and the byte, 0 when
 * empty, as they were then; a reserved address 0). After reset div is DIV_RST, the rest 0.
 * 6000 clocks on Verilator, 1500 on Icarus. Every case must happen (checks named cover): a
 * read and a write of every register, a push while full, a pop while empty and one with a
 * byte, a write of a control register that sets the enable byte and not the count byte or the
 * other way round, a reserved address. Checks named model and cover. Stops at the first
 * failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbUartSifiveRegs;
    import UartSifivePkg::*;
    `DC_TEST_MUTANT_HOOK(top)

`ifdef VERILATOR
    localparam N_CYCLES = 6000;
`else
    localparam N_CYCLES = 1500;
`endif
    localparam [15:0] DIV_RST = 16'h1234;

    logic        clk;
    logic        rst_n;
    logic        req_valid;
    wire         req_ready;
    logic        req_we;
    logic [11:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    wire         rsp_valid;
    wire  [31:0] rsp_rdata;
    wire         tx_push;
    wire  [7:0]  tx_data;
    logic        tx_full;
    wire         rx_pop;
    logic [7:0]  rx_data;
    logic        rx_empty;
    wire         txen, nstop, rxen;
    wire  [2:0]  txcnt, rxcnt;
    wire  [1:0]  ie;
    wire  [15:0] div;
    wire         div_wr;
    logic [1:0]  ip;

    logic        m_txen, m_nstop, m_rxen;   // the model
    logic [2:0]  m_txcnt, m_rxcnt;
    logic [1:0]  m_ie;
    logic [15:0] m_div;
    logic        m_rsp;                     // an answer is due now
    logic [31:0] m_rdata;
    integer      seed;
    logic [N_REGS-1:0] seen_read, seen_write;
    logic        seen_push_full, seen_pop_empty, seen_pop_byte, seen_partial, seen_reserved;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    UartSifiveRegs #(.DIV_RST(DIV_RST)) u_uart_sifive_regs(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .tx_push, .tx_data, .tx_full, .rx_pop, .rx_data, .rx_empty,
        .txen, .nstop, .txcnt, .rxen, .rxcnt, .ie, .div, .div_wr, .ip);

    // The register at a byte address: 0 .. N_REGS-1 (offset / 4), or -1 for a reserved one
    // (the byte in the word does not matter).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic int reg_of(input logic [11:0] a);
        if (a[11:2] < 10'(N_REGS))
            return int'(a[11:2]);
        return -1;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // The value a read of register r gives now, field by field.
    function automatic logic [31:0] model_reg(input int r);
        logic [31:0] v;
        v = '0;
        case (r)
            TXDATA / 4: v[FLAG_BIT] = tx_full;
            RXDATA / 4: begin
                v[FLAG_BIT] = rx_empty;
                v[7:0]      = rx_empty ? 8'h00 : rx_data;
            end
            TXCTRL / 4: begin
                v[EN_BIT]                 = m_txen;
                v[NSTOP_BIT]              = m_nstop;
                v[CNT_LSB +: CNT_BITS]    = m_txcnt;
            end
            RXCTRL / 4: begin
                v[EN_BIT]                 = m_rxen;
                v[CNT_LSB +: CNT_BITS]    = m_rxcnt;
            end
            IE / 4:     v[1:0] = m_ie;
            IP / 4:     v[1:0] = ip;
            DIV / 4:    v[DIV_BITS-1:0] = m_div;
            default:    v = '0;
        endcase
        return v;
    endfunction

    // A new request.
    task automatic new_request;
        int r;
        r = $unsigned($random(seed)) % 16;
        req_we    = ($random(seed) % 2) == 0;
        req_wstrb = ($random(seed) % 3 == 0) ? 4'($random(seed)) : 4'hf;
        req_wdata = $random(seed);
        if (r == 0) begin
            // A reserved address: 0x1c, above it, a register's offset with a high bit.
            case ($unsigned($random(seed)) % 3)
                0:       req_addr = 12'h01c;
                1:       req_addr = 12'h020 + 12'($unsigned($random(seed)) % 'h7e0);
                default: req_addr = 12'h800 + 12'(4 * ($unsigned($random(seed)) % N_REGS));
            endcase
            return;
        end
        req_addr = 12'(4 * ($unsigned($random(seed)) % N_REGS));
    endtask

    initial begin
        int   r;
        logic taken;
        logic push, pop;
        {seen_read, seen_write} = '0;
        {seen_push_full, seen_pop_empty, seen_pop_byte, seen_partial, seen_reserved} = '0;
        seed      = 11;
        req_valid = 1'b0;
        req_we    = 1'b0;
        req_addr  = '0;
        req_wdata = '0;
        req_wstrb = '0;
        tx_full   = 1'b0;
        rx_empty  = 1'b1;
        rx_data   = '0;
        ip        = '0;
        {m_txen, m_nstop, m_rxen, m_txcnt, m_rxcnt, m_ie} = '0;
        m_div     = DIV_RST;
        m_rsp     = 1'b0;
        m_rdata   = '0;
        @(posedge rst_n);
        taken = 1'b0;
        repeat (N_CYCLES) begin
            // The inputs of this clock, set at the falling edge.
            @(negedge clk);
            if (taken)
                req_valid = 1'b0;
            tx_full  = ($random(seed) % 4) == 0;
            rx_empty = ($random(seed) % 3) == 0;
            rx_data  = 8'($random(seed));
            ip       = 2'($random(seed));
            if (!req_valid && ($random(seed) % 8) != 0) begin
                new_request();
                req_valid = 1'b1;
            end
            #1;
            taken = req_valid && req_ready;
            r     = reg_of(req_addr);
            push  = taken && req_we && r == TXDATA / 4 && req_wstrb[0];
            pop   = taken && !req_we && r == RXDATA / 4;
            if ({txen, nstop, txcnt, rxen, rxcnt, ie, div} !==
                {m_txen, m_nstop, m_txcnt, m_rxen, m_rxcnt, m_ie, m_div})
                `DC_TEST_FAIL(model, $sformatf(
                    "fields %b %b %0d %b %0d %b %h, expected %b %b %0d %b %0d %b %h",
                    txen, nstop, txcnt, rxen, rxcnt, ie, div,
                    m_txen, m_nstop, m_txcnt, m_rxen, m_rxcnt, m_ie, m_div))
            if (tx_push !== push || (push && tx_data !== req_wdata[7:0]) || rx_pop !== pop ||
                div_wr !== (taken && req_we && r == DIV / 4) ||
                rsp_valid !== m_rsp || (m_rsp && rsp_rdata !== m_rdata))
                `DC_TEST_FAIL(model, $sformatf(
                    "push %b %h pop %b div_wr %b rsp %b %h, expected push %b %h pop %b rsp %b %h",
                    tx_push, tx_data, rx_pop, div_wr, rsp_valid, rsp_rdata,
                    push, req_wdata[7:0], pop, m_rsp, m_rdata))
            // The edge: the model, from the values of this clock.
            m_rsp   = taken && !req_we;
            m_rdata = model_reg(r);
            if (taken && !req_we && r >= 0) seen_read[r] = 1'b1;
            if (taken && req_we && r >= 0)  seen_write[r] = 1'b1;
            if (taken && r < 0)             seen_reserved = 1'b1;
            if (push && tx_full)            seen_push_full = 1'b1;
            if (pop && rx_empty)            seen_pop_empty = 1'b1;
            if (pop && !rx_empty)           seen_pop_byte = 1'b1;
            if (taken && req_we && (r == TXCTRL / 4 || r == RXCTRL / 4) &&
                req_wstrb[0] != req_wstrb[CNT_LSB / 8])
                seen_partial = 1'b1;
            if (taken && req_we && r == TXCTRL / 4) begin
                if (req_wstrb[0])            {m_nstop, m_txen} = req_wdata[1:0];
                if (req_wstrb[CNT_LSB / 8])  m_txcnt = req_wdata[CNT_LSB +: CNT_BITS];
            end
            if (taken && req_we && r == RXCTRL / 4) begin
                if (req_wstrb[0])            m_rxen = req_wdata[EN_BIT];
                if (req_wstrb[CNT_LSB / 8])  m_rxcnt = req_wdata[CNT_LSB +: CNT_BITS];
            end
            if (taken && req_we && r == IE / 4 && req_wstrb[0])
                m_ie = req_wdata[1:0];
            if (taken && req_we && r == DIV / 4) begin
                if (req_wstrb[0]) m_div[7:0]  = req_wdata[7:0];
                if (req_wstrb[1]) m_div[15:8] = req_wdata[15:8];
            end
        end
        if (seen_read != '1 || seen_write != '1 || !seen_push_full || !seen_pop_empty ||
            !seen_pop_byte || !seen_partial || !seen_reserved)
            `DC_TEST_FAIL(cover, $sformatf(
                "read %b write %b push full %b pop empty %b pop byte %b partial %b reserved %b",
                seen_read, seen_write, seen_push_full, seen_pop_empty, seen_pop_byte,
                seen_partial, seen_reserved))
        $display("PASS");
        $finish;
    end
endmodule
