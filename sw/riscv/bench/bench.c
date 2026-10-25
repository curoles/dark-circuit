/* Support of the riscv-tests benchmarks (benchmarks/ of riscv-tests) on the Mig CPUs: the
 * functions their common/syscalls.c gives, without its host interface.
 *
 * The benchmarks only keep the core busy with real code (branches, calls, loads and
 * stores) to measure its cycles; their own results are not wanted: printf and setStats do
 * nothing. Their sources are compiled unchanged, their main as bench_main (-include
 * bench_main.h); main here runs it BENCH_REPEAT times (-DBENCH_REPEAT=<n>, default 1), so
 * the run is as long as wanted. The run ends with the exit of crt0.S (semihosting):
 * status 0.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

// bench_main.h renames the benchmark's main, not the one of this file.
#undef main

#ifndef BENCH_REPEAT
#define BENCH_REPEAT 1
#endif

int bench_main(int argc, char** argv);

int printf(const char* format, ...)
{
    (void)format;
    return 0;
}

void setStats(int enable)
{
    (void)enable;
}

void* memcpy(void* dest, const void* src, size_t n)
{
    char*       d = dest;
    const char* s = src;
    while (n--)
        *d++ = *s++;
    return dest;
}

void* memset(void* dest, int c, size_t n)
{
    char* d = dest;
    while (n--)
        *d++ = (char)c;
    return dest;
}

size_t strlen(const char* s)
{
    const char* p = s;
    while (*p)
        p++;
    return (size_t)(p - s);
}

char* strcpy(char* dest, const char* src)
{
    char* d = dest;
    while ((*d++ = *src++) != 0)
        ;
    return dest;
}

int strcmp(const char* a, const char* b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int main(void)
{
    for (int k = 0; k < BENCH_REPEAT; k++)
        bench_main(0, (char**)0);
    return 0;
}
