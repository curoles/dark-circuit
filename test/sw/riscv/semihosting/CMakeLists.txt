set(SW ${PROJECT_SOURCE_DIR}/sw/riscv)

# The program needs the RISC-V toolchain, the test also needs QEMU.
if(DARK_CIRCUIT_RISCV AND DARK_CIRCUIT_QEMU)
    dc_add_riscv_program(sw_riscv_semihosting
        SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c test_semihosting.c
        FLAGS -O2 -Wall -Wextra -ffreestanding -I${SW}/semihosting
        LINK_FLAGS -T ${SW}/qemu_virt.ld)
    dc_add_qemu_test(sw_riscv_semihosting
        ELF ${CMAKE_CURRENT_BINARY_DIR}/sw_riscv_semihosting.elf
        EXIT_CODE 3 OUTPUT "semihost_write0 works[\r\n]+OK")
endif()
