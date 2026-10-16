#pragma once

#include <cstdint>

#undef OPCODE
#define OPCODE(name, pop, sop, fmt) OP_##name,
enum OpcodeId {
#include "isa/isa-define.h"
OP__LAST_ID, OP__SIZE=OP__LAST_ID };
#undef OPCODE

OpcodeId opcode_get_id(const char* opcode_name);

static inline bool opcode_valid_id(OpcodeId id) {
    return id < OP__LAST_ID;
}

uint32_t opcode_encode(OpcodeId id);
