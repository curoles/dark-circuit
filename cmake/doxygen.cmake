# @brief Documentation of the RTL with Doxygen: target doc writes <build>/doc/html.
#
# Doxygen reads SystemVerilog through tools/sv2doxy.py, a filter that turns it into C++.
# Use of Doxygen is controlled by cache variable DARK_CIRCUIT_USE_DOXYGEN (AUTO, ON or OFF);
# graphs need Graphviz (dot).

dc_use_tool(DOXYGEN doxygen)

if(DARK_CIRCUIT_DOXYGEN AND PYTHON3_BIN)
    find_program(DOT_BIN dot)
    set(DOC_DIR ${CMAKE_BINARY_DIR}/doc)
    if(DOT_BIN)
        set(DOC_HAVE_DOT YES)
    else()
        set(DOC_HAVE_DOT NO)
    endif()
    # The Doxyfile outside DOC_DIR: deleting the documentation keeps it.
    configure_file(${CMAKE_CURRENT_LIST_DIR}/Doxyfile.in ${CMAKE_BINARY_DIR}/Doxyfile @ONLY)
    add_custom_target(doc
        COMMAND ${CMAKE_COMMAND} -E make_directory ${DOC_DIR}
        COMMAND ${DOXYGEN_BIN} ${CMAKE_BINARY_DIR}/Doxyfile
        COMMAND ${CMAKE_COMMAND} -E echo "Documentation: ${DOC_DIR}/html/index.html"
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Doxygen: documentation of the RTL"
        VERBATIM)
endif()
