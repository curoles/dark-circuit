/**@file
 * @brief:  SREC parser
 * @author: Igor Lesik 2019
 */
#include "srec.h"

#include <cstdlib>
#include <cstdio>
#include <cstdint>

static
void srec_parse_s3(
    char* s,
    void* context,
    void (*load_data)(void*, uint64_t addr, uint32_t d[4])
)
{
    // Read address, 32 bits 8 chars
    char c = s[8];
    s[8] = '\0';
    uint64_t addr = strtoul(s, nullptr, 16);
    s[8] = c;
    s += 8;

    // Read 4 32-bit words
    uint32_t data[4];
    for (unsigned int i = 0; i < 4; ++i) {
        s[8] = '\0';
        data[i] = __builtin_bswap32(strtoul(s, nullptr, 16));
        s[8] = c;
        s += 8;
    }
    load_data(context, addr, data);
}

bool srec_parse(
    const char* path,
    uint64_t* start_addr,
    void* context,
    void (*load_data)(void*, uint64_t addr, uint32_t d[4])
)
{
    FILE* file = fopen(path, "r");
    if (file == nullptr) return false;

    bool rc = true;
    char buf[1024];

    while (!feof(file))
    {
        char* s = fgets(buf, sizeof(buf), file);
        if (s == nullptr) break;

        if (s[0] != 'S') {
            printf("Error: line must start with 'S'\n");
            rc = false;
            break;
        }

        ++s;

        char type = s[0];
        ++s;

        char count_str[3] = {s[0], s[1], '\0'};
        s += 2;
        unsigned int count = atoi(count_str);

        if (type == '3') {
            srec_parse_s3(s, context, load_data);
        }
        else if (type == '7') { // start address
            if (start_addr != nullptr) {
                s[8] = '\0';
                *start_addr = strtoul(s, nullptr, 16);
            }
        }
        else {
            continue;
        }
    }

    fclose(file);

    return rc;
}
