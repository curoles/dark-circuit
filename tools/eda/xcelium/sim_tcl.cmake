function(make_tcl_code ret_tcl_code)

    set(tcl_code
        "# auto generated XRUN Tcl script\n"
        "set assert_report_incompletes 0\n"
    )

    #if (DUT MATCHES XXX)
    #    list(APPEND tcl_code
    #        "# XXX TB\n"
    #    )
    #endif()

    list(APPEND tcl_code
        "run\n"
        "exit\n"
    )

    set(${ret_tcl_code} ${tcl_code} PARENT_SCOPE)
endfunction()


set(TCL_CODE "")
make_tcl_code(TCL_CODE)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/sim.tcl ${TCL_CODE})

