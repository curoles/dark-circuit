/**@file
 * @brief:  SREC parser
 * @author: Igor Lesik 2019
 */
#include <cstdint>

bool srec_parse(
    const char* path,
    uint64_t* start_addr,
    void* context,
    void (*load_data)(void*, uint64_t addr, uint32_t d[4])
);

