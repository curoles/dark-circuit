// tprintf (sw/riscv/tprintf) on every PE of TbMig6: tsnprintf's text for each case must be
// the expected one (integers, widths, strings, %p, truncation, and %a of float bits:
// normal, subnormal, zero, infinity, NaN); prints "tprintf: hart <n> ok, <k> cases" through
// tprintf itself and exits with 0, else prints the first case that differs and exits with 1.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdarg.h>
#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "tprintf.h"

namespace {

int cases;
int failed;

// The two strings are the same.
bool same(const char* a, const char* b)
{
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return *a == *b;
}

// tsnprintf(fmt, ...) must give expected; the first case that does not is printed.
void check(const char* expected, const char* fmt, ...)
{
    char    text[48];
    va_list ap;

    va_start(ap, fmt);
    tvsnprintf(text, sizeof text, fmt, ap);
    va_end(ap);
    cases++;
    if (!same(text, expected) && failed++ == 0)
        tprintf("tprintf: \"%s\" gave \"%s\", expected \"%s\"\n", fmt, text, expected);
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    check("42", "%d", 42);
    check("-7", "%i", -7);
    check("-2147483648", "%d", INT32_MIN);
    check("4294967295", "%u", 0xffffffffu);
    check("ff FF", "%x %X", 255u, 255u);
    check("000000ff", "%08x", 255u);
    check("  42|42  |-0042", "%4d|%-4d|%05d", 42, 42, -42);
    check("x|abc|  ab|(null)", "%c|%s|%4s|%s", 'x', "abc", "ab", static_cast<const char*>(0));
    check("100%", "%d%%", 100);
    check("0x00001000", "%p", reinterpret_cast<void*>(0x1000));
    check("[hart 3] 7 cycles", "[hart %d] %lu cycles", 3, 7ul);
    check("%q", "%q");

    check("0x1p+0", "%a", tbits(1.0f));
    check("-0x1.8p+3", "%a", tbits(-12.0f));
    check("0x1.99999ap-4", "%a", tbits(0.1f));
    check("0x1.fffffep+127", "%a", 0x7f7fffffu);     // the largest float
    check("0x1p-126", "%a", 0x00800000u);            // the smallest normal one
    check("0x1p-149", "%a", 0x00000001u);            // the smallest subnormal one
    check("0x0p+0 -0x0p+0", "%a %a", 0x00000000u, 0x80000000u);
    check("inf -inf nan", "%a %a %a", 0x7f800000u, 0xff800000u, 0x7fc00000u);

    char      small[5];
    const int n = tsnprintf(small, sizeof small, "%d", 123456);
    cases++;
    if ((n != 6 || !same(small, "1234")) && failed++ == 0)
        tprintf("tprintf: truncation gave %d \"%s\"\n", n, small);

    if (failed != 0)
        return 1;
    tprintf("tprintf: hart %u ok, %d cases\n", mig6::csr::mhartid::read(), cases);
    return 0;
}
