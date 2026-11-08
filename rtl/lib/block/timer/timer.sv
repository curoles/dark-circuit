/* Timer: a machine timer, the time mtime and an alarm mtimecmp per hart (the RISC-V ACLINT
 * MTIMER, the timer part of SiFive's CLINT), wiring only.
 *
 * mtime is a 64-bit counter that counts in every clock with tick = 1 (the platform gives the
 * rate: tie it to 1 to count clocks). mtimecmp[h] is an absolute time: irq[h] is 1 while
 * mtime >= mtimecmp[h], a level, until software writes a later mtimecmp[h] (an alarm in the
 * past fires at once, it is not missed). irq[h] is registered: it follows the compare one
 * clock later, also after a write of mtimecmp. mtimecmp resets to all ones (no alarm before
 * software sets one), mtime to 0. The registers are behind the library's register port
 * (kb pattern rtl/lib/block/plic/register_port) at the CLINT's addresses (TimerPkg): 64-bit
 * registers as two 32-bit words, the low word first, written byte by byte; software reads
 * mtime as the high word, the low word, the high word again (RV32: the low word may carry).
 * A reserved address reads 0, a write there is ignored. The irq outputs go where the
 * platform wants them: a PLIC source (a peripheral timer) or a hart's mtip. The decisions:
 * kb rtl/lib/block/timer/design.
 *
 *              register port (req_*, rsp_*)
 *                        |
 *                  RegPortTarget
 *                        |  acc_rd / acc_wr, acc_addr, acc_wdata, acc_wstrb
 *                  decode (CmpEq on acc_addr): which register, which 32-bit word
 *                        |
 *      +-----------------+----------------------------+
 *      | we, wstrb (low or high word)                 | we, wstrb
 *      v                                              v
 *  StrbCounter mtime (64) <-- tick (inc)          StrbReg mtimecmp[h] (64), reset all ones
 *      |                                              |
 *      +------------------> CmpGe <-------------------+      (one per hart h)
 *                             |  mtime >= mtimecmp[h]
 *                          DffSyncRst
 *                             |
 *                          irq[h]
 *
 *  reads: MuxOneHot of {mtime, mtimecmp[h]} low and high words --> rd_data
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Timer #(
    parameter  N_HARTS    = 1,                      // alarms: mtimecmp[h], irq[h]
    localparam ADDR_WIDTH = TimerPkg::ADDR_BITS,    // bits of req_addr: the 64 KiB map
    localparam DATA_WIDTH = 32,                     // bits of a register access
    localparam STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,     // synchronous reset, active low
    input  wire                  tick,      // mtime counts now
    output wire [N_HARTS-1:0]    irq,       // mtime >= mtimecmp[h], one clock later
    // Register port
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,    // 1 write, 0 read
    input  wire [ADDR_WIDTH-1:0] req_addr,  // byte address inside the timer
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [STRB_WIDTH-1:0] req_wstrb, // bytes written
    output wire                  rsp_valid, // the answer to a read
    output wire [DATA_WIDTH-1:0] rsp_rdata
);
    localparam WA = ADDR_WIDTH - 2;     // bits of a word address
    localparam NW = 2 + 2 * N_HARTS;    // words of the read mux: mtime, then each mtimecmp

    `DC_STATIC_ASSERT(a_harts, N_HARTS >= 1 && N_HARTS <= TimerPkg::MAX_HARTS)

    // The word address of register word w: 0, 1 mtime low, high; 2 + 2h, 3 + 2h mtimecmp[h].
    function automatic [WA-1:0] word_addr(input int w);
        int a;
        a = (w < 2) ? TimerPkg::MTIME + 4 * w : TimerPkg::MTIMECMP_BASE + 4 * (w - 2);
        return WA'(a / 4);
    endfunction

    // A read has no side effect here: only RegPortTarget uses it.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  acc_rd;       // a read is taken now
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  acc_wr;       // a write is taken now
    // Bits 1:0 pick a byte: the strobes do that.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [ADDR_WIDTH-1:0] acc_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] acc_wdata;
    wire [STRB_WIDTH-1:0] acc_wstrb;
    wire [DATA_WIDTH-1:0] rd_data;      // the selected register word
    wire [NW-1:0]         sel;          // word w is accessed now
    wire [NW-1:0][DATA_WIDTH-1:0] words;    // every register word, read
    wire [63:0]           mtime;
    wire [N_HARTS-1:0][63:0] mtimecmp;
    wire [N_HARTS-1:0]    reached;      // mtime >= mtimecmp[h]

    // Register port and decode.
    RegPortTarget #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_reg_port_target(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .hold(1'b0), .acc_rd, .acc_wr, .acc_addr, .acc_wdata,
        .acc_wstrb, .rd_data);

    // @kb: rtl/lib/block/timer/design
    for (genvar w = 0; w < NW; w++) begin: g_decode
        localparam [WA-1:0] ADDR = word_addr(w);
        CmpEq #(WA) u_cmp_eq(.in1(acc_addr[ADDR_WIDTH-1:2]), .in2(ADDR), .eq(sel[w]));
    end

    // A 64-bit register is written as two words: the strobes of the access go to the bytes
    // of the word accessed, wdata to both.
    // mtime: counts on tick, a write wins (StrbCounter).
    wire       mtime_sel;
    wire       mtime_we;
    wire [7:0] mtime_wstrb;
    Or2  #(1) u_or2_mtime(.in1(sel[0]), .in2(sel[1]), .out(mtime_sel));
    And2 #(1) u_and2_mtime(.in1(acc_wr), .in2(mtime_sel), .out(mtime_we));
    And2 #(8) u_and2_mtime_wstrb(.in1({acc_wstrb, acc_wstrb}),
                                 .in2({{STRB_WIDTH{sel[1]}}, {STRB_WIDTH{sel[0]}}}),
                                 .out(mtime_wstrb));
    StrbCounter #(.WIDTH(64)) u_strb_counter_mtime(
        .clk, .rst_n, .we(mtime_we), .wstrb(mtime_wstrb), .wdata({acc_wdata, acc_wdata}),
        .inc(tick), .q(mtime));

    // mtimecmp[h]: an alarm, all ones after reset; irq[h] the registered compare.
    for (genvar h = 0; h < N_HARTS; h++) begin: g_hart
        wire       cmp_sel;
        wire       cmp_we;
        wire [7:0] cmp_wstrb;
        Or2  #(1) u_or2(.in1(sel[2 + 2 * h]), .in2(sel[3 + 2 * h]), .out(cmp_sel));
        And2 #(1) u_and2(.in1(acc_wr), .in2(cmp_sel), .out(cmp_we));
        And2 #(8) u_and2_wstrb(.in1({acc_wstrb, acc_wstrb}),
                               .in2({{STRB_WIDTH{sel[3 + 2 * h]}}, {STRB_WIDTH{sel[2 + 2 * h]}}}),
                               .out(cmp_wstrb));
        StrbReg #(.WIDTH(64), .RST_VAL('1)) u_strb_reg_mtimecmp(
            .clk, .rst_n, .we(cmp_we), .wstrb(cmp_wstrb), .wdata({acc_wdata, acc_wdata}),
            .q(mtimecmp[h]));
        CmpGe #(64) u_cmp_ge(.in1(mtime), .in2(mtimecmp[h]), .ge(reached[h]));
    end
    DffSyncRst #(.WIDTH(N_HARTS)) u_dff_sync_rst_irq(.clk, .rst_n, .in(reached), .out(irq));

    // Reads: every register word, by its select; a reserved address selects none (0).
    assign words[0] = mtime[31:0];
    assign words[1] = mtime[63:32];
    for (genvar h = 0; h < N_HARTS; h++) begin: g_read
        assign words[2 + 2 * h] = mtimecmp[h][31:0];
        assign words[3 + 2 * h] = mtimecmp[h][63:32];
    end
    MuxOneHot #(.N(NW), .WIDTH(DATA_WIDTH)) u_mux_one_hot_rd(.in(words), .sel, .out(rd_data));

    // At most one register word is accessed.
    `DC_ASSERT(a_one_word, $onehot0(sel))

endmodule
