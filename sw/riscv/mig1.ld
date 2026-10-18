/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig1/cfg/mig1_config.yaml and mig1.ld.j2 by tools/config_gen.py
 *
 * Linker script of programs for Mig1 RISC-V CPU (Mig1Cpu).
 *
 * Mig1Cpu loads the same image into instruction ROM and data RAM, both at
 * address 0: code is fetched from ROM, loads and stores go to RAM, so .rodata
 * and .data are read from RAM. Code written to RAM at run time can not run.
 * Code starts at the reset address, with .text.start (_start of crt0.S) or .text.init
 * (_start of the standard riscv-tests environment) first.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 65536
}

SECTIONS
{
    .text 0x00000000 : {
        KEEP(*(.text.start))
        KEEP(*(.text.init))
        *(.text .text.*)
    } > RAM

    .rodata : {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > RAM

    .data : {
        *(.data .data.*)
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
    } > RAM

    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.* .bss .bss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
