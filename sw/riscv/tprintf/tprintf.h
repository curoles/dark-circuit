/* tprintf: a small printf for test programs, bare metal, through semihosting.
 *
 * tprintf(fmt, ...) prints, tsnprintf(buf, size, fmt, ...) formats into buf (always
 * terminated, at most size - 1 characters; returns the length the whole text would have),
 * tvsnprintf the same with a va_list. A conversion: %[-][0][width][l]<c>:
 *   d i   int, decimal                 u    unsigned, decimal
 *   x X   unsigned, hex (lower, upper) p    pointer: 0x and 8 hex digits
 *   c     a character                  s    a string
 *   %     a percent sign
 *   a     a float as hex, exact: sign, significand and exponent, -0x1.8p+3 for -1.5 * 2^3
 *         (C99's %a); 0x0p+0, inf, nan. Its argument is the float's bits, tbits(x): a float
 *         passed through ... becomes a double, and that needs the soft-float library, which
 *         programs do not link (-nostdlib).
 * '-' left-justifies in the width, '0' pads numbers with zeros; 'l' is accepted (long is int
 * on RV32). No 64-bit numbers (they need the library's 64-bit division), no %e, %f, %g. An
 * unknown conversion prints as written.
 *
 * Not named printf: compilers turn printf("text\n") into puts("text"), which programs do not
 * have.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int tvsnprintf(char* buf, size_t size, const char* fmt, va_list ap);
int tsnprintf(char* buf, size_t size, const char* fmt, ...);
int tprintf(const char* fmt, ...);

/* The bits of a float, for %a. */
static inline uint32_t tbits(float x)
{
    uint32_t bits;
    __builtin_memcpy(&bits, &x, sizeof bits);
    return bits;
}

#ifdef __cplusplus
}
#endif
