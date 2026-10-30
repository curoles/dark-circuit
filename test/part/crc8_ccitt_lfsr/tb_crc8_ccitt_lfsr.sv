/* Test of Crc8CcittLfsr, INIT 0x00 and 0xFF.
 *
 * The standard check: the ASCII string "123456789", most significant bit of each byte first,
 * gives 0xF4 with INIT 0x00 (CRC-8/SMBUS). Then random messages, of random length, with
 * clocks without calc_crc in between (crc holds) and init_crc between messages (also
 * together with calc_crc: init wins), and a reset in the middle. The model is the textbook
 * bitwise CRC: shift left, XOR 0x07 when the bit that leaves differs from the message bit;
 * it is checked in every clock. Also checks crc = INIT after reset. 2000 clocks. Stops at the
 * first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCrc8Check #(
    parameter [7:0] INIT = 8'hFF
)(
    input  wire  clk,
    output logic done
);
    localparam N_CLOCKS = 2000;

    logic       rst_n;
    logic       din;
    logic       init_crc;
    logic       calc_crc;
    wire  [7:0] crc;
    logic [7:0] model;
    integer     seed;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] rnd;
    /* verilator lint_on UNUSEDSIGNAL */

    Crc8CcittLfsr #(.INIT(INIT)) u_crc8_ccitt_lfsr(
        .clk, .rst_n, .din, .init_crc, .calc_crc, .crc);

    // The bitwise CRC of one message bit.
    function automatic logic [7:0] crc_bit(input logic [7:0] c, input logic b);
        return (c[7] != b) ? ((c << 1) ^ 8'h07) : (c << 1);
    endfunction

    // One clock: drive, check after the edge against the model.
    task automatic step(input logic r, input logic d, input logic i, input logic e);
        rst_n = r; din = d; init_crc = i; calc_crc = e;
        @(posedge clk);
        if (!r || i)  model = INIT;
        else if (e)   model = crc_bit(model, d);
        #1;
        if (crc !== model)
            $fatal(1, "Crc8 INIT %h: rst_n %b din %b init %b calc %b: crc %h, expected %h",
                   INIT, r, d, i, e, crc, model);
    endtask

    initial begin
        logic [7:0] text [9];
        done = 1'b0;
        seed = 1 + int'(INIT);
        model = 'x;
        // Reset: crc = INIT.
        step(1'b0, 1'b0, 1'b0, 1'b0);
        // The standard check, "123456789".
        for (int k = 0; k < 9; k++)
            text[k] = 8'h31 + 8'(k);
        for (int k = 0; k < 9; k++)
            for (int b = 7; b >= 0; b--)
                step(1'b1, text[k][b], 1'b0, 1'b1);
        if (INIT == 8'h00 && crc !== 8'hF4)
            $fatal(1, "Crc8 INIT 00: the check string 123456789 gives %h, expected F4", crc);
        // Random messages.
        for (int c = 0; c < N_CLOCKS; c++) begin
            rnd = $random(seed);
            step(c != N_CLOCKS / 2, rnd[0], rnd[7:2] == 6'd0, rnd[1] || rnd[9:8] == 2'd0);
        end
        done = 1'b1;
    end
endmodule

module TbCrc8CcittLfsr;
    wire clk;
    wire done_00;
    wire done_ff;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbCrc8Check #(.INIT(8'h00)) u_check_00(.clk, .done(done_00));
    TbCrc8Check #(.INIT(8'hFF)) u_check_ff(.clk, .done(done_ff));

    initial begin
        wait (done_00 && done_ff);
        $finish;
    end
endmodule
