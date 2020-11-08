/* Mig1 CPU C TB.
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
    printf("\n\nTest Mig1 CPU\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    VTbTop top;

    Tick tick(top);


    printf("\n\nSUCCESS\n");

    return 0;
}
