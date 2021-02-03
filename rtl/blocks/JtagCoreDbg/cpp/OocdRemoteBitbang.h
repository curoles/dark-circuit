/**@file
 * @brief Remote JTAG Bitbang TCP server for OpenOCD.
 * @author Igor Lesik 2021
 *
 */
#pragma once

#include <cstdint>

class OocdRemoteBitbang
{
    typedef unsigned char wire;

    // JTAG signals
    wire tck_, tms_, tdi_, trstn_, tdo_;

    bool quit_request_;

    int socket_fd_;
    int client_fd_;

public:
    OocdRemoteBitbang(uint16_t port);

    void drive_signals(
        wire* tck,
        wire* tms,
        wire* tdi,
        wire* trstn,
        wire  tdo);

    bool client_connected() const {return (client_fd_ > 0);}

private:

    // Check for a client connecting, and accept if there is one.
    void accept_oocd();

    void execute_oocd_command();

    void reset() {
    //    //trstn = 0;
    }

    void set_pins(wire tck, wire tms, wire tdi) {
        tck_ = tck;
        tms_ = tms;
        tdi_ = tdi;
    }

public:

    int handle_jtag_tick(
        wire* tck,
        wire* tms,
        wire* tdi,
        wire* trstn,
        wire  tdo
    )
    {
        drive_signals(tck, tms, tdi, trstn, tdo);

        return quit_request_ ? (/*exit_code()*/1 << 1 | 1) : 0;
    }
};

extern "C" void dpi_jtag_create(unsigned int port);

extern "C" int dpi_jtag_tick(
    unsigned char* tck,
    unsigned char* tms,
    unsigned char* tdi,
    unsigned char* trstn,
    unsigned char  tdo
);

