/* Strobed register: a register written byte by byte, as a device's registers are written
 * through the register port (kb pattern rtl/lib/block/plic/register_port).
 *
 * WIDTH bits, any number: bytes 0 to NBYTES - 1, the last one partial when WIDTH is not a
 * multiple of 8 (a PLIC priority of 3 bits is one partial byte). At a rising edge with we = 1
 * every byte b with wstrb[b] = 1 takes wdata's bits of that byte; the other bytes keep their
 * value, and without we all keep it. Reset sets RST_VAL. wdata and wstrb are the low WIDTH
 * bits and NBYTES strobes of the register port's access (acc_wdata, acc_wstrb of
 * RegPortTarget); we is "this register is written now" (the device's decode).
 *
 *   wdata, wstrb, we --> byte b: we & wstrb[b] ? wdata's byte : kept --> q
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module StrbReg #(
    parameter             WIDTH   = 32,                 // bits held
    parameter [WIDTH-1:0] RST_VAL = '0,                 // value after reset
    localparam            NBYTES  = (WIDTH + 7) / 8     // bytes, the last one may be partial
)(
    input  wire              clk,
    input  wire              rst_n,     // synchronous reset, active low
    input  wire              we,        // this register is written now
    input  wire [NBYTES-1:0] wstrb,     // bytes written
    input  wire [WIDTH-1:0]  wdata,     // the bytes, each at its place
    output logic [WIDTH-1:0] q
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    // @kb: rtl/lib/block/strb_reg/design
    always_ff @(posedge clk)
        if (!rst_n)
            q <= RST_VAL;
        else if (we)
            for (int i = 0; i < WIDTH; i++)
                if (wstrb[i / 8])
                    q[i] <= wdata[i];

    // Without a write the register keeps its value.
    `DC_ASSERT_NEXT(a_kept, !we, $stable(q))

endmodule
