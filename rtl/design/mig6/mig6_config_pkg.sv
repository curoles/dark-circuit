// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig6/cfg/mig6_config.yaml and mig6_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig6: struct mig6_cfg_t, its default MIG6_CFG has the values of
// cfg/mig6_config.yaml. Modules that read a knob take `parameter mig6_cfg_t CFG`.
// A new knob: a line in the YAML and a field here. The memory map is Mig6PmaPkg's
// (cfg/mig6_pma.yaml).
package Mig6ConfigPkg;

    // When a router's head asks VC allocation (the library's NocPkg::ROUTE_*).
    typedef enum logic [1:0] {
        NOC_ROUTE_REGISTERED = 2'd0,   // the clock after it reaches the front: 3 clocks a router
        NOC_ROUTE_EARLY      = 2'd1    // in the clock it reaches the front: 2 clocks a router
    } noc_route_e;

    // Who gives a router's head its output VC (the library's NocPkg::ALLOC_*).
    typedef enum logic [1:0] {
        NOC_ALLOC_SEPARATE   = 2'd0,   // VC allocation, then the switch in a later clock
        NOC_ALLOC_COMBINED   = 2'd1    // the switch, as the head wins it: a clock less a router
    } noc_alloc_e;

    typedef struct packed {
        logic [31:0] rst_addr;         // PC after reset, byte address
        int unsigned btb_index_width;  // BTB in IF: 1 << btb_index_width entries
        int unsigned btb_tag_width;    // BTB tag; with the index it should cover the word
                                       // address of imem: then no two pcs share an entry
        int unsigned ras_addr_width;   // return-address stack: 1 << ras_addr_width entries
        int unsigned icache_sets_width;    // I-cache: 2 ways of 1 << icache_sets_width lines
        int unsigned dcache_sets_width;    // D-cache: 2 ways of 1 << dcache_sets_width lines
        int unsigned cache_line_words;     // words in a line of both caches and the memory
        int unsigned plic_prio_width;      // each PE's PLIC: bits of a priority
        int unsigned dma_source;           // its sources: DMA channel c's done, error at
                                           // dma_source + 2c, + 2c + 1
        int unsigned dma_depth;            // each PE's DMA: transactions in flight
        int unsigned dma_max_burst;        // ... words of a read burst, a power of 2
        int unsigned noc_buf_depth;        // the routers' input buffers: flits a VC, credits
        noc_route_e  noc_route;            // ... when a head asks VC allocation
        noc_alloc_e  noc_alloc;            // ... who gives a head its output VC
    } mig6_cfg_t;

    localparam mig6_cfg_t MIG6_CFG = '{
        rst_addr:        32'h0000_0000,
        btb_index_width: 6,    // 64 entries
        btb_tag_width:   8,
        ras_addr_width:  3,    // 8 entries
        icache_sets_width: 6,  // 64 lines a way
        dcache_sets_width: 6,  // 64 lines a way
        cache_line_words:  2,   // 8 bytes a line
        plic_prio_width:   2,
        dma_source:        1,
        dma_depth:         8,
        dma_max_burst:     8,
        noc_buf_depth:     8,
        noc_route:         NOC_ROUTE_EARLY,
        noc_alloc:         NOC_ALLOC_COMBINED
    };

endpackage
