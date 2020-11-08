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
    //top.eval();

    top.wr_en = 1;
    top.rd_en = 0;

    for (unsigned int i = 0; i < 64; ++i)
    {
        top.wr_addr = i;
        top.wr_data = i;
        tick();
    }

    top.wr_en = 0;
    top.rd_en = 1;

    for (unsigned int i = 0; i < 64; ++i)
    {
        top.rd_addr = i;
        tick();
        //printf("%x\n", top.rd_data);
        if (top.rd_data != i) {
            printf("\n\nFAIL\n");
            return 1;
        }
    }

    printf("\n\nSUCCESS\n");

    return 0;
}
