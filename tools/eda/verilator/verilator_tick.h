/**
 * @brief  Verilator time simulation helpers.
 * @author Igor Lesik 2020
 *
 */
#pragma once

#include "VTbTop.h"
#include "verilated.h"

void sim_change_clk(VTbTop& top);

uint64_t sim_time();
 
static inline void sim_tick(VTbTop& top)
{
    sim_change_clk(top);
    sim_change_clk(top);
}

struct Tick
{
    VTbTop& tb_;

    Tick(VTbTop& top):tb_(top){}

    void tick() {sim_tick(tb_);}

    void operator()(){tick();}
};
