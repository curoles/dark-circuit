/**@file
 * @brief Remote JTAG Bitbang TCP server for OpenOCD.
 * @author Igor Lesik 2021
 *
 */
#include "OocdRemoteBitbang.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cassert>

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>

static OocdRemoteBitbang* bitbang_server_instance_ = nullptr;

extern "C"
void dpi_jtag_create(unsigned int port)
{
    if (!bitbang_server_instance_) {
        bitbang_server_instance_ = new OocdRemoteBitbang(port);
    }
}

extern "C"
int dpi_jtag_tick(
    unsigned char* tck,
    unsigned char* tms,
    unsigned char* tdi,
    unsigned char* trstn,
    unsigned char  tdo
)
{
    assert(bitbang_server_instance_);

    return bitbang_server_instance_->
         handle_jtag_tick(tck, tms, tdi, trstn, tdo);
}

OocdRemoteBitbang::
OocdRemoteBitbang(uint16_t port):
    quit_request_(false),
    socket_fd_(0),
    client_fd_(0)
{
    socket_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);

    if (socket_fd_ == -1) {
        fprintf(stderr, "remote_bitbang failed to make socket: %s (%d)\n", strerror(errno), errno);
        abort();
    }

    ::fcntl(socket_fd_, F_SETFL, O_NONBLOCK);
    int reuseaddr = 1;
    if (setsockopt(socket_fd_, SOL_SOCKET, SO_REUSEADDR, &reuseaddr, sizeof(int)) == -1) {
        fprintf(stderr, "remote_bitbang failed setsockopt: %s (%d)\n", strerror(errno), errno);
        abort();
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(port);

    if (::bind(socket_fd_, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        fprintf(stderr, "remote_bitbang failed to bind socket: %s (%d)\n", strerror(errno), errno);
        abort();
    }

    if (::listen(socket_fd_, 1) == -1) {
        fprintf(stderr, "remote_bitbang failed to listen on socket: %s (%d)\n", strerror(errno), errno);
        abort();
    }

    socklen_t addrlen = sizeof(addr);
    if (getsockname(socket_fd_, (struct sockaddr*)&addr, &addrlen) == -1) {
        fprintf(stderr, "remote_bitbang getsockname failed: %s (%d)\n", strerror(errno), errno);
        abort();
    }

    tck_ = 1;
    tms_ = 1;
    tdi_ = 1;
    trstn_ = 1;

    fprintf(stderr, "This emulator compiled with JTAG Remote Bitbang client. To enable, use +jtag_dpi_enable=1.\n");
    fprintf(stderr, "Listening on port %d\n", ntohs(addr.sin_port));
}

void OocdRemoteBitbang::accept_oocd()
{
    fprintf(stderr, "Attempting to accept client socket\n");

    bool keep_waiting = true;

    while (keep_waiting)
    {
        client_fd_ = ::accept(socket_fd_, NULL, NULL);

        if (client_fd_ == -1) {
            if (errno == EAGAIN) {
                // No client waiting to connect right now.
            } else {
                fprintf(stderr, "failed to accept on socket: %s (%d)\n", strerror(errno), errno);
                keep_waiting = false;
                abort();
            }
        } else {
            ::fcntl(client_fd_, F_SETFL, O_NONBLOCK);
            fprintf(stderr, "Connection from OpenOCD accepted successfully.\n");
            keep_waiting = false;
        }
    }
}

void
OocdRemoteBitbang::
drive_signals(
    wire* tck,
    wire* tms,
    wire* tdi,
    wire* trstn,
    wire  tdo
)
{
    if (client_connected()) {
        tdo_ = tdo; // read Test Data Output
        execute_oocd_command();
    } else {
        accept_oocd(); // check connection request
    }

    *tck = tck_;
    *tms = tms_;
    *tdi = tdi_;
    *trstn = trstn_;
}

void
OocdRemoteBitbang::
execute_oocd_command()
{
    char command;
    bool keep_waiting = true;

    while (keep_waiting)
    {
        ssize_t num_chars_read = ::read(client_fd_, &command, sizeof(command));

        if (num_chars_read == -1)
        {
            if (errno == EAGAIN) {
                // We'll try again the next call.
                //fprintf(stderr, "Received no command. Will try again on the next call\n");
            } else {
                fprintf(stderr, "remote_bitbang failed to read on socket: %s (%d)\n",
                        strerror(errno), errno);
                keep_waiting = false;
                abort();
            }
        } else if (num_chars_read == 0) {
            fprintf(stderr, "No Command Received.\n");
            keep_waiting = true;
        } else {
            keep_waiting = false;
        }
    }

    //fprintf(stderr, "Received a command %c\n", command);
    bool do_reply = false;
    char reply_char = '?';

    switch (command) {
    case 'B': /* fprintf(stderr, "*BLINK*\n"); */ break;
    case 'b': /* fprintf(stderr, "_______\n"); */ break;
    case 'r': reset(); break; // This is wrong. 'r' has other bits that indicated TRST and SRST.
    case '0': set_pins(0, 0, 0); break;
    case '1': set_pins(0, 0, 1); break;
    case '2': set_pins(0, 1, 0); break;
    case '3': set_pins(0, 1, 1); break;
    case '4': set_pins(1, 0, 0); break;
    case '5': set_pins(1, 0, 1); break;
    case '6': set_pins(1, 1, 0); break;
    case '7': set_pins(1, 1, 1); break;
    case 'R': do_reply = true; reply_char = tdo_ ? '1' : '0'; break;
    case 'Q': quit_request_ = true; break;
    default:
      fprintf(stderr, "remote_bitbang got unsupported command '%c'\n",
              command);
    }

    if (do_reply)
    {
        while (1) {
            ssize_t bytes = write(client_fd_, &reply_char, sizeof(reply_char));

            if (bytes == -1) {
                fprintf(stderr, "failed to write to socket: %s (%d)\n", strerror(errno), errno);
                abort();
            }

            if (bytes > 0) {
                break;
            }
        }
    }

    if (quit_request_) {
        fprintf(stderr, "Remote end disconnected\n");
        ::close(client_fd_);
        client_fd_ = 0;
    }
}
