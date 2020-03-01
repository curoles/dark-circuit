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

    tick();


    printf("\n\nDone\n");

    return 0;
}
