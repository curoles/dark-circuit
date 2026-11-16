// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig6/cfg/mig6_config.yaml and mig6_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig6: struct mig6_cfg_t, its default MIG6_CFG has the values of
// cfg/mig6_config.yaml. Modules that read a knob take `parameter mig6_cfg_t CFG`.
// A new knob: a line in the YAML and a field here.
package Mig6ConfigPkg;

    // The PLIC in the I/O region (Mig3Cpu).
    typedef struct packed {
        logic [31:0] offset;           // from io_base, a multiple of its size
        int unsigned addr_width;       // its region: 1 << addr_width bytes
        int unsigned sources;          // interrupt sources, IDs 1 to sources
        int unsigned prio_width;       // bits of a priority
    } mig6_plic_cfg_t;

    // The Timer in the I/O region (Mig3Cpu): 64 KiB (TimerPkg), its interrupt a PLIC source.
    typedef struct packed {
        logic [31:0] offset;           // from io_base, a multiple of 64 KiB
        int unsigned source;           // the PLIC source of its interrupt
    } mig6_timer_cfg_t;

    // The UART in the I/O region (Mig3Cpu): UartSifive, 4 KiB (UartSifivePkg), its interrupt a
    // PLIC source, its pins Mig3Cpu's.
    typedef struct packed {
        logic [31:0] offset;           // from io_base, a multiple of 4 KiB
        int unsigned source;           // the PLIC source of its interrupt
        int unsigned div_rst;          // div after reset: the boot rate, f / (div_rst + 1)
    } mig6_uart_cfg_t;

    // The DMA in the I/O region (Mig3Cpu): DmaSifive, 4 KiB of registers a channel
    // (DmaSifivePkg), a second agent on the memory; two PLIC sources a channel.
    typedef struct packed {
        logic [31:0] offset;           // from io_base, a multiple of its size
        int unsigned channels;         // 1 or more
        int unsigned source;           // channel c: done at source + 2c, error + 1
    } mig6_dma_cfg_t;

    typedef struct packed {
        logic [31:0] rst_addr;         // PC after reset, byte address
        int unsigned mem_addr_width;   // Mig3Cpu memories: 1 << mem_addr_width bytes each
        logic [31:0] io_base;          // I/O region, uncached: byte address, a multiple of
                                       // its size
        int unsigned io_addr_width;    // I/O region: 1 << io_addr_width bytes
        mig6_plic_cfg_t plic;          // the PLIC in the I/O region (Mig3Cpu)
        mig6_timer_cfg_t timer;        // the Timer in the I/O region (Mig3Cpu)
        mig6_uart_cfg_t uart;          // the UART in the I/O region (Mig3Cpu)
        mig6_dma_cfg_t dma;            // the DMA in the I/O region (Mig3Cpu)
        int unsigned btb_index_width;  // BTB in IF: 1 << btb_index_width entries
        int unsigned btb_tag_width;    // BTB tag; with the index it should cover the word
                                       // address of imem: then no two pcs share an entry
        int unsigned ras_addr_width;   // return-address stack: 1 << ras_addr_width entries
        int unsigned icache_sets_width;    // I-cache: 2 ways of 1 << icache_sets_width lines
        int unsigned dcache_sets_width;    // D-cache: 2 ways of 1 << dcache_sets_width lines
        int unsigned cache_line_words;     // words in a line of both caches and the memory
    } mig6_cfg_t;

    localparam mig6_cfg_t MIG6_CFG = '{
        rst_addr:        32'h0000_0000,
        mem_addr_width:  16,   // 65536 bytes each
        io_base:         32'h0c00_0000,
        io_addr_width:   26,   // 67108864 bytes
        plic: '{offset: 32'h0000_0000, addr_width: 22,
                sources: 16, prio_width: 3},
        timer: '{offset: 32'h0040_0000, source: 2},
        uart: '{offset: 32'h0041_0000, source: 3,
                div_rst: 15},
        dma: '{offset: 32'h0042_0000, channels: 4,
               source: 4},
        btb_index_width: 6,    // 64 entries
        btb_tag_width:   8,
        ras_addr_width:  3,    // 8 entries
        icache_sets_width: 6,  // 64 lines a way
        dcache_sets_width: 6,  // 64 lines a way
        cache_line_words:  2    // 8 bytes a line
    };

endpackage
