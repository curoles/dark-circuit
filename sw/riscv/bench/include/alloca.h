/* alloca.h for the riscv-tests benchmarks on the Mig CPUs: the toolchain has no C library;
 * alloca is the compiler's (memory on the stack of the caller).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef BENCH_ALLOCA_H
#define BENCH_ALLOCA_H

#define alloca(size) __builtin_alloca(size)

#endif
