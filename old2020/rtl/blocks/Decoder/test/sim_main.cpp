/* Decoder Verilator C TB.
 * author: Igor Lesik 2020
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>

#include "Vtb_top.h"
#include "eda/verilator_tick.h"


int main(int argc, char* argv[])
{
    printf("\n\nTest Decoder\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    Vtb_top top;

    Tick tick(top);

    for (unsigned int i = 0; i < 7; ++i)
    {
        top.n = i;
        tick();
        printf("%d decode to %x encode to %d\n", top.n, top.dec, top.enc);
        if (i != top.enc) return 1;
    }

    printf("\n\nDone\n");

    return 0;
}
