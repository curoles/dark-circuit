/* Address decode: which of N_RULES address regions holds an address, as one select per rule.
 *
 * Rule r is a region of 1 << width bytes at base, aligned to its size (a device's registers,
 * a memory): addr is in it when its bits above width are base's. The regions do not overlap,
 * so at most one select is 1; miss=1 when none holds addr (the caller's default target, a
 * memory). The map is parameters, fixed by the platform, one flat vector each with rule 0 in
 * the low bits, written {rule N-1, ..., rule 0} (Icarus takes no packed array parameters):
 * BASES[r*ADDR_WIDTH +: ADDR_WIDTH], WIDTHS[r*8 +: 8]. Elaboration checks that every base is
 * aligned to its region and that no two regions overlap. Combinational.
 *
 *   addr --+--> addr[AW-1:width 0] == base 0[AW-1:width 0] -------------> sel[0]
 *          +--> ...                                                    > ...
 *          +--> addr[AW-1:width N-1] == base N-1[AW-1:width N-1] -------> sel[N-1]
 *                                             no select is 1 ---------> miss
 *
 * A building block of an interconnect: its selects drive a demultiplexer of requests
 * (ReqDemux) and a multiplexer of answers (as PULP's addr_decode with axi_demux, OpenTitan's
 * address decode with tlul_socket_1n).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module AddrDecode #(
    parameter                          ADDR_WIDTH = 32,    // bits of an address
    parameter                          N_RULES    = 1,     // regions
    parameter [N_RULES*ADDR_WIDTH-1:0] BASES      = '0,    // where each region starts
    parameter [N_RULES*8-1:0]          WIDTHS     = '0     // each region has 1 << width bytes
)(
    // The bits below the smallest region are not used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [N_RULES-1:0]    sel,       // sel[r]: region r holds addr
    output wire                  miss       // no region holds addr
);
    function automatic logic [ADDR_WIDTH-1:0] base_of(input int r);
        return BASES[r*ADDR_WIDTH +: ADDR_WIDTH];
    endfunction

    function automatic int width_of(input int r);
        return int'(WIDTHS[r*8 +: 8]);
    endfunction

    // Every region smaller than the address space and aligned to its size.
    function automatic logic regions_ok();
        for (int r = 0; r < N_RULES; r++)
            if (width_of(r) >= ADDR_WIDTH ||
                (base_of(r) & ((ADDR_WIDTH'(1) << width_of(r)) - ADDR_WIDTH'(1))) != '0)
                return 1'b0;
        return 1'b1;
    endfunction

    // No two regions overlap: aligned, they do when the larger one holds the other's base.
    function automatic logic disjoint();
        int w;
        for (int r = 0; r < N_RULES; r++)
            for (int s = r + 1; s < N_RULES; s++) begin
                w = (width_of(r) > width_of(s)) ? width_of(r) : width_of(s);
                if ((base_of(r) >> w) == (base_of(s) >> w))
                    return 1'b0;
            end
        return 1'b1;
    endfunction

    `DC_STATIC_ASSERT(a_rules, N_RULES >= 1)
    `DC_STATIC_ASSERT(a_regions, regions_ok())
    `DC_STATIC_ASSERT(a_disjoint, disjoint())

    // @kb: rtl/lib/block/addr_decode/design
    for (genvar r = 0; r < N_RULES; r++) begin: g_rule
        localparam                  W    = width_of(r);    // the bits of an offset in it
        localparam [ADDR_WIDTH-1:0] BASE = base_of(r);
        assign sel[r] = addr[ADDR_WIDTH-1:W] == BASE[ADDR_WIDTH-1:W];
    end
    assign miss = sel == '0;

endmodule
