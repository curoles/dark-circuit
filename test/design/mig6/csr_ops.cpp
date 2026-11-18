// The C++ CSR header (sw/riscv/mig6_csr_ops.hpp) on every PE of TbMig6: read, write, set,
// clear and the fields of a few CSRs, through mig6::csr::<name>; prints "csr ops: hart <n>"
// and exits with 0 when every check holds, else prints the line of the first that fails and
// exits with 1.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6_csr_ops.hpp"
#include "semihosting.h"

using namespace mig6::csr;

namespace {

constexpr uint32_t mesh_x = 2;      // Mig6NocPkg::MESH_X: PEs in a row

// Appends the decimal digits of v at line[i]; returns the index after them.
int put_dec(char *line, int i, uint32_t v)
{
    char digits[11];
    int  n = 0;

    do {
        digits[n++] = static_cast<char>('0' + v % 10);
        v /= 10;
    } while (v != 0);
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

// Prints "csr ops: hart <n> ok", or "csr ops: hart <n> failed at line <line>".
void say(int line_failed)
{
    char line[64];
    int  i = 0;

    i = put_str(line, i, "csr ops: hart ");
    i = put_dec(line, i, mhartid::read());
    if (line_failed == 0) {
        i = put_str(line, i, " ok");
    } else {
        i = put_str(line, i, " failed at line ");
        i = put_dec(line, i, static_cast<uint32_t>(line_failed));
    }
    i = put_str(line, i, "\n");
    line[i] = '\0';
    semihost_write0(line);
}

// The checks; the line of the first that fails, 0 when all hold.
int check()
{
    mscratch::write(0x12345678u);
    if (mscratch::read() != 0x12345678u)
        return __LINE__;
    mscratch::clear(0x000000ffu);
    if (mscratch::read() != 0x12345600u)
        return __LINE__;
    mscratch::set(0x0000000fu);
    if (mscratch::read() != 0x1234560fu)
        return __LINE__;

    mstatus::fields status{.val = mstatus::read()};
    if (status.mpp != 3)                        // machine mode only
        return __LINE__;
    mstatus::set(mstatus::mpie_mask);           // MPIE: no interrupt comes of it
    status.val = mstatus::read();
    if (status.mpie != 1)
        return __LINE__;
    mstatus::clear(mstatus::mpie_mask);
    status.val = mstatus::read();
    if (status.mpie != 0)
        return __LINE__;

    const misa::fields isa{.val = misa::read()};
    if (isa.val != misa::reset || isa.i != 1 || isa.m != 1 || isa.a != 1)
        return __LINE__;

    const uint32_t       hart = mhartid::read();
    const mnodeid::fields node{.val = mnodeid::read()};
    if (node.x != hart % mesh_x || node.y != hart / mesh_x)
        return __LINE__;

    fcsr::write(0);
    frm::write(5);                              // a view: fcsr's frm
    const fcsr::fields fp{.val = fcsr::read()};
    if (fp.frm != 5 || fp.fflags != 0)
        return __LINE__;

    const uint32_t c0 = cycle::read();
    const uint32_t c1 = cycle::read();
    if (c1 == c0)
        return __LINE__;
    return 0;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    const int line = check();

    say(line);
    return (line == 0) ? 0 : 1;
}
