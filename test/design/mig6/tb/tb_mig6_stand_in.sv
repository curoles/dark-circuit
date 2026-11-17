/* A stand-in core for Mig6's network tests: the requester of a library request channel, a
 * word wide, in place of Mig6Core and Mig6Pe's word pick.
 *
 * First a fixed start in its window of WORDS words at BASE (every word written, two read
 * back, an atomic add), then N_REQS random requests in the window: reads, writes and
 * atomics of the nine operations, bytes, halfwords and words with their strobes, CBOs, with
 * random gaps; an offer stays the same until taken. Every N_REQS / N_COUNTER requests, if
 * N_COUNTER is above 0, one of them is an atomic add of 1 to the shared counter at
 * COUNTER_ADDR instead. A shadow memory of the window, updated in the order the requests
 * are taken, gives each read's and atomic's answer, which the stand-in computes itself (the
 * window is its own: no other requester writes it); every answer must be the oldest
 * expected one. A counter add's answer (the old count) cannot be known here, as other
 * requesters add too: it goes to counter_olds, for the test to check. At the end every
 * opcode must have been sent and an offer must have waited (req_ready low); then done.
 * Checks before the end of a clock (the falling edge), drives after its rising edge.
 * Stops at the first mismatch with $fatal.
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
    output logic [DATA_WIDTH-1:0] req_wdata,
    output logic [STRB_WIDTH-1:0] req_wstrb,
    input  wire                   rsp_valid,
    input  wire  [DATA_WIDTH-1:0] rsp_data,
    output logic                  done
);
    localparam N_FIXED = WORDS + 3;     // the fixed start: writes, two reads, an atomic
    localparam SPACING = (N_COUNTER > 0) ? N_REQS / N_COUNTER : N_REQS + 1;

    // An expected answer: a known word, or a counter add's old count.
    typedef struct packed {
        logic        counter;
        logic [31:0] data;
    } expect_t;

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
    integer                   n_sent;               // requests taken
    integer                   n_counter;            // counter adds offered
    integer                   n_op [8];             // per opcode, by its value
    integer                   n_not_ready;          // clocks with an offer not taken
    logic                     taken;                // the offer is taken at the next edge
    logic                     is_counter;           // the offer is a counter add
    req_op_e                  op;
    logic [31:0]              old;
    logic [$clog2(WORDS)-1:0] w;                    // the word of a request in the window

    // A request offered: the fixed start, a counter add, or a random one.
    task automatic offer(input integer k);
        integer      word;
        integer      kind;
        integer      off;

        word       = {$random(seed)} % WORDS;
        req_we     = 1'b0;
        req_atop   = ATOP_NONE;
        req_cmo    = CachePkg::CMO_NONE;
        req_wdata  = $random(seed);
        req_wstrb  = '0;
        req_size   = SIZE_WIDTH'(2);
        is_counter = 1'b0;
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
            is_counter = 1'b1;                  // an add of 1 to the shared counter
            req_atop   = ATOP_LD_ADD;
            req_wdata  = 32'd1;
            n_counter  = n_counter + 1;
        end else begin
            kind = {$random(seed)} % 20;
            if (kind < 6) begin                 // a read
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
            end else begin                      // a CBO, a write without strobes
                req_we  = 1'b1;
                req_cmo = CachePkg::cmo_t'(1 + {$random(seed)} % 3);
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
        req_addr  = is_counter ? ADDR_WIDTH'(COUNTER_ADDR) : ADDR_WIDTH'(BASE + 4 * word + off);
        req_valid = 1'b1;
    endtask

    initial begin
        done        = 1'b0;
        req_valid   = 1'b0;
        seed        = SEED;
        cycle       = 0;
        n_sent      = 0;
        n_counter   = 0;
        n_not_ready = 0;
        for (int i = 0; i < 8; i++) n_op[i] = 0;
        wait (rst_n);
        while (!(n_sent == N_FIXED + N_REQS && expect_q.size() == 0 && !req_valid)) begin
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
                if (expect_q[0].counter)
                    counter_olds.push_back(rsp_data);
                else if (rsp_data !== expect_q[0].data)
                    $fatal(1, "Mig6 stand-in %0d: answer %h, expected %h", ID, rsp_data,
                           expect_q[0].data);
                void'(expect_q.pop_front());
            end
            if (taken) begin                    // the shadow memory, the expected answer
                w  = req_addr[$clog2(WORDS)+1:2];
                op = (req_cmo != CachePkg::CMO_NONE) ? REQ_CBO
                   : (req_atop != ATOP_NONE) ? REQ_ATOMIC : req_we ? REQ_WRITE : REQ_READ;
                n_op[op] = n_op[op] + 1;
                if (is_counter)
                    expect_q.push_back('{counter: 1'b1, data: '0});
                else
                    case (op)
                        REQ_READ:
                            expect_q.push_back('{counter: 1'b0, data: shadow[w]});
                        REQ_WRITE:
                            for (int b = 0; b < 4; b++)
                                if (req_wstrb[b]) shadow[w][8*b +: 8] = req_wdata[8*b +: 8];
                        REQ_ATOMIC: begin
                            old = shadow[w];
                            expect_q.push_back('{counter: 1'b0, data: old});
                            shadow[w] = amo(req_atop, old, req_wdata);
                        end
                        default: ;              // REQ_CBO: nothing changes
                    endcase
                n_sent = n_sent + 1;
            end
            @(posedge clk);
            #1;
            if (taken) req_valid = 1'b0;
            if (!req_valid && n_sent < N_FIXED + N_REQS
                && (n_sent < N_FIXED || {$random(seed)} % 4 != 0))
                offer(n_sent);
        end
        $display("Mig6 stand-in %0d: %0d requests in %0d clocks, %0d not ready", ID, n_sent,
                 cycle, n_not_ready);
        $display("Mig6 stand-in %0d: read %0d write %0d atomic %0d cbo %0d, counter adds %0d",
                 ID, n_op[REQ_READ], n_op[REQ_WRITE], n_op[REQ_ATOMIC], n_op[REQ_CBO],
                 n_counter);
        if (n_op[REQ_READ] == 0 || n_op[REQ_WRITE] == 0 || n_op[REQ_ATOMIC] == 0
            || n_op[REQ_CBO] == 0 || n_not_ready == 0 || n_counter != N_COUNTER)
            $fatal(1, "Mig6 stand-in %0d: a case never happened (a count above is 0)", ID);
        done = 1'b1;
    end
endmodule
