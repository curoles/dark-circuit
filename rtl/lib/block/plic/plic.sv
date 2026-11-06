/* PLIC: the RISC-V Platform-Level Interrupt Controller (riscv-plic-spec), wiring only.
 *
 * N_SOURCES interrupt sources (IDs 1 to N_SOURCES, src[k]) to N_CONTEXTS contexts (a hart's
 * privilege mode each, eip[c]), priorities of PRIO_WIDTH bits, the spec's register map
 * (PlicPkg) behind the library's register port (kb pattern rtl/lib/block/plic/register_port):
 * any bus through an adapter. Source k is edge triggered when EDGE_TRIGGERED[k] is 1, level
 * triggered when 0 (fixed by the platform). The sources are synchronous to clk. The decisions
 * of the whole PLIC: kb rtl/lib/block/plic/design.
 *
 *   req_*, rsp_* <--> RegPortTarget --acc_*--> PlicDecode --sel_*--+
 *                       ^hold   ^rd_data                           |
 *                       |       +--- MuxOneHot <--- every register +--> And2 with acc_wr:
 *                    DelayLine <--- claim_en                       |    StrbReg priority[k],
 *                                                                  |    enable[c][w],
 *                                                                  |    threshold[c]
 *                                                                  +--> And2 with acc_rd:
 *                                                                  |    claim_en[c]
 *                                                                  +--> And3 with acc_wr, the
 *                                                                       ID's bytes: complete_en
 *
 *   src[k] --> PlicGateway k --ip--> PlicTarget c --> eip[c], claim_id[c]
 *                 ^ claim[k], complete[k]  ^ prio, ie[c], threshold[c]
 *                 +---------- PlicClaim <--- claim_en, claim_id, complete_en, the written ID
 *
 * Registers: a StrbReg per priority (PRIO_WIDTH bits), per word of enables (32 bits, the last
 * word the bits left; bit 0 of word 0 is ID 0: written 0, so it reads 0) and per threshold;
 * the pending bits are the gateways' ip, the claim register is the target's claim_id. A read
 * takes the selected register (MuxOneHot of every register's word; a reserved address
 * selects none and reads 0). A read of a claim register claims claim_id; a write of it
 * completes the written ID when its bytes are all written (acc_wstrb) and it is enabled for
 * the context (PlicClaim).
 *
 * Atomic claims: the claim ID is registered, so in the clock after a claim it still names the
 * claimed source; no request is taken in that clock (hold, kb rtl/lib/block/plic/top). The
 * other registers act at once, but the targets see a write one clock later: a claim right
 * after a write of an enable or a priority sees them before the write.
 *
 * ADDR_WIDTH: the bits of req_addr, at most 26 (the map's 64 MiB) and enough for the claim
 * register of the last context; the bits above it are 0. DATA_WIDTH: 32 (the spec's
 * registers), a parameter as the register port's.
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Plic #(
    parameter                 N_SOURCES      = 31,                  // IDs 1 to N_SOURCES
    parameter                 N_CONTEXTS     = 1,                   // targets
    parameter                 PRIO_WIDTH     = 3,                   // bits of a priority
    parameter [N_SOURCES:1]   EDGE_TRIGGERED = '0,                  // source k: edge, level
    parameter                 ADDR_WIDTH     = PlicPkg::ADDR_BITS,  // bits of req_addr
    parameter                 DATA_WIDTH     = 32,                  // bits of a register
    localparam                STRB_WIDTH     = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,     // synchronous reset, active low
    input  wire [N_SOURCES:1]    src,       // the interrupts of the sources
    output wire [N_CONTEXTS-1:0] eip,       // to the contexts (a hart's meip or seip)
    // Register port
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,    // 1 write, 0 read
    input  wire [ADDR_WIDTH-1:0] req_addr,  // byte address inside the PLIC
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [STRB_WIDTH-1:0] req_wstrb, // bytes written
    output wire                  rsp_valid, // the answer to a read
    output wire [DATA_WIDTH-1:0] rsp_rdata
);
    localparam AB   = PlicPkg::ADDR_BITS;
    localparam W    = PlicPkg::id_words(N_SOURCES);     // words of bits per ID
    localparam IDW  = $clog2(N_SOURCES + 1);            // bits of an ID
    localparam IDB  = (IDW + 7) / 8;                    // bytes of an ID
    localparam PB   = (PRIO_WIDTH + 7) / 8;             // bytes of a priority or threshold
    localparam LAST = PlicPkg::CONTEXT_BASE + PlicPkg::CONTEXT_STRIDE * (N_CONTEXTS - 1) +
                      PlicPkg::CLAIM_COMPLETE;          // the last register's address

    `DC_STATIC_ASSERT(a_sizes, N_SOURCES >= 1 && N_SOURCES <= PlicPkg::MAX_SOURCES &&
                      N_CONTEXTS >= 1 && N_CONTEXTS <= PlicPkg::MAX_CONTEXTS &&
                      PRIO_WIDTH >= 1 && PRIO_WIDTH <= 32)
    `DC_STATIC_ASSERT(a_port, DATA_WIDTH == 32 && ADDR_WIDTH <= AB && LAST < (1 << ADDR_WIDTH))

    // Bits of an enable word w: 32, the last word the bits left.
    function automatic int ew(input int w);
        return (32 * (w + 1) <= N_SOURCES + 1) ? 32 : N_SOURCES + 1 - 32 * w;
    endfunction

    // The words of the read mux, in the order of the selects: {priorities, pending words,
    // enable words, thresholds, claim registers}, the last at 0.
    localparam OFF_THR  = N_CONTEXTS;
    localparam OFF_EN   = 2 * N_CONTEXTS;
    localparam OFF_PEND = OFF_EN + N_CONTEXTS * W;
    localparam OFF_PRIO = OFF_PEND + W;
    localparam NR       = OFF_PRIO + N_SOURCES + 1;     // words, ID 0's priority too

    wire                  hold;         // take no request: the clock after a claim
    wire                  acc_rd;       // a read is taken now
    wire                  acc_wr;       // a write is taken now
    wire [ADDR_WIDTH-1:0] acc_addr;
    // The bits and bytes above the widest register are not used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] acc_wdata;
    wire [STRB_WIDTH-1:0] acc_wstrb;
    wire [AB-1:0]         byte_addr;    // bits 1:0 pick a byte: the strobes do that
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] rd_data;      // the selected register

    wire [N_SOURCES:0]                  sel_priority;
    wire [W-1:0]                        sel_pending;
    wire [N_CONTEXTS-1:0][W-1:0]        sel_enable;
    wire [N_CONTEXTS-1:0]               sel_threshold;
    wire [N_CONTEXTS-1:0]               sel_claim;

    wire [N_SOURCES:0]                  ip;             // pending, by source ID
    wire [N_SOURCES:0][PRIO_WIDTH-1:0]  prio;           // by source ID, ID 0's is 0
    wire [N_CONTEXTS-1:0][N_SOURCES:0]  ie;             // enables of each context
    wire [N_CONTEXTS-1:0][PRIO_WIDTH-1:0] threshold;
    wire [N_CONTEXTS-1:0][IDW-1:0]      claim_id;       // the ID a claim of c gets
    wire [N_CONTEXTS-1:0]               claim_en;       // context c claims now
    wire [N_CONTEXTS-1:0]               complete_en;    // context c completes now
    wire                                id_written;     // the write has all bytes of an ID
    wire                                claimed;        // some context claims now
    // Bit 0 is ID 0: no source.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N_SOURCES:0]                  claim;          // source k is claimed now
    wire [N_SOURCES:0]                  complete;       // source k completes now
    /* verilator lint_on UNUSEDSIGNAL */
    wire [NR-1:0][DATA_WIDTH-1:0]       rd_words;       // every register, read
    wire [NR-1:0]                       rd_sel;         // its select

    // Register port and decode.
    RegPortTarget #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_reg_port_target(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .hold, .acc_rd, .acc_wr, .acc_addr, .acc_wdata, .acc_wstrb,
        .rd_data);

    assign byte_addr = AB'(acc_addr);
    PlicDecode #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(N_CONTEXTS)) u_plic_decode(
        .addr(byte_addr[AB-1:2]), .sel_priority, .sel_pending, .sel_enable, .sel_threshold,
        .sel_claim);

    // @kb: rtl/lib/block/plic/top
    // Gateways.
    assign ip[0] = 1'b0;
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_source
        PlicGateway #(.EDGE_TRIGGERED(EDGE_TRIGGERED[k])) u_gateway(
            .clk, .rst_n, .src(src[k]), .claim(claim[k]), .complete(complete[k]), .ip(ip[k]));
    end

    // Priorities.
    assign prio[0] = '0;
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_priority
        wire we;    // priority k is written now
        And2 #(1) u_and2(.in1(acc_wr), .in2(sel_priority[k]), .out(we));
        StrbReg #(.WIDTH(PRIO_WIDTH)) u_strb_reg(
            .clk, .rst_n, .we, .wstrb(acc_wstrb[PB-1:0]), .wdata(acc_wdata[PRIO_WIDTH-1:0]),
            .q(prio[k]));
    end

    // Per context: enables, threshold, claim and complete, the target.
    AndReduce #(IDB) u_and_reduce_id(.in(acc_wstrb[IDB-1:0]), .out(id_written));
    for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_context
        for (genvar w = 0; w < W; w++) begin: g_enable
            localparam EW = ew(w);
            wire           we;      // enable word w of context c is written now
            wire [EW-1:0]  wdata;   // bit 0 of word 0 (ID 0) written 0
            And2 #(1) u_and2(.in1(acc_wr), .in2(sel_enable[c][w]), .out(we));
            if (w == 0) begin: g_id0
                assign wdata = {acc_wdata[EW-1:1], 1'b0};
            end else begin: g_ids
                assign wdata = acc_wdata[EW-1:0];
            end
            StrbReg #(.WIDTH(EW)) u_strb_reg(
                .clk, .rst_n, .we, .wstrb(acc_wstrb[(EW + 7) / 8 - 1:0]), .wdata,
                .q(ie[c][32 * w +: EW]));
        end

        wire we_threshold;  // the threshold of context c is written now
        And2 #(1) u_and2_threshold(.in1(acc_wr), .in2(sel_threshold[c]), .out(we_threshold));
        StrbReg #(.WIDTH(PRIO_WIDTH)) u_strb_reg_threshold(
            .clk, .rst_n, .we(we_threshold), .wstrb(acc_wstrb[PB-1:0]),
            .wdata(acc_wdata[PRIO_WIDTH-1:0]), .q(threshold[c]));

        And2 #(1) u_and2_claim(.in1(acc_rd), .in2(sel_claim[c]), .out(claim_en[c]));
        And3 #(1) u_and3_complete(
            .in1(acc_wr), .in2(sel_claim[c]), .in3(id_written), .out(complete_en[c]));

        PlicTarget #(.N_SOURCES(N_SOURCES), .PRIO_WIDTH(PRIO_WIDTH)) u_target(
            .clk, .rst_n, .ip, .ie(ie[c]), .prio, .threshold(threshold[c]), .eip(eip[c]),
            .claim_id(claim_id[c]));
    end

    PlicClaim #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(N_CONTEXTS)) u_claim(
        .claim_en, .claim_id, .complete_en, .complete_id({N_CONTEXTS{acc_wdata[IDW-1:0]}}),
        .ie, .claim, .complete);

    // No request in the clock after a claim (the claim ID is registered).
    OrReduce #(N_CONTEXTS) u_or_reduce_claimed(.in(claim_en), .out(claimed));
    DelayLine #(.DEPTH(1), .RESET(1)) u_delay_line_hold(
        .clk, .rst_n, .in(claimed), .out(hold));

    // Reads: every register's word, by its select.
    assign rd_sel = {sel_priority, sel_pending, sel_enable, sel_threshold, sel_claim};
    for (genvar k = 0; k <= N_SOURCES; k++) begin: g_rd_priority
        assign rd_words[OFF_PRIO + k] = DATA_WIDTH'(prio[k]);
    end
    for (genvar w = 0; w < W; w++) begin: g_rd_pending
        assign rd_words[OFF_PEND + w] = DATA_WIDTH'(ip[32 * w +: ew(w)]);
    end
    for (genvar c = 0; c < N_CONTEXTS; c++) begin: g_rd_context
        for (genvar w = 0; w < W; w++) begin: g_enable
            assign rd_words[OFF_EN + c * W + w] = DATA_WIDTH'(ie[c][32 * w +: ew(w)]);
        end
        assign rd_words[OFF_THR + c] = DATA_WIDTH'(threshold[c]);
        assign rd_words[c]           = DATA_WIDTH'(claim_id[c]);
    end
    MuxOneHot #(.N(NR), .WIDTH(DATA_WIDTH)) u_mux_one_hot_rd(
        .in(rd_words), .sel(rd_sel), .out(rd_data));

endmodule
