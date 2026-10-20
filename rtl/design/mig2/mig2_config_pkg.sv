// THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
// Generated from rtl/design/mig2/cfg/mig2_config.yaml and mig2_config_pkg.sv.j2 by tools/config_gen.py
//
// Configuration of Mig2, Mig2Pkg takes its MIG2_* constants from here.
package Mig2ConfigPkg;

    // PC after reset, byte address.
    localparam RST_ADDR = 32'h0000_0000;

    // imem and dmem: 65536 bytes each.
    localparam MEM_ADDR_WIDTH = 16;

endpackage
