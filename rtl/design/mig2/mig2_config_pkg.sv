// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig2/cfg/mig2_config.yaml and mig2_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig2: struct mig2_cfg_t, its default MIG2_CFG has the values of
// cfg/mig2_config.yaml. Modules that read a knob take `parameter mig2_cfg_t CFG`.
// A new knob: a line in the YAML and a field here.
package Mig2ConfigPkg;

    typedef struct packed {
        logic [31:0] rst_addr;         // PC after reset, byte address
        int unsigned mem_addr_width;   // Mig2Cpu memories: 1 << mem_addr_width bytes each
    } mig2_cfg_t;

    localparam mig2_cfg_t MIG2_CFG = '{
        rst_addr:       32'h0000_0000,
        mem_addr_width: 16   // 65536 bytes each
    };

endpackage
