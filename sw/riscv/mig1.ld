/* Linker script of programs for Mig1 RISC-V CPU (Mig1Cpu).
 *
 * Mig1Cpu loads the same image into instruction ROM and data RAM, both at
 * address 0: code is fetched from ROM, loads and stores go to RAM, so .rodata
 * and .data are read from RAM. Code written to RAM at run time can not run.
 * Reset address is 0, so .text.start (_start of crt0.S) is first.
 * LENGTH is 1 << Mig1Pkg::MEM_ADDR_WIDTH, change both together.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
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
