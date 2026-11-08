/* UART line models for testbenches: SimUartTx sends frames on a serial line, SimUartRx
 * receives them (a console: it prints the characters and keeps them).
 *
 * The frame (asynchronous serial, the line idle at 1): a start bit 0, DATA_BITS data bits
 * (5 to 8), least significant first, a parity bit when PARITY is not 0 (1 even: the data and
 * parity bits have an even number of ones; 2 odd), STOP_BITS stop bits 1 (1 or 2). A bit
 * lasts CLKS_PER_BIT clocks (at least 4); the models count clocks, no time delays, so they
 * run on Icarus and Verilator alike. Both run on the rising edge of clk.
 *
 *   tx/rx:  1 1 1 | 0 | d0 d1 ... d(n-1) | p | 1 (1) | 1 1 ...
 *                 start  data, LSB first  parity stop   idle
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

/* SimUartTx: sends the frames of its queue on tx, back to back or with gap idle bits between
 * them (set by the testbench). push() a byte (its DATA_BITS low bits), send() a string;
 * push_bad() a frame with a wrong stop bit (0, a framing error) or a wrong parity bit, to test
 * a receiver (it is followed by at least one idle bit); idle() is 1 when everything is sent.
 * Frames are back to back when gap is 0: the next start bit follows the last stop bit. tx is
 * 1 during reset and between frames.
 */
