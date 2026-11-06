/* Test of AddrDecode, behave or struct version.
 *
 * Model: a region holds an address when base <= addr < base + size (a subtraction, not the
 * RTL's compare of the high bits); every select and miss compared. Three maps: one rule
 * (12-bit addresses), three rules of different sizes, one at 0 (16-bit), two rules as Mig3's
 * I/O region would have them (32-bit). Addresses: for a random rule its first and last byte,
 * the byte before and after it and a random one in it, or any address: 2000 on Verilator,
 * 300 on Icarus. Every rule and miss must have happened, a rule's first and last byte too
 * (checks named cover). Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbAddrDecodeCheck #(
    parameter                          ADDR_WIDTH = 16,
    parameter                          N_RULES    = 1,
    parameter [N_RULES*ADDR_WIDTH-1:0] BASES      = '0,    // as AddrDecode's
    parameter [N_RULES*8-1:0]          WIDTHS     = '0
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_ADDRS = 2000;
`else
    localparam N_ADDRS = 300;
`endif
    typedef logic [ADDR_WIDTH-1:0] addr_t;

    addr_t              addr;
    wire  [N_RULES-1:0] sel;
    wire                miss;
    logic [N_RULES-1:0] seen;           // rule r selected
    logic [N_RULES-1:0] seen_first;     // ... at its first byte
    logic [N_RULES-1:0] seen_last;      // ... at its last byte
    logic               seen_miss;
    integer             seed;

    AddrDecode #(.ADDR_WIDTH(ADDR_WIDTH), .N_RULES(N_RULES), .BASES(BASES), .WIDTHS(WIDTHS))
        u_addr_decode(.addr, .sel, .miss);

    function automatic addr_t base_of(input int r);
        return BASES[r*ADDR_WIDTH +: ADDR_WIDTH];
    endfunction

    function automatic addr_t size_of(input int r);
        return addr_t'(1) << WIDTHS[r*8 +: 8];
    endfunction

    task automatic check(input addr_t a);
        logic [N_RULES-1:0] exp;
        addr = a;
        #1;
        for (int r = 0; r < N_RULES; r++)
            exp[r] = a >= base_of(r) && a - base_of(r) < size_of(r);
        if (sel !== exp || miss !== (exp == '0))
            `DC_TEST_FAIL(model, $sformatf({
                "AddrDecode %0d rules: addr %h, sel %b miss %b, expected %b"},
                N_RULES, a, sel, miss, exp))
        seen      = seen | sel;
        seen_miss = seen_miss | miss;
        for (int r = 0; r < N_RULES; r++) begin
            if (a == base_of(r))
                seen_first[r] = 1'b1;
            if (a == base_of(r) + size_of(r) - 1)
                seen_last[r] = 1'b1;
        end
    endtask

    function automatic addr_t random_addr();
        return addr_t'({$random(seed), $random(seed)});
    endfunction

    initial begin
        int r;
        done       = 1'b0;
        seed       = ADDR_WIDTH * 8 + N_RULES;
        seen       = '0;
        seen_first = '0;
        seen_last  = '0;
        seen_miss  = 1'b0;
        repeat (N_ADDRS) begin
            r = {$random(seed)} % N_RULES;
            case ({$random(seed)} % 6)
                0:       check(base_of(r));
                1:       check(base_of(r) + size_of(r) - 1);
                2:       check(base_of(r) - 1);
                3:       check(base_of(r) + size_of(r));
                4:       check(base_of(r) + (random_addr() & (size_of(r) - 1)));
                default: check(random_addr());
            endcase
        end
        if (seen !== '1 || seen_first !== '1 || seen_last !== '1 || !seen_miss)
            `DC_TEST_FAIL(cover, $sformatf("AddrDecode %0d rules: seen %b first %b last %b miss %b",
                                           N_RULES, seen, seen_first, seen_last, seen_miss))
        done = 1'b1;
    end
endmodule

module TbAddrDecode;
    `DC_TEST_MUTANT_HOOK(top)

    wire [2:0] done;

    TbAddrDecodeCheck #(.ADDR_WIDTH(12), .N_RULES(1), .BASES(12'h400), .WIDTHS(8'd8))
        u_check_1(.done(done[0]));
    TbAddrDecodeCheck #(.ADDR_WIDTH(16), .N_RULES(3),
                        .BASES({16'hc100, 16'h8000, 16'h0000}), .WIDTHS({8'd8, 8'd14, 8'd12}))
        u_check_3(.done(done[1]));
    TbAddrDecodeCheck #(.ADDR_WIDTH(32), .N_RULES(2),
                        .BASES({32'h0c40_0000, 32'h0c00_0000}), .WIDTHS({8'd12, 8'd22}))
        u_check_mig3(.done(done[2]));

    initial begin
        wait (done == '1);
        $display("PASS");
        $finish;
    end
endmodule
