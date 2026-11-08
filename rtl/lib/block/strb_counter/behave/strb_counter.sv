/* Strobed counter: a counter that is also a strobed register (StrbReg), written byte by byte
 * through the register port and counting otherwise.
 *
 * WIDTH bits, any number: bytes 0 to NBYTES - 1, the last one partial when WIDTH is not a
 * multiple of 8. At a rising edge with we = 1 every byte b with wstrb[b] = 1 takes wdata's
 * bits of that byte, the other bytes keep their value, and it does not count: a write wins.
 * With we = 0 and inc = 1 it counts, q + 1 (wrapping to 0 after all ones); else it keeps its
 * value. Reset sets RST_VAL. For a device's counter that software reads and sets, such as a
 * timer's time (Timer's mtime) or an event count; wdata, wstrb and we as for StrbReg.
 *
 *   we, wstrb, wdata --> byte b: wstrb[b] ? wdata's byte : kept --+
 *   inc -----------------> q + 1 ----------------------------------+--> q
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module StrbCounter #(
    parameter             WIDTH   = 64,                 // bits held
    parameter [WIDTH-1:0] RST_VAL = '0,                 // value after reset
    localparam            NBYTES  = (WIDTH + 7) / 8     // bytes, the last one may be partial
)(
    input  wire              clk,
    input  wire              rst_n,     // synchronous reset, active low
    input  wire              we,        // this register is written now
    input  wire [NBYTES-1:0] wstrb,     // bytes written
    input  wire [WIDTH-1:0]  wdata,     // the bytes, each at its place
    input  wire              inc,       // count now (unless written)
    output logic [WIDTH-1:0] q
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    // @kb: rtl/lib/block/strb_counter/design
    always_ff @(posedge clk)
        if (!rst_n)
            q <= RST_VAL;
        else if (we) begin
            for (int i = 0; i < WIDTH; i++)
                if (wstrb[i / 8])
                    q[i] <= wdata[i];
        end else if (inc)
            q <= q + 1'b1;

    // Without a write or a count the counter keeps its value; a count adds one.
    `DC_ASSERT_NEXT(a_kept, !we && !inc, $stable(q))
    `DC_ASSERT_NEXT(a_count, !we && inc, q == WIDTH'($past(q) + 1'b1))

endmodule
