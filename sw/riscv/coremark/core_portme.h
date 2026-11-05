/* CoreMark (EEMBC) on the Mig CPUs: the port configuration that CoreMark's sources include
 * (coremark.h). CoreMark's own files are compiled unchanged (fetched by cmake/fetch.cmake);
 * this file and core_portme.c are the port, written for this project.
 *
 * Bare metal, no C library: no floating point (the seconds are whole numbers), no time.h,
 * no stdio; printf is the one of sw/riscv/bench/bench.c, which prints nothing (CoreMark's
 * report is not wanted, core_portme.c prints one line itself). The seeds come from volatile
 * variables (core_portme.c), the data block of 2000 bytes is on the stack, one context.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>

#define HAS_FLOAT       0
#define HAS_TIME_H      0
#define USE_CLOCK       0
#define HAS_STDIO       0
#define HAS_PRINTF      1   // printf of bench.c: prints nothing

#ifndef COMPILER_VERSION
#define COMPILER_VERSION "GCC" __VERSION__
#endif
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS "-O2"
#endif
#define MEM_LOCATION "STACK"

// The data types CoreMark asks for: 8, 16 and 32 bits; ee_ptr_int holds a pointer.
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;  // not used: HAS_FLOAT is 0
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef ee_u32         ee_ptr_int;
typedef size_t         ee_size_t;

// Align an offset to a 32-bit value (the matrix's memory blocks).
#define align_mem(x) (void*)(4 + (((ee_ptr_int)(x) - 1) & ~3))

// Ticks are clock cycles (rdcycle, core_portme.c).
#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD  MEM_STACK

#define MULTITHREAD       1
#define USE_PTHREAD       0
#define USE_FORK          0
#define USE_SOCKET        0
#define MAIN_HAS_NOARGC   0
#define MAIN_HAS_NORETURN 0

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

extern ee_u32 default_num_contexts;

void portable_init(core_portable* p, int* argc, char* argv[]);
void portable_fini(core_portable* p);

// The printf of bench.c (prints nothing), for CoreMark's ee_printf (HAS_PRINTF).
int printf(const char* format, ...);

#endif
