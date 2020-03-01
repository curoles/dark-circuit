/**
 * @brief  Verilator time simulation helpers.
 * @author Igor Lesik 2020
 *
 */
#pragma once

#include "Vtb_top.h"
#include "verilated.h"

void sim_change_clk(Vtb_top& top);

static inline void sim_tick(Vtb_top& top)
{
    sim_change_clk(top);
    sim_change_clk(top);
}

struct Tick
{
    Vtb_top& tb_;

    Tick(Vtb_top& top):tb_(top){}

    void tick() {sim_tick(tb_);}

    void operator()(){tick();}
};
