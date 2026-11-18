// C++ on Mig6, bare metal (no exceptions, RTTI, heap or global constructors; the build's
// DC_RISCV_CXX_FLAGS, the linker script's check), on every PE of TbMig6: a template, constexpr
// and a namespace, with C headers (semihosting.h, and mig6_csr_ops.h inside
// mig6_csr_ops.hpp). An int8 dot product with an int32 sum, as the layer's kernel will
// compute, is evaluated by the compiler (static_assert) and by the core from volatile copies
// of the same vectors; prints "cpp: hart <n> dot <d>" and exits with 0 when the two agree.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6_csr_ops.hpp"
#include "semihosting.h"

namespace kernel {

// The dot product of two vectors of N elements of type T, summed in Acc.
template <typename Acc, typename T, int N>
constexpr Acc dot(const T (&a)[N], const T (&b)[N])
{
    Acc sum = 0;
    for (int i = 0; i < N; i++)
        sum += static_cast<Acc>(a[i]) * static_cast<Acc>(b[i]);
    return sum;
}

}   // namespace kernel

namespace {

constexpr int8_t a[8] = {1, -2, 3, -4, 127, -128, 0, 5};
constexpr int8_t b[8] = {5, 6, -7, 8, 127, 127, 9, -1};
constexpr int32_t expected = kernel::dot<int32_t>(a, b);
static_assert(expected == 5 - 12 - 21 - 32 + 16129 - 16256 + 0 - 5, "dot at compile time");

// Appends the decimal digits of v (and its sign) at line[i]; returns the index after them.
int put_dec(char *line, int i, int32_t v)
{
    char     digits[11];
    int      n = 0;
    uint32_t u = (v < 0) ? 0u - static_cast<uint32_t>(v) : static_cast<uint32_t>(v);

    if (v < 0)
        line[i++] = '-';
    do {
        digits[n++] = static_cast<char>('0' + u % 10);
        u /= 10;
    } while (u != 0);
    while (n > 0)
        line[i++] = digits[--n];
    return i;
}

// Appends the text s at line[i]; returns the index after it.
int put_str(char *line, int i, const char *s)
{
    while (*s != '\0')
        line[i++] = *s++;
    return i;
}

}   // namespace

// extern "C": in a freestanding program main is an ordinary function, C++ would mangle its
// name, and crt0.S calls main.
extern "C" int main()
{
    volatile int8_t va[8];
    volatile int8_t vb[8];
    int8_t          ra[8];
    int8_t          rb[8];
    char            line[48];
    int             i = 0;

    for (int k = 0; k < 8; k++) {
        va[k] = a[k];
        vb[k] = b[k];
    }
    for (int k = 0; k < 8; k++) {
        ra[k] = va[k];
        rb[k] = vb[k];
    }
    const int32_t d = kernel::dot<int32_t>(ra, rb);

    i = put_str(line, i, "cpp: hart ");
    i = put_dec(line, i, static_cast<int32_t>(mig6::csr::mhartid::read()));
    i = put_str(line, i, " dot ");
    i = put_dec(line, i, d);
    i = put_str(line, i, "\n");
    line[i] = '\0';
    semihost_write0(line);
    return (d == expected) ? 0 : 1;
}
