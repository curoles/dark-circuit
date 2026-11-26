/* Request data width downsizer: a request channel a line wide (LINE_WORDS words) to one a
 * word wide that takes read bursts; made of blocks, parts and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). The request's kind
 * by its size (CmpEq with the line's): line, line_rd (And2 with Inv of we), line_wr (And2).
 * The word it goes as: per word an OrReduce of its strobes, a PriorityEncoder of them (a
 * store strobes one word: the highest set is the one), Mux2 by line_wr against the address's
 * word bits. MuxN picks that word's data and strobes; a line write's address is the line's
 * with that word (Mux2), a line's size the word's (Mux2), a line read's len LINE_WORDS - 1
 * (Mux2). The queue of kinds is a Fifo, full holding back an answered request (And2, Inv).
 * The answers: a Counter of the line's words come (it wraps to 0 after the last, CmpEq:
 * LINE_WORDS is a power of 2), a DffEn per gathered word enabled by a Decoder of the count;
 * the line is the last word with them, a single word goes into every word (Mux2 by the
 * kind).
 *
 *   req_size CmpEq LINE_SIZE --> line --(And2 we / NOT we)--> line_wr, line_rd
 *   strobes --OrReduce per word--> PriorityEncoder --Mux2 (line_wr) / addr word--> idx
 *   idx --MuxN--> tgt_req_wdata, tgt_req_wstrb;  {line, idx, 0} --Mux2 (line_wr)--> addr
 *   blocked = req_rsp AND full;  tgt_req_valid = req_valid AND NOT blocked
 *   tgt_rsp: kind (Fifo); k (Counter, wraps after the last); gath[k] (Decoder, DffEn)
 *            rsp_valid = tgt_rsp_valid AND (NOT kind OR last)
 *            rsp_data  = Mux2 (kind): {LINE_WORDS{tgt_rsp_data}}, {tgt_rsp_data, gath}
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqDataWidthDown #(
    parameter  ADDR_WIDTH    = 32,      // byte address
    parameter  WORD_WIDTH    = 32,      // bits of the narrow channel's data
    parameter  LINE_WORDS    = 2,       // words of the wide channel's data, a power of 2
    parameter  FIELDS_WIDTH  = 8,       // bits of the other fields, passed as they are
    parameter  LEN_WIDTH     = 1,       // bits of the narrow req_len: bursts of 1 << it
    parameter  PENDING_WIDTH = 1,       // up to 1 << PENDING_WIDTH answered requests owed
    localparam LINE_WIDTH    = WORD_WIDTH * LINE_WORDS,
    localparam WSTRB_WIDTH   = WORD_WIDTH / 8,
    localparam LSTRB_WIDTH   = LINE_WIDTH / 8
)(
    input  wire                    clk,
    input  wire                    rst_n,           // synchronous, active low
    // Requester: a line wide
    input  wire                    req_valid,
    output wire                    req_ready,
    input  wire                    req_we,          // a write
    input  wire                    req_rsp,         // wants an answer
    input  wire [ADDR_WIDTH-1:0]   req_addr,        // byte address
    input  wire [2:0]              req_size,        // 1 << req_size bytes: a word or less, a line
    input  wire [LINE_WIDTH-1:0]   req_wdata,
    input  wire [LSTRB_WIDTH-1:0]  req_wstrb,
    input  wire [FIELDS_WIDTH-1:0] req_fields,
    output wire                    rsp_valid,       // an answer: a line
    output wire [LINE_WIDTH-1:0]   rsp_data,
    // Target: a word wide, read bursts
    output wire                    tgt_req_valid,
    input  wire                    tgt_req_ready,
    output wire                    tgt_req_we,
    output wire                    tgt_req_rsp,
    output wire [LEN_WIDTH-1:0]    tgt_req_len,     // beats - 1: LINE_WORDS - 1 for a line read
    output wire [ADDR_WIDTH-1:0]   tgt_req_addr,
    output wire [2:0]              tgt_req_size,
    output wire [WORD_WIDTH-1:0]   tgt_req_wdata,
    output wire [WSTRB_WIDTH-1:0]  tgt_req_wstrb,
    output wire [FIELDS_WIDTH-1:0] tgt_req_fields,
    input  wire                    tgt_rsp_valid,   // an answer: a word
    input  wire [WORD_WIDTH-1:0]   tgt_rsp_data
);
    localparam WORD_SIZE = $clog2(WSTRB_WIDTH);     // req_size of a word
    localparam LINE_SIZE = $clog2(LSTRB_WIDTH);     // ... of a line

    `DC_STATIC_ASSERT(a_widths, WORD_WIDTH >= 8 && (WORD_WIDTH & (WORD_WIDTH - 1)) == 0 &&
                                LINE_WORDS >= 1 && (LINE_WORDS & (LINE_WORDS - 1)) == 0 &&
                                ADDR_WIDTH > LINE_SIZE && FIELDS_WIDTH >= 1)
    `DC_STATIC_ASSERT(a_burst_fits, LEN_WIDTH >= 1 && LINE_WORDS <= (1 << LEN_WIDTH))

    // @kb: rtl/lib/block/req_data_width_down/design
    if (LINE_WORDS == 1) begin: g_one_word
        // A line is a word: the request as it is, its answer as it is.
        assign req_ready      = tgt_req_ready;
        assign tgt_req_valid  = req_valid;
        assign tgt_req_we     = req_we;
        assign tgt_req_rsp    = req_rsp;
        assign tgt_req_len    = '0;
        assign tgt_req_addr   = req_addr;
        assign tgt_req_size   = req_size;
        assign tgt_req_wdata  = req_wdata;
        assign tgt_req_wstrb  = req_wstrb;
        assign tgt_req_fields = req_fields;
        assign rsp_valid      = tgt_rsp_valid;
        assign rsp_data       = tgt_rsp_data;
    end else begin: g_words
        localparam WI = $clog2(LINE_WORDS);         // bits of a word's index in the line

        wire [LINE_WORDS-1:0][WORD_WIDTH-1:0]  words;       // the request's line, by word
        wire [LINE_WORDS-1:0][WSTRB_WIDTH-1:0] strbs;       // ... its strobes
        wire [LINE_WORDS-1:0]                  strobed;     // a word with strobes
        wire                                   we_n;
        wire                                   line;        // the request is a line's size
        wire                                   line_rd;     // ... a read: a burst
        wire                                   line_wr;     // ... a write: the strobed word
        wire [WI-1:0]                          strobed_idx; // the strobed word
        // Whether a word has strobes: the encoder's valid is not needed (none: word 0).
        /* verilator lint_off UNUSEDSIGNAL */
        wire                                   any_strobed;
        /* verilator lint_on UNUSEDSIGNAL */
        wire [WI-1:0]                          idx;         // the word it goes as
        wire [ADDR_WIDTH-1:0]                  word_addr;   // the line's address, word idx
        wire                                   blocked;     // answered, and the queue full
        wire                                   blocked_n;
        wire                                   take;        // the target takes the request
        wire                                   push;        // ... an answered one
        wire                                   kind;        // the oldest owed is a line read
        wire                                   kind_n;
        wire                                   empty;
        wire                                   full;
        // Status the block does not need.
        /* verilator lint_off UNUSEDSIGNAL */
        wire [PENDING_WIDTH:0]                 count;
        wire                                   almost_full;
        wire                                   almost_empty;
        wire                                   co_k;
        wire [LINE_WORDS-1:0]                  gather_en;   // the last word is not stored
        /* verilator lint_on UNUSEDSIGNAL */
        wire                                   line_word;   // a word of a line read comes
        wire                                   last;        // ... its last
        wire                                   rsp_one;     // a single word, or a line's last
        wire [WI-1:0]                          k;           // words of the line come so far
        wire [LINE_WORDS-2:0][WORD_WIDTH-1:0]  gath;        // ... but the last, bypassed

        assign words = req_wdata;
        assign strbs = req_wstrb;

        // The request's kind and the word it goes as.
        CmpEq #(3) u_cmp_eq_line(.in1(req_size), .in2(3'(LINE_SIZE)), .eq(line));
        Inv  #(1) u_inv_we(.in(req_we), .out(we_n));
        And2 #(1) u_and2_line_rd(.in1(line), .in2(we_n), .out(line_rd));
        And2 #(1) u_and2_line_wr(.in1(line), .in2(req_we), .out(line_wr));
        for (genvar i = 0; i < LINE_WORDS; i++) begin: g_strobed
            OrReduce #(WSTRB_WIDTH) u_or_reduce_strobed(.in(strbs[i]), .out(strobed[i]));
        end
        PriorityEncoder #(.SIZE(WI)) u_priority_encoder_strobed(
            .in(strobed), .out(strobed_idx), .valid(any_strobed));
        Mux2 #(WI) u_mux2_idx(.in0(req_addr[LINE_SIZE-1:WORD_SIZE]), .in1(strobed_idx),
                              .sel(line_wr), .out(idx));

        // The narrow request.
        And2 #(1) u_and2_blocked(.in1(req_rsp), .in2(full), .out(blocked));
        Inv  #(1) u_inv_blocked(.in(blocked), .out(blocked_n));
        And2 #(1) u_and2_tgt_valid(.in1(req_valid), .in2(blocked_n), .out(tgt_req_valid));
        And2 #(1) u_and2_req_ready(.in1(tgt_req_ready), .in2(blocked_n), .out(req_ready));
        And2 #(1) u_and2_take(.in1(tgt_req_valid), .in2(tgt_req_ready), .out(take));
        assign tgt_req_we     = req_we;
        assign tgt_req_rsp    = req_rsp;
        assign tgt_req_fields = req_fields;
        Mux2 #(LEN_WIDTH) u_mux2_len(.in0(LEN_WIDTH'(0)), .in1(LEN_WIDTH'(LINE_WORDS - 1)),
                                     .sel(line_rd), .out(tgt_req_len));
        assign word_addr = {req_addr[ADDR_WIDTH-1:LINE_SIZE], idx, WORD_SIZE'(0)};
        Mux2 #(ADDR_WIDTH) u_mux2_addr(.in0(req_addr), .in1(word_addr), .sel(line_wr),
                                       .out(tgt_req_addr));
        Mux2 #(3) u_mux2_size(.in0(req_size), .in1(3'(WORD_SIZE)), .sel(line),
                              .out(tgt_req_size));
        MuxN #(.N(LINE_WORDS), .WIDTH(WORD_WIDTH)) u_mux_n_wdata(.in(words), .sel(idx),
                                                                 .out(tgt_req_wdata));
        MuxN #(.N(LINE_WORDS), .WIDTH(WSTRB_WIDTH)) u_mux_n_wstrb(.in(strbs), .sel(idx),
                                                                  .out(tgt_req_wstrb));

        // The kinds of the answers owed, oldest first.
        And2 #(1) u_and2_push(.in1(take), .in2(req_rsp), .out(push));
        Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(1)) u_fifo_kind(
            .clk, .rst_n, .write(push), .data_in(line_rd), .read(rsp_valid),
            .data_out(kind), .empty, .full, .count, .almost_full, .almost_empty);

        // The answers: a line read's words gathered, the last bypassed.
        And2 #(1) u_and2_line_word(.in1(tgt_rsp_valid), .in2(kind), .out(line_word));
        CmpEq #(WI) u_cmp_eq_last(.in1(k), .in2(WI'(LINE_WORDS - 1)), .eq(last));
        Counter #(.WIDTH(WI)) u_counter_k(
            .clk, .rst_n, .load(1'b0), .in(WI'(0)), .up_down(1'b1), .count_en(line_word),
            .out(k), .co(co_k));
        Decoder #(.SIZE(WI)) u_decoder_gather(.in(k), .en(line_word), .out(gather_en));
        for (genvar i = 0; i < LINE_WORDS - 1; i++) begin: g_gath
            DffEn #(WORD_WIDTH) u_dff_en_gath(.clk, .en(gather_en[i]), .in(tgt_rsp_data),
                                              .out(gath[i]));
        end
        Inv  #(1) u_inv_kind(.in(kind), .out(kind_n));
        Or2  #(1) u_or2_rsp_one(.in1(kind_n), .in2(last), .out(rsp_one));
        And2 #(1) u_and2_rsp_valid(.in1(tgt_rsp_valid), .in2(rsp_one), .out(rsp_valid));
        Mux2 #(LINE_WIDTH) u_mux2_rsp_data(.in0({LINE_WORDS{tgt_rsp_data}}),
                                           .in1({tgt_rsp_data, gath}), .sel(kind),
                                           .out(rsp_data));

        // See the behave version.
        `DC_ASSERT(a_line_aligned, !(req_valid && line && req_addr[LINE_SIZE-1:0] != '0))
        `DC_ASSERT(a_line_read_answered, !(req_valid && line_rd && !req_rsp))
        `DC_ASSERT(a_line_write_one_word, !(req_valid && line_wr && !$onehot0(strobed)))
        `DC_ASSERT(a_answer_expected, !(tgt_rsp_valid && empty))
    end

    `DC_ASSERT(a_size_known, !(req_valid && req_size > 3'(WORD_SIZE) &&
                               req_size != 3'(LINE_SIZE)))

endmodule
