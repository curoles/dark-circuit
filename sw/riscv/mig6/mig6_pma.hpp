/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_pma.yaml and mig6_pma.hpp.j2 by tools/pma_gen.py
 *
 * Mig6's memory map for C++ programs, as rtl/design/mig6/cfg/mig6_pma.yaml describes it
 * (PMA-style: physical memory attributes); the numbers are mig6_pma.h's. A namespace per
 * region, mig6::pma::<name>: base, size, addr_width, its attributes (cacheable, io,
 * atomics, reservable, target), contains(addr), and pointers into it:
 *   at<T, offset>()  checked when compiled: the T at offset lies inside the region
 *   at<T>(offset)    not checked, for an offset known only when running
 * pma_of(addr) gives the attributes of the region that holds addr (hit false when none
 * does), as Mig6PmaPkg's pma_of in the hardware; constexpr, so a program can check its
 * buffers when compiled:
 *     static_assert(mig6::pma::shared::atomics, "the barrier needs AMOs");
 *     volatile uint32_t* count = mig6::pma::shared::at<uint32_t, 0x40>();
 */
#pragma once

#include <stdint.h>

extern "C" {
#include "mig6_pma.h"
}

namespace mig6::pma {

// Where a PE sends an access.
enum class target_t : uint8_t {
    local,
    net,
    devices
};

// A region's attributes.
struct attributes_t {
    bool     hit;           // a region holds the address
    bool     cacheable;     // the core's caches may hold it
    bool     io;            // side effects: never speculated, merged or repeated
    bool     atomics;       // AMOs allowed
    bool     reservable;    // LR/SC allowed
    target_t target;        // where a PE sends the access
};

// local: the PE's local memory, code and data, private to its core
namespace local {
    constexpr uint32_t base       = MIG6_PMA_LOCAL_BASE;
    constexpr uint32_t size       = MIG6_PMA_LOCAL_SIZE;
    constexpr uint32_t addr_width = MIG6_PMA_LOCAL_ADDR_WIDTH;
    constexpr bool     cacheable  = MIG6_PMA_LOCAL_CACHEABLE;
    constexpr bool     io         = MIG6_PMA_LOCAL_IO;
    constexpr bool     atomics    = MIG6_PMA_LOCAL_ATOMICS;
    constexpr bool     reservable = MIG6_PMA_LOCAL_RESERVABLE;
    constexpr target_t target     = target_t::local;
    constexpr attributes_t attributes = {true, cacheable, io, atomics, reservable, target};

    constexpr bool contains(uint32_t addr) { return addr - base < size; }

    template <typename T, uint32_t offset>
    inline volatile T* at()
    {
        static_assert(offset < size && sizeof(T) <= size - offset,
                      "at<T, offset>: the T at offset is not inside the region local");
        return reinterpret_cast<volatile T*>(base + offset);
    }

    template <typename T>
    inline volatile T* at(uint32_t offset) { return reinterpret_cast<volatile T*>(base + offset); }
}   // namespace local

// plic: the PE's PLIC (rtl/lib/block/plic, sw/riscv/drivers/plic.h), one context: meip
namespace plic {
    constexpr uint32_t base       = MIG6_PMA_PLIC_BASE;
    constexpr uint32_t size       = MIG6_PMA_PLIC_SIZE;
    constexpr uint32_t addr_width = MIG6_PMA_PLIC_ADDR_WIDTH;
    constexpr bool     cacheable  = MIG6_PMA_PLIC_CACHEABLE;
    constexpr bool     io         = MIG6_PMA_PLIC_IO;
    constexpr bool     atomics    = MIG6_PMA_PLIC_ATOMICS;
    constexpr bool     reservable = MIG6_PMA_PLIC_RESERVABLE;
    constexpr target_t target     = target_t::devices;
    constexpr attributes_t attributes = {true, cacheable, io, atomics, reservable, target};

    constexpr bool contains(uint32_t addr) { return addr - base < size; }

    template <typename T, uint32_t offset>
    inline volatile T* at()
    {
        static_assert(offset < size && sizeof(T) <= size - offset,
                      "at<T, offset>: the T at offset is not inside the region plic");
        return reinterpret_cast<volatile T*>(base + offset);
    }

