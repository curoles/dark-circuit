#include "isa/isa.h"

#include <cstring>
#include <cstdint>

#undef OPCODE
#define OPCODE(name, pop, sop, fmt) #name,
static const char* opcode_names[] = {
#include "isa/isa-define.h"
nullptr };
#undef OPCODE

OpcodeId opcode_get_id(const char* opcode_name)
{
    for (size_t id = 0; id < OP__SIZE; ++id) {
        if (0 == strcmp(opcode_name, opcode_names[id])) {
            return static_cast<OpcodeId>(id);
        }
    }

    return OP__LAST_ID;
}

struct Encode {
    uint32_t pop : 4;
    uint32_t sop : 4;
};

#undef OPCODE
#define OPCODE(name, pop, sop, fmt) {0b##pop, 0b##sop },
static const Encode encode_table[] = {
#include "isa/isa-define.h"
{0, 0} };
#undef OPCODE

uint32_t opcode_encode(OpcodeId id)
{
    Encode en = encode_table[id];

    uint32_t op = (en.pop << 28) | (en.sop << 24);


    return op;
}
