/* UART receiver: receives asynchronous serial frames on rx, a byte a frame; behavioral.
 *
 * rx comes from a pin, asynchronous to clk: two flops bring it into clk's domain first
 * (metastability), as SignalClockSync does in the struct version. Then, at every tick
 * (OVERSAMPLE = 16 ticks a bit, from a TickGen in the device):
 *  - idle: a start bit is the line 0 at a tick after 1 at the tick before (a falling edge);
 *  - every bit, the start bit too, is decided by the majority of three samples at ticks 7, 8
 *    and 9 after that edge (its middle): a glitch of one sample does not change a bit (noise),
 *    and a start bit that is not 0 there is no start (a glitch on the idle line);
 *  - data bits, least significant first (5 + data_bits), the parity bit (parity), then the
 *    first stop bit: at its middle the frame is done. A second stop bit is idle line to the
 *    receiver (as a 16550: it checks the first stop bit only).
 * out_valid is 1 for a clock with out_data, frame_err (the stop bit is 0) and parity_err
 * (the parity bit is wrong); a byte with an error is given too (out_data changes while a
 * frame comes in: read it with out_valid). The format is read at the start bit. After a
 * frame the line must be 1 at a tick before a new start bit (a stop bit 0 starts nothing).
 *
 *   rx --2 flops--> rx_s --at ticks--> edge: start --> count 16 ticks a bit -->
 *       samples at 7, 8, 9 --> majority --> start check, data, parity, stop --> out_*
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartRx import UartPkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  wire        tick,        // OVERSAMPLE ticks a bit
    input  data_bits_t data_bits,   // 5 + data_bits data bits
    input  parity_e    parity,
    input  wire        rx,          // the serial line: a pin, asynchronous to clk
    output logic       out_valid,   // a frame is received: for one clock
    output logic [7:0] out_data,
    output logic       frame_err,   // its stop bit was 0
    output logic       parity_err   // its parity bit was wrong
);
    localparam CW = $clog2(OVERSAMPLE);

    logic [1:0]    sync;            // the synchronizer: rx_s = sync[1]
    logic          rx_s;
    logic          last;            // rx_s at the tick before (idle)
    logic          busy;            // a frame is received
    logic [CW-1:0] count;           // ticks since its start edge, in the bit
    logic [3:0]    bit_n;           // the bit decided next: 0 the start bit
    logic [1:0]    samples;         // the samples at ticks 7 and 8
    logic          maj;             // the bit, at tick 9: the majority of the three samples
    logic [3:0]    n_data;          // the format of the frame received, read at its start
    parity_e       par;
    logic          p;               // the parity of its data bits so far

    // @kb: rtl/lib/io/uart/design
    always_ff @(posedge clk)
        sync <= {sync[0], rx};
    assign rx_s = sync[1];

    assign maj = (samples[0] & samples[1]) | (samples[0] & rx_s) | (samples[1] & rx_s);

    always_ff @(posedge clk)
        if (!rst_n) begin
            busy      <= 1'b0;
            last      <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (tick && !busy) begin
                last <= rx_s;
                if (last && !rx_s) begin            // a falling edge: maybe a start bit
                    busy     <= 1'b1;
                    count    <= '0;
                    bit_n    <= '0;
                    n_data   <= 4'(5 + int'(data_bits));
                    par      <= parity;
                    p        <= 1'b0;
                    out_data <= '0;                 // a shorter format: 0 in the bits above
                end
            end else if (tick) begin
                count <= count + 1'b1;
                if (count == CW'(7))
                    samples[0] <= rx_s;
                if (count == CW'(8))
                    samples[1] <= rx_s;
                if (count == CW'(9)) begin          // the middle of the bit: decide it
                    bit_n <= bit_n + 1'b1;
                    if (bit_n == 4'd0) begin
                        if (maj)
                            busy <= 1'b0;           // no start bit: a glitch
                    end else if (bit_n <= n_data) begin
                        out_data[3'(bit_n - 4'd1)] <= maj;
                        p                      <= p ^ maj;
                    end else if (bit_n == n_data + 4'd1 && par != PARITY_NONE) begin
                        parity_err <= maj != ((par == PARITY_ODD) ? !p : p);
                    end else begin                  // the first stop bit: the frame is done
                        frame_err  <= !maj;
                        if (par == PARITY_NONE)
                            parity_err <= 1'b0;
                        out_valid  <= 1'b1;
                        busy       <= 1'b0;
                        last       <= maj;          // a stop bit 0: wait for the line at 1
                    end
                end
            end
        end

    // A frame ends at least one bit after it started; out_valid lasts one clock.
    `DC_ASSERT_NEXT(a_valid_one_clock, out_valid, !out_valid)

endmodule
