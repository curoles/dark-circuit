/**@file
 * @brief public Semihosting APIs based on ARM definitions.
 *
 * Copyright (c) 2023 Igor Lesik
 *
 * Based on the ARM semihosting API from:
 * https://github.com/ARM-software/abi-aa/blob/main/semihosting/semihosting.rst
 *
 * RISC-V semihosting also follows these conventions:
 * https://github.com/riscv/riscv-semihosting-spec/blob/main/riscv-semihosting-spec.adoc
 *
 * EBREAK was primarily designed to be used by a debugger to cause execution to stop
 * and fall back into the debugger. EBREAK is also used by the standard gcc compiler
 * to mark code paths that should not be executed.
 *
 * Another use of EBREAK is to support "semihosting", where the execution environment
 * includes a debugger that can provide services over an alternate system call interface
 * built around the EBREAK instruction.
 *
 * Because the RISC-V base ISA does not provide more than one EBREAK instruction,
 * RISC-V semihosting uses a special sequence of instructions to distinguish
 * a semihosting EBREAK from a debugger inserted EBREAK.
 *
 * RISC-V Semihosting Trap Sequence shows the instruction sequence
 * used to invoke a Semihosting operation.
 *
 * RISC-V Semihosting Trap Sequence:
 * ```
 * slli x0, x0, 0x1f       # 0x01f01013    Entry NOP
 * ebreak                  # 0x00100073    Break to debugger
 * srai x0, x0, 7          # 0x40705013    NOP encoding the semihosting call number 7
 * ```
 *
 * OPERATION NUMBER REGISTER A0
 * PARAMETER REGISTER        A1
 * RETURN REGISTER           A0
 * Data block field size     64 bits on riscv64
 */
#include <stddef.h>
#include <stdint.h>

#include "semihosting.h"

#ifndef __riscv
    #error Must be RISC-V
#endif

// Only stddef.h and stdint.h are used, they come with the compiler,
// so this file compiles without a C library.
//
// Define RISCV_SEMIHOSTING_OVERRIDES_ENABLE (-D...) to define `_exit`, `_write`
// and others for a C library.

static size_t semihost_strlen(const char *s)
{
    size_t len = 0;
    while (s[len] != '\0')
        len++;
    return len;
}

// https://github.com/riscv-non-isa/riscv-c-api-doc/blob/master/riscv-c-api.md
#if __riscv_xlen == 64
    typedef uint64_t field_t;
#else
    typedef uint32_t field_t;
#endif

/*
 * @brief Manually execute a semihosting instruction.
 *
 * @param instr instruction code to run
 * @param args instruction specific arguments
 *
 * @return integer return code of instruction
 *
 *
 * QEMU requires that the semihosting trap instruction sequence, consisting of
 * three uncompressed instructions, lie in the same page, and refuses to
 * interpret the trap sequence if these instructions are placed across two
 * different pages.
 *
 * The QEMU RISC-V `semihost_exec` function, which occupies 12 bytes, is aligned at a
 * 16-byte boundary to ensure that the three trap sequence instructions are
 * never placed across two different pages.
 */
long __attribute__((aligned(16))) semihost_exec(enum SemihostInstr instr, void *args)
{
    register unsigned long a0 __asm__ ("a0") = instr;
    register void *a1 __asm__ ("a1") = args; // argument pack
    register long ret __asm__ ("a0");

    __asm__ volatile (
        ".balign 16\n"             // Align in case the function is inlined
        ".option push\n"
        ".option norvc\n"          // Force non-compressed RISC-V instructions
        "slli zero, zero, 0x1f\n"  // Entry NOP
        "ebreak\n"                 // Break to debugger
        "srai zero, zero, 0x7\n"   // NOP encoding the semihosting call number 7
        ".option pop\n"
        : "=r" (ret) : "r" (a0), "r" (a1) : "memory");

    // The "memory" clobber prevents the compiler from removing the asm block,
    // and prevents reordering loads or stores across.

    return ret;
}

/**
 * @brief Read a byte from the console
 *
 * @return char byte read from the console.
 */
char semihost_poll_in(void)
{
    field_t args = 0;

    return (char)semihost_exec(SEMIHOST_READC, &args);
}

/**
 * @brief Write a byte to the console
 *
 * @param c byte to write to console
 */
void semihost_poll_out(char c)
{
    (void)semihost_exec(SEMIHOST_WRITEC, &c);
}

// For some printf implementation.
__attribute__((weak)) void putchar_(char c)
{
    semihost_poll_out(c);
}

struct __attribute__((__packed__)) semihost_open_args {
    field_t path;
    field_t mode;
    field_t path_len;
};

/**
 * @brief Open a file on the host system
 *
 * @param path file path to open. Can be absolute or relative to current
 *             directory of the running process.
 * @param mode value from @ref semihost_open_mode.
 *
 * @retval handle positive handle on success.
 * @retval -1 on failure.
 */
long semihost_open(const char *path, long mode)
{
    struct semihost_open_args args = {
        .path = (field_t)path,
        .mode = (field_t)mode,
        .path_len = (field_t)semihost_strlen(path)
    };

    return semihost_exec(SEMIHOST_OPEN, &args);
}

