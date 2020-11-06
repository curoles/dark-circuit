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


int main(int argc, char* argv[])
{
    printf("\n\nTest Shift Register\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    VTbTop top;

    Tick tick(top);

    top.in1 = 0;

    tick();

    printf("\n\nDone\n");

    return 0;
}
