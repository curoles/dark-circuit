/* SimROM C TB.
 *
 * Author: Igor Lesik 2020
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>
#include <random>

#include "VTbTop.h"
#include "eda/verilator/verilator_tick.h"

int main(int argc, char* argv[])
{
    printf("\n\nTest SimROM\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    VTbTop top;

    Tick tick(top);

    //top.filename.assign("mem.txt");
    top.eval();

    for (unsigned int i = 0; i < 4; ++i)
    {
        top.addr = i;
        tick();
        //printf("%x\n", top.data);
        if (top.data != i) {
            printf("\n\nFAIL\n");
            return 1;
        }
    }

    printf("\n\nSUCCESS\n");

    return 0;
}
