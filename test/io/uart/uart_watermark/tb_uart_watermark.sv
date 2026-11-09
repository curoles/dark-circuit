/* Test of UartWatermark: every input, exhaustively (counts of 4 bits, levels of 3, the two
 * enables), against a model that compares numbers. Checks named model. Stops at the first
 * failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbUartWatermark;
    `DC_TEST_MUTANT_HOOK(top)

    logic [3:0] tx_count, rx_count;
    logic [2:0] tx_level, rx_level;
    logic [1:0] ie;
    wire  [1:0] ip;
    wire        irq;
    logic [1:0] m_ip;

    UartWatermark #(.COUNT_WIDTH(4), .LEVEL_WIDTH(3)) u_uart_watermark(
        .tx_count, .tx_level, .rx_count, .rx_level, .ie, .ip, .irq);

    initial begin
        for (int tc = 0; tc < 16; tc++)
            for (int tl = 0; tl < 8; tl++)
                for (int rc = 0; rc < 16; rc++)
                    for (int rl = 0; rl < 8; rl++)
                        for (int e = 0; e < 4; e++) begin
                            tx_count = 4'(tc);
                            tx_level = 3'(tl);
                            rx_count = 4'(rc);
                            rx_level = 3'(rl);
                            ie       = 2'(e);
                            #1;
                            m_ip = {rc > rl, tc < tl};
                            if (ip !== m_ip || irq !== ((m_ip & ie) != 0))
                                `DC_TEST_FAIL(model, $sformatf(
                                    "tx %0d/%0d rx %0d/%0d ie %b: ip %b irq %b, expected %b",
                                    tc, tl, rc, rl, ie, ip, irq, m_ip))
                        end
        $display("PASS");
        $finish;
    end
endmodule
