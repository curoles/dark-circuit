# Designs of this build tree: DARK_CIRCUIT_DESIGNS is ALL (every directory here),
# a list of design names, or empty (none; the library only).
if(DARK_CIRCUIT_DESIGNS STREQUAL "ALL")
    file(GLOB entries LIST_DIRECTORIES true RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
         ${CMAKE_CURRENT_SOURCE_DIR}/*)
    set(designs)
    foreach(entry IN LISTS entries)
        if(IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${entry})
            list(APPEND designs ${entry})
        endif()
    endforeach()
else()
    set(designs ${DARK_CIRCUIT_DESIGNS})
endif()

foreach(design IN LISTS designs)
    if(NOT IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${design})
        message(FATAL_ERROR "DARK_CIRCUIT_DESIGNS: no design ${design} in test/design")
    endif()
    add_subdirectory(${design})
endforeach()

if(designs)
    message(STATUS "DESIGNS: ${designs}")
else()
    message(STATUS "DESIGNS: none")
endif()
