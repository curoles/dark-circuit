#if(USE_VERILATOR)
#add_subdirectory(verilator)
#endif()

if(USE_XCELIUM)
add_subdirectory(xcelium)
endif()
