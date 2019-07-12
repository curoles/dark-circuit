#pragma once

#undef OPCODE
#define OPCODE(name, pop, sop, fmt) OP_#name,
enum OpcodeId {
#include "isa/isa-define.h"
OP_LAST };
#undef OPCODE
