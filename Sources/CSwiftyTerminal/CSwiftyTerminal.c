#include "CSwiftyTerminal.h"

#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

void st_write_stdout(const char *text) {
    fputs(text, stdout);
    fflush(stdout);
}

void st_write_stderr(const char *text) {
    fputs(text, stderr);
    fflush(stderr);
}

void st_line_buffer_stdout(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
}

int st_isatty(int fd) {
    return isatty(fd);
}

// Expected length of a UTF-8 sequence from its lead byte; 1 for ASCII or invalid bytes.
static int st_utf8_length(unsigned char lead) {
    if (lead >= 0xF0 && lead <= 0xF4) return 4;
    if (lead >= 0xE0) return lead <= 0xEF ? 3 : 1;
    if (lead >= 0xC2) return 2;
    return 1;
}

// A byte read while checking whether Escape started a sequence but that belongs to the next
// key press (Escape, then Enter typed quickly).
static int st_pending_byte = -1;

static int st_read_byte(unsigned char *byte) {
    if (st_pending_byte >= 0) {
        *byte = (unsigned char)st_pending_byte;
        st_pending_byte = -1;
        return 1;
    }
    return read(STDIN_FILENO, byte, 1) == 1 ? 1 : 0;
}

static struct termios st_raw_saved;
static int st_raw_depth = 0;
static struct sigaction st_raw_previous_term;
static struct sigaction st_raw_previous_hup;

static void st_raw_signalled(int signal_number) {
    tcsetattr(STDIN_FILENO, TCSANOW, &st_raw_saved);
    sigaction(SIGTERM, &st_raw_previous_term, NULL);
    sigaction(SIGHUP, &st_raw_previous_hup, NULL);
    raise(signal_number);
}

int st_raw_enter(void) {
    if (st_raw_depth > 0) {
        st_raw_depth++;
        return 1;
    }
    if (!isatty(STDIN_FILENO) || tcgetattr(STDIN_FILENO, &st_raw_saved) != 0) {
        return 0;
    }
    struct termios raw = st_raw_saved;
    raw.c_lflag &= ~(ICANON | ECHO | ISIG);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = st_raw_signalled;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, &st_raw_previous_term);
    sigaction(SIGHUP, &action, &st_raw_previous_hup);
    if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
        sigaction(SIGTERM, &st_raw_previous_term, NULL);
        sigaction(SIGHUP, &st_raw_previous_hup, NULL);
        return 0;
    }
    st_raw_depth = 1;
    return 1;
}

void st_raw_exit(void) {
    if (st_raw_depth == 0 || --st_raw_depth > 0) {
        return;
    }
    tcsetattr(STDIN_FILENO, TCSANOW, &st_raw_saved);
    sigaction(SIGTERM, &st_raw_previous_term, NULL);
    sigaction(SIGHUP, &st_raw_previous_hup, NULL);
}

int st_read_key(unsigned char *buffer, int capacity) {
    if (capacity < 1 || !st_raw_enter()) {
        return -1;
    }

    int count = st_read_byte(&buffer[0]);
    if (count == 1) {
        struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN};
        if (buffer[0] == 27) {
            // Collect the rest of a CSI/SS3 sequence; a lone Escape has nothing pending.
            unsigned char next;
            if (count < capacity && poll(&input, 1, 40) > 0 && read(STDIN_FILENO, &next, 1) == 1) {
                if (next == '[' || next == 'O') {
                    buffer[count++] = next;
                    while (count < capacity && poll(&input, 1, 40) > 0) {
                        if (read(STDIN_FILENO, &buffer[count], 1) != 1) break;
                        count++;
                        unsigned char last = buffer[count - 1];
                        if (count >= 3 && last >= 64 && last <= 126) break;
                    }
                } else {
                    st_pending_byte = next;
                }
            }
        } else {
            int expected = st_utf8_length(buffer[0]);
            while (count < expected && count < capacity && poll(&input, 1, 40) > 0) {
                if (read(STDIN_FILENO, &buffer[count], 1) != 1) break;
                count++;
            }
        }
    }

    st_raw_exit();
    return count;
}

static struct termios st_secret_original;
static struct sigaction st_secret_previous_action;

static void st_secret_interrupted(int signal_number) {
    tcsetattr(STDIN_FILENO, TCSANOW, &st_secret_original);
    sigaction(SIGINT, &st_secret_previous_action, NULL);
    raise(signal_number);
}

char *st_read_secret_line(void) {
    int hide = isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &st_secret_original) == 0;
    if (hide) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = st_secret_interrupted;
        sigemptyset(&action.sa_mask);
        sigaction(SIGINT, &action, &st_secret_previous_action);
        struct termios silent = st_secret_original;
        silent.c_lflag &= ~(ECHO);
        silent.c_lflag |= ECHONL;
        tcsetattr(STDIN_FILENO, TCSANOW, &silent);
    }

    char *line = NULL;
    size_t capacity = 0;
    ssize_t length = getline(&line, &capacity, stdin);

    if (hide) {
        tcsetattr(STDIN_FILENO, TCSANOW, &st_secret_original);
        sigaction(SIGINT, &st_secret_previous_action, NULL);
    }
    if (length < 0) {
        free(line);
        return NULL;
    }
    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
        line[--length] = '\0';
    }
    return line;
}

int st_terminal_columns(void) {
    struct winsize size;
    return ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? size.ws_col : 80;
}

int st_terminal_rows(void) {
    struct winsize size;
    return ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_row > 0 ? size.ws_row : 24;
}
