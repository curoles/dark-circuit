// The C++ CSR header (sw/riscv/mig6/mig6_csr_ops.hpp) on every PE of TbMig6: read, write, set,
// clear and the fields of a few CSRs, through mig6::csr::<name>; prints "csr ops: hart <n> ok"
// and exits with 0 when every check holds, else prints the line of the first that fails and
// exits with 1.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "tprintf.h"

using namespace mig6::csr;

namespace {

constexpr uint32_t mesh_x = 2;      // Mig6NocPkg::MESH_X: PEs in a row

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

    if (line != 0) {
        tprintf("csr ops: hart %u failed at line %d\n", mhartid::read(), line);
        return 1;
    }
    tprintf("csr ops: hart %u ok\n", mhartid::read());
    return 0;
}
