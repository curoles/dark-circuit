/* Request data width downsizer: a request channel a line wide (LINE_WORDS words) to one a
 * word wide that takes read bursts; behavioral.
 *
 * Both channels are the library's: requests on valid/ready, a request with req_rsp answered
 * req_len + 1 times in order (kb rtl/lib/block/bursts), one or more clocks after its target
 * took it, with no ready. A cache's memory side is a line wide; a network or bus a word wide
 * carries a line as a burst (AXI's data width converter, "downsizer"). Each wide request is
 * one narrow request:
 * - A read of a whole line (req_size the line's: a cache's refill) is a read burst of
 *   LINE_WORDS words (req_len LINE_WORDS - 1, a word's size) at the line's address. Its
 *   answers, word 0 first, are gathered; the line is answered in the clock its last word
 *   comes (that word bypassed into it), one wide answer.
 * - A write of a whole line (a write-through cache's store: the line with strobes on the
 *   stored bytes only) is a write of the one word that has strobes, at that word's address,
 *   with its strobes: the memory writes the same bytes. A store never spans two words
 *   (a_line_write_one_word); a write with no strobes (a CBO: a store of no bytes) is word 0.
 * - A request of a word or less (uncached accesses, atomics, LR/SC) is itself, its data and
 *   strobes the word of the line its address names; its answer word goes into every word of
 *   the line (the requester picks its bytes by the address, as from a wide memory).
 * Other sizes do not come (a_size_known). The other fields (FIELDS_WIDTH bits: an atomic's
 * operation, a CBO, exclusive, ...) go with the request. Answers come in order, so a queue
 * (Fifo) keeps for every answered request taken whether it is a line read; while it is full
 * no answered request goes (req_ready 0), PENDING_WIDTH sized as a ReqMux's (requests). With
 * LINE_WORDS 1 the block is wires.
 *
 *   req (line wide) --> line read:  burst of LINE_WORDS words ----------> tgt (word wide)
 *                       line write: the strobed word, its address
 *                       else:       the word the address names
 *   tgt_rsp --> kind (Fifo: a line read?) --> gather words 0 .. LINE_WORDS-2; the last
 *               word with them --> rsp (a line);  a single word --> into every word
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
    // @kb: rtl/lib/block/bursts
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

        logic [LINE_WORDS-1:0][WORD_WIDTH-1:0]  words;      // the request's line, by word
        logic [LINE_WORDS-1:0][WSTRB_WIDTH-1:0] strbs;      // ... its strobes
        logic [LINE_WORDS-1:0]                  strobed;    // a word with strobes
        logic                                   line;       // the request is a line's size
        logic                                   line_rd;    // ... a read: a burst
        logic                                   line_wr;    // ... a write: the strobed word
        logic [WI-1:0]                          idx;        // the word it goes as
        logic                                   blocked;    // answered, and the queue full
        logic                                   take;       // the target takes the request
        // The kinds of the answers owed, oldest first.
        logic                                   kind;       // the oldest is a line read
        logic                                   empty;
        logic                                   full;
        // Status the block does not need.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [PENDING_WIDTH:0]                 count;
        logic                                   almost_full;
        logic                                   almost_empty;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [WI-1:0]                          k;          // words of the line come so far
        logic [LINE_WORDS-2:0][WORD_WIDTH-1:0]  gath;       // ... but the last, bypassed
        logic                                   last;       // the word come is a line's last

        // The word of the line with strobes (a store has one, a CBO none: word 0).
        function automatic logic [WI-1:0] strobed_word(input logic [LINE_WORDS-1:0] s);
            logic [WI-1:0] w;
            w = '0;
            for (int i = LINE_WORDS - 1; i >= 0; i--)
                if (s[i])
                    w = WI'(i);
            return w;
        endfunction

        assign words   = req_wdata;
        assign strbs   = req_wstrb;
        for (genvar i = 0; i < LINE_WORDS; i++) begin: g_strobed
            assign strobed[i] = |strbs[i];
        end
        assign line    = req_size == 3'(LINE_SIZE);
        assign line_rd = line && !req_we;
        assign line_wr = line && req_we;
        assign idx     = line_wr ? strobed_word(strobed) : req_addr[LINE_SIZE-1:WORD_SIZE];

        // The narrow request.
        assign blocked        = req_rsp && full;
        assign tgt_req_valid  = req_valid && !blocked;
        assign req_ready      = tgt_req_ready && !blocked;
        assign take           = tgt_req_valid && tgt_req_ready;
        assign tgt_req_we     = req_we;
        assign tgt_req_rsp    = req_rsp;
        assign tgt_req_len    = line_rd ? LEN_WIDTH'(LINE_WORDS - 1) : '0;
        assign tgt_req_addr   = line_wr ? {req_addr[ADDR_WIDTH-1:LINE_SIZE], idx,
                                           WORD_SIZE'(0)}
                                        : req_addr;
        assign tgt_req_size   = line ? 3'(WORD_SIZE) : req_size;
        assign tgt_req_wdata  = words[idx];
        assign tgt_req_wstrb  = strbs[idx];
        assign tgt_req_fields = req_fields;

        Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(1)) u_fifo_kind(
            .clk, .rst_n, .write(take && req_rsp), .data_in(line_rd), .read(rsp_valid),
            .data_out(kind), .empty, .full, .count, .almost_full, .almost_empty);

        // The answers: a line read's words gathered, the last bypassed; a single word into
        // every word of the line.
        assign last = k == WI'(LINE_WORDS - 1);

        always_ff @(posedge clk)
            if (!rst_n)
                k <= '0;
            else if (tgt_rsp_valid && kind)
                k <= last ? '0 : k + 1'b1;

        always_ff @(posedge clk)
            if (tgt_rsp_valid && kind && !last)
                gath[k] <= tgt_rsp_data;

        assign rsp_valid = tgt_rsp_valid && (!kind || last);
        assign rsp_data  = kind ? {tgt_rsp_data, gath} : {LINE_WORDS{tgt_rsp_data}};

        // A line is read or written whole: aligned, a read answered; a line write's store
        // is in one word.
        `DC_ASSERT(a_line_aligned, !(req_valid && line && req_addr[LINE_SIZE-1:0] != '0))
        `DC_ASSERT(a_line_read_answered, !(req_valid && line_rd && !req_rsp))
        `DC_ASSERT(a_line_write_one_word, !(req_valid && line_wr && !$onehot0(strobed)))
        `DC_ASSERT(a_answer_expected, !(tgt_rsp_valid && empty))
    end

    `DC_ASSERT(a_size_known, !(req_valid && req_size > 3'(WORD_SIZE) &&
                               req_size != 3'(LINE_SIZE)))

endmodule
