// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig3/cfg/mig3_config.yaml and mig3_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig3: struct mig3_cfg_t, its default MIG3_CFG has the values of
// cfg/mig3_config.yaml. Modules that read a knob take `parameter mig3_cfg_t CFG`.
// A new knob: a line in the YAML and a field here.
package Mig3ConfigPkg;

    typedef struct packed {
        logic [31:0] rst_addr;         // PC after reset, byte address
        int unsigned mem_addr_width;   // Mig3Cpu memories: 1 << mem_addr_width bytes each
        int unsigned btb_index_width;  // BTB in IF: 1 << btb_index_width entries
        int unsigned btb_tag_width;    // BTB tag; with the index it should cover the word
                                       // address of imem: then no two pcs share an entry
        int unsigned ras_addr_width;   // return-address stack: 1 << ras_addr_width entries
        int unsigned icache_sets_width;    // I-cache: 2 ways of 1 << icache_sets_width lines
        int unsigned dcache_sets_width;    // D-cache: 2 ways of 1 << dcache_sets_width lines
        int unsigned cache_line_words;     // words in a line of both caches and the memory
    } mig3_cfg_t;

    localparam mig3_cfg_t MIG3_CFG = '{
        rst_addr:        32'h0000_0000,
        mem_addr_width:  16,   // 65536 bytes each
        btb_index_width: 4,    // 16 entries
        btb_tag_width:   10,
        ras_addr_width:  3,    // 8 entries
        icache_sets_width: 6,  // 64 lines a way
        dcache_sets_width: 6,  // 64 lines a way
        cache_line_words:  2    // 8 bytes a line
    };

endpackage