module SimUartTx #(
    parameter CLKS_PER_BIT = 16,        // clocks of a bit
    parameter DATA_BITS    = 8,         // 5 to 8
    parameter PARITY       = 0,         // 0 none, 1 even, 2 odd
    parameter STOP_BITS    = 1          // 1 or 2
)(
    input  wire  clk,
    input  wire  rst_n,                 // synchronous reset, active low
    output logic tx                     // the serial line
);
    localparam NBITS = 1 + DATA_BITS + (PARITY != 0 ? 1 : 0) + STOP_BITS;  // bits of a frame

    // A frame to send: {bad_parity (the parity bit inverted), bad_stop (the first stop bit 0),
    // data}. A vector, not a struct: Icarus has no queues of structs.
    typedef logic [9:0] frame_t;

    frame_t     queue[$];
    int         gap = 0;                // idle bits after every frame, set by the testbench
    logic [NBITS-1:0] bits;             // the frame on the line, bit 0 first
    int         bit_n;                  // the bit on the line
    int         clk_n;                  // clocks of it so far
    int         idle_left;              // idle clocks before the next frame
    bit         busy;                   // a frame is on the line
    bit         cur_bad_stop;           // ... with a stop bit 0

    initial begin
        busy      = 1'b0;
        idle_left = 0;
    end

    function automatic void push(input logic [7:0] data);
        queue.push_back({2'b00, data});
    endfunction

    function automatic void push_bad(input logic [7:0] data, input bit bad_stop,
                                     input bit bad_parity);
        queue.push_back({bad_parity, bad_stop, data});
    endfunction

    function automatic void send(input string s);
        for (int i = 0; i < s.len(); i++)
            push(s[i]);
    endfunction

    function automatic bit idle();
        return queue.size() == 0 && !busy && idle_left == 0;
    endfunction

    // The bits of a frame, bit 0 (the start bit) first.
    function automatic logic [NBITS-1:0] frame_bits(input frame_t f);
        logic [NBITS-1:0] b;
        logic             p;
        b = '1;
        b[0] = 1'b0;
        p = 1'b0;
        for (int i = 0; i < DATA_BITS; i++) begin
            b[1 + i] = f[i];
            p        = p ^ f[i];
        end
        if (PARITY != 0)
            b[1 + DATA_BITS] = ((PARITY == 2) ? !p : p) ^ f[9];
        if (f[8])
            b[NBITS - STOP_BITS] = 1'b0;
        return b;
    endfunction

    // A model: its state changes at once inside the clocked process (blocking assignments);
    // only the line is a delayed assignment.
    /* verilator lint_off BLKSEQ */

    // The next frame of the queue goes on the line now.
    task automatic start_frame();
        frame_t f;
        f            = queue.pop_front();
        bits         = frame_bits(f);
        cur_bad_stop = f[8];
        bit_n        = 0;
        clk_n        = 0;
        busy         = 1'b1;
        tx          <= bits[0];
    endtask

    always @(posedge clk)
        if (!rst_n) begin
            tx       <= 1'b1;
            busy      = 1'b0;
            idle_left = 0;
        end else if (busy) begin
            if (clk_n < CLKS_PER_BIT - 1)
                clk_n = clk_n + 1;
            else begin
                clk_n = 0;
                bit_n = bit_n + 1;
                if (bit_n < NBITS)
                    tx <= bits[bit_n];
                else begin
                    // The frame is sent: gap idle bits (at least one after a stop bit 0, so
                    // that the next start bit is a falling edge), else the next frame now.
                    busy      = 1'b0;
                    idle_left = ((cur_bad_stop && gap == 0) ? 1 : gap) * CLKS_PER_BIT;
                    if (idle_left == 0 && queue.size() > 0)
                        start_frame();
                    else
                        tx <= 1'b1;
                end
            end
        end else if (idle_left > 0) begin
            idle_left = idle_left - 1;
            if (idle_left == 0 && queue.size() > 0)
                start_frame();
        end else if (queue.size() > 0)
            start_frame();

    /* verilator lint_on BLKSEQ */

    initial if (CLKS_PER_BIT < 4 || DATA_BITS < 5 || DATA_BITS > 8 || PARITY < 0 || PARITY > 2 ||
                STOP_BITS < 1 || STOP_BITS > 2)
        $fatal(1, "SimUartTx: unsupported frame format or rate");

endmodule

/* SimUartRx: receives frames on rx. A start bit is a falling edge from 1, checked again in the
 * middle of the bit (still 0, else a glitch: ignored); every later bit is sampled in its
 * middle, CLKS_PER_BIT clocks apart. A byte is kept (received, the characters in text) also
 * when its frame has an error: a stop bit 0 counts in framing_errors, a wrong parity bit in
 * parity_errors. With ECHO = 1 every character is printed with $write as it comes. After a
 * frame it waits for the line to be 1 before a new start bit (a stop bit 0 is no start).
 */
module SimUartRx #(
    parameter CLKS_PER_BIT = 16,        // clocks of a bit
    parameter DATA_BITS    = 8,         // 5 to 8
    parameter PARITY       = 0,         // 0 none, 1 even, 2 odd
    parameter STOP_BITS    = 1,         // 1 or 2
    parameter ECHO         = 1          // print the characters
)(
    input  wire  clk,
    input  wire  rst_n,                 // synchronous reset, active low
    input  wire  rx                     // the serial line
);
    localparam NBITS = 1 + DATA_BITS + (PARITY != 0 ? 1 : 0) + STOP_BITS;  // bits of a frame

    logic [7:0] received[$];            // the bytes, in order
    string      text;                   // ... as characters
    int         framing_errors;
    int         parity_errors;
    bit         armed;                  // the line was 1 since the last frame: a 0 is a start
    bit         busy;                   // a frame is being received
    int         bit_n;                  // the bit to sample next
    int         wait_n;                 // clocks to its middle
    logic [NBITS-1:0] bits;             // the bits sampled

    initial begin
        text           = "";
        framing_errors = 0;
        parity_errors  = 0;
        armed          = 1'b0;
        busy           = 1'b0;
    end

    function automatic string got();
        return text;
    endfunction

    function automatic void clear();
        received.delete();
        text           = "";
        framing_errors = 0;
        parity_errors  = 0;
    endfunction

    // The frame is complete: keep its byte, check its parity and stop bits.
    function automatic void frame_done();
        logic [7:0] data;
        logic       p;
        data = '0;
        p    = 1'b0;
        for (int i = 0; i < DATA_BITS; i++) begin
            data[i] = bits[1 + i];
            p       = p ^ bits[1 + i];
        end
        if (PARITY != 0 && bits[1 + DATA_BITS] !== ((PARITY == 2) ? !p : p))
            parity_errors = parity_errors + 1;
        for (int s = NBITS - STOP_BITS; s < NBITS; s++)
            if (bits[s] !== 1'b1) begin
                framing_errors = framing_errors + 1;
                break;
            end
        received.push_back(data);
        text = $sformatf("%s%c", text, data);
        if (ECHO != 0)
            $write("%c", data);
    endfunction

    // A model: its state changes at once inside the clocked process (blocking assignments);
    // only the line is a delayed assignment.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk)
        if (!rst_n) begin
            armed = 1'b0;
            busy  = 1'b0;
        end else if (!busy) begin
            if (rx === 1'b1)
                armed = 1'b1;
            else if (armed && rx === 1'b0) begin       // a falling edge: maybe a start bit
                busy   = 1'b1;
                bit_n  = 0;
                wait_n = (CLKS_PER_BIT - 1) / 2 - 1;    // the middle of the start bit
            end
        end else if (wait_n > 0)
            wait_n = wait_n - 1;
        else begin
            bits[bit_n] = rx;
            if (bit_n == 0 && rx !== 1'b0)
                busy = 1'b0;                            // a glitch, no start bit
            else if (bit_n == NBITS - 1) begin
                frame_done();
                busy  = 1'b0;
                armed = 1'b0;
            end else begin
                bit_n  = bit_n + 1;
                wait_n = CLKS_PER_BIT - 1;
            end
        end

    /* verilator lint_on BLKSEQ */

    initial if (CLKS_PER_BIT < 4 || DATA_BITS < 5 || DATA_BITS > 8 || PARITY < 0 || PARITY > 2 ||
                STOP_BITS < 1 || STOP_BITS > 2)
        $fatal(1, "SimUartRx: unsupported frame format or rate");

endmodule