/**
 * @brief Close a file
 *
 * @param fd handle returned by @ref semihost_open.
 *
 * @retval 0 on success.
 * @retval -1 on failure.
 */
long semihost_close(long fd)
{
    field_t args = (field_t)fd;

    return semihost_exec(SEMIHOST_CLOSE, &args);
}
/**
 * @brief Query the size of a file
 *
 * @param fd handle returned by @ref semihost_open.
 *
 * @retval positive file size on success.
 * @retval -1 on failure.
 */
long semihost_flen(long fd)
{
    field_t args = (field_t)fd;

    return semihost_exec(SEMIHOST_FLEN, &args);
}
/**
 * @brief Seeks to an absolute position in a file.
 *
 * @param fd handle returned by @ref semihost_open.
 * @param offset offset from the start of the file in bytes.
 *
 * @retval 0 on success.
 * @retval -errno negative error code on failure.
 */
long semihost_seek(long fd, long offset)
{
    field_t args[2] = { (field_t)fd, (field_t)offset };

    return semihost_exec(SEMIHOST_SEEK, args);
}

struct __attribute__((packed)) semihost_read_args {
    field_t fd;
    field_t buf;
    field_t len;
};

/**
 * @brief Read the contents of a file into a buffer.
 *
 * @param fd handle returned by @ref semihost_open.
 * @param buf buffer to read data into.
 * @param len number of bytes to read.
 *
 * @retval read number of bytes read on success.
 * @retval -errno negative error code on failure.
 */
long semihost_read(long fd, void *buf, long len)
{
    struct semihost_read_args args = {
        .fd = (field_t)fd,
        .buf = (field_t)buf,
        .len = (field_t)len
    };

    long ret = semihost_exec(SEMIHOST_READ, &args);

    if (ret == len) { // EOF condition
        ret = -5; // -EIO
    }
    else if (ret == 0) { // All bytes read
        ret = len;
    }
    return ret;
}

struct __attribute__((__packed__)) semihost_write_args {
    field_t fd;
    field_t buf;
    field_t len;
};

/**
 * @brief Write the contents of a buffer into a file.
 *
 * @param fd handle returned by @ref semihost_open.
 * @param buf buffer to write data from.
 * @param len number of bytes to write.
 *
 * @retval 0 on success.
 * @retval -errno negative error code on failure.
 */
long semihost_write(long fd, const void *buf, long len)
{
    struct semihost_write_args args = {
        .fd  = (field_t)fd,
        .buf = (field_t)buf,
        .len = (field_t)len
    };

    return semihost_exec(SEMIHOST_WRITE, &args);
}

/** @brief Write null terminated string to stdout/stderr.
 *
 */
long semihost_write0(const char *buf)
{
    semihost_exec(SEMIHOST_WRITE0, (void*)buf);

    return 0;
}

struct __attribute__((__packed__)) semihost_exit_args {
    field_t reason;
    field_t status;
};

/**
 * @brief Exit simulation.
 *
 * @param status application return status.
 *
 * Weak so alternate HALs (e.g. emulator/Protium shim) can override the exit path.
 *
 * SEMIHOST_EXIT_EXTENDED takes block {reason, status} on 32-bit and 64-bit.
 * SEMIHOST_EXIT takes the block only on 64-bit; on 32-bit A1 is the reason
 * itself and status is lost (QEMU riscv32 exits with 1 when given the block).
 */
__attribute__((weak)) _Noreturn void semihost_exit(int status)
{
    struct semihost_exit_args exit_args = {
        .reason = (field_t)SEMIHOST_STOPPED_APP_EXIT,
        .status = (field_t)status
    };

    semihost_exec(SEMIHOST_EXIT_EXTENDED, &exit_args);

    __builtin_unreachable();
}

struct __attribute__((__packed__)) semihost_get_cmdline_args {
    field_t buf; ///< a pointer to a buffer of at least the size specified in word two
    field_t len; ///< the length of the buffer in bytes
};

/**
 * @brief Get application command line
 *
 * @see https://developer.arm.com/documentation/dui0471/i/semihosting/sys-get-cmdline--0x15-
 *
 * @return error code, 0 if the call is successful
 */
long semihost_get_cmdline(char* buf, long len)
{
    struct semihost_get_cmdline_args args = {
        .buf = (field_t)buf,
        .len = (field_t)len // QEMU adjust this field to output string len
    };

    return semihost_exec(SEMIHOST_GET_CMDLINE, &args);
}

#ifdef RISCV_SEMIHOSTING_OVERRIDES_ENABLE

#include <sys/types.h>

_Noreturn void _exit(int status)
{
    semihost_exit(status);
}

// SEMIHOST_WRITE needs a host handle from SEMIHOST_OPEN of ":tt", not fd 1,
// so characters go one by one with SEMIHOST_WRITEC.
ssize_t _write(int fd, const void* buf, size_t count)
{
    (void)fd;  // stdout and stderr both go to the debug terminal
    for (size_t i = 0; i < count; i++)
        semihost_poll_out(((const char*)buf)[i]);

    return count;
}

#endif // RISCV_SEMIHOSTING_OVERRIDES_ENABLE
