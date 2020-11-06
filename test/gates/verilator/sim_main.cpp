/* Standard Gates Verilator C TB.
 *
 * Author: Igor Lesik 2020
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>

#include "VTbTop.h"
#include "eda/verilator/verilator_tick.h"

static void set_inputs(VTbTop& top)
{
    top.in1 = 0;
}

static bool check_outputs(const VTbTop& top)
{
    if (top.out_inv != ~top.in1) return false;

    return true;
}

int main(int argc, char* argv[])
{
    printf("\n\nTest Basic Gates\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    VTbTop top;

    Tick tick(top);

    for (unsigned int i = 0; i < 100; ++i)
    {
        set_inputs(top);
        tick();
        if (!check_outputs(top)) {
            printf("\n\nFAIL\n");
            return 1;
        }
    }

    printf("\n\nSUCCESS\n");

    return 0;
}
