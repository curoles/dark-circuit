# Author: Igor Lesik 2020

option(XPROP_ENABLE "enable x-propagation detection" OFF)
option(COVERAGE_ENABLE "enable coverage" ON)
set(UVMHOME "CDNS-1.2" CACHE STRING "UVM files location")

function(make_xrun_compile_options ret_options)

    set(options "")

    list(APPEND options
        #-fast_recompilation
        -64bit
        -sv
        -disable_sem2009
        -l ${CMAKE_CURRENT_BINARY_DIR}/xrun.compile.log
        #-setenv HOME=${RTLHOME}
        -uvmhome '${UVMHOME}'
    )

    if (XPROP_ENABLE)
        list(APPEND options -xprop)
    endif()

    list(APPEND options
        #+define+AAA+BBB
        ${TB_FLIST}
        ${TB_TOP_FILE}
    )

    set(${ret_options} ${options} PARENT_SCOPE)
endfunction()

set(XRUN_COMPILE_OPTIONS "")
make_xrun_compile_options(XRUN_COMPILE_OPTIONS)

add_custom_target(compile_rtl
    xrun -compile ${XRUN_COMPILE_OPTIONS}
)

#add_custom_target(set_env
#    echo module add licenses scl enable devtoolset-8 bash
#)

function(make_xrun_elaborate_options ret_options)

    set(options "")

    list(APPEND options
        -noupdate
        -uvmhome '${UVMHOME}'
        #-fast_recompilation
        -disable_sem2009
        -l ${CMAKE_CURRENT_BINARY_DIR}/xrun.elaborate.log
        -top ${TB_TOP}
    )

    if (COVERAGE_ENABLE)
        list(APPEND options -coverage A)
    endif()

    set(${ret_options} ${options} PARENT_SCOPE)
endfunction()


set(XRUN_ELABORATE_OPTIONS "")
make_xrun_elaborate_options(XRUN_ELABORATE_OPTIONS)

add_custom_target(elaborate_rtl
    xrun -elaborate ${XRUN_ELABORATE_OPTIONS}
    DEPENDS compile_rtl
)

# Do not include(tcl.cmake), call it as a script.
add_custom_command(OUTPUT sim.tcl
    COMMAND ${CMAKE_COMMAND} -DDUT=${DUT} -P ${DARKCIRCUIT_SOURCE_DIR}/tools/eda/xcelium/sim_tcl.cmake
)

function(make_xrun_options ret_xrun_options)

    set(options
        -R
        -64bit
        -l xrun.run.log
        -xceligen on=1903
        #-disable_sem2009
        -input sim.tcl
        #+xxx_home=${RTLHOME}
    )

    if (UVM_ENABLE)
        list(APPEND options
            +UVM_VERBOSITY=${UVM_VERBOSITY}
            +UVM_TESTNAME=${UVM_TESTNAME}
        )
    endif()

    if (COVERAGE_ENABLE)
        list(APPEND options -covoverwrite)
    endif()

    set(${ret_xrun_options} ${options} PARENT_SCOPE)
endfunction()


set(XRUN_OPTIONS "")
make_xrun_options(XRUN_OPTIONS)

set(HASH_LITERAL "#")

add_custom_command(OUTPUT xrun-cmd
    COMMAND echo \"${HASH_LITERAL}!/bin/bash\" > xrun-cmd
    COMMAND echo xrun ${XRUN_OPTIONS} >> xrun-cmd
    COMMAND chmod a+x xrun-cmd
)

add_custom_target(make_run ALL
    DEPENDS elaborate_rtl
    DEPENDS xrun-cmd
    DEPENDS sim.tcl
)

add_custom_target(run_rtl
    COMMAND ${CMAKE_CURRENT_BINARY_DIR}/xrun-cmd
    DEPENDS sim.tcl
    DEPENDS xrun-cmd
)

