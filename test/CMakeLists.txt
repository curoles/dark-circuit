# Tests of the library, unless DARK_CIRCUIT_LIB_TESTS is OFF (the build tree of one design).
if(DARK_CIRCUIT_LIB_TESTS)
    add_subdirectory(gate)
    add_subdirectory(sim)
    add_subdirectory(part)
    add_subdirectory(block)
    add_subdirectory(numeric)
    add_subdirectory(sw)
else()
    message(STATUS "LIBRARY TESTS: disabled by DARK_CIRCUIT_LIB_TESTS=OFF")
endif()

# Designs of DARK_CIRCUIT_DESIGNS.
add_subdirectory(design)
