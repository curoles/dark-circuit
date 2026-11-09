/* UART watermarks: the interrupt conditions of a UART's FIFOs from their fill levels; made of
 * gates, wiring only.
 *
 * txwm: the transmit FIFO has fewer than tx_level entries (room for more: refill it); rxwm:
 * the receive FIFO has more than rx_level entries (drain it). These are SiFive's conditions
 * (txcnt, rxcnt; tx_level 0 never asks for bytes, rx_level 0 asks for every byte). ip has
 * both, ip & ie any of them is irq: a level, from the FIFOs' counters and the registers, so it
 * drops in the clock after the push or pop that ends the condition. That is before the answer
 * of the read that popped, so software needs no read-back before completing at a PLIC.
 *
 *   tx_count, tx_level --> CmpGe, Inv --> txwm --+--> ip --> And2 ie --> OrReduce --> irq
 *   rx_level, rx_count --> CmpGe, Inv --> rxwm --+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartWatermark #(
    parameter COUNT_WIDTH = 4,      // bits of a FIFO's count: 0 to its depth
    parameter LEVEL_WIDTH = 3       // bits of a watermark
)(
    input  wire [COUNT_WIDTH-1:0] tx_count,    // entries in the transmit FIFO
    input  wire [LEVEL_WIDTH-1:0] tx_level,
    input  wire [COUNT_WIDTH-1:0] rx_count,    // entries in the receive FIFO
    input  wire [LEVEL_WIDTH-1:0] rx_level,
    input  wire [1:0]             ie,          // [1] rxwm, [0] txwm
    output wire [1:0]             ip,          // [1] rxwm, [0] txwm
    output wire                   irq          // ip & ie, any
);
    `DC_STATIC_ASSERT(a_widths, COUNT_WIDTH > LEVEL_WIDTH && LEVEL_WIDTH >= 1)

    wire [COUNT_WIDTH-1:0] tx_at;       // tx_level, as wide as a count
    wire [COUNT_WIDTH-1:0] rx_at;
    wire                   tx_ge;       // tx_count >= tx_level
    wire                   rx_ge;       // rx_level >= rx_count
    wire [1:0]             on;          // ip & ie

    // @kb: rtl/lib/io/uart/uart_sifive/design
    assign tx_at = {{(COUNT_WIDTH - LEVEL_WIDTH){1'b0}}, tx_level};
    assign rx_at = {{(COUNT_WIDTH - LEVEL_WIDTH){1'b0}}, rx_level};
    CmpGe #(COUNT_WIDTH) u_cmp_ge_tx(.in1(tx_count), .in2(tx_at), .ge(tx_ge));
    CmpGe #(COUNT_WIDTH) u_cmp_ge_rx(.in1(rx_at), .in2(rx_count), .ge(rx_ge));
    Inv  #(2) u_inv_ip(.in({rx_ge, tx_ge}), .out(ip));
    And2 #(2) u_and2_on(.in1(ip), .in2(ie), .out(on));
    OrReduce #(2) u_or_reduce_irq(.in(on), .out(irq));

endmodule
