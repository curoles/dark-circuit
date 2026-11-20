// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig6/cfg/mig6_config.yaml and mig6_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig6: struct mig6_cfg_t, its default MIG6_CFG has the values of
// cfg/mig6_config.yaml. Modules that read a knob take `parameter mig6_cfg_t CFG`.
// A new knob: a line in the YAML and a field here. The memory map is Mig6PmaPkg's
// (cfg/mig6_pma.yaml).
package Mig6ConfigPkg;

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
        dma_source:        1
    };

endpackage
