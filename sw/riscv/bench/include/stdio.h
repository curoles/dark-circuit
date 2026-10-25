/* stdio.h for the riscv-tests benchmarks on the Mig CPUs: the toolchain has no C library;
 * bench.c gives printf, which prints nothing.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef BENCH_STDIO_H
#define BENCH_STDIO_H

int printf(const char* format, ...);

#endif
