/* UART line models for testbenches: SimUartTx sends frames on a serial line, SimUartRx
 * receives them (a console: it prints the characters and keeps them).
 *
 * The frame (asynchronous serial, the line idle at 1): a start bit 0, DATA_BITS data bits
 * (5 to 8), least significant first, a parity bit when PARITY is not 0 (1 even: the data and
 * parity bits have an even number of ones; 2 odd), STOP_BITS stop bits 1 (1 or 2). A bit
 * lasts CLKS_PER_BIT clocks (at least 4); the models count clocks, no time delays, so they
 * run on Icarus and Verilator alike. Both run on the rising edge of clk; their state changes
 * with nonblocking assignments only (the next values are computed in locals of the clocked
 * process), so a testbench that reads it at the same edge sees the values of that clock.
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

    always @(posedge clk) begin: p_line
        // The next state, from the state of this clock.
        logic [NBITS-1:0] n_bits;
        int               n_bit;
        int               n_clk;
        int               n_idle;
        bit               n_busy;
        bit               n_bad_stop;
        logic             n_tx;
        bit               start;        // the next frame of the queue goes on the line now
        frame_t           f;
        n_bits     = bits;
        n_bit      = bit_n;
        n_clk      = clk_n;
        n_idle     = idle_left;
        n_busy     = busy;
        n_bad_stop = cur_bad_stop;
        n_tx       = tx;
        start      = 1'b0;
        if (!rst_n) begin
            n_tx   = 1'b1;
            n_busy = 1'b0;
            n_idle = 0;
        end else if (busy) begin
            if (clk_n < CLKS_PER_BIT - 1)
                n_clk = clk_n + 1;
            else begin
                n_clk = 0;
                n_bit = bit_n + 1;
                if (n_bit < NBITS)
                    n_tx = bits[n_bit];
                else begin
                    // The frame is sent: gap idle bits (at least one after a stop bit 0, so
                    // that the next start bit is a falling edge), else the next frame now.
                    n_busy = 1'b0;
                    n_tx   = 1'b1;
                    n_idle = ((cur_bad_stop && gap == 0) ? 1 : gap) * CLKS_PER_BIT;
                    start  = n_idle == 0 && queue.size() > 0;
                end
            end
        end else if (idle_left > 0) begin
            n_idle = idle_left - 1;
            start  = n_idle == 0 && queue.size() > 0;
        end else
            start = queue.size() > 0;
        if (start) begin
            f          = queue.pop_front();
            n_bits     = frame_bits(f);
            n_bad_stop = f[8];
            n_bit      = 0;
            n_clk      = 0;
            n_busy     = 1'b1;
            n_tx       = n_bits[0];
        end
        tx           <= n_tx;
        bits         <= n_bits;
        bit_n        <= n_bit;
        clk_n        <= n_clk;
        idle_left    <= n_idle;
        busy         <= n_busy;
        cur_bad_stop <= n_bad_stop;
    end

    initial if (CLKS_PER_BIT < 4 || DATA_BITS < 5 || DATA_BITS > 8 || PARITY < 0 || PARITY > 2 ||
                STOP_BITS < 1 || STOP_BITS > 2)
        $fatal(1, "SimUartTx: unsupported frame format or rate");

endmodule

/* SimUartRx: receives frames on rx. A start bit is a falling edge from 1, checked again in the
 * middle of the bit (still 0, else a glitch: ignored); every later bit is sampled in its
 * middle, CLKS_PER_BIT clocks apart. A byte is kept (received; got() gives them as a string)
 * also when its frame has an error: a stop bit 0 counts in framing_errors, a wrong parity bit
 * in parity_errors. With ECHO = 1 every character is printed with $write as it comes. After a
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
    int         framing_errors;
    int         parity_errors;
    bit         armed;                  // the line was 1 since the last frame: a 0 is a start
    bit         busy;                   // a frame is being received
    int         bit_n;                  // the bit to sample next
    int         wait_n;                 // clocks to its middle
    logic [NBITS-1:0] bits;             // the bits sampled

    initial begin
        framing_errors = 0;
        parity_errors  = 0;
        armed          = 1'b0;
        busy           = 1'b0;
    end

    // The bytes received, as characters.
    function automatic string got();
        string s;
        s = "";
        foreach (received[i])
            s = $sformatf("%s%c", s, received[i]);
        return s;
    endfunction

    function automatic void clear();
        received.delete();
        framing_errors = 0;
        parity_errors  = 0;
    endfunction

    // A complete frame: {a stop bit 0, a wrong parity bit, the data}.
    function automatic logic [9:0] decode(input logic [NBITS-1:0] f);
        logic [7:0] data;
        logic       p;
        logic       perr;
        logic       ferr;
        data = '0;
        p    = 1'b0;
        perr = 1'b0;
        ferr = 1'b0;
        for (int i = 0; i < DATA_BITS; i++) begin
            data[i] = f[1 + i];
            p       = p ^ f[1 + i];
        end
        if (PARITY != 0 && f[1 + DATA_BITS] !== ((PARITY == 2) ? !p : p))
            perr = 1'b1;
        for (int s = NBITS - STOP_BITS; s < NBITS; s++)
            if (f[s] !== 1'b1)
                ferr = 1'b1;
        return {ferr, perr, data};
    endfunction

    always @(posedge clk) begin: p_line
        // The next state, from the state of this clock.
        logic [NBITS-1:0] n_bits;
        int               n_bit;
        int               n_wait;
        bit               n_busy;
        bit               n_armed;
        logic [9:0]       frame;        // a complete frame, decoded
        n_bits  = bits;
        n_bit   = bit_n;
        n_wait  = wait_n;
        n_busy  = busy;
        n_armed = armed;
        if (!rst_n) begin
            n_armed = 1'b0;
            n_busy  = 1'b0;
        end else if (!busy) begin
            if (rx === 1'b1)
                n_armed = 1'b1;
            else if (armed && rx === 1'b0) begin       // a falling edge: maybe a start bit
                n_busy = 1'b1;
                n_bit  = 0;
                n_wait = (CLKS_PER_BIT - 1) / 2 - 1;    // the middle of the start bit
            end
        end else if (wait_n > 0)
            n_wait = wait_n - 1;
        else begin
            n_bits[bit_n] = rx;
            if (bit_n == 0 && rx !== 1'b0)
                n_busy = 1'b0;                          // a glitch, no start bit
            else if (bit_n == NBITS - 1) begin
                frame = decode(n_bits);
                received.push_back(frame[7:0]);
                framing_errors <= framing_errors + int'(frame[9]);
                parity_errors  <= parity_errors + int'(frame[8]);
                if (ECHO != 0)
                    $write("%c", frame[7:0]);
                n_busy  = 1'b0;
                n_armed = 1'b0;
            end else begin
                n_bit  = bit_n + 1;
                n_wait = CLKS_PER_BIT - 1;
            end
        end
        bits   <= n_bits;
        bit_n  <= n_bit;
        wait_n <= n_wait;
        busy   <= n_busy;
        armed  <= n_armed;
    end

    initial if (CLKS_PER_BIT < 4 || DATA_BITS < 5 || DATA_BITS > 8 || PARITY < 0 || PARITY > 2 ||
                STOP_BITS < 1 || STOP_BITS > 2)
        $fatal(1, "SimUartRx: unsupported frame format or rate");

endmodule
