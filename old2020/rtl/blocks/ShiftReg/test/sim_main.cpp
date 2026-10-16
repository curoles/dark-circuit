/* Adder-Comparator Verilator C TB.
 * author: Igor Lesik 2019
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
    printf("\n\nTest Shift Register\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    Vtb_top top;

    Tick tick(top);

    const uint32_t init_val = 0x1234567F; 
    top.srl_prl = 0;
    top.prl_in = init_val;

    tick();

    if (top.prl_out != init_val) return 1;
    if (top.srl_out != (init_val >> 31)) return 1;

    top.srl_in = 0;
    top.srl_prl = 1;

    for (int i = 1; i < 32; ++i)
    {
        tick();
        //printf("%x expect %x\n", top.prl_out, (init_val << i));
        if (top.prl_out != (init_val << i)) return 1;
        if (top.srl_out != ((init_val << i) >> 31)) return 1;
    }

    printf("\n\nDone\n");

    return 0;
}
