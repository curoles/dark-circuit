// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig6/cfg/mig6_pma.yaml and mig6_pma_pkg.sv.j2 by tools/pma_gen.py
//
// Mig6's memory map, as cfg/mig6_pma.yaml describes it (PMA-style: physical memory
// attributes). Per region: <NAME>_BASE, <NAME>_SIZE, <NAME>_ADDR_WIDTH (the low address bits
// inside it) and <NAME>_PMA, its attributes (pma_t). pma_of(addr) gives the attributes of
// the region that holds addr (hit 1), or all 0 when none does; a region decodes by its top
// address bits, a base being a multiple of its size. The parts ask the attributes by name:
// the caches cacheable, a PE target, the assertions atomics and io. phys_of(addr) is the
// address beyond the PE: an alias's (a second window onto a region, alias_of in the YAML)
// in the region it aliases, so the network and the memory see one address per byte.
package Mig6PmaPkg;

    // Where a PE sends an access.
    typedef enum logic [1:0] {
        TARGET_LOCAL,
        TARGET_NET,
        TARGET_DEVICES
    } target_e;

    // A region's attributes.
    typedef struct packed {
        logic    hit;           // a region holds the address
        logic    cacheable;     // the core's caches may hold it
        logic    io;            // side effects: never speculated, merged or repeated
        logic    atomics;       // AMOs allowed
        logic    reservable;    // LR/SC allowed
        target_e target;        // where a PE sends the access
    } pma_t;

    // Every region's constants; a part uses some.
    /* verilator lint_off UNUSEDPARAM */

    // local: the PE's local memory, code and data, private to its core
    localparam logic [31:0] LOCAL_BASE       = 32'h0000_0000;
    localparam logic [31:0] LOCAL_SIZE       = 32'h0001_0000;
    localparam int          LOCAL_ADDR_WIDTH = 16;
    // hit, cacheable, io, atomics, reservable, target
    localparam pma_t        LOCAL_PMA        =
        pma_t'({1'b1, 1'b0, 1'b0, 1'b0, 1'b1, TARGET_LOCAL});

    // plic: the PE's PLIC (rtl/lib/block/plic, sw/riscv/drivers/plic.h), one context: meip
    localparam logic [31:0] PLIC_BASE       = 32'h0c00_0000;
    localparam logic [31:0] PLIC_SIZE       = 32'h0040_0000;
    localparam int          PLIC_ADDR_WIDTH = 22;
    // hit, cacheable, io, atomics, reservable, target
    localparam pma_t        PLIC_PMA        =
        pma_t'({1'b1, 1'b0, 1'b1, 1'b0, 1'b0, TARGET_DEVICES});

    // dma: the PE's DMA's registers (DmaSifive: SiFive's PDMA map, sw/riscv/drivers/dma.h)
    localparam logic [31:0] DMA_BASE       = 32'h0c42_0000;
    localparam logic [31:0] DMA_SIZE       = 32'h0000_1000;
    localparam int          DMA_ADDR_WIDTH = 12;
    // hit, cacheable, io, atomics, reservable, target
    localparam pma_t        DMA_PMA        =
        pma_t'({1'b1, 1'b0, 1'b1, 1'b0, 1'b0, TARGET_DEVICES});

    // shared: the shared memory at the mesh's edge, one copy that all PEs share
    localparam logic [31:0] SHARED_BASE       = 32'h8000_0000;
    localparam logic [31:0] SHARED_SIZE       = 32'h0010_0000;
    localparam int          SHARED_ADDR_WIDTH = 20;
    // hit, cacheable, io, atomics, reservable, target
    localparam pma_t        SHARED_PMA        =
        pma_t'({1'b1, 1'b0, 1'b0, 1'b1, 1'b1, TARGET_NET});

    // shared_cached: the shared memory, cacheable
    localparam logic [31:0] SHARED_CACHED_BASE       = 32'h9000_0000;
    localparam logic [31:0] SHARED_CACHED_SIZE       = 32'h0010_0000;
    localparam int          SHARED_CACHED_ADDR_WIDTH = 20;
    // hit, cacheable, io, atomics, reservable, target
    localparam pma_t        SHARED_CACHED_PMA        =
        pma_t'({1'b1, 1'b1, 1'b0, 1'b1, 1'b1, TARGET_NET});
    /* verilator lint_on UNUSEDPARAM */

    // The attributes of the region that holds addr, all 0 (hit 0) when none does. A region
    // decodes by its top address bits: the bits inside the smallest region are not read.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic pma_t pma_of(logic [31:0] addr);
        if (addr[31:16] == 16'h0000)
            return LOCAL_PMA;
        if (addr[31:22] == 10'h030)
            return PLIC_PMA;
        if (addr[31:12] == 20'h0_c420)
            return DMA_PMA;
        if (addr[31:20] == 12'h800)
            return SHARED_PMA;
        if (addr[31:20] == 12'h900)
            return SHARED_CACHED_PMA;
        return '0;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // The address an access has beyond the PE (its network interface, the memory): in an
    // alias, the same offset in the region it aliases; any other address as it is.
    function automatic logic [31:0] phys_of(logic [31:0] addr);
        if (addr[31:20] == 12'h900)   // shared_cached
            return {12'h800, addr[19:0]};   // shared
        return addr;
    endfunction

endpackage
