# @brief Sources of other projects, fetched at configure time (FetchContent).
#
# Only the source at a pinned commit is fetched: this project compiles what it needs
# with its own rules (a test suite with dc_add_riscv_program, for example). Fetching
# happens when cmake configures, never when it builds; a build directory fetches once,
# later configures do not go to the network (the commit is pinned, updates are off).
# Without network, -D FETCHCONTENT_SOURCE_DIR_<NAME>=<local checkout> uses a checkout
# that is already there (standard CMake). A project that must be built by its own build
# system (like Spike) is an ExternalProject, not a source fetch.

include(FetchContent)

# dc_fetch_source(<NAME> GIT_REPOSITORY <url> GIT_TAG <commit> [GIT_SUBMODULES <path>...])
#
# Define cache variable DARK_CIRCUIT_USE_<NAME> (AUTO, ON or OFF) and fetch the source
# of <NAME> into the build directory (_deps/<name>-src); set DARK_CIRCUIT_<NAME> to TRUE
# and <NAME>_DIR to the source directory when it is available. <name> is <NAME> in
# lower case. AUTO: when the source is not fetched yet and the repository can not be
# reached (git ls-remote, 30 s), <NAME> is disabled with a message instead of failing.
# GIT_SUBMODULES: only these submodules, none when not given.
function(dc_fetch_source NAME)
    cmake_parse_arguments(F "" "GIT_REPOSITORY;GIT_TAG" "GIT_SUBMODULES" ${ARGN})
    if(NOT F_GIT_REPOSITORY OR NOT F_GIT_TAG)
        message(FATAL_ERROR "dc_fetch_source(${NAME}): GIT_REPOSITORY and GIT_TAG are required")
    endif()
    string(TOLOWER ${NAME} name)

    set(use DARK_CIRCUIT_USE_${NAME})
    set(${use} AUTO CACHE STRING "Use ${NAME}: AUTO (if it can be fetched), ON (required) or OFF")
    set_property(CACHE ${use} PROPERTY STRINGS AUTO ON OFF)
    string(TOUPPER "${${use}}" mode)
    if(NOT mode MATCHES "^(AUTO|ON|OFF)$")
        message(FATAL_ERROR "${use}=${${use}}, expected AUTO, ON or OFF")
    endif()
    set(DARK_CIRCUIT_${NAME} FALSE PARENT_SCOPE)
    if(mode STREQUAL "OFF")
        message(STATUS "${NAME}: disabled by ${use}=OFF")
        return()
    endif()

    # Ask the network only when the source is neither fetched nor given locally.
    set(src ${FETCHCONTENT_BASE_DIR}/${name}-src)
    if(mode STREQUAL "AUTO" AND NOT FETCHCONTENT_SOURCE_DIR_${NAME} AND NOT EXISTS ${src}/.git)
        find_package(Git QUIET)
        if(GIT_FOUND)
            execute_process(COMMAND ${GIT_EXECUTABLE} ls-remote --heads ${F_GIT_REPOSITORY}
                            RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET TIMEOUT 30)
        else()
            set(result 1)
        endif()
        if(NOT result EQUAL 0)
            message(STATUS "${NAME}: ${F_GIT_REPOSITORY} can not be reached, ${NAME} tests are disabled")
            return()
        endif()
    endif()

    # GIT_SUBMODULES with an empty value means no submodules (not all of them).
    if(NOT F_GIT_SUBMODULES)
        set(F_GIT_SUBMODULES "")
    endif()
    FetchContent_Declare(${name}
        GIT_REPOSITORY ${F_GIT_REPOSITORY}
        GIT_TAG        ${F_GIT_TAG}
        GIT_SUBMODULES "${F_GIT_SUBMODULES}"
        SOURCE_SUBDIR  no-cmake-build)  # source only: no add_subdirectory
    set(FETCHCONTENT_UPDATES_DISCONNECTED_${NAME} ON CACHE BOOL "Do not update ${NAME}: its commit is pinned")
    FetchContent_MakeAvailable(${name})

    message(STATUS "${NAME}: enabled, ${${name}_SOURCE_DIR} (commit ${F_GIT_TAG})")
    set(DARK_CIRCUIT_${NAME} TRUE PARENT_SCOPE)
    set(${NAME}_DIR ${${name}_SOURCE_DIR} PARENT_SCOPE)
endfunction()

# riscv-tests: self-checking RISC-V ISA tests (BSD license) and their standard
# environment env/p, a submodule of riscv-tests (riscv-test-env, BSD license).
dc_fetch_source(RISCV_TESTS
    GIT_REPOSITORY https://github.com/riscv-software-src/riscv-tests.git
    GIT_TAG        d7e86f701b929b5d801f8cda1a4871ab05f452bb
    GIT_SUBMODULES env)
