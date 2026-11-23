/* A stand-in core for Mig6's network tests: the requester of a library request channel, a
 * word wide, in place of Mig6Core and Mig6Pe's word pick.
 *
 * First a fixed start in its window of WORDS words at BASE (every word written, two read
 * back, an atomic add), then N_REQS random requests in the window: reads, writes and
 * atomics of the nine operations, bytes, halfwords and words with their strobes, burst
 * reads of 2 to 1 << LEN_WIDTH words (req_len, inside the window), CBOs, LRs and SCs
 * (exclusive, a word; most SCs to the word reserved), with random gaps; an offer
 * stays the same until taken; req_rsp is set exactly for the requests answered (all but a
 * write and a CBO). Every N_REQS / N_COUNTER requests, if N_COUNTER is above 0, one of them
 * is an atomic add of 1 to the shared counter at COUNTER_ADDR instead. A shadow memory of
 * the window, updated in the order the requests are taken, gives each read's, LR's and
 * atomic's answer (a burst's, one a word), which the stand-in computes itself (the window
 * is its own: no other
 * requester writes it); a model of its reservation (the monitor's: one word, set by an LR,
 * ended by its write, atomic or SC of that word, replaced by another LR) gives each SC's
 * status, SC_SUCCESS or SC_FAIL (a successful SC writes the shadow); every answer must be
 * the oldest expected one. A counter add's answer (the old count) cannot be known here, as
 * other requesters add too: it goes to counter_olds, for the test to check.
 * N_LRSC increments of the word at LRSC_ADDR, if N_LRSC is above 0, now and then between the
 * random requests, each a loop: an LR, wait for its answer, an SC of the answer + 1, wait
 * for its status, again until it succeeds (no other request between an LR and its SC, and
 * a new LR only with no answer owed); other requesters do
 * the same, so the SCs fail now and then (n_lrsc_fail), and the word must end up added
 * N_LRSC times by each, for the test to check. At the end every opcode must have been sent,
 * a burst read, an SC of the window must have succeeded and one failed, and an offer must
 * have waited
 * (req_ready low); then done. Checks before the end of a clock (the falling edge), drives
 * after its rising edge. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module TbMig6StandIn import Mig6NocPkg::*, AtomicPkg::*; #(
    parameter ID           = 0,         // for messages
    parameter SEED         = 1,
    parameter BASE         = 0,         // byte address of the window
    parameter WORDS        = 16,        // words of the window, a power of 2
    parameter N_REQS       = 3000,      // random requests after the fixed start
    parameter N_COUNTER    = 0,         // of them: atomic adds of 1 to the shared counter
    parameter COUNTER_ADDR = 0,         // byte address of the shared counter
    parameter N_LRSC       = 0,         // increments of the LR/SC word, loops of LR and SC
    parameter LRSC_ADDR    = 0,         // byte address of the LR/SC word
    parameter MAX_CYCLES   = 200000
)(
    input  wire                   clk,
    input  wire                   rst_n,
    output logic                  req_valid,
    input  wire                   req_ready,
    output logic                  req_we,
    output logic [ADDR_WIDTH-1:0] req_addr,
    output logic [SIZE_WIDTH-1:0] req_size,
    output atop_t                 req_atop,
    output CachePkg::cmo_t        req_cmo,
    output logic                  req_excl,
    output logic [LEN_WIDTH-1:0]  req_len,
    output logic                  req_rsp,
    output logic [DATA_WIDTH-1:0] req_wdata,
    output logic [STRB_WIDTH-1:0] req_wstrb,
    input  wire                   rsp_valid,
    input  wire  [DATA_WIDTH-1:0] rsp_data,
    output logic                  done
);
    localparam N_FIXED = WORDS + 3;     // the fixed start: writes, two reads, an atomic
    localparam SPACING = (N_COUNTER > 0) ? N_REQS / N_COUNTER : N_REQS + 1;

    // An expected answer: a known word (or an SC's status), a counter add's old count, an
    // LR/SC loop's LR (its answer makes the SC) or SC (its status ends the loop or not).
    typedef enum logic [1:0] {
        EXP_KNOWN,
        EXP_COUNTER,
        EXP_LRSC_LR,
        EXP_LRSC_SC
    } exp_kind_e;

    typedef struct packed {
        exp_kind_e   kind;
        logic [31:0] data;
    } expect_t;

    // An offer that is not a random one.
    typedef enum logic [1:0] {
        OFFER_RANDOM,
        OFFER_COUNTER,
        OFFER_LRSC_LR,
        OFFER_LRSC_SC
    } offer_e;

    // The LR/SC loop: none, its LR's answer awaited, its SC next, its SC's status awaited.
    typedef enum logic [1:0] {
        LOOP_IDLE,
        LOOP_WAIT_LR,
        LOOP_SC_NEXT,
        LOOP_WAIT_SC
    } loop_e;

    // The atomic operations, computed here (AtomicUnit uses Alu2): op(old, operand).
    localparam atop_t ATOPS [9] = '{ATOP_LD_ADD, ATOP_LD_CLR, ATOP_LD_EOR, ATOP_LD_SET,
                                    ATOP_LD_SMAX, ATOP_LD_SMIN, ATOP_LD_UMAX, ATOP_LD_UMIN,
                                    ATOP_SWAP};

    function automatic logic [31:0] amo(atop_t op, logic [31:0] old, logic [31:0] x);
        case (op)
            ATOP_LD_ADD:  return old + x;
            ATOP_LD_CLR:  return old & ~x;
            ATOP_LD_EOR:  return old ^ x;
            ATOP_LD_SET:  return old | x;
            ATOP_LD_SMAX: return ($signed(old) > $signed(x)) ? old : x;
            ATOP_LD_SMIN: return ($signed(old) < $signed(x)) ? old : x;
            ATOP_LD_UMAX: return (old > x) ? old : x;
            ATOP_LD_UMIN: return (old < x) ? old : x;
            default:      return x;     // ATOP_SWAP
        endcase
    endfunction

    logic [31:0]              shadow [WORDS];
    expect_t                  expect_q [$];
    logic [31:0]              counter_olds [$];     // the old counts its adds got back
    integer                   seed;
    integer                   cycle;
    integer                   n_sent;               // random and counter requests taken
    integer                   n_counter;            // counter adds offered
    integer                   n_op [8];             // per opcode, by its value
    integer                   n_not_ready;          // clocks with an offer not taken
    integer                   n_burst;              // burst reads taken
    integer                   n_sc_ok;              // SCs of the window that succeeded
    integer                   n_sc_fail;            // ... that failed
    integer                   n_lrsc_ok;            // LR/SC increments done
    integer                   n_lrsc_fail;          // their SCs that failed
    logic                     resv_valid;           // the model of the reservation
    logic [ADDR_WIDTH-1:0]    resv_addr;            // ... of this word
    loop_e                    loop;
    logic [31:0]              loop_val;             // the LR's answer: the SC writes it + 1
    logic                     taken;                // the offer is taken at the next edge
    offer_e                   offer_kind;
    req_op_e                  op;
    logic [31:0]              old;
    logic [ADDR_WIDTH-1:0]    word_addr;            // the word of a request
    logic [$clog2(WORDS)-1:0] w;                    // ... in the window

    // A request offered: the fixed start, a counter add, or a random one.
    task automatic offer(input integer k);
        integer      word;
        integer      kind;
        integer      off;

        word       = {$random(seed)} % WORDS;
        req_we     = 1'b0;
        req_atop   = ATOP_NONE;
        req_cmo    = CachePkg::CMO_NONE;
        req_excl   = 1'b0;
        req_wdata  = $random(seed);
        req_wstrb  = '0;
        req_len    = '0;
        req_size   = SIZE_WIDTH'(2);
        offer_kind = OFFER_RANDOM;
        if (k < WORDS) begin                    // fixed: write word k
            word      = k;
            req_we    = 1'b1;
            req_wstrb = '1;
        end else if (k < WORDS + 2) begin       // fixed: read words 0 and WORDS - 1
            word = (k == WORDS) ? 0 : WORDS - 1;
        end else if (k == WORDS + 2) begin      // fixed: an atomic add on word 1
            word     = 1;
            req_atop = ATOP_LD_ADD;
        end else if ((k - N_FIXED) % SPACING == 0 && n_counter < N_COUNTER) begin
            offer_kind = OFFER_COUNTER;         // an add of 1 to the shared counter
            req_atop   = ATOP_LD_ADD;
            req_wdata  = 32'd1;
            n_counter  = n_counter + 1;
        end else begin
            kind = {$random(seed)} % 26;
            if (kind >= 24) begin               // a burst read of words, inside the window
                word    = {$random(seed)} % (WORDS - 1);
                req_len = LEN_WIDTH'(1 + {$random(seed)} %
                                     ((WORDS - 1 - word < (1 << LEN_WIDTH) - 1)
                                      ? WORDS - 1 - word : (1 << LEN_WIDTH) - 1));
            end else if (kind < 6) begin        // a read
                req_size = SIZE_WIDTH'({$random(seed)} % 3);
            end else if (kind < 12) begin       // a write of a byte, a halfword or a word
                req_we   = 1'b1;
                req_size = SIZE_WIDTH'({$random(seed)} % 3);
                off      = (req_size == 0) ? {$random(seed)} % 4
                         : (req_size == 1) ? 2 * ({$random(seed)} % 2) : 0;
                req_wstrb = (req_size == 0) ? 4'b0001 << off
                          : (req_size == 1) ? 4'b0011 << off : 4'b1111;
            end else if (kind < 19) begin       // an atomic
                req_atop = ATOPS[{$random(seed)} % 9];
            end else if (kind < 20) begin       // a CBO, a write without strobes
                req_we  = 1'b1;
                req_cmo = CachePkg::cmo_t'(1 + {$random(seed)} % 3);
            end else if (kind < 22) begin       // an LR
                req_excl = 1'b1;
            end else begin                      // an SC, most to the word reserved
                req_excl  = 1'b1;
                req_we    = 1'b1;
                req_wstrb = '1;
                if (resv_valid && resv_addr - ADDR_WIDTH'(BASE) < ADDR_WIDTH'(4 * WORDS)
                    && {$random(seed)} % 4 != 0)
                    word = int'(resv_addr - ADDR_WIDTH'(BASE)) / 4;
            end
        end
        off = 0;
        if (req_we && req_cmo == CachePkg::CMO_NONE)
            for (int b = 0; b < 4; b++)
                if (req_wstrb[b]) begin
                    off = b;
                    break;
                end
        if (!req_we && req_size == 0) off = {$random(seed)} % 4;
        if (!req_we && req_size == 1) off = 2 * ({$random(seed)} % 2);
        req_addr  = (offer_kind == OFFER_COUNTER) ? ADDR_WIDTH'(COUNTER_ADDR)
                                                  : ADDR_WIDTH'(BASE + 4 * word + off);
        req_rsp   = !req_we || req_excl;        // all but a write and a CBO
        req_valid = 1'b1;
    endtask

    // The LR/SC loop's requests: its LR, its SC of the LR's answer + 1.
    task automatic offer_loop(input logic sc);
        req_we     = sc;
        req_atop   = ATOP_NONE;
        req_cmo    = CachePkg::CMO_NONE;
        req_excl   = 1'b1;
        req_rsp    = 1'b1;
        req_len    = '0;
        req_addr   = ADDR_WIDTH'(LRSC_ADDR);
        req_size   = SIZE_WIDTH'(2);
        req_wdata  = sc ? loop_val + 32'd1 : 32'd0;
        req_wstrb  = sc ? '1 : '0;
        offer_kind = sc ? OFFER_LRSC_SC : OFFER_LRSC_LR;
        req_valid  = 1'b1;
    endtask

    initial begin
        done        = 1'b0;
        req_valid   = 1'b0;
        seed        = SEED;
        cycle       = 0;
        n_sent      = 0;
        n_counter   = 0;
        n_not_ready = 0;
        n_burst     = 0;
        n_sc_ok     = 0;
        n_sc_fail   = 0;
        n_lrsc_ok   = 0;
        n_lrsc_fail = 0;
        resv_valid  = 1'b0;
        resv_addr   = '0;
        loop        = LOOP_IDLE;
        loop_val    = '0;
        offer_kind  = OFFER_RANDOM;
        for (int i = 0; i < 8; i++) n_op[i] = 0;
        wait (rst_n);
        while (!(n_sent == N_FIXED + N_REQS && n_lrsc_ok == N_LRSC && expect_q.size() == 0
                 && !req_valid)) begin
            @(negedge clk);
            taken = req_valid && req_ready;
            cycle = cycle + 1;
            if (cycle > MAX_CYCLES)
                $fatal(1, "Mig6 stand-in %0d: no end after %0d clocks: %0d taken, %0d owed",
                       ID, MAX_CYCLES, n_sent, expect_q.size());
            if (req_valid && !req_ready) n_not_ready = n_not_ready + 1;
            if (rsp_valid) begin
                if (expect_q.size() == 0)
                    $fatal(1, "Mig6 stand-in %0d: an answer %h, none expected", ID, rsp_data);
                case (expect_q[0].kind)
                    EXP_COUNTER:
                        counter_olds.push_back(rsp_data);
                    EXP_LRSC_LR: begin
                        loop_val = rsp_data;
                        loop     = LOOP_SC_NEXT;
                    end
                    EXP_LRSC_SC: begin
                        if (rsp_data == SC_SUCCESS) begin
                            n_lrsc_ok = n_lrsc_ok + 1;
                            loop      = LOOP_IDLE;
                        end else if (rsp_data == SC_FAIL) begin
                            n_lrsc_fail = n_lrsc_fail + 1;
                            loop        = LOOP_IDLE;    // again later, from a new LR
                        end else
                            $fatal(1, "Mig6 stand-in %0d: SC status %h", ID, rsp_data);
                    end
                    default:
                        if (rsp_data !== expect_q[0].data)
                            $fatal(1, "Mig6 stand-in %0d: answer %h, expected %h", ID, rsp_data,
                                   expect_q[0].data);
                endcase
                void'(expect_q.pop_front());
            end
            if (taken) begin                    // the shadow memory, the expected answer
                word_addr = {req_addr[ADDR_WIDTH-1:2], 2'b00};
                w  = req_addr[$clog2(WORDS)+1:2];
                op = (req_cmo != CachePkg::CMO_NONE) ? REQ_CBO
                   : (req_atop != ATOP_NONE) ? REQ_ATOMIC
                   : req_excl ? (req_we ? REQ_SC : REQ_LR) : req_we ? REQ_WRITE : REQ_READ;
                // The reservation, as the monitor keeps it.
                if (op == REQ_LR) begin
                    resv_valid = 1'b1;
                    resv_addr  = word_addr;
                end
                case (offer_kind)
                    OFFER_COUNTER: begin
                        expect_q.push_back('{kind: EXP_COUNTER, data: '0});
                        n_op[op] = n_op[op] + 1;
                        n_sent   = n_sent + 1;
                    end
                    OFFER_LRSC_LR: begin
                        expect_q.push_back('{kind: EXP_LRSC_LR, data: '0});
                        loop = LOOP_WAIT_LR;
                    end
                    OFFER_LRSC_SC: begin
                        expect_q.push_back('{kind: EXP_LRSC_SC, data: '0});
                        resv_valid = 1'b0;
                        loop       = LOOP_WAIT_SC;
                    end
                    default: begin
                        n_op[op] = n_op[op] + 1;
                        n_sent   = n_sent + 1;
                        case (op)
                            REQ_READ, REQ_LR: begin     // a word each, req_len + 1
                                for (int k = 0; k <= int'(req_len); k++)
                                    expect_q.push_back('{kind: EXP_KNOWN,
                                                         data: shadow[int'(w) + k]});
                                if (req_len != '0) n_burst = n_burst + 1;
                            end
                            REQ_WRITE: begin
                                for (int b = 0; b < 4; b++)
                                    if (req_wstrb[b]) shadow[w][8*b +: 8] = req_wdata[8*b +: 8];
                                if (resv_addr == word_addr) resv_valid = 1'b0;
                            end
                            REQ_ATOMIC: begin
                                old = shadow[w];
                                expect_q.push_back('{kind: EXP_KNOWN, data: old});
                                shadow[w] = amo(req_atop, old, req_wdata);
                                if (resv_addr == word_addr) resv_valid = 1'b0;
                            end
                            REQ_SC: begin
                                if (resv_valid && resv_addr == word_addr) begin
                                    expect_q.push_back('{kind: EXP_KNOWN, data: SC_SUCCESS});
                                    shadow[w] = req_wdata;
                                    n_sc_ok   = n_sc_ok + 1;
                                end else begin
                                    expect_q.push_back('{kind: EXP_KNOWN, data: SC_FAIL});
                                    n_sc_fail = n_sc_fail + 1;
                                end
                                resv_valid = 1'b0;
                            end
                            default: ;          // REQ_CBO: nothing changes
                        endcase
                    end
                endcase
            end
            @(posedge clk);
            #1;
            if (taken) req_valid = 1'b0;
            if (!req_valid) begin
                // The LR/SC loop first: its SC after its LR's answer; a new increment now and
                // then, and at the end until all are done; no other request meanwhile.
                if (loop == LOOP_SC_NEXT)
                    offer_loop(1'b1);
                else if (loop == LOOP_IDLE && n_lrsc_ok < N_LRSC && n_sent >= N_FIXED
                         && expect_q.size() == 0
                         && ({$random(seed)} % 16 == 0 || n_sent == N_FIXED + N_REQS))
                    offer_loop(1'b0);
                else if (loop == LOOP_IDLE && n_sent < N_FIXED + N_REQS
                         && (n_sent < N_FIXED || {$random(seed)} % 4 != 0))
                    offer(n_sent);
            end
        end
        $display("Mig6 stand-in %0d: %0d requests in %0d clocks, %0d not ready", ID, n_sent,
                 cycle, n_not_ready);
        $display("Mig6 stand-in %0d: read %0d (bursts %0d) write %0d atomic %0d", ID,
                 n_op[REQ_READ], n_burst, n_op[REQ_WRITE], n_op[REQ_ATOMIC]);
        $display("Mig6 stand-in %0d: cbo %0d lr %0d sc %0d", ID, n_op[REQ_CBO], n_op[REQ_LR],
                 n_op[REQ_SC]);
        $display("Mig6 stand-in %0d: SCs %0d ok %0d failed, counter %0d, LR/SC %0d (%0d failed)",
                 ID, n_sc_ok, n_sc_fail, n_counter, n_lrsc_ok, n_lrsc_fail);
        if (n_op[REQ_READ] == 0 || n_op[REQ_WRITE] == 0 || n_op[REQ_ATOMIC] == 0
            || n_op[REQ_CBO] == 0 || n_op[REQ_LR] == 0 || n_op[REQ_SC] == 0 || n_burst == 0
            || n_sc_ok == 0
            || n_sc_fail == 0 || n_not_ready == 0 || n_counter != N_COUNTER
            || n_lrsc_ok != N_LRSC)
            $fatal(1, "Mig6 stand-in %0d: a case never happened (a count above is 0)", ID);
        done = 1'b1;
    end
endmodule
