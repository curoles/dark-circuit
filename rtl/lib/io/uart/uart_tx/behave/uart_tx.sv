/* UART transmitter: sends each byte it takes as an asynchronous serial frame on tx;
 * behavioral.
 *
 * The frame format (UartPkg: data_bits, parity, stop2) is read when a byte is taken. A byte is
 * taken on the input channel (in_valid, in_ready; the library's valid/ready rules) while
 * nothing is sent: in_ready = !busy, from a flop. The frame starts at the next tick and every
 * bit lasts OVERSAMPLE (16) ticks exactly, so the bit rate is the tick rate / 16 (tick: a
 * TickGen in the device). tx comes from a flop (a pin must not glitch): the frame shifts out,
 * least significant bit first, ones shift in behind it, so tx is 1 when idle and during
 * reset. busy is 1 from the taken byte to the end of its last stop bit.
 *
 *   in_data, format --> frame (start, data, parity, stop) --hold--> at a tick: shift --> tx
 *   tick --> count 16 ticks a bit --> shift the next bit out; after the last bit: !busy
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartTx import UartPkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  wire        tick,        // OVERSAMPLE ticks a bit
    input  data_bits_t data_bits,   // 5 + data_bits data bits
    input  parity_e    parity,
    input  wire        stop2,       // 2 stop bits, else 1
    input  wire        in_valid,    // a byte to send
    output wire        in_ready,
    input  wire [7:0]  in_data,
    output wire        tx,          // the serial line
    output logic       busy         // a byte is taken, its frame not sent yet
);
    localparam CW = $clog2(OVERSAMPLE);

    logic [FRAME_MAX-1:0] hold;     // the frame of the byte taken, until it starts
    logic [FRAME_MAX-1:0] shift;    // the frame on the line, bit 0 out
    logic                 started;  // the frame is on the line (it starts at a tick)
    logic [3:0]           left;     // its bits not finished yet
    logic [CW-1:0]        count;    // ticks of the bit on the line so far
    logic                 take;

    // The bits of a frame, bit 0 (the start bit) first; ones above the last stop bit.
    function automatic logic [FRAME_MAX-1:0] frame_of(input logic [7:0] d, input data_bits_t db,
                                                      input parity_e par);
        logic [FRAME_MAX-1:0] f;
        logic                 p;
        int                   n;
        n    = 5 + int'(db);
        f    = '1;
        f[0] = 1'b0;
        p    = 1'b0;
        for (int i = 0; i < 8; i++)
            if (i < n) begin
                f[1 + i] = d[i];
                p        = p ^ d[i];
            end
        if (par != PARITY_NONE)
            f[1 + n] = (par == PARITY_ODD) ? !p : p;
        return f;
    endfunction

    // Bits of a frame: 1 start, 5 + db data, 0 or 1 parity, 1 or 2 stop.
    function automatic logic [3:0] bits_of(input data_bits_t db, input parity_e par,
                                           input logic two);
        return 4'(7 + int'(db) + ((par != PARITY_NONE) ? 1 : 0) + (two ? 1 : 0));
    endfunction

    // @kb: rtl/lib/io/uart/design
    assign in_ready = !busy;
    assign take     = in_valid && in_ready;
    assign tx       = shift[0];

    always_ff @(posedge clk)
        if (!rst_n) begin
            busy    <= 1'b0;
            started <= 1'b0;
            shift   <= '1;
        end else if (take) begin
            hold    <= frame_of(in_data, data_bits, parity);
            left    <= bits_of(data_bits, parity, stop2);
            busy    <= 1'b1;
            started <= 1'b0;
        end else if (busy && tick) begin
            if (!started) begin                 // the frame starts at a tick
                started <= 1'b1;
                shift   <= hold;
                count   <= '0;
            end else if (count == CW'(OVERSAMPLE - 1)) begin
                count <= '0;
                shift <= {1'b1, shift[FRAME_MAX-1:1]};
                left  <= left - 1'b1;
                if (left == 4'd1) begin         // the last bit ends: the line is 1 behind it
                    busy    <= 1'b0;
                    started <= 1'b0;
                end
            end else
                count <= count + 1'b1;
        end

    // A byte is taken only while nothing is sent; the line is 1 while idle.
    `DC_ASSERT(a_idle_line, busy || tx)

endmodule
