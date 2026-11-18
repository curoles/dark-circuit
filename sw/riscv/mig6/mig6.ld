/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_pma.yaml and mig6.ld.j2 by tools/pma_gen.py
 *
 * Linker script of programs for a Mig6 PE: code and data in its local memory, the region
 * local of the memory map (rtl/design/mig6/cfg/mig6_pma.yaml), code first, where the core
 * starts (Mig6Pe asserts that its reset address is the region's base). The testbench loads
 * the image into every PE's local memory; the caches are in front of it. Code starts with
 * .text.start (_start of crt0.S) or .text.init (_start of the standard riscv-tests
 * environment); the stack starts at the region's end.
 * Global constructors of C++ (.init_array, .ctors) are refused: crt0.S calls main without
 * running them, so the link fails instead of an object staying uninitialized.
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

    .init_array : {
        KEEP(*(.init_array .init_array.* .ctors .ctors.*))
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

ASSERT(SIZEOF(.init_array) == 0,
       "a global constructor, crt0.S does not run it: make it constexpr or init it in main")
