/* assert.h for the riscv-tests benchmarks on the Mig CPUs: the toolchain has no C library.
 * qsort includes it without using assert; assert checks nothing (as with NDEBUG): the
 * benchmarks check their results themselves (verify).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef BENCH_ASSERT_H
#define BENCH_ASSERT_H

#define assert(expr) ((void)0)

#endif
