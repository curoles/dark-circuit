/* Mig6, for simulation: the grid of PEs (Mig6PeGrid) and the shared memory at its edge.
 *
 * A prototype (rtl/design/mig6/README.md). The shared memory is the region shared of the
 * memory map (Mig6PmaPkg, cfg/mig6_pma.yaml): one copy that all PEs share, node (MEM_X,
 * MEM_Y) of the meshes, reached by the grid's edge link. Its network interface (Mig6MemNetIf)
 * takes the requests to AtomicUnit (the AMOs, the barrier, done where the one copy lives) in
 * front of a SimLatencyRAM of the region's size (latency 1, always ready); a request's
 * address inside the region is the RAM's address. Each PE's debug port and traces come out
 * as arrays, PE p at index p.
 *
 *   Mig6PeGrid u_grid ==edge==> Mig6MemNetIf u_shared_net_if --> AtomicUnit u_atomic_unit
 *                     <=======                                     --> SimLatencyRAM u_shared
 *
 * peek_shared() reads a byte of the shared memory, for testbenches.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

// Mig6Pkg alone is imported: Mig6NocPkg names a few of the same constants (STRB_WIDTH).
module Mig6 import Mig6Pkg::*; #(
    parameter mig6_cfg_t CFG        = MIG6_CFG, // configuration, see Mig6ConfigPkg
    parameter            BUF_DEPTH  = 4,        // the routers' input buffers: credits
    parameter            LINK_DELAY = 1         // clocks of a link between two routers
)(
    input  wire                                 clk,
    input  wire                                 rst_n,      // synchronous reset, active low
    // PE p: its debug port and traces
    output wire         [Mig6NocPkg::N_PES-1:0] halt,       // halted at EBREAK
    output retire_t     [Mig6NocPkg::N_PES-1:0] retire,     // for trace in testbench
    output pipe_trace_t [Mig6NocPkg::N_PES-1:0] pipe_trace, // pipeline view for testbench
    input  dbg_req_t    [Mig6NocPkg::N_PES-1:0] dbg_req,    // debug, used while halted
    output dbg_rsp_t    [Mig6NocPkg::N_PES-1:0] dbg_rsp
);
    localparam SHARED_ADDR_WIDTH = Mig6PmaPkg::SHARED_ADDR_WIDTH;   // 1 << it bytes
    localparam AW = Mig6NocPkg::ADDR_WIDTH;    // the shared memory's channel: a byte address,
    localparam DW = Mig6NocPkg::DATA_WIDTH;    // a word with its strobes, a size
    localparam SW = Mig6NocPkg::STRB_WIDTH;
    localparam ZW = Mig6NocPkg::SIZE_WIDTH;

    Mig6NocPkg::req_link_fwd_t mem_req_fwd;
    Mig6NocPkg::link_bwd_t     mem_req_bwd;
    Mig6NocPkg::rsp_link_fwd_t mem_rsp_fwd;
    Mig6NocPkg::link_bwd_t     mem_rsp_bwd;
    // The shared memory's network interface to AtomicUnit, AtomicUnit to the RAM
    logic                      au_valid;
    logic                      au_ready;
    logic                      au_we;
    logic [AW-1:0]             au_addr;
    logic [ZW-1:0]             au_size;
    AtomicPkg::atop_t          au_atop;
    logic [DW-1:0]             au_wdata;
    logic [SW-1:0]             au_wstrb;
    logic                      au_rsp_valid;
    logic [DW-1:0]             au_rsp_data;
    logic                      ram_valid;
    logic                      ram_ready;
    logic                      ram_we;
    // The RAM takes words with strobes, its address inside the region: the size and the
    // address's other bits are not read.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [AW-1:0]             ram_addr;
    logic [ZW-1:0]             ram_size;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [DW-1:0]             ram_wdata;
    logic [SW-1:0]             ram_wstrb;
    logic                      ram_rsp_valid;
    logic [DW-1:0]             ram_rsp_data;

    Mig6PeGrid #(.CFG(CFG), .BUF_DEPTH(BUF_DEPTH), .LINK_DELAY(LINK_DELAY)) u_grid(
        .clk, .rst_n, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp,
        .mem_req_fwd, .mem_req_bwd, .mem_rsp_fwd, .mem_rsp_bwd);

    Mig6MemNetIf #(.BUF_DEPTH(BUF_DEPTH)) u_shared_net_if(
        .clk, .rst_n,
        .noc_req_fwd(mem_req_fwd), .noc_req_bwd(mem_req_bwd),
        .noc_rsp_fwd(mem_rsp_fwd), .noc_rsp_bwd(mem_rsp_bwd),
        .mem_req_valid(au_valid), .mem_req_ready(au_ready), .mem_req_we(au_we),
        .mem_req_addr(au_addr), .mem_req_size(au_size), .mem_req_atop(au_atop),
        .mem_req_wdata(au_wdata), .mem_req_wstrb(au_wstrb),
        .mem_rsp_valid(au_rsp_valid), .mem_rsp_data(au_rsp_data));

    // Atomics where the one copy is.
    // @kb: rtl/lib/block/atomic/design
    AtomicUnit #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .ATOM_WIDTH(DW), .PENDING_WIDTH(2))
        u_atomic_unit(
        .clk, .rst_n,
        .req_valid(au_valid), .req_ready(au_ready), .req_we(au_we), .req_addr(au_addr),
        .req_size(au_size), .req_atop(au_atop), .req_wdata(au_wdata), .req_wstrb(au_wstrb),
        .rsp_valid(au_rsp_valid), .rsp_data(au_rsp_data),
        .mem_req_valid(ram_valid), .mem_req_ready(ram_ready), .mem_req_we(ram_we),
        .mem_req_addr(ram_addr), .mem_req_size(ram_size), .mem_req_wdata(ram_wdata),
        .mem_req_wstrb(ram_wstrb), .mem_rsp_valid(ram_rsp_valid),
        .mem_rsp_data(ram_rsp_data));

    // The shared memory: the region's size; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(SW), .ADDR_WIDTH(SHARED_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_shared(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_addr[SHARED_ADDR_WIDTH-1:2], 2'b00}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    // Byte at offset a of the shared memory.
    function automatic logic [7:0] peek_shared(input logic [SHARED_ADDR_WIDTH-1:0] a);
        return u_shared.peek(a);
    endfunction

endmodule
