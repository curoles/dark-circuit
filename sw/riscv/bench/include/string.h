/* string.h for the riscv-tests benchmarks on the Mig CPUs: the toolchain has no C library;
 * bench.c gives these functions.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef BENCH_STRING_H
#define BENCH_STRING_H

#include <stddef.h>

void*  memcpy(void* dest, const void* src, size_t n);
void*  memset(void* dest, int c, size_t n);
size_t strlen(const char* s);
char*  strcpy(char* dest, const char* src);
int    strcmp(const char* a, const char* b);

#endif