    template <typename T>
    inline volatile T* at(uint32_t offset) { return reinterpret_cast<volatile T*>(base + offset); }
}   // namespace plic

// dma: the PE's DMA's registers (DmaSifive: SiFive's PDMA map, sw/riscv/drivers/dma.h)
namespace dma {
    constexpr uint32_t base       = MIG6_PMA_DMA_BASE;
    constexpr uint32_t size       = MIG6_PMA_DMA_SIZE;
    constexpr uint32_t addr_width = MIG6_PMA_DMA_ADDR_WIDTH;
    constexpr bool     cacheable  = MIG6_PMA_DMA_CACHEABLE;
    constexpr bool     io         = MIG6_PMA_DMA_IO;
    constexpr bool     atomics    = MIG6_PMA_DMA_ATOMICS;
    constexpr bool     reservable = MIG6_PMA_DMA_RESERVABLE;
    constexpr target_t target     = target_t::devices;
    constexpr attributes_t attributes = {true, cacheable, io, atomics, reservable, target};

    constexpr bool contains(uint32_t addr) { return addr - base < size; }

    template <typename T, uint32_t offset>
    inline volatile T* at()
    {
        static_assert(offset < size && sizeof(T) <= size - offset,
                      "at<T, offset>: the T at offset is not inside the region dma");
        return reinterpret_cast<volatile T*>(base + offset);
    }

    template <typename T>
    inline volatile T* at(uint32_t offset) { return reinterpret_cast<volatile T*>(base + offset); }
}   // namespace dma

// shared: the shared memory at the mesh's edge, one copy that all PEs share
namespace shared {
    constexpr uint32_t base       = MIG6_PMA_SHARED_BASE;
    constexpr uint32_t size       = MIG6_PMA_SHARED_SIZE;
    constexpr uint32_t addr_width = MIG6_PMA_SHARED_ADDR_WIDTH;
    constexpr bool     cacheable  = MIG6_PMA_SHARED_CACHEABLE;
    constexpr bool     io         = MIG6_PMA_SHARED_IO;
    constexpr bool     atomics    = MIG6_PMA_SHARED_ATOMICS;
    constexpr bool     reservable = MIG6_PMA_SHARED_RESERVABLE;
    constexpr target_t target     = target_t::net;
    constexpr attributes_t attributes = {true, cacheable, io, atomics, reservable, target};

    constexpr bool contains(uint32_t addr) { return addr - base < size; }

    template <typename T, uint32_t offset>
    inline volatile T* at()
    {
        static_assert(offset < size && sizeof(T) <= size - offset,
                      "at<T, offset>: the T at offset is not inside the region shared");
        return reinterpret_cast<volatile T*>(base + offset);
    }

    template <typename T>
    inline volatile T* at(uint32_t offset) { return reinterpret_cast<volatile T*>(base + offset); }
}   // namespace shared

// shared_cached: the shared memory, cacheable
namespace shared_cached {
    constexpr uint32_t base       = MIG6_PMA_SHARED_CACHED_BASE;
    constexpr uint32_t size       = MIG6_PMA_SHARED_CACHED_SIZE;
    constexpr uint32_t addr_width = MIG6_PMA_SHARED_CACHED_ADDR_WIDTH;
    constexpr bool     cacheable  = MIG6_PMA_SHARED_CACHED_CACHEABLE;
    constexpr bool     io         = MIG6_PMA_SHARED_CACHED_IO;
    constexpr bool     atomics    = MIG6_PMA_SHARED_CACHED_ATOMICS;
    constexpr bool     reservable = MIG6_PMA_SHARED_CACHED_RESERVABLE;
    constexpr target_t target     = target_t::net;
    constexpr attributes_t attributes = {true, cacheable, io, atomics, reservable, target};

    constexpr bool contains(uint32_t addr) { return addr - base < size; }

    template <typename T, uint32_t offset>
    inline volatile T* at()
    {
        static_assert(offset < size && sizeof(T) <= size - offset,
                      "at<T, offset>: the T at offset is not inside the region shared_cached");
        return reinterpret_cast<volatile T*>(base + offset);
    }

    template <typename T>
    inline volatile T* at(uint32_t offset) { return reinterpret_cast<volatile T*>(base + offset); }
}   // namespace shared_cached

// The attributes of the region that holds addr; hit false (all false) when none does.
constexpr attributes_t pma_of(uint32_t addr)
{
    if (local::contains(addr))
        return local::attributes;
    if (plic::contains(addr))
        return plic::attributes;
    if (dma::contains(addr))
        return dma::attributes;
    if (shared::contains(addr))
        return shared::attributes;
    if (shared_cached::contains(addr))
        return shared_cached::attributes;
    return {false, false, false, false, false, target_t::local};
}

}   // namespace mig6::pma
